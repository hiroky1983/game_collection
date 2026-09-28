import Foundation

/// CPU の設定。
///
/// 1 手の読みは **`playouts`（回数の上限）と `timeLimit`（実時間の上限）の早い方**で打ち切る（#1465）。
/// `timeLimit` を nil にすると `playouts` 回を必ず回すので、種を固定すれば結果が完全に再現する
/// （テスト・計測は nil を使う。実時間で打ち切ると再現しないため）。
public struct GoEngineConfig: Sendable {
    public var playouts: Int
    /// UCT の探索定数。大きいほど広く浅く読む。
    public var exploration: Double
    public var seed: UInt64
    public var timeLimit: TimeInterval?
    /// 最善手（訪問数が最大の手）を打つ確率。1 なら常に最善手（#1465）。
    public var bestMoveChance: Double
    /// 最善手を外すとき、最善手との勝率の差がこの幅以内の手から選ぶ（許す損の幅）。
    public var mistakeMargin: Double

    public init(
        playouts: Int,
        exploration: Double = 1.0,
        seed: UInt64 = 0xA50_B1BA,
        timeLimit: TimeInterval? = nil,
        bestMoveChance: Double = 1.0,
        mistakeMargin: Double = GoLevel.mistakeMargin
    ) {
        self.playouts = playouts
        self.exploration = exploration
        self.seed = seed
        self.timeLimit = timeLimit
        self.bestMoveChance = bestMoveChance
        self.mistakeMargin = mistakeMargin
    }

    /// 段階ごとの出荷値（考える時間・回数の上限・最善手を打つ確率。#1465）。
    ///
    /// テストは実時間で打ち切ると再現しないので、この関数ではなく
    /// `GoEngineConfig(playouts:seed:timeLimit: nil)` を直接組み立てること。
    public static func level(_ level: GoLevel, seed: UInt64 = 0xA50_B1BA) -> GoEngineConfig {
        GoEngineConfig(
            playouts: level.playouts, seed: seed, timeLimit: level.timeLimit,
            bestMoveChance: level.bestMoveChance, mistakeMargin: GoLevel.mistakeMargin
        )
    }
}

/// 純モンテカルロ木探索（UCT）の CPU（#398）。
///
/// 定石データベースも既存エンジンの移植も使わない（権利確認チェックリスト: GPL エンジンの
/// コード・定石データを一切持ち込まない）。実装は公開アルゴリズム（UCT・2006）そのままで、
/// 評価は**中国ルールの面積計算による勝敗のみ**。9路だからこの素朴さで初中級の強さが出る。
public struct GoEngine: Sendable {
    public let config: GoEngineConfig
    public let ruleset: GoRuleset

    public init(config: GoEngineConfig, ruleset: GoRuleset) {
        self.config = config
        self.ruleset = ruleset
    }

    public init(level: GoLevel, ruleset: GoRuleset, seed: UInt64 = 0xA50_B1BA) {
        self.init(config: .level(level, seed: seed), ruleset: ruleset)
    }

    // MARK: - 木

    private struct Node {
        var move: GoMove?
        var parent: Int
        var children: [Int] = []
        var untried: [GoMove]
        var visits: Int = 0
        var wins: Double = 0
        /// この節点へ来た手を打った側。root は nil。
        var mover: GoStone?
    }

    /// 現局面で打つ手。合法手が無ければパス。`bestMoveChance` の確率で最善手、外れたら `mistakeMove`。
    public func bestMove(state: GoState) -> GoMove {
        search(state: state).move
    }

