import Foundation

public protocol GomokuEngine: Sendable {
    func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)?
}

// MARK: - Zobrist

private struct GomokuLCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 33)
    }
}

private enum GomokuZobrist {
    // [color 0-1][square 0-224]
    static let stone: [[UInt64]] = {
        var rng = GomokuLCG(state: 0xABCD_1234_CAFE_9876)
        var t = [[UInt64]](repeating: [UInt64](repeating: 0, count: 225), count: 2)
        for c in 0..<2 { for sq in 0..<225 { t[c][sq] = rng.next() } }
        return t
    }()
    static let sideToMove: UInt64 = {
        var rng = GomokuLCG(state: 0xDEAD_BEEF_1234_5678)
        return rng.next()
    }()
}

extension GomokuBoard {
    func zobristHash(stone: GomokuStone) -> UInt64 {
        var h: UInt64 = 0
        for (sq, s) in cells.enumerated() {
            guard let s else { continue }
            h ^= GomokuZobrist.stone[s.rawValue][sq]
        }
        if stone == .black { h ^= GomokuZobrist.sideToMove }
        return h
    }
}

// MARK: - Transposition Table

private enum GomokuTTFlag: UInt8 { case exact, lower, upper }

private struct GomokuTTEntry {
    var hash: UInt64 = 0
    var score: Int32 = 0
    var depth: Int8 = -1
    var flag: GomokuTTFlag = .exact
    var bestMove: UInt16 = 0xFFFF  // row*15+col、0xFFFF=なし
}

private let GOMOKU_TT_SIZE = 1 << 18  // 256K エントリ ≈ 4MB

// MARK: - Engine（公開 API）

public struct SimpleGomokuEngine: GomokuEngine {
    let depth: Int
    let timeLimit: TimeInterval

    public init(level: Int = 1) {
        switch level {
        case 0:  (depth, timeLimit) = (3, 0.4)
        case 2:  (depth, timeLimit) = (5, 1.5)
        default: (depth, timeLimit) = (4, 0.8)
        }
    }

    public func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)? {
        var ctx = GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit)
        return ctx.search(board: board, stone: stone)
    }
}

// MARK: - SearchContext

private struct GomokuSearchContext {
    let maxDepth: Int
    let deadline: Date
    var killers: [[Int?]]   // killers[ply][0..1]、row*15+col でエンコード
    var tt: [GomokuTTEntry]

    init(maxDepth: Int, timeLimit: TimeInterval) {
        self.maxDepth = maxDepth
        self.deadline = Date().addingTimeInterval(timeLimit)
        self.killers = [[Int?]](repeating: [nil, nil], count: maxDepth + 10)
        self.tt = [GomokuTTEntry](repeating: GomokuTTEntry(), count: GOMOKU_TT_SIZE)
    }

    // MARK: 反復深化

    mutating func search(board: GomokuBoard, stone: GomokuStone) -> (Int, Int)? {
        let candidates = candidateMoves(board: board)
        guard !candidates.isEmpty else { return (gomokuBoardSize / 2, gomokuBoardSize / 2) }

        // 即勝ち
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

        var orderedEncoded = orderMoves(candidates.map { $0.0 * gomokuBoardSize + $0.1 },
                                        board: board, stone: stone, killers: [nil, nil], ttMove: nil)
        guard let first = orderedEncoded.first else { return candidates.first }
        var best: (Int, Int) = (first / gomokuBoardSize, first % gomokuBoardSize)

        for d in 1...maxDepth {
            if Date() > deadline { break }
            var localBest: Int? = nil
            var bestScore = Int.min + 1
            var alpha = Int.min + 1
            let beta = Int.max
            var aborted = false
            var b = board

            for encoded in orderedEncoded {
                if Date() > deadline { aborted = true; break }
                let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
                b[r, c] = stone
                let score: Int
                if b.checkWin(row: r, col: c) {
                    score = 100_000 + d
                } else {
                    score = -negamax(&b, stone: opp, depth: d - 1,
                                     alpha: -beta, beta: -alpha, ply: 1)
                }
                b[r, c] = nil
                if score > bestScore { bestScore = score; localBest = encoded }
                if score > alpha { alpha = score }
            }

            if !aborted, let lb = localBest {
                best = (lb / gomokuBoardSize, lb % gomokuBoardSize)
                orderedEncoded.removeAll { $0 == lb }
                orderedEncoded.insert(lb, at: 0)
            }
            if aborted { break }
        }
        return best
    }

    // MARK: αβ ネガマックス + 置換表 + キラー

