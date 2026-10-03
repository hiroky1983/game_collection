import Foundation
import Core

// MARK: - 手の選び方（#1464）

/// 段階ごとの「最善手を打つ確率」（会長決裁 2026-09-26・2026-09-27）。
///
/// 難易度は**考える時間**（`OthelloEngine.timeLimit`）・読む深さの上限（`depthLimit`）と、この確率で決める。
/// 確率が外れたときは、自分の手と相手の応手の 2 手だけ読んで全候補に点を付け、最善から `slipMargin` 以内の損で済む手
/// （打つと終局まで相手の 1 手で負けが決まる手は除く）のうち、最善以外から乱択する。
struct OthelloMovePolicy: Equatable, Sendable {
    /// 探索が出した最善手をそのまま打つ確率（0...1）。
    var bestMoveProbability: Double
    /// 外したときに許す損の幅（`evaluate` の点数）。
    var slipMargin: Int

    /// 最善手だけを選ぶ（むずかしい）。
    static let exact = OthelloMovePolicy(bestMoveProbability: 1, slipMargin: 0)
    /// 探索を素直に回すだけでよいか。
    var isExact: Bool { bestMoveProbability >= 1 }
}

/// オセロの CPU。
///
/// | level | 表示 | 考える時間 | 読む深さの上限 | 最善手を打つ確率 |
/// |---|---|---|---|---|
/// | -1 | 入門 | 0.3 秒 | 1 手先 | `noviceBestMoveProbability` |
/// | 0 | かんたん | 0.5 秒 | 3 手先 | `easyBestMoveProbability` |
/// | 1 | ふつう | 1 秒 | 4 手先 | `normalBestMoveProbability` |
/// | 2 | むずかしい | 1.5 秒 | 無し（終局まで） | 100% |
///
/// **段階の差は、この時間・深さの上限・確率の 3 つだけで付ける**（#1464・会長決裁 2026-09-27）。
/// 探索（反復深化 αβ・位置評価）は全段階で同じで、時間が来るか深さの上限まで読み終えたら打つ。
/// むずかしいは深さの上限が無いので、空きが少なくなれば時間内に終局まで読み切る（終盤の完全読み）。
/// 以前（#1401）の段階ごとの打ち方（入門=自分にいちばん不利な手・簡単=最も多く返る手・局面数の上限）は廃止した。
/// 深さの上限が奇数なのは、偶数の深さは 1 つ手前の奇数より弱くなることがあるため（実測）。ただしふつうは #1658 で
/// 4 手にした（かんたん 3 手に対して 3 手と 5 手のあいだの強さに収まることを実測で確かめた）。
/// 確率の根拠は `docs/analytics/othello-1464-ladder.md`（上の段の得点率 90% 以上で最も高い値）。
/// ふつうだけは #1658（会長決裁 2026-10-01）で、かんたんに対する得点率 60〜70% に下げた（`docs/analytics/othello-1658-normal.md`）。
///
/// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
public struct OthelloEngine: Sendable {
    let level: Int
    /// 1 手の考える時間の上限（秒）。読み終われば早く打つ。
    let timeLimit: TimeInterval
    /// 読む深さの上限（`nil` なら無し＝終局まで）。
    let depthLimit: Int?
    /// 読む局面数の上限。出荷値では使わない（`.max`）。計測が考える時間を局面数に置き換えるための口。
    let nodeLimit: Int
    let policy: OthelloMovePolicy
    /// 乱数の種。`nil` なら実プレイ用に毎回違う乱数を使う（テスト・計測だけが種を渡して再現する）。
    /// `policy` が乱数を使わない段階（むずかしい）は、この値を見ない。
    let seed: UInt64?
    /// テスト専用: 現在時刻の取得元（#1133 CodeRabbit 指摘）。実時間に依存しない固定時計を
    /// 注入できるようにし、実行環境の速度差でフレークする回帰テストを避ける。
    let now: @Sendable () -> Date

    public init(level: Int = CPUStrength.standard.rawValue) {
        self.init(level: level, seed: nil)
    }

