import Foundation

/// 将棋 AI の境界（USI 風）。
public protocol ShogiEngine: Sendable {
    func bestMove(sfen: String) async -> String?
}

// MARK: - Piece Values

enum PieceValue {
    static func base(_ type: PieceType) -> Int {
        switch type {
        case .pawn: return 100
        case .lance: return 300
        case .knight: return 400
        case .silver: return 500
        case .gold: return 600
        case .bishop: return 800
        case .rook: return 1000
        case .king: return 100_000
        }
    }

    static func onBoard(_ p: Piece) -> Int {
        if p.promoted {
            switch p.type {
            case .pawn, .lance, .knight, .silver: return 600
            case .bishop: return 1200
            case .rook: return 1300
            default: break
            }
        }
        return base(p.type)
    }
}

// MARK: - Zobrist Hashing

private struct LCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 33)
    }
}

private enum Zobrist {
    // [pieceType 0-7][color 0-1][promoted 0-1][square 0-80]
    static let piece: [[[[UInt64]]]] = {
        var rng = LCG(state: 0xDEAD_BEEF_CAFE_BABE)
        var t = [[[[UInt64]]]](
            repeating: [[[UInt64]]](
                repeating: [[UInt64]](
                    repeating: [UInt64](repeating: 0, count: 81),
                    count: 2),
                count: 2),
            count: 8)
        for pt in 0..<8 { for c in 0..<2 { for pr in 0..<2 { for sq in 0..<81 {
            t[pt][c][pr][sq] = rng.next()
        }}}}
        return t
    }()

    // [color 0-1][pieceType 0-6 droppable][count 0-18]
    static let hand: [[[UInt64]]] = {
        var rng = LCG(state: 0xCAFE_BABE_DEAD_BEEF)
        var t = [[[UInt64]]](
            repeating: [[UInt64]](
                repeating: [UInt64](repeating: 0, count: 19),
                count: 7),
            count: 2)
        for c in 0..<2 { for pt in 0..<7 { for n in 0..<19 {
            t[c][pt][n] = rng.next()
        }}}
        return t
    }()

    static let sideToMove: UInt64 = {
        var rng = LCG(state: 0x1234_5678_9ABC_DEF0)
        return rng.next()
    }()
}

extension Position {
    func zobristHash() -> UInt64 {
        var h: UInt64 = 0
        for (sq, p) in squares.enumerated() {
            guard let p else { continue }
            h ^= Zobrist.piece[p.type.rawValue][p.color.rawValue][p.promoted ? 1 : 0][sq]
        }
        for c in 0..<2 {
            for t in 0..<7 {
                let n = hands[c][t]
                if n > 0 { h ^= Zobrist.hand[c][t][min(n, 18)] }
            }
        }
        if sideToMove == .black { h ^= Zobrist.sideToMove }
        return h
    }
}

// MARK: - Transposition Table

private enum TTFlag: UInt8 { case exact, lower, upper }

private struct TTEntry {
    var hash: UInt64 = 0
    var score: Int32 = 0
    var depth: Int8 = -1
    var flag: TTFlag = .exact
}

private let TT_SIZE = 1 << 19  // 512K エントリ ≈ 8MB

// MARK: - 前進ボーナステーブル（駒の種類ごとに自陣からの距離 0-8 で定義）

// 0=自陣、8=相手の奥。成り駒は PieceValue.onBoard が既に高いのでボーナス不要。
private let advanceTable: [[Int]] = [
    // pawn  0-8
    [0, 3, 6, 9, 12, 18, 30, 50, 70],
    // lance 0-8
    [0, 3, 6, 9, 12, 16, 22, 32, 40],
    // knight 0-8（最後の2段は実質不可なので0）
    [0, 0, 5, 10, 15, 22, 32, 0, 0],
    // silver 0-8
    [0, 4, 7, 11, 15, 19, 24, 28, 32],
    // gold 0-8
    [0, 3, 5,  8, 11, 14, 17, 20, 23],
    // bishop 0-8
    [0, 2, 4,  7, 10, 14, 18, 23, 28],
    // rook 0-8
    [0, 3, 6,  9, 12, 16, 20, 24, 28],
    // king 0-8（王の安全度は kingSafety が担当）
    [0, 0, 0,  0,  0,  0,  0,  0,  0],
]

// MARK: - Engine（公開 API）

public struct SimpleMinimaxEngine: ShogiEngine {
    let depth: Int
    let usePositional: Bool
    let useBook: Bool
    let timeLimit: TimeInterval

