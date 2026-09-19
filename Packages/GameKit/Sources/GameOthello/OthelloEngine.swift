import Foundation
import Core

/// オセロの CPU。
///
/// | level | 表示 | 打ち方 |
/// |---|---|---|
/// | -1 | 入門 | 角が取れれば取り、そうでなければ**角のとなり**を好んで打つ（#1174） |
/// | 0 | 簡単 | 読まずに**最も多く返る手**を選ぶ（角の価値もモビリティも知らない初心者の打ち方） |
/// | 1 | ふつう | 深さ 3 の αβ + 位置評価 |
/// | 2 | むずかしい | 深さ 5 の αβ + 位置評価 |
/// | 3 | ガチ | 深さ 5 を読んでから深さ 7 を読み直す αβ + 位置評価（1 手 2.5 秒・#1174） |
///
/// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
///
/// **level 0 が「石数を最大にするだけ」なのは意図**（#1013）。以前は深さ 1 + 位置評価で、
/// 角を確実に取り・角の隣を避けるので初心者には強すぎた（でたらめに打つ相手に 88.3%・平均 +16.9 石。
/// 実測は #1013）。オセロでは序盤に石を取りすぎると打てる場所が減るため、石数だけを見る打ち方は
/// それ自体が弱く、かつ**乱数を使わないので毎回同じ弱さ**になる（「かんたんが不安定」の解消）。
/// 「入門」はその下に、**角のとなり（X打ち・C打ち）を自分から選ぶ**という初心者の癖を足したもの。
/// 角を相手に渡しやすくなるぶん簡単より弱く、こちらも乱数を使わないので弱さがぶれない。
public struct OthelloEngine: Sendable {
    let level: Int

    public init(level: Int = CPUStrength.standard.rawValue) { self.level = level }

    public func bestMove(board: OthelloBoard, stone: OthelloStone) async -> (row: Int, col: Int)? {
        let moves = board.validMoves(for: stone)
        guard !moves.isEmpty else { return nil }
        let strength = CPUStrength.strength(for: level)
        if strength == .novice { return noviceMove(moves, on: board, for: stone) }
        if strength == .easy { return greediestMove(moves, on: board, for: stone) }

        let (depth, timeLimit): (Int, TimeInterval)
        switch strength {
        case .serious: (depth, timeLimit) = (5, Self.seriousTimeLimit)
        case .hard:    (depth, timeLimit) = (5, 0.8)
        default:       (depth, timeLimit) = (3, 0.5)
        }

        let deadline = Date().addingTimeInterval(timeLimit)
        let shallow = rootSearch(moves, board: board, stone: stone, depth: depth, deadline: deadline)
        guard strength == .serious else { return shallow.best }

        // 「ガチ」だけは深さ 5 のあとに深さ 7 をもう一度読み、**時間内に読み切れたときだけ**
        // そちらを採る（#1174）。この探索は反復深化を持たないので、深い読みを途中で打ち切ると
        // 見ていない手が残り、深さ 5 を読み切るより弱い手を返しうる。2 段構えにすれば
        // 遅い端末でも「むずかしい」を下回らない。既存 3 段階の読み方は 1 段のままで変えない。
        let deep = rootSearch(moves, board: board, stone: stone,
                              depth: Self.seriousDeepDepth, deadline: deadline)
        return deep.completed ? deep.best : shallow.best
    }

    /// 「ガチ」の深い方の読み（#1174）。
    static let seriousDeepDepth = 7
    /// 「ガチ」の 1 手の持ち時間（#1174）。深さ 5 と深さ 7 の 2 段ぶんを合わせた上限。
    static let seriousTimeLimit: TimeInterval = 2.5