    /// 計測用: 打つ手に加えて、回したプレイアウト数と実時間の上限で打ち切ったかを返す（#1465）。
    func search(state: GoState) -> (move: GoMove, playouts: Int, timedOut: Bool) {
        guard !state.isTwoPassEnd else { return (.pass, 0, false) }

        let rootMoves = rootCandidates(state)
        guard !rootMoves.isEmpty else { return (.pass, 0, false) }
        // 選択肢が 1 つしか無いなら読む意味が無い（パスしか無い終盤で時間を使わない）。
        guard rootMoves.count > 1 else { return (rootMoves[0], 0, false) }

        var random = GoRandom(seed: config.seed)
        var nodes: [Node] = [Node(move: nil, parent: -1, untried: rootMoves, mover: nil)]
        let clock = ContinuousClock()
        let start = clock.now

        var iteration = 0
        var timedOut = false
        while iteration < config.playouts {
            // 実時間の上限は 32 回ごとに見る（毎回時計を読むと playout より重くなる）。
            // 上限から後始末ぶん（`timeMargin`）を引いた時点で止め、1 手の合計が上限を超えないようにする。
            if let limit = config.timeLimit, iteration > 0, iteration % 32 == 0,
               (clock.now - start) > .seconds(max(0, limit - Self.timeMargin)) {
                timedOut = true
                break
            }
            iteration += 1

            var playout = state.playoutCopy()
            var node = 0

            // 1. 選択: 未展開の手が無くなるまで UCT で降りる。
            while nodes[node].untried.isEmpty, !nodes[node].children.isEmpty {
                node = selectChild(of: node, in: nodes)
                if let move = nodes[node].move { playout.play(move) }
            }

            // 2. 展開: 未展開の手を 1 つ試す。
            if !nodes[node].untried.isEmpty {
                let pick = random.index(below: nodes[node].untried.count)
                let move = nodes[node].untried.remove(at: pick)
                let mover = playout.sideToMove
                playout.play(move)
                var untried = GoPlayout.candidateMoves(in: playout)
                if untried.isEmpty { untried = [.pass] }
                nodes.append(Node(move: move, parent: node, untried: untried, mover: mover))
                let child = nodes.count - 1
                nodes[node].children.append(child)
                node = child
            }

            // 3. 評価: ランダム対局を最後まで打ち切って面積計算で勝敗を決める。
            GoPlayout.run(&playout, random: &random)
            let winner = GoScoring.score(board: playout.board, ruleset: ruleset).winner

            // 4. 逆伝播: その手を打った側から見た勝ちを足す。
            var current = node
            while current >= 0 {
                nodes[current].visits += 1
                if let mover = nodes[current].mover {
                    if let winner {
                        if winner == mover { nodes[current].wins += 1 }
                    } else {
                        nodes[current].wins += 0.5
                    }
                }
                current = nodes[current].parent
            }
        }

        // 訪問回数が最大の手を選ぶ（勝率ではなく訪問数。MCTS の標準）。
        // 同数のときは候補の並び順で決め、乱数に依存させない（再現性のため）。
        let best = nodes[0].children.max { lhs, rhs in
            nodes[lhs].visits < nodes[rhs].visits
        }
        guard let best, let move = nodes[best].move else { return (rootMoves[0], iteration, timedOut) }
        return (mistakeMove(best: best, move: move, nodes: nodes, state: state, random: &random) ?? move,
                iteration, timedOut)
    }

    /// 実時間の上限から引く後始末ぶん（秒）。32 回ぶんのプレイアウトと手の選び直しが上限を超えないための余裕。
    static let timeMargin: TimeInterval = 0.02

    /// 外しの候補に入れる最低の訪問数。読みの回数が少なすぎる手は勝率の見積もりが当てにならない。
    static let minMistakeVisits = 10

