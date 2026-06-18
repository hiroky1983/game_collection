import Foundation

public struct OthelloEngine: Sendable {
    let level: Int

    public init(level: Int = 1) { self.level = level }

    public func bestMove(board: OthelloBoard, stone: OthelloStone) async -> (row: Int, col: Int)? {
        let moves = board.validMoves(for: stone)
        guard !moves.isEmpty else { return nil }

        let (depth, timeLimit): (Int, TimeInterval)
        switch level {
        case 0:  (depth, timeLimit) = (1, 0.2)
        case 2:  (depth, timeLimit) = (5, 0.8)
        default: (depth, timeLimit) = (3, 0.5)
        }

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
