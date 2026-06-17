import Foundation

public protocol GomokuEngine: Sendable {
    func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)?
}

public struct SimpleGomokuEngine: GomokuEngine {
    let depth: Int
    let timeLimit: TimeInterval

    public init(level: Int = 1) {
        switch level {
        case 0:  (depth, timeLimit) = (1, 0.3)
        case 2:  (depth, timeLimit) = (3, 0.8)
        default: (depth, timeLimit) = (2, 0.5)
        }
    }

    public func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)? {
        let candidates = candidateMoves(board: board)
        guard !candidates.isEmpty else {
            return (gomokuBoardSize / 2, gomokuBoardSize / 2)
        }

        // 即勝ち手
        for (r, c) in candidates {
            var b = board; b[r, c] = stone
            if b.checkWin(row: r, col: c) { return (r, c) }
        }
        // 相手の即勝ちをブロック
        let opp = stone.opponent
        for (r, c) in candidates {
            var b = board; b[r, c] = opp
            if b.checkWin(row: r, col: c) { return (r, c) }
        }

        let deadline = Date().addingTimeInterval(timeLimit)
        var best = candidates.first!
        var bestScore = Int.min + 1
        let beta = Int.max

        for (r, c) in candidates {
            if Date() > deadline { break }
            var b = board; b[r, c] = stone
            let score = -negamax(b, stone: opp, depth: depth - 1,
                                 alpha: -(beta), beta: -bestScore, deadline: deadline)
            if score > bestScore { bestScore = score; best = (r, c) }
        }
        return best
    }

    private func negamax(_ board: GomokuBoard, stone: GomokuStone, depth: Int,
                         alpha: Int, beta: Int, deadline: Date) -> Int {
        if depth == 0 || Date() > deadline {
            return staticEval(board, for: stone.opponent) - staticEval(board, for: stone)
        }
        var alpha = alpha
        for (r, c) in candidateMoves(board: board) {
            var b = board; b[r, c] = stone
            let score: Int
            if b.checkWin(row: r, col: c) {
                score = 100_000 + depth
            } else {
                score = -negamax(b, stone: stone.opponent, depth: depth - 1,
                                 alpha: -beta, beta: -alpha, deadline: deadline)
            }
            if score > alpha { alpha = score }
            if alpha >= beta { return beta }
        }
        return alpha
    }

    private func staticEval(_ board: GomokuBoard, for stone: GomokuStone) -> Int {
        var score = 0
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize {
                guard board[row, col] == stone else { continue }
                for (dr, dc) in dirs {
                    // 始点のみカウント（逆方向の始点は除外して二重計上を防ぐ）
                    let pr = row - dr, pc = col - dc
                    if pr >= 0 && pr < gomokuBoardSize && pc >= 0 && pc < gomokuBoardSize
                        && board[pr, pc] == stone { continue }
                    var count = 1
                    var r = row + dr, c = col + dc
                    while r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize
                            && board[r, c] == stone { count += 1; r += dr; c += dc }
                    let openFront = r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize
                        && board[r, c] == nil
                    let br = row - dr, bc = col - dc
                    let openBack = br >= 0 && br < gomokuBoardSize && bc >= 0 && bc < gomokuBoardSize
                        && board[br, bc] == nil
                    score += patternScore(count: count, open: (openFront ? 1 : 0) + (openBack ? 1 : 0))
                }
            }
        }
        return score
    }

    private func patternScore(count: Int, open: Int) -> Int {
        guard open > 0 else { return 0 }
        switch count {
        case 5...: return 100_000
        case 4:    return open == 2 ? 10_000 : 1_000
        case 3:    return open == 2 ?    500 :   100
        case 2:    return open == 2 ?     50 :    10
        default:   return 1
        }
    }

    private func candidateMoves(board: GomokuBoard) -> [(Int, Int)] {
        if board.cells.allSatisfy({ $0 == nil }) {
            return [(gomokuBoardSize / 2, gomokuBoardSize / 2)]
        }
        var seen = Set<Int>()
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize {
                guard board[row, col] != nil else { continue }
                for dr in -2...2 {
                    for dc in -2...2 {
                        let r = row + dr, c = col + dc
                        guard r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize,
                              board[r, c] == nil else { continue }
                        seen.insert(r * gomokuBoardSize + c)
                    }
                }
            }
        }
        let center = gomokuBoardSize / 2
        return seen.map { ($0 / gomokuBoardSize, $0 % gomokuBoardSize) }
            .sorted { a, b in
                let da = abs(a.0 - center) + abs(a.1 - center)
                let db = abs(b.0 - center) + abs(b.1 - center)
                return da < db
            }
    }
}