    public init(level: Int = 1) {
        switch level {
        case 0:  (depth, usePositional, useBook, timeLimit) = (3, false, false, 0.5)
        case 2:  (depth, usePositional, useBook, timeLimit) = (5, true,  true,  1.5)
        default: (depth, usePositional, useBook, timeLimit) = (4, true,  false, 1.0)
        }
    }

    public func bestMove(sfen: String) async -> String? {
        guard var pos = Position.fromSFEN(sfen) else { return nil }
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { return nil }

        if useBook, let booked = OpeningBook.move(for: sfen),
           let m = Move.fromUSI(booked), moves.contains(m) { return booked }

        var ctx = SearchContext(maxDepth: depth, usePositional: usePositional, timeLimit: timeLimit)
        return ctx.search(&pos)?.usi
    }

    func kingSafety(_ pos: Position, _ color: Side) -> Int {
        SearchContext(maxDepth: depth, usePositional: usePositional, timeLimit: 0).kingSafety(pos, color)
    }
}

// MARK: - SearchContext（探索の可変状態）

private struct SearchContext {
    let maxDepth: Int
    let usePositional: Bool
    let deadline: Date
    var killers: [[Move?]]   // killers[ply][0..1]
    var tt: [TTEntry]

    init(maxDepth: Int, usePositional: Bool, timeLimit: TimeInterval) {
        self.maxDepth = maxDepth
        self.usePositional = usePositional
        self.deadline = Date().addingTimeInterval(timeLimit)
        self.killers = [[Move?]](repeating: [nil, nil], count: maxDepth + 20)
        self.tt = [TTEntry](repeating: TTEntry(), count: TT_SIZE)
    }

    // MARK: 反復深化

    mutating func search(_ pos: inout Position) -> Move? {
        var orderedMoves = orderMoves(pos.legalMoves(), pos: pos, killers: [nil, nil])
        var best: Move? = orderedMoves.first

        for d in 1...maxDepth {
            if Date() > deadline { break }
            var localBest: Move?
            var bestScore = Int.min + 1
            var alpha = Int.min + 1
            let beta = Int.max
            var aborted = false

            for move in orderedMoves {
                if Date() > deadline { aborted = true; break }
                let undo = pos.make(move)
                let score = -negamax(&pos, depth: d - 1, alpha: -beta, beta: -alpha, ply: 1)
                pos.unmake(undo)
                if score > bestScore { bestScore = score; localBest = move }
                if score > alpha { alpha = score }
            }

            if !aborted, let lb = localBest {
                best = lb
                orderedMoves.removeAll { $0 == lb }
                orderedMoves.insert(lb, at: 0)
            }
            if aborted { break }
        }
        return best
    }

    // MARK: αβ ネガマックス + 置換表 + キラー + Null Move + LMR

