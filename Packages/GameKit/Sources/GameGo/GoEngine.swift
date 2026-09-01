import Foundation

/// CPU の設定。
///
/// `timeLimit` は**実時間の上限**で、遅い端末でも 1 手が長引かないための歯止め。
/// nil にすると `playouts` 回を必ず回すので、種を固定すれば結果が完全に再現する
/// （テストは常に nil を使う。実時間で打ち切ると再現しないため）。
public struct GoEngineConfig: Sendable {
    public var playouts: Int
    /// UCT の探索定数。大きいほど広く浅く読む。
    public var exploration: Double
    public var seed: UInt64
    public var timeLimit: TimeInterval?

    public init(
        playouts: Int,
        exploration: Double = 1.0,
        seed: UInt64 = 0xA50_B1BA,
        timeLimit: TimeInterval? = nil
    ) {
        self.playouts = playouts
        self.exploration = exploration
        self.seed = seed
        self.timeLimit = timeLimit
    }

    /// 強さ 3 段階の既定値。9路なら「強」でも 1 手 1 秒以内に収まるよう実時間の上限を掛ける。
    ///
    /// テストは実時間で打ち切ると再現しないので、この関数ではなく
    /// `GoEngineConfig(playouts:seed:timeLimit: nil)` を直接組み立てること。
    public static func level(_ level: GoLevel, seed: UInt64 = 0xA50_B1BA) -> GoEngineConfig {
        GoEngineConfig(playouts: level.playouts, seed: seed, timeLimit: level.timeLimit)
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

    /// 現局面での最善手。合法手が無ければパス。
    public func bestMove(state: GoState) -> GoMove {
        guard !state.isTwoPassEnd else { return .pass }

        let rootMoves = rootCandidates(state)
        guard !rootMoves.isEmpty else { return .pass }
        // 選択肢が 1 つしか無いなら読む意味が無い（パスしか無い終盤で時間を使わない）。
        guard rootMoves.count > 1 else { return rootMoves[0] }

        var random = GoRandom(seed: config.seed)
        var nodes: [Node] = [Node(move: nil, parent: -1, untried: rootMoves, mover: nil)]
        let clock = ContinuousClock()
        let start = clock.now

        var iteration = 0
        while iteration < config.playouts {
            iteration += 1
            // 実時間の上限は 32 回ごとに見る（毎回時計を読むと playout より重くなる）。
            if let limit = config.timeLimit, iteration % 32 == 0,
               (clock.now - start) > .seconds(limit) {
                break
            }

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
        guard let best, let move = nodes[best].move else { return rootMoves[0] }
        return move
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
    func rootCandidates(_ state: GoState) -> [GoMove] {
        let moves = GoPlayout.candidateMoves(in: state)
        guard !moves.isEmpty else { return [.pass] }

        let counted = GoScoring.area(of: state.board)
        guard counted.neutral == 0 else { return moves }

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