    /// テスト・計測用: 段階の出荷値から、指定したものだけを差し替える。
    /// `timeLimitOverride` は時間切れの挙動を決定的に検証するため（#1133）。
    /// `depthLimitOverride` は計測が深さの上限の候補を試すため（#1566）。
    init(level: Int, timeLimitOverride: TimeInterval? = nil, depthLimitOverride: Int? = nil, nodeLimit: Int = .max,
         policy: OthelloMovePolicy? = nil, seed: UInt64? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.level = level
        let shipped = Self.settings(for: CPUStrength.strength(for: level))
        self.timeLimit = timeLimitOverride ?? shipped.timeLimit
        self.depthLimit = depthLimitOverride ?? shipped.depthLimit
        self.nodeLimit = nodeLimit
        self.policy = policy ?? shipped.policy
        self.seed = seed
        self.now = now
    }

    /// 段階の出荷値（#1464）。
    static func settings(for strength: CPUStrength)
        -> (timeLimit: TimeInterval, depthLimit: Int?, policy: OthelloMovePolicy) {
        switch strength {
        case .novice: return (0.3, 1, policy(noviceBestMoveProbability))
        case .easy:   return (0.5, 3, policy(easyBestMoveProbability))
        case .normal: return (1.0, 4, policy(normalBestMoveProbability))
        case .hard:   return (1.5, nil, .exact)
        }
    }

    /// 最善手を打つ確率（#1464 の実測。上の段の得点率が 90% 以上になる、10% 刻みで最も高い値。上から順に決めた:
    /// むずかしい 100% に対しふつう 90%、ふつう 90% に対しかんたん 60%、かんたん 60% に対し入門 50%）。
    /// ふつうは #1658 で 5 手・90% → 4 手・60% に下げた（かんたんに対する得点率 91.8% → 開始局面 1〜400 の 800 局で 64.8%）。
    static let noviceBestMoveProbability = 0.5
    static let easyBestMoveProbability = 0.6
    static let normalBestMoveProbability = 0.6

    /// 外したときに許す損の幅（`evaluate` の点数）。X 打ち（角のななめとなり）の減点 1 つ・着手可能数の差 4 手ぶん。
    /// 角を相手に渡す手（角の点 120）は入らない。実測で、外しの候補（最善以外）が残る局面は 8 割強（平均 3 手）。
    static let slipMargin = 40

    static func policy(_ probability: Double) -> OthelloMovePolicy {
        OthelloMovePolicy(bestMoveProbability: probability, slipMargin: slipMargin)
    }

    public func bestMove(board: OthelloBoard, stone: OthelloStone) async -> (row: Int, col: Int)? {
        move(board: board, stone: stone)
    }

    /// `bestMove` の中身（await を含まない）。計測（`CPU_BENCH`）が同期で呼ぶ。
    func move(board: OthelloBoard, stone: OthelloStone) -> (row: Int, col: Int)? {
        let moves = board.validMoves(for: stone)
        guard !moves.isEmpty else { return nil }
        let deadline = self.deadline()
        if !policy.isExact {
            var rng = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
            if Double.random(in: 0..<1, using: &rng) >= policy.bestMoveProbability,
               let slip = slipMove(moves, board: board, stone: stone, using: &rng) {
                return slip
            }
        }
        let empties = othelloBoardSize * othelloBoardSize - board.count(for: .black) - board.count(for: .white)
        let maxDepth = max(1, min(depthLimit ?? empties, empties))
        return iterativeDeepening(moves, board: board, stone: stone, maxDepth: maxDepth,
                                  deadline: deadline, nodeLimit: nodeLimit)
    }

    /// 考える時間の締切。`timeLimit: .infinity`（計測が局面数で打ち切るとき）は時間で打ち切らない。
    /// 締切を過ぎてから探索を巻き戻して手を返すまでの分（`searchOverhead`）を先に引き、1 手が上限を超えないようにする。
    func deadline() -> Date {
        timeLimit.isFinite ? now().addingTimeInterval(timeLimit - Self.searchOverhead) : .distantFuture
    }