    mutating func negamax(_ pos: inout Position, depth: Int, alpha: Int, beta: Int, ply: Int, nullOk: Bool = true) -> Int {
        if Date() > deadline { return evaluate(pos) }

        // 置換表参照
        let hash = pos.zobristHash()
        let ttIdx = Int(hash & UInt64(TT_SIZE - 1))
        let entry = tt[ttIdx]
        if entry.hash == hash && Int(entry.depth) >= depth {
            let s = Int(entry.score)
            switch entry.flag {
            case .exact:
                if s >= beta  { return beta  }
                if s <= alpha { return alpha }
                return s
            case .lower:
                if s >= beta  { return beta }
            case .upper:
                if s <= alpha { return alpha }
            }
        }

        if depth == 0 { return quiesce(&pos, alpha: alpha, beta: beta, qdepth: 0) }

        // 詰み専用探索（残り深さ3以下で王手がかかっていない場合のみ詰みチェック）
        if depth <= 3 {
            if let mateScore = mateSearch(&pos, depth: depth * 2 + 1, ply: ply) {
                return mateScore
            }
        }

        // Null Move Pruning（王手がかかっていない + 十分な深さ + 局面に駒がある）
        if nullOk && depth >= 3 && !pos.isInCheck() && hasNonPawnPieces(pos) {
            let R = depth >= 6 ? 3 : 2  // 削減量（深いほど大きく削減）
            let undo = pos.makeNull()
            let nullScore = -negamax(&pos, depth: depth - 1 - R, alpha: -beta, beta: -beta + 1, ply: ply + 1, nullOk: false)
            pos.unmakeNull(undo)
            if nullScore >= beta {
                return beta  // Null Move カット
            }
        }

        let moves = pos.legalMoves()
        if moves.isEmpty { return -PieceValue.base(.king) - depth }

        var alpha = alpha
        var flag: TTFlag = .upper
        let killerSet = ply < killers.count ? killers[ply] : [nil, nil]
        let orderedMoves = orderMoves(moves, pos: pos, killers: killerSet)

        for (moveCount, move) in orderedMoves.enumerated() {
            let undo = pos.make(move)

            var score: Int
            if moveCount == 0 {
                // PV手はフル深さで探索
                score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            } else {
                // LMR: 非キャプチャ・非昇格の後半手は削減して探索
                let isQuiet = !isCapture(move, pos) && !isPromotion(move)
                let lmrDepth: Int
                if depth >= 3 && moveCount >= 4 && isQuiet {
                    let reduction = moveCount >= 8 ? 2 : 1
                    lmrDepth = max(1, depth - 1 - reduction)
                } else {
                    lmrDepth = depth - 1
                }

                // ゼロウィンドウ探索
                score = -negamax(&pos, depth: lmrDepth, alpha: -alpha - 1, beta: -alpha, ply: ply + 1)

                // LMR 削減した手がアルファを超えたらフル深さで再探索
                if score > alpha && lmrDepth < depth - 1 {
                    score = -negamax(&pos, depth: depth - 1, alpha: -alpha - 1, beta: -alpha, ply: ply + 1)
                }
                // PVS: alpha < score < beta ならフルウィンドウで再探索
                if score > alpha && score < beta {
                    score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
                }
            }

            pos.unmake(undo)

            if score >= beta {
                if ply < killers.count && !isCapture(move, pos) {
                    killers[ply][1] = killers[ply][0]
                    killers[ply][0] = move
                }
                tt[ttIdx] = TTEntry(hash: hash, score: Int32(beta), depth: Int8(clamping: depth), flag: .lower)
                return beta
            }
            if score > alpha {
                alpha = score
                flag = .exact
            }
        }

        tt[ttIdx] = TTEntry(hash: hash, score: Int32(alpha), depth: Int8(clamping: depth), flag: flag)
        return alpha
    }

    // MARK: 詰み専用探索（奇数手詰めを読む）

    mutating func mateSearch(_ pos: inout Position, depth: Int, ply: Int) -> Int? {
        if Date() > deadline { return nil }
        let moves = pos.legalMoves()
        if moves.isEmpty { return -PieceValue.base(.king) - ply }
        if depth <= 0 { return nil }

        // 王手になる手のみ探索
        let checks = moves.filter { move in
            let undo = pos.make(move)
            let inCheck = pos.isInCheck()  // 相手が王手状態か
            pos.unmake(undo)
            return inCheck
        }
        guard !checks.isEmpty else { return nil }

        for move in checks {
            let undo = pos.make(move)
            // 相手の応手が全て詰みかどうか確認
            let replies = pos.legalMoves()
            if replies.isEmpty {
                // 詰み発見
                pos.unmake(undo)
                return PieceValue.base(.king) + ply
            }
            // 全応手を試して逃げられるか確認
            var allMate = true
            for reply in replies {
                let undo2 = pos.make(reply)
                let result = mateSearch(&pos, depth: depth - 2, ply: ply + 2)
                pos.unmake(undo2)
                if result == nil {
                    allMate = false
                    break
                }
            }
            pos.unmake(undo)
            if allMate { return PieceValue.base(.king) + ply }
        }
        return nil
    }

    // MARK: 静止探索（取り合いが落ち着くまで探索）