    /// 根の手を 1 巡して最善を返す。`completed` は時間切れで打ち切られなかったか。
    /// 打ち切られた場合もそこまでの最善を返す（従来どおり）。
    private func rootSearch(_ moves: [(Int, Int)], board: OthelloBoard, stone: OthelloStone,
                            depth: Int, deadline: Date) -> (best: (row: Int, col: Int), completed: Bool) {
        var best = moves[0]
        var bestScore = Int.min + 1
        for (r, c) in moves {
            if Date() > deadline { return (best, false) }
            var b = board
            b.place(row: r, col: c, stone: stone)
            let score = -negamax(b, stone: stone.opponent, depth: depth - 1,
                                 alpha: Int.min + 1, beta: Int.max, deadline: deadline)
            if score > bestScore { bestScore = score; best = (r, c) }
        }
        // 最後の根手の探索中に期限切れになっていた場合もここで拾う。ループ先頭のチェックだけだと、
        // 全ての根手を一応は評価しているのに「読み切った」と誤って報告してしまう（検証指摘）。
        return (best, Date() <= deadline)
    }

    /// 「入門」の着手（#1174）。角が取れるなら取り、そうでなければ**角のとなり**
    /// （X打ち・C打ち）へ好んで打つ。初心者がやりがちな打ち方をそのまま真似たもので、
    /// 角を相手に渡しやすくなる。角のとなりが無い局面では「簡単」と同じ打ち方に落ちる。
    ///
    /// 角を取れるときに取るのは、「勝てるのに取らない」不自然さを避けるため
    /// （弱くはするが壊さない）。乱数は使わないので同じ盤面には必ず同じ手を返す。
    func noviceMove(_ moves: [(Int, Int)], on board: OthelloBoard,
                    for stone: OthelloStone) -> (row: Int, col: Int) {
        if let corner = moves.first(where: { Self.isCorner(row: $0.0, col: $0.1) }) { return corner }
        let nextToCorner = moves.filter { Self.isNextToCorner(row: $0.0, col: $0.1) }
        return greediestMove(nextToCorner.isEmpty ? moves : nextToCorner, on: board, for: stone)
    }

    /// 四隅か。
    static func isCorner(row: Int, col: Int) -> Bool {
        (row == 0 || row == othelloBoardSize - 1) && (col == 0 || col == othelloBoardSize - 1)
    }

    /// 四隅のいずれかと隣り合う升（X打ち・C打ち）か。
    static func isNextToCorner(row: Int, col: Int) -> Bool {
        let last = othelloBoardSize - 1
        for cornerRow in [0, last] {
            for cornerCol in [0, last] where abs(row - cornerRow) <= 1 && abs(col - cornerCol) <= 1 {
                if !(row == cornerRow && col == cornerCol) { return true }
            }
        }
        return false
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

    private func negamax(_ board: OthelloBoard, stone: OthelloStone, depth: Int,
                         alpha: Int, beta: Int, deadline: Date) -> Int {
        if board.isFull { return finalScore(board, for: stone) }
        let moves = board.validMoves(for: stone)
        if depth == 0 || Date() > deadline { return evaluate(board, for: stone) }
        if moves.isEmpty {
            if board.validMoves(for: stone.opponent).isEmpty { return finalScore(board, for: stone) }
            return -negamax(board, stone: stone.opponent, depth: depth - 1,
                            alpha: -beta, beta: -alpha, deadline: deadline)
        }
        var alpha = alpha
        for (r, c) in moves {
            if Date() > deadline { break }
            var b = board
            b.place(row: r, col: c, stone: stone)
            let score = -negamax(b, stone: stone.opponent, depth: depth - 1,
                                 alpha: -beta, beta: -alpha, deadline: deadline)
            alpha = max(alpha, score)
            if alpha >= beta { return beta }
        }
        return alpha
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

    private func evaluate(_ board: OthelloBoard, for stone: OthelloStone) -> Int {
        var pos = 0
        for i in 0..<(othelloBoardSize * othelloBoardSize) {
            guard let s = board.cells[i] else { continue }
            pos += (s == stone ? 1 : -1) * Self.weights[i]
        }
        let mobility = board.validMoves(for: stone).count - board.validMoves(for: stone.opponent).count
        return pos + mobility * 10
    }

    private func finalScore(_ board: OthelloBoard, for stone: OthelloStone) -> Int {
        let mine = board.count(for: stone), opp = board.count(for: stone.opponent)
        if mine > opp { return  1_000_000 + mine - opp }
        if mine < opp { return -1_000_000 + mine - opp }
        return 0
    }
}