    /// 締切を過ぎてから手を返すまでの余裕（秒）。引かないと、むずかしいが 1.5 秒を 1 ミリ秒ほど超えた（実測）。
    static let searchOverhead = 0.02

    /// 計測用: 手に加えて、読んだ局面数と読み切った深さを返す（`policy` は通さず、探索そのものだけを見る）。
    func analyze(board: OthelloBoard, stone: OthelloStone) -> (move: (row: Int, col: Int), nodes: Int, depth: Int)? {
        let moves = board.validMoves(for: stone)
        guard !moves.isEmpty else { return nil }
        let empties = othelloBoardSize * othelloBoardSize - board.count(for: .black) - board.count(for: .white)
        let maxDepth = max(1, min(depthLimit ?? empties, empties))
        var nodes = 0, depth = 0
        let move = iterativeDeepening(moves, board: board, stone: stone, maxDepth: maxDepth,
                                      deadline: deadline(), nodeLimit: nodeLimit,
                                      nodes: &nodes, completedDepth: &depth)
        return (move, nodes, depth)
    }

    /// 最善手を外すときの手（#1464）。全候補に自分の手と相手の応手の 2 手だけ（入門は 1 手）読んで点を付け、点の最も高い手を
    /// 除いたうち、最善から `slipMargin` 以内の損の手から乱択する。角を渡す手・角を捨てる手は幅の外に出る。
    /// 候補が無い・選べる手が即負けの手だけなら `nil`（呼び出し側が探索して最善手を打つ）。
    func slipMove(_ moves: [(Int, Int)], board: OthelloBoard, stone: OthelloStone,
                  using rng: inout SplitMix64) -> (row: Int, col: Int)? {
        var pool = slipPool(moves, board: board, stone: stone)
        while !pool.isEmpty {
            let move = pool.remove(at: Int.random(in: 0..<pool.count, using: &rng))
            if !Self.allowsImmediateLoss(board, move: move, stone: stone) { return move }
        }
        return nil
    }

    /// 外しの採点で読む深さ（自分の手＋相手の応手）。1 手だけ（打った直後の評価）だと、相手に角を渡す手が見えない。
    /// ただし**その段の深さの上限より深くは読まない**（入門は 1 手）。上限より深く読んで採点すると、外した手のほうが
    /// 探索の最善手より良い手になりうる（実測: 入門の確率を 50% に下げると、かんたんの得点率が 100% のときより下がった）。
    static let slipReadDepth = 2
    var slipDepth: Int { min(Self.slipReadDepth, depthLimit ?? Self.slipReadDepth) }

    /// 外しの候補（即負けの確認前）。最善（2 手読みの点が最も高い手）を除く。
    func slipPool(_ moves: [(Int, Int)], board: OthelloBoard, stone: OthelloStone) -> [(Int, Int)] {
        var scored: [(move: (Int, Int), score: Int)] = []
        for (r, c) in moves {
            var b = board
            b.place(row: r, col: c, stone: stone)
            var nodes = 0
            // 全幅で読む（αβ の窓を狭めると「最善から〜以内」を判定できる値が返らない）。
            let score = -negamax(b, stone: stone.opponent, depth: slipDepth - 1,
                                 alpha: -Int.max, beta: Int.max, deadline: .distantFuture,
                                 nodes: &nodes, nodeLimit: .max)
            scored.append(((r, c), score))
        }
        guard let best = scored.map(\.score).max(), let top = scored.firstIndex(where: { $0.score == best })
        else { return [] }
        scored.remove(at: top)
        return scored.filter { $0.score >= best - policy.slipMargin }.map(\.move)
    }

    /// `move` を打つと、その場で終局して負けるか、相手の次の 1 手で終局して負けが決まる（＝即負け）か。
    static func allowsImmediateLoss(_ board: OthelloBoard, move: (Int, Int), stone: OthelloStone) -> Bool {
        func isLostEnd(_ b: OthelloBoard) -> Bool {
            b.validMoves(for: .black).isEmpty && b.validMoves(for: .white).isEmpty
                && b.count(for: stone) < b.count(for: stone.opponent)
        }
        var b = board
        b.place(row: move.0, col: move.1, stone: stone)
        if isLostEnd(b) { return true }
        for (r, c) in b.validMoves(for: stone.opponent) {
            var reply = b
            reply.place(row: r, col: c, stone: stone.opponent)
            if isLostEnd(reply) { return true }
        }
        return false
    }

