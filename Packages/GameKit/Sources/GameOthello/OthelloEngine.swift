import Foundation

/// オセロの CPU。
///
/// | level | 表示 | 打ち方 |
/// |---|---|---|
/// | 0 | 弱 | 読まずに**最も多く返る手**を選ぶ（角の価値もモビリティも知らない初心者の打ち方） |
/// | 1 | 普通 | 深さ 3 の αβ + 位置評価 |
/// | 2 | 強 | 深さ 5 の αβ + 位置評価 |
///
/// **level 0 が「石数を最大にするだけ」なのは意図**（#1013）。以前は深さ 1 + 位置評価で、
/// 角を確実に取り・角の隣を避けるので初心者には強すぎた（でたらめに打つ相手に 88.3%・平均 +16.9 石。
/// 実測は #1013）。オセロでは序盤に石を取りすぎると打てる場所が減るため、石数だけを見る打ち方は
/// それ自体が弱く、かつ**乱数を使わないので毎回同じ弱さ**になる（「かんたんが不安定」の解消）。
public struct OthelloEngine: Sendable {
    let level: Int

    public init(level: Int = 1) { self.level = level }

    public func bestMove(board: OthelloBoard, stone: OthelloStone) async -> (row: Int, col: Int)? {
        let moves = board.validMoves(for: stone)
        guard !moves.isEmpty else { return nil }
        if level == 0 { return greediestMove(moves, on: board, for: stone) }

        let (depth, timeLimit): (Int, TimeInterval) = level == 2 ? (5, 0.8) : (3, 0.5)

        let deadline = Date().addingTimeInterval(timeLimit)
        var best = moves.first!
        var bestScore = Int.min + 1

        for (r, c) in moves {
            if Date() > deadline { break }
            var b = board
            b.place(row: r, col: c, stone: stone)
            let score = -negamax(b, stone: stone.opponent, depth: depth - 1,
                                 alpha: Int.min + 1, beta: Int.max, deadline: deadline)
            if score > bestScore { bestScore = score; best = (r, c) }
        }
        return best
    }

    /// 「弱」の着手（#1013）。置いたあとの自分の石が最も多くなる手を選ぶ。
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