    mutating func quiesce(_ pos: inout Position, alpha: Int, beta: Int, qdepth: Int) -> Int {
        if qdepth >= 6 || Date() > deadline { return evaluate(pos) }

        let standPat = evaluate(pos)
        if standPat >= beta { return beta }
        if standPat + 1300 < alpha { return alpha }

        var alpha = max(alpha, standPat)

        let captures = pos.legalMoves().filter { isCapture($0, pos) }
        for move in captures.sorted(by: { captureScore($0, pos) > captureScore($1, pos) }) {
            let undo = pos.make(move)
            let score = -quiesce(&pos, alpha: -beta, beta: -alpha, qdepth: qdepth + 1)
            pos.unmake(undo)
            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    // MARK: 指し手オーダリング（MVV-LVA + キラー）

    func orderMoves(_ moves: [Move], pos: Position, killers: [Move?]) -> [Move] {
        moves
            .map { ($0, moveScore($0, pos: pos, killers: killers)) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    func moveScore(_ move: Move, pos: Position, killers: [Move?]) -> Int {
        switch move {
        case let .board(from, to, promote):
            if let cap = pos.squares[to] {
                let victim   = PieceValue.onBoard(cap)
                let attacker = pos.squares[from].map { PieceValue.onBoard($0) } ?? 0
                return 10_000 + victim * 10 - attacker
            }
            if promote { return 500 }
        case .drop: break
        }
        if killers.contains(where: { $0 == move }) { return 4_000 }
        return 0
    }

    func captureScore(_ move: Move, _ pos: Position) -> Int {
        guard case let .board(from, to, _) = move, let cap = pos.squares[to] else { return 0 }
        return PieceValue.onBoard(cap) * 10 - (pos.squares[from].map { PieceValue.onBoard($0) } ?? 0)
    }

    func isCapture(_ move: Move, _ pos: Position) -> Bool {
        guard case let .board(_, to, _) = move else { return false }
        return pos.squares[to] != nil
    }

    func isPromotion(_ move: Move) -> Bool {
        guard case let .board(_, _, promote) = move else { return false }
        return promote
    }

    // Null Move Pruning の適用条件: 歩以外の駒が盤上にあるか
    func hasNonPawnPieces(_ pos: Position) -> Bool {
        pos.squares.contains { p in
            guard let p else { return false }
            return p.color == pos.sideToMove && p.type != .pawn && p.type != .king
        }
    }

    // MARK: 静的評価

    func evaluate(_ pos: Position) -> Int {
        var score = 0

        for sq in 0..<Sq.count {
            guard let p = pos.squares[sq] else { continue }
            let v = PieceValue.onBoard(p)
            let sign = p.color == .black ? 1 : -1
            score += sign * v

            if usePositional && !p.promoted {
                let rank = Sq.rank(sq)
                let advance = p.color == .black ? (8 - rank) : rank
                score += sign * advanceTable[p.type.rawValue][advance]

                switch p.type {
                case .bishop:
                    let mob = slidingMobility(pos, sq: sq, color: p.color,
                                             dirs: [(-1,-1),(1,-1),(-1,1),(1,1)])
                    score += sign * mob * 8
                case .rook:
                    let mob = slidingMobility(pos, sq: sq, color: p.color,
                                             dirs: [(-1,0),(1,0),(0,-1),(0,1)])
                    score += sign * mob * 4
                case .lance:
                    let lanceDir = p.color == .black ? (0, -1) : (0, 1)
                    let mob = slidingMobility(pos, sq: sq, color: p.color, dirs: [lanceDir])
                    score += sign * mob * 2
                default: break
                }
            }
        }

        for type in PieceType.allCases where type.isDroppable {
            score += pos.hands[Side.black.rawValue][type.rawValue] * PieceValue.base(type)
            score -= pos.hands[Side.white.rawValue][type.rawValue] * PieceValue.base(type)
        }

        if usePositional {
            score += kingSafety(pos, .black) - kingSafety(pos, .white)
        }

        return pos.sideToMove == .black ? score : -score
    }

    func slidingMobility(_ pos: Position, sq: Int, color: Side, dirs: [(Int, Int)]) -> Int {
        var count = 0
        for (df, dr) in dirs {
            var f = Sq.file(sq) + df
            var r = Sq.rank(sq) + dr
            while Sq.onBoard(file: f, rank: r) {
                let idx = Sq.index(file: f, rank: r)
                if let p = pos.squares[idx] {
                    if p.color != color { count += 1 }
                    break
                }
                count += 1
                f += df; r += dr
            }
        }
        return count
    }

    func kingSafety(_ pos: Position, _ color: Side) -> Int {
        guard let k = pos.squares.firstIndex(where: { $0?.type == .king && $0?.color == color }) else {
            return 0
        }
        let kf = Sq.file(k), kr = Sq.rank(k)
        var s = 0
        for (df, dr) in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)] {
            let f = kf + df, r = kr + dr
            guard Sq.onBoard(file: f, rank: r),
                  let p = pos.squares[Sq.index(file: f, rank: r)], p.color == color else { continue }
            s += (p.type == .gold || p.type == .silver) ? 30 : 0
        }
        s += abs(kf - 4) * 15
        let homeRank = color == .black ? 8 : 0
        s += max(0, 2 - abs(kr - homeRank)) * 10
        return s
    }
}