    /// 最善手を外すときの手（#1465）。`bestMoveChance` の確率で `nil`（最善手を打つ）。
    ///
    /// 外すときは、最善手を除いた根の候補のうち、次をすべて満たす手から乱択する:
    /// - 勝率が最善手から `mistakeMargin` 以内（大石を取られる手などは勝率が大きく落ちるので入らない）
    /// - 訪問数が `minMistakeVisits` 以上（勝率の見積もりが当てになる）
    /// - パスではない（パスは終局につながる）
    /// - 打った直後にアタリ（呼吸点 1）になる自分の石が、最善手を打ったときより増えない
    ///   （自分からアタリに飛び込む手・取られかけの石を見捨てる手＝次の一手で石を取られる手を除く）
    /// 自分の眼をつぶす手は、もともと根の候補に入らない（`GoPlayout.candidateMoves`）。
    /// 候補が無ければ `nil`（最善手を打つ）。
    private func mistakeMove(best: Int, move: GoMove, nodes: [Node], state: GoState,
                             random: inout GoRandom) -> GoMove? {
        guard config.bestMoveChance < 1, move != .pass else { return nil }
        let roll = Double(random.next() >> 11) / Double(1 << 53)
        guard roll >= config.bestMoveChance else { return nil }
        let bestRate = nodes[best].wins / Double(max(1, nodes[best].visits))
        let bestAtari = Self.stonesInAtari(after: move, in: state)
        let pool = nodes[0].children.filter { child in
            guard child != best, let candidate = nodes[child].move, candidate != .pass,
                  nodes[child].visits >= Self.minMistakeVisits,
                  nodes[child].wins / Double(nodes[child].visits) >= bestRate - config.mistakeMargin
            else { return false }
            return Self.stonesInAtari(after: candidate, in: state) <= bestAtari
        }
        guard !pool.isEmpty else { return nil }
        return nodes[pool[random.index(below: pool.count)]].move
    }

    /// `move` を打った直後に、アタリ（呼吸点 1）になっている打った側の石の数。
    static func stonesInAtari(after move: GoMove, in state: GoState) -> Int {
        var next = state.playoutCopy()
        let color = state.sideToMove
        guard next.play(move) == nil else { return .max }
        var seen = Set<GoPoint>()
        var count = 0
        let board = next.board
        for row in 0..<board.size {
            for col in 0..<board.size {
                let point = GoPoint(row: row, col: col)
                guard board[point] == color, !seen.contains(point) else { continue }
                let group = next.group(at: point)
                seen.formUnion(group.stones)
                if group.liberties == 1 { count += group.stones.count }
            }
        }
        return count
    }

    private func selectChild(of node: Int, in nodes: [Node]) -> Int {
        let parentVisits = max(1, nodes[node].visits)
        let logParent = Foundation.log(Double(parentVisits))
        var bestScore = -Double.infinity
        var best = nodes[node].children[0]
        for child in nodes[node].children {
            let visits = nodes[child].visits
            let score: Double
            if visits == 0 {
                score = .infinity
            } else {
                let winRate = nodes[child].wins / Double(visits)
                score = winRate + config.exploration * (logParent / Double(visits)).squareRoot()
            }
            if score > bestScore {
                bestScore = score
                best = child
            }
        }
        return best
    }

    // MARK: - パスの方針

    /// 根の候補手。
    ///
    /// **パスを無条件に候補へ入れない**のが要点。入れると、まだ地の境界も決まっていない序盤に
    /// CPU がパスして対局が終わってしまう（面積計算 + コミの評価では、空点だらけの盤面でも
    /// 白が勝っていると見えるため）。パスを候補に入れるのは次の 2 つだけ:
    ///
    /// 1. 眼を埋める以外に打てる手が無い（＝打つと損しかしない）
    /// 2. ダメ（どちらの地でもない空点）が無くなっていて、かつ現時点の面積計算で自分が勝っている
    ///
    /// 2 は「境界が全部決まったら、勝っている側は打ち急がずに終わらせてよい」という終局判断で、
    /// 人間の打ち方とも一致する。
    ///
    /// 2 の条件は「相手が直前にパスした」場合にも緩める（#1378）。セキがあるとダメが 0 にならず、
    /// 人間が優勢でパスしても CPU が打ち続けて終局できなくなるため。パスを候補に加えるだけで、
    /// 選ぶかどうかは MCTS の訪問数に任せる。
    func rootCandidates(_ state: GoState) -> [GoMove] {
        let moves = GoPlayout.candidateMoves(in: state)
        guard !moves.isEmpty else { return [.pass] }

        let counted = GoScoring.area(of: state.board)
        guard counted.neutral == 0 || state.consecutivePasses >= 1 else { return moves }

        let score = GoScore(
            blackArea: counted.black,
            whiteArea: counted.white,
            neutral: counted.neutral,
            komi: ruleset.komi,
            handicapCompensation: ruleset.handicapCompensation
        )
        guard score.winner == state.sideToMove else { return moves }
        return moves + [.pass]
    }
}