    /// 反復深化。深さ 1 から `maxDepth` まで順に上げ、**時間内に読み切れた最後の深さの手だけ**を使う
    /// （#1133）。時間切れになった深さの `rootSearch` は「未評価の候補手が残ったままの best」や
    /// 「探索途中で打ち切られ壊れた評価値で埋まった `negamax` の戻り値」を含みうるため、その深さの
    /// 結果は丸ごと捨てる。読み切れた深さが1つも無ければ `moves[0]` に倒す
    /// （深さ 1 すら時間内に終わらないほど遅い場合の保険。実運用では起こらない想定）。
    func iterativeDeepening(_ moves: [(Int, Int)], board: OthelloBoard, stone: OthelloStone,
                            maxDepth: Int, deadline: Date, nodeLimit: Int = .max) -> (row: Int, col: Int) {
        var nodes = 0, depth = 0
        return iterativeDeepening(moves, board: board, stone: stone, maxDepth: maxDepth, deadline: deadline,
                                  nodeLimit: nodeLimit, nodes: &nodes, completedDepth: &depth)
    }

    func iterativeDeepening(_ moves: [(Int, Int)], board: OthelloBoard, stone: OthelloStone,
                            maxDepth: Int, deadline: Date, nodeLimit: Int,
                            nodes: inout Int, completedDepth: inout Int) -> (row: Int, col: Int) {
        var best = moves[0]
        for d in 1...maxDepth {
            if now() > deadline { break }
            let result = rootSearch(moves, board: board, stone: stone, depth: d, deadline: deadline,
                                    nodes: &nodes, nodeLimit: nodeLimit)
            guard result.completed else { break }
            best = result.best
            completedDepth = d
        }
        return best
    }
    /// 根の手を 1 巡して最善を返す。`completed` は時間切れで打ち切られなかったか。
    /// 打ち切られた場合の `best` は読み残しがある不完全な結果なので、呼び出し側
    /// （`iterativeDeepening`）は使わずに前の深さの結果を採る（#1133）。
    ///
    /// 根でも αβ を効かせる（#1401）: それまでの最善の点数を `alpha` として渡すので、それ以下と分かった
    /// 手は途中で読むのをやめる。`score > bestScore` のときだけ差し替えるので、同点は先の手を採る
    /// （全幅で読んでいた頃と同じ手が返る）。
    func rootSearch(_ moves: [(Int, Int)], board: OthelloBoard, stone: OthelloStone,
                            depth: Int, deadline: Date, nodes: inout Int,
                            nodeLimit: Int = .max) -> (best: (row: Int, col: Int), completed: Bool) {
        var best = moves[0]
        var bestScore = Int.min + 1
        for (r, c) in Self.ordered(moves) {
            if now() > deadline || nodes > nodeLimit { return (best, false) }
            var b = board
            b.place(row: r, col: c, stone: stone)
            let score = -negamax(b, stone: stone.opponent, depth: depth - 1,
                                 alpha: -Int.max, beta: -bestScore, deadline: deadline,
                                 nodes: &nodes, nodeLimit: nodeLimit)
            if score > bestScore { bestScore = score; best = (r, c) }
        }
        // 最後の根手の探索中に期限切れ・上限超えになっていた場合もここで拾う。ループ先頭のチェックだけだと、
        // 全ての根手を一応は評価しているのに「読み切った」と誤って報告してしまう（検証指摘）。
        return (best, now() <= deadline && nodes <= nodeLimit)
    }

