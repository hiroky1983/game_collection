import Foundation
import Core

/// オセロの CPU。
///
/// | level | 表示 | 打ち方 |
/// |---|---|---|
/// | -1 | 入門 | 2 手先まで読んで**自分にいちばん不利な手**を選ぶ（#1401。乱数なし） |
/// | 0 | 簡単 | 読まずに**最も多く返る手**を選ぶ（角の価値もモビリティも知らない初心者の打ち方） |
/// | 1 | ふつう | 深さ 2 の αβ + 位置評価（局面数の上限 2 万） |
/// | 2 | むずかしい | 深さ 5 までの反復深化 αβ + 位置評価。空き 12 以下は終局まで読む（局面数の上限 80 万） |
///
/// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
///
/// **強さは時間ではなく「読む局面数」で決める**（#1401）。端末が遅いと時間切れで浅い読みに落ち、
/// 段階の差が端末ごとに変わっていた。時間の上限（5 秒）は暴走を止める安全用。
///
/// **段階どうしの差は先後入れ替えの実測で決めた**（会長決裁 2026-09-26: 上の段の負けが 3% 以下）。
/// 評価関数が同じ探索どうしは深さを 1〜2 変えても 10〜20% は負けるので、ふつうは深さ 2、
/// むずかしいは深さ 5 + 終盤の完全読みと大きく離してある。深さ 3 と 4 は偶奇の癖で
/// 深さ 4 が深さ 3 に 20% 負ける。詳細は `CPUBenchTests`。
///
/// **level 0 が「石数を最大にするだけ」なのは意図**（#1013）。以前は深さ 1 + 位置評価で、
/// 角を確実に取り・角の隣を避けるので初心者には強すぎた（でたらめに打つ相手に 88.3%・平均 +16.9 石。
/// 実測は #1013）。オセロでは序盤に石を取りすぎると打てる場所が減るため、石数だけを見る打ち方は
/// それ自体が弱く、かつ**乱数を使わないので毎回同じ弱さ**になる（「かんたんが不安定」の解消）。
public struct OthelloEngine: Sendable {
    let level: Int
    /// テスト専用: 持ち時間を上書きする（時間切れの挙動を決定的に検証するため・#1133）。
    /// `nil` なら `level` から決まる通常の持ち時間を使う。
    let timeLimitOverride: TimeInterval?
    /// テスト専用: 現在時刻の取得元（#1133 CodeRabbit 指摘）。実時間に依存しない固定時計を
    /// 注入できるようにし、実行環境の速度差でフレークする回帰テストを避ける。
    let now: @Sendable () -> Date

    public init(level: Int = CPUStrength.standard.rawValue) {
        self.level = level
        self.timeLimitOverride = nil
        self.now = { Date() }
    }

    /// テスト用: 持ち時間・時計を直接指定する（#1133 回帰テスト用）。
    init(level: Int, timeLimitOverride: TimeInterval? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.level = level
        self.timeLimitOverride = timeLimitOverride
        self.now = now
    }

    public func bestMove(board: OthelloBoard, stone: OthelloStone) async -> (row: Int, col: Int)? {
        move(board: board, stone: stone)
    }

    /// `bestMove` の中身（await を含まない）。計測（`CPU_BENCH`）が同期で呼ぶ。
    func move(board: OthelloBoard, stone: OthelloStone) -> (row: Int, col: Int)? {
        let moves = board.validMoves(for: stone)
        guard !moves.isEmpty else { return nil }
        let strength = CPUStrength.strength(for: level)
        if strength == .novice { return noviceMove(moves, on: board, for: stone) }
        if strength == .easy { return greediestMove(moves, on: board, for: stone) }

        let empties = othelloBoardSize * othelloBoardSize - board.count(for: .black) - board.count(for: .white)
        let (maxDepth, nodeLimit, defaultTimeLimit): (Int, Int, TimeInterval)
        switch strength {
        case .hard:
            let depth = empties <= Self.hardEndgameEmpties ? empties : Self.hardMaxDepth
            (maxDepth, nodeLimit, defaultTimeLimit) = (depth, Self.hardNodeLimit, Self.safetyTimeLimit)
        default:
            (maxDepth, nodeLimit, defaultTimeLimit) = (Self.normalMaxDepth, Self.normalNodeLimit, Self.safetyTimeLimit)
        }
        let timeLimit = timeLimitOverride ?? defaultTimeLimit

        let deadline = now().addingTimeInterval(timeLimit)
        return iterativeDeepening(moves, board: board, stone: stone, maxDepth: maxDepth,
                                  deadline: deadline, nodeLimit: nodeLimit)
    }