    mutating func negamax(_ board: inout GomokuBoard, stone: GomokuStone, depth: Int,
                          alpha: Int, beta: Int, ply: Int) -> Int {
        if Date() > deadline { return evaluate(board, for: stone) }

        let hash = board.zobristHash(stone: stone)
        let ttIdx = Int(hash & UInt64(GOMOKU_TT_SIZE - 1))
        let entry = tt[ttIdx]
        var ttMove: Int? = nil

        if entry.hash == hash {
            if Int(entry.depth) >= depth {
                let s = Int(entry.score)
                switch entry.flag {
                case .exact:
                    if s >= beta  { return beta  }
                    if s <= alpha { return alpha }
                    return s
                case .lower: if s >= beta  { return beta }
                case .upper: if s <= alpha { return alpha }
                }
            }
            if entry.bestMove != 0xFFFF { ttMove = Int(entry.bestMove) }
        }

        if depth == 0 { return evaluate(board, for: stone) }

        let candidates = candidateMoves(board: board)
        if candidates.isEmpty { return 0 }

        var alpha = alpha
        var flag: GomokuTTFlag = .upper
        var bestMoveEncoded = 0xFFFF
        let killerSet = ply < killers.count ? killers[ply] : [nil, nil]

        for encoded in orderMoves(candidates.map { $0.0 * gomokuBoardSize + $0.1 },
                                  board: board, stone: stone, killers: killerSet, ttMove: ttMove) {
            let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
            board[r, c] = stone
            let score: Int
            if board.checkWin(row: r, col: c) {
                score = 100_000 + depth
            } else {
                score = -negamax(&board, stone: stone.opponent, depth: depth - 1,
                                 alpha: -beta, beta: -alpha, ply: ply + 1)
            }
            board[r, c] = nil

            if score >= beta {
                if ply < killers.count {
                    killers[ply][1] = killers[ply][0]
                    killers[ply][0] = encoded
                }
                tt[ttIdx] = GomokuTTEntry(hash: hash, score: Int32(beta),
                                          depth: Int8(clamping: depth), flag: .lower,
                                          bestMove: UInt16(encoded))
                return beta
            }
            if score > alpha {
                alpha = score
                flag = .exact
                bestMoveEncoded = encoded
            }
        }

        tt[ttIdx] = GomokuTTEntry(hash: hash, score: Int32(alpha),
                                  depth: Int8(clamping: depth), flag: flag,
                                  bestMove: bestMoveEncoded < 0xFFFF ? UInt16(bestMoveEncoded) : 0xFFFF)
        return alpha
    }

    // MARK: 指し手オーダリング（TT手 > 勝ち手 > ブロック > キラー > 脅威スコア）

    func orderMoves(_ encoded: [Int], board: GomokuBoard, stone: GomokuStone,
                    killers: [Int?], ttMove: Int?) -> [Int] {
        encoded.sorted { a, b in
            moveScore(a, board: board, stone: stone, killers: killers, ttMove: ttMove) >
            moveScore(b, board: board, stone: stone, killers: killers, ttMove: ttMove)
        }
    }

    func moveScore(_ encoded: Int, board: GomokuBoard, stone: GomokuStone,
                   killers: [Int?], ttMove: Int?) -> Int {
        if let tm = ttMove, tm == encoded { return 300_000 }
        let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
        var b = board
        b[r, c] = stone
        let myThreat = localThreatScore(b, row: r, col: c, stone: stone)
        if myThreat >= 100_000 { return 200_000 }
        b[r, c] = stone.opponent
        let oppThreat = localThreatScore(b, row: r, col: c, stone: stone.opponent)
        if oppThreat >= 100_000 { return 190_000 }
        if killers.contains(where: { $0 == encoded }) { return 100_000 }
        return myThreat + oppThreat
    }

    // 指定升に置いたときの局所的連続カウント（自分視点）
    func localThreatScore(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone) -> Int {
        guard let s = board[row, col], s == stone else { return 0 }
        var score = 0
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var count = 1
            for sign in [-1, 1] {
                var r = row + dr * sign, c = col + dc * sign
                while r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize
                        && board[r, c] == stone { count += 1; r += dr * sign; c += dc * sign }
            }
            if count >= 5 { return 100_000 }
            else if count == 4 { score += 10_000 }
            else if count == 3 { score += 1_000 }
            else if count == 2 { score += 100 }
        }
        return score
    }

    // MARK: 静的評価（現在手番視点）

    func evaluate(_ board: GomokuBoard, for stone: GomokuStone) -> Int {
        staticEval(board, for: stone) - staticEval(board, for: stone.opponent)
    }

    func staticEval(_ board: GomokuBoard, for stone: GomokuStone) -> Int {
        var score = 0
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize {
                guard board[row, col] == stone else { continue }
                for (dr, dc) in dirs {
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
                    score += patternScore(count: count,
                                          open: (openFront ? 1 : 0) + (openBack ? 1 : 0))
                }
            }
        }
        return score
    }

    func patternScore(count: Int, open: Int) -> Int {
        guard open > 0 else { return 0 }
        switch count {
        case 5...: return 100_000
        case 4:    return open == 2 ? 10_000 : 1_000
        case 3:    return open == 2 ?    500 :   100
        case 2:    return open == 2 ?     50 :    10
        default:   return 1
        }
    }

    // MARK: 候補手生成（既存石から2マス以内の空き升）

    func candidateMoves(board: GomokuBoard) -> [(Int, Int)] {
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
                abs(a.0 - center) + abs(a.1 - center) < abs(b.0 - center) + abs(b.1 - center)
            }
    }
}