    func negamax(_ board: OthelloBoard, stone: OthelloStone, depth: Int,
                         alpha: Int, beta: Int, deadline: Date,
                         nodes: inout Int, nodeLimit: Int) -> Int {
        nodes += 1
        if board.isFull { return finalScore(board, for: stone) }
        let moves = board.validMoves(for: stone)
        if depth == 0 || nodes > nodeLimit || now() > deadline { return evaluate(board, for: stone) }
        if moves.isEmpty {
            if board.validMoves(for: stone.opponent).isEmpty { return finalScore(board, for: stone) }
            return -negamax(board, stone: stone.opponent, depth: depth - 1,
                            alpha: -beta, beta: -alpha, deadline: deadline,
                            nodes: &nodes, nodeLimit: nodeLimit)
        }
        var alpha = alpha
        for (r, c) in Self.ordered(moves) {
            if nodes > nodeLimit || now() > deadline { break }
            var b = board
            b.place(row: r, col: c, stone: stone)
            let score = -negamax(b, stone: stone.opponent, depth: depth - 1,
                                 alpha: -beta, beta: -alpha, deadline: deadline,
                                 nodes: &nodes, nodeLimit: nodeLimit)
            alpha = max(alpha, score)
            if alpha >= beta { return beta }
        }
        return alpha
    }

    /// 位置評価の高い手から読む（αβ の刈り込みが効く・#1401）。同点は元の並びを保つ。
    static func ordered(_ moves: [(Int, Int)]) -> [(Int, Int)] {
        moves.enumerated().sorted { a, b in
            let wa = weights[a.element.0 * othelloBoardSize + a.element.1]
            let wb = weights[b.element.0 * othelloBoardSize + b.element.1]
            return wa != wb ? wa > wb : a.offset < b.offset
        }.map(\.element)
    }

    private static let weights: [Int] = [
        120, -20,  20,   5,   5,  20, -20, 120,
        -20, -40,  -5,  -5,  -5,  -5, -40, -20,
         20,  -5,  15,   3,   3,  15,  -5,  20,
          5,  -5,   3,   3,   3,   3,  -5,   5,
          5,  -5,   3,   3,   3,   3,  -5,   5,
         20,  -5,  15,   3,   3,  15,  -5,  20,
        -20, -40,  -5,  -5,  -5,  -5, -40, -20,
        120, -20,  20,   5,   5,  20, -20, 120,
    ]

    /// 位置評価 + 着手可能数の差 + 終盤の石数差（#1401）。外周のすぐ内側の升の減点は、**その真上・真横の
    /// 外周の升（角のとなりなら角）が空いているあいだだけ**効かせる（埋まったあとは相手に辺を渡す危険がないので、
    /// 減点し続けると自分から良い手を避けてしまう）。-5 の升も同じ扱いにしたほうが実測で強かった
    /// （角だけに絞ると むずかしい 対 ふつう の負けが 3% を超えた）。
    func evaluate(_ board: OthelloBoard, for stone: OthelloStone) -> Int {
        let last = othelloBoardSize - 1
        var pos = 0
        var mine = 0, opp = 0
        for i in 0..<(othelloBoardSize * othelloBoardSize) {
            guard let s = board.cells[i] else { continue }
            var w = Self.weights[i]
            if w < 0 {
                let r = i / othelloBoardSize, c = i % othelloBoardSize
                let anchorRow = r <= 1 ? 0 : (r >= last - 1 ? last : r)
                let anchorCol = c <= 1 ? 0 : (c >= last - 1 ? last : c)
                if board[anchorRow, anchorCol] != nil { w = 5 }
            }
            if s == stone { pos += w; mine += 1 } else { pos -= w; opp += 1 }
        }
        let mobility = board.validMoves(for: stone).count - board.validMoves(for: stone.opponent).count
        let empties = othelloBoardSize * othelloBoardSize - mine - opp
        let discs = empties <= Self.discPhaseEmpties ? (mine - opp) * (Self.discPhaseEmpties - empties + 1) : 0
        return pos + mobility * Self.mobilityWeight + discs
    }
    static let mobilityWeight = 10
    static let discPhaseEmpties = 16

    private func finalScore(_ board: OthelloBoard, for stone: OthelloStone) -> Int {
        let mine = board.count(for: stone), opp = board.count(for: stone.opponent)
        if mine > opp { return  1_000_000 + mine - opp }
        if mine < opp { return -1_000_000 + mine - opp }
        return 0
    }
}