    /// 「むずかしい」の読みの深さ（#502 のまま）。
    static let hardMaxDepth = 5
    /// 終盤の完全読み（#1401）: 空きがこの数以下なら終局まで読む。
    static let hardEndgameEmpties = 12
    static let normalMaxDepth = 2

    /// 「読む局面数」の上限（#1401）。**強さは時間ではなくこの数で決める**（端末が遅いと時間切れで
    /// 読みが浅くなり、段階の差が端末によって変わっていた）。実測（`CPUBenchLadder`）で、
    /// 深さの上限まで読み切れる大きさにしてある。
    static let normalNodeLimit = 20_000
    static let hardNodeLimit = 800_000

    /// 入門が悪手を選ぶときに読む深さ（#1401）。
    static let noviceDepth = 2

    /// 時間の上限は暴走を止める安全用（実運用では局面数の上限が先に効く）。
    static let safetyTimeLimit: TimeInterval = 5

    /// 反復深化。深さ 1 から `maxDepth` まで順に上げ、**時間内に読み切れた最後の深さの手だけ**を使う
    /// （#1133）。時間切れになった深さの `rootSearch` は「未評価の候補手が残ったままの best」や
    /// 「探索途中で打ち切られ壊れた評価値で埋まった `negamax` の戻り値」を含みうるため、その深さの
    /// 結果は丸ごと捨てる。読み切れた深さが1つも無ければ `moves[0]` に倒す
    /// （深さ 1 すら時間内に終わらないほど遅い場合の保険。実運用では起こらない想定）。
    func iterativeDeepening(_ moves: [(Int, Int)], board: OthelloBoard, stone: OthelloStone,
                                    maxDepth: Int, deadline: Date,
                                    nodeLimit: Int = .max) -> (row: Int, col: Int) {
        var best = moves[0]
        var nodes = 0
        for d in 1...maxDepth {
            if now() > deadline { break }
            let result = rootSearch(moves, board: board, stone: stone, depth: d, deadline: deadline,
                                    nodes: &nodes, nodeLimit: nodeLimit)
            guard result.completed else { break }
            best = result.best
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

    /// 「入門」の着手（#1401）。**2 手先まで読んで、自分にいちばん不利になる手を選ぶ**（乱数なし）。
    /// 角を相手に渡し、角のとなりへ飛びつく初心者の癖を極端にしたもの。
    ///
    /// 以前（#1174）は「角が取れれば取り、そうでなければ角のとなりを好む」だったが、簡単（石数最大）が
    /// もともと弱く、入門に負け越さなかった（先後入れ替え 80 局で入門の 27 勝）。「上の段は下の段に
    /// ほぼ負けない」（会長決裁 2026-09-26）を満たすため、悪手そのものを選ぶ形にした。
    /// 同点は `validMoves` の並びで先のものを採るので、同じ盤面には必ず同じ手を返す。
    func noviceMove(_ moves: [(Int, Int)], on board: OthelloBoard,
                    for stone: OthelloStone) -> (row: Int, col: Int) {
        var best = moves[0]
        var bestScore = Int.max
        for (r, c) in moves {
            var b = board
            b.place(row: r, col: c, stone: stone)
            var nodes = 0
            let score = -negamax(b, stone: stone.opponent, depth: Self.noviceDepth - 1,
                                 alpha: -Int.max, beta: Int.max, deadline: .distantFuture,
                                 nodes: &nodes, nodeLimit: .max)
            if score < bestScore { bestScore = score; best = (r, c) }
        }
        return best
    }

    /// 「簡単」の着手（#1013）。置いたあとの自分の石が最も多くなる手を選ぶ。
    /// 同点は `validMoves` の並び（左上から）で先のものを採るので、同じ盤面には必ず同じ手を返す。
    func greediestMove(_ moves: [(Int, Int)], on board: OthelloBoard,
                       for stone: OthelloStone) -> (row: Int, col: Int) {
        var best = moves[0]
        var bestCount = -1
        for (r, c) in moves {
            var b = board
            b.place(row: r, col: c, stone: stone)
            let count = b.count(for: stone)
            if count > bestCount {
                bestCount = count
                best = (r, c)
            }
        }
        return best
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
