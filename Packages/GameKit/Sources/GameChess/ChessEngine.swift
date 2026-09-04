import Foundation

/// チェス AI の境界（UCI 風）。将棋の `ShogiEngine` と同じ形にしてある。
public protocol ChessEngine: Sendable {
    func bestMove(fen: String) async -> String?
}

// MARK: - 駒の価値

enum ChessPieceValue {
    static func base(_ type: ChessPieceType) -> Int {
        switch type {
        case .pawn:   return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook:   return 500
        case .queen:  return 900
        case .king:   return 20_000
        }
    }
}

/// 詰みの評価値。`ply` を引いて**近い詰みほど高く**評価する（長引かせずに詰ませる）。
/// `Int.min` を使わないのは、ネガマックスで符号を反転するときに溢れるため。
private let mateScore = 1_000_000

// MARK: - 位置評価テーブル

/// 駒の配置に対する加点表。**数表を他所から写さず、方針から計算して作る**（#462 の権利確認）。
///
/// 方針は 4 つだけ:
/// 1. 中央に近いほど良い（利きが増える）
/// 2. ポーンは前進するほど良い（成りに近づく）。ただし中央のポーンを厚めに見る
/// 3. ナイトは端で極端に弱くなる（利きが盤外に落ちる）ので中央寄せを強めに掛ける
/// 4. キングは中盤は自陣の端で安全、終盤は中央が強い（駒が減れば自ら戦える）
///
/// 添字は**白から見た** rank index。黒は `mirrored(_:)` で上下を反転して引く。
enum ChessPieceSquareTable {
    /// 中央からの遠さ（0 = 中央 4 マス、3 = 隅）。
    private static func centerDistance(_ square: Int) -> Int {
        let f = ChessSquare.file(square), r = ChessSquare.rank(square)
        return max(abs(f * 2 - 7), abs(r * 2 - 7)) / 2
    }

    private static func build(_ value: @escaping (_ file: Int, _ rank: Int, _ square: Int) -> Int) -> [Int] {
        (0..<ChessSquare.count).map { value(ChessSquare.file($0), ChessSquare.rank($0), $0) }
    }

    /// 中央寄せの基本形（中央 +weight、隅 -weight）。
    private static func centered(_ weight: Int) -> [Int] {
        build { _, _, sq in weight - centerDistance(sq) * ((weight * 2) / 3) }
    }

    static let pawn: [Int] = build { file, rank, _ in
        // 前進度（白のポーンは rank index が小さいほど前）。
        let advance = 6 - rank                    // 初期段 (rank 6) が 0、7段目が 5
        guard advance >= 0 else { return 0 }
        // 中央 2 筋（d/e）は序盤の陣形の要なので厚めに見る。
        let centerFile = (file == 3 || file == 4) ? 12 : (file == 2 || file == 5) ? 4 : 0
        return advance * advance * 2 + centerFile
    }

    static let knight: [Int] = centered(24)
    static let bishop: [Int] = centered(12)
    static let queen: [Int] = centered(6)

    static let rook: [Int] = build { file, rank, _ in
        // 7段目（相手陣の 2段目・rank index 1）のルークは強い。中央 2 筋も僅かに加点。
        (rank == 1 ? 22 : 0) + ((file == 3 || file == 4) ? 6 : 0)
    }

    /// 中盤のキング: 端に寄って自陣に居るほど安全。
    static let kingMiddle: [Int] = build { file, rank, _ in
        let home = rank >= 6 ? 18 : (rank == 5 ? 0 : -24)
        let corner = (file <= 2 || file >= 5) ? 14 : -10
        return home + corner
    }

    /// 終盤のキング: 中央に出るほど強い。
    static let kingEnd: [Int] = centered(30)

    /// 黒の駒が引くための上下反転。
    @inline(__always) static func mirrored(_ square: Int) -> Int {
        ChessSquare.index(file: ChessSquare.file(square), rank: 7 - ChessSquare.rank(square))
    }

    /// `color` の駒がそのマスに居ることの加点。
    @inline(__always) static func value(
        _ table: [Int], square: Int, color: ChessColor
    ) -> Int {
        table[color == .white ? square : mirrored(square)]
    }
}

// MARK: - Zobrist ハッシュ

private struct ChessLCG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 33)
    }
}

private enum ChessZobrist {
    // [pieceType 0-5][color 0-1][square 0-63]
    static let piece: [[[UInt64]]] = {
        var rng = ChessLCG(state: 0x9E37_79B9_7F4A_7C15)
        var t = [[[UInt64]]](
            repeating: [[UInt64]](repeating: [UInt64](repeating: 0, count: 64), count: 2),
            count: 6)
        for pt in 0..<6 { for c in 0..<2 { for sq in 0..<64 { t[pt][c][sq] = rng.next() } } }
        return t
    }()

    static let castling: [UInt64] = {
        var rng = ChessLCG(state: 0xC2B2_AE3D_27D4_EB4F)
        return (0..<16).map { _ in rng.next() }
    }()

    /// アンパッサン標的は**筋だけ**を混ぜる（同じ筋なら効果は同じで、段は手番から決まる）。
    static let enPassantFile: [UInt64] = {
        var rng = ChessLCG(state: 0x1656_67B1_9E37_79F9)
        return (0..<8).map { _ in rng.next() }
    }()

    static let whiteToMove: UInt64 = {
        var rng = ChessLCG(state: 0x8521_4F35_2A7C_11D3)
        return rng.next()
    }()
}

extension ChessPosition {
    func zobristHash() -> UInt64 {
        var h: UInt64 = 0
        for (sq, p) in squares.enumerated() {
            guard let p else { continue }
            h ^= ChessZobrist.piece[p.type.rawValue][p.color.rawValue][sq]
        }
        h ^= ChessZobrist.castling[castling.rawValue & 0xF]
        if let ep = enPassant { h ^= ChessZobrist.enPassantFile[ChessSquare.file(ep)] }
        if sideToMove == .white { h ^= ChessZobrist.whiteToMove }
        return h
    }
}

// MARK: - 置換表

private enum ChessTTFlag: UInt8 { case exact, lower, upper }

private struct ChessTTEntry {
    var hash: UInt64 = 0
    var score: Int32 = 0
    var depth: Int8 = -1
    var flag: ChessTTFlag = .exact
}

private let chessTTSize = 1 << 18  // 256K エントリ

// MARK: - Engine（公開 API）

public struct SimpleChessEngine: ChessEngine {
    let depth: Int
    let usePositional: Bool
    let useQuiescence: Bool
    let useBook: Bool
    let timeLimit: TimeInterval

    /// 難易度。**表示している強さの文言と中身が一致していること**（#416 の教訓）:
    ///
    /// | level | 表示 | 探索深さ | 静止探索 | 位置評価 | 定跡 |
    /// |---|---|---|---|---|---|
    /// | 0 | 弱（駒の損得だけ） | 2 | 無し | 無し | 無し |
    /// | 1 | 普通（駒の働きも見る） | 3 | 有り | 有り | 無し |
    /// | 2 | 強（定跡＋深読み） | 5 | 有り | 有り | 有り |
    ///
    /// level 0 で静止探索を切っているのは「初心者が勝てる最弱」を作るため。
    /// 静止探索が無いと取り合いの途中で数え終えるので、駒の只捨てを見落とす。
    public init(level: Int = 1) {
        switch level {
        case 0:  (depth, usePositional, useQuiescence, useBook, timeLimit) = (2, false, false, false, 0.5)
        case 2:  (depth, usePositional, useQuiescence, useBook, timeLimit) = (5, true, true, true, 2.0)
        default: (depth, usePositional, useQuiescence, useBook, timeLimit) = (3, true, true, false, 1.0)
        }
    }

    /// テスト用の直接指定。時間切れによる打ち切りを避けたいときに `timeLimit` を大きく取る。
    init(depth: Int, usePositional: Bool, useQuiescence: Bool, useBook: Bool, timeLimit: TimeInterval) {
        self.depth = depth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        self.useBook = useBook
        self.timeLimit = timeLimit
    }

    public func bestMove(fen: String) async -> String? {
        guard var pos = ChessPosition.fromFEN(fen) else { return nil }
        guard !pos.legalMoves().isEmpty else { return nil }

        if useBook, let booked = ChessOpeningBook.move(for: fen),
           let m = ChessMove.fromUCI(booked), pos.legalMoves().contains(m) { return booked }

        var ctx = ChessSearchContext(
            maxDepth: depth, usePositional: usePositional,
            useQuiescence: useQuiescence, timeLimit: timeLimit
        )
        return ctx.search(&pos)?.uci
    }

    /// 静的評価（テストから覗く用）。手番側から見た点数。
    func evaluate(_ pos: ChessPosition) -> Int {
        ChessSearchContext(
            maxDepth: depth, usePositional: usePositional,
            useQuiescence: useQuiescence, timeLimit: 0
        ).evaluate(pos)
    }
}

// MARK: - SearchContext（探索の可変状態）

struct ChessSearchContext {
    let maxDepth: Int
    let usePositional: Bool
    let useQuiescence: Bool
    let deadline: Date
    var killers: [[ChessMove?]]
    private var tt: [ChessTTEntry]

    init(maxDepth: Int, usePositional: Bool, useQuiescence: Bool, timeLimit: TimeInterval) {
        self.maxDepth = maxDepth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        self.deadline = Date().addingTimeInterval(timeLimit)
        self.killers = [[ChessMove?]](repeating: [nil, nil], count: maxDepth + 10)
        self.tt = [ChessTTEntry](repeating: ChessTTEntry(), count: chessTTSize)
    }

    // MARK: 反復深化

    mutating func search(_ pos: inout ChessPosition) -> ChessMove? {
        var orderedMoves = orderMoves(pos.legalMoves(), pos: pos, killers: [nil, nil])
        var best: ChessMove? = orderedMoves.first

        for d in 1...maxDepth {
            if Date() > deadline { break }
            var localBest: ChessMove?
            var bestScore = -mateScore * 2
            var alpha = -mateScore * 2
            let beta = mateScore * 2
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
                // 次の深さでは前回の最善手から読む（αβ の刈り込みが最も効く並び）。
                orderedMoves.removeAll { $0 == lb }
                orderedMoves.insert(lb, at: 0)
            }
            if aborted { break }
        }
        return best
    }

    // MARK: αβ ネガマックス + 置換表 + キラー手

    mutating func negamax(
        _ pos: inout ChessPosition, depth: Int, alpha: Int, beta: Int, ply: Int
    ) -> Int {
        if Date() > deadline { return evaluate(pos) }

        // 50手ルールに達した局面は引き分け。ここを見ないと、探索が「取れないまま
        // 延々と駒を往復させる手順」を勝ち筋と誤認する。
        if pos.halfmoveClock >= 100 { return 0 }

        let hash = pos.zobristHash()
        let ttIdx = Int(hash & UInt64(chessTTSize - 1))
        let entry = tt[ttIdx]
        if entry.hash == hash && Int(entry.depth) >= depth {
            let s = Int(entry.score)
            switch entry.flag {
            case .exact:
                // fail-hard: bounds の外に出る値はクランプして返す。
                if s >= beta { return beta }
                if s <= alpha { return alpha }
                return s
            case .lower:
                if s >= beta { return beta }
            case .upper:
                if s <= alpha { return alpha }
            }
        }

        let moves = pos.legalMoves()
        if moves.isEmpty {
            // **チェックメイトとステイルメイトをここで分ける**。将棋のように
            // 「合法手ゼロ＝負け」で括ると、ステイルメイト（引き分け）を負けと読んで
            // 勝てる終盤をわざと膠着させる打ち方になる。
            return pos.isKingInCheck(pos.sideToMove) ? -(mateScore - ply) : 0
        }

        if depth <= 0 {
            return useQuiescence ? quiesce(&pos, alpha: alpha, beta: beta, qdepth: 0) : evaluate(pos)
        }

        var alpha = alpha
        var flag: ChessTTFlag = .upper
        let killerSet = ply < killers.count ? killers[ply] : [nil, nil]

        for move in orderMoves(moves, pos: pos, killers: killerSet) {
            let capture = isCapture(move, pos)
            let undo = pos.make(move)
            let score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            pos.unmake(undo)

            if score >= beta {
                if ply < killers.count && !capture {
                    killers[ply][1] = killers[ply][0]
                    killers[ply][0] = move
                }
                tt[ttIdx] = ChessTTEntry(
                    hash: hash, score: Int32(clamping: beta),
                    depth: Int8(clamping: depth), flag: .lower)
                return beta
            }
            if score > alpha {
                alpha = score
                flag = .exact
            }
        }

        tt[ttIdx] = ChessTTEntry(
            hash: hash, score: Int32(clamping: alpha),
            depth: Int8(clamping: depth), flag: flag)
        return alpha
    }

    // MARK: 静止探索（取り合いが落ち着くまで読む）

    mutating func quiesce(
        _ pos: inout ChessPosition, alpha: Int, beta: Int, qdepth: Int
    ) -> Int {
        if qdepth >= 6 || Date() > deadline { return evaluate(pos) }

        let standPat = evaluate(pos)
        if standPat >= beta { return beta }
        // デルタ枝刈り: 最大の取り駒（クイーン 900）を足しても alpha に届かないなら見る意味がない。
        if standPat + ChessPieceValue.base(.queen) < alpha { return alpha }

        var alpha = max(alpha, standPat)
        let captures = pos.legalMoves().filter { isCapture($0, pos) || $0.promotion != nil }
        for move in captures.sorted(by: { captureScore($0, pos) > captureScore($1, pos) }) {
            let undo = pos.make(move)
            let score = -quiesce(&pos, alpha: -beta, beta: -alpha, qdepth: qdepth + 1)
            pos.unmake(undo)
            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    // MARK: 指し手オーダリング（MVV-LVA + キラー手）

    func orderMoves(_ moves: [ChessMove], pos: ChessPosition, killers: [ChessMove?]) -> [ChessMove] {
        moves
            .map { ($0, moveScore($0, pos: pos, killers: killers)) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    func moveScore(_ move: ChessMove, pos: ChessPosition, killers: [ChessMove?]) -> Int {
        if let victim = capturedPiece(move, pos) {
            let attacker = pos.squares[move.from].map { ChessPieceValue.base($0.type) } ?? 0
            return 100_000 + ChessPieceValue.base(victim.type) * 10 - attacker
        }
        if let promotion = move.promotion { return 90_000 + ChessPieceValue.base(promotion) }
        if killers.contains(where: { $0 == move }) { return 40_000 }
        return 0
    }

    func captureScore(_ move: ChessMove, _ pos: ChessPosition) -> Int {
        let promotion = move.promotion.map { ChessPieceValue.base($0) } ?? 0
        guard let victim = capturedPiece(move, pos) else { return promotion }
        let attacker = pos.squares[move.from].map { ChessPieceValue.base($0.type) } ?? 0
        return ChessPieceValue.base(victim.type) * 10 - attacker + promotion
    }

    /// この手で取られる駒。**アンパッサンでは `to` が空**なので、盤を直接見るだけでは取り逃がす。
    func capturedPiece(_ move: ChessMove, _ pos: ChessPosition) -> ChessPiece? {
        if let occupant = pos.squares[move.to] { return occupant }
        guard pos.isEnPassant(move) else { return nil }
        return pos.squares[ChessSquare.index(
            file: ChessSquare.file(move.to), rank: ChessSquare.rank(move.from))]
    }

    func isCapture(_ move: ChessMove, _ pos: ChessPosition) -> Bool {
        capturedPiece(move, pos) != nil
    }

    // MARK: 静的評価（手番側から見た点数）

    func evaluate(_ pos: ChessPosition) -> Int {
        var score = 0
        var nonPawnMaterial = 0

        for sq in 0..<ChessSquare.count {
            guard let p = pos.squares[sq] else { continue }
            let sign = p.color == .white ? 1 : -1
            score += sign * ChessPieceValue.base(p.type)
            if p.type != .pawn && p.type != .king { nonPawnMaterial += ChessPieceValue.base(p.type) }
        }

        guard usePositional else { return pos.sideToMove == .white ? score : -score }

        // 終盤かどうかは「キングとポーンを除く駒の総額」で決める。キングの評価表を
        // 中盤用（隅に隠れる）と終盤用（中央へ出る）で切り替えるため。
        let isEndgame = nonPawnMaterial <= 2 * ChessPieceValue.base(.rook)

        for sq in 0..<ChessSquare.count {
            guard let p = pos.squares[sq] else { continue }
            let sign = p.color == .white ? 1 : -1
            let table: [Int]
            switch p.type {
            case .pawn:   table = ChessPieceSquareTable.pawn
            case .knight: table = ChessPieceSquareTable.knight
            case .bishop: table = ChessPieceSquareTable.bishop
            case .rook:   table = ChessPieceSquareTable.rook
            case .queen:  table = ChessPieceSquareTable.queen
            case .king:   table = isEndgame ? ChessPieceSquareTable.kingEnd : ChessPieceSquareTable.kingMiddle
            }
            score += sign * ChessPieceSquareTable.value(table, square: sq, color: p.color)
        }

        // ビショップ 2 枚は開いた盤面で強い（定番の加点）。
        score += (bishopCount(pos, .white) >= 2 ? 30 : 0) - (bishopCount(pos, .black) >= 2 ? 30 : 0)
        if !isEndgame {
            score += kingShield(pos, .white) - kingShield(pos, .black)
        }
        return pos.sideToMove == .white ? score : -score
    }

    private func bishopCount(_ pos: ChessPosition, _ color: ChessColor) -> Int {
        pos.squares.reduce(into: 0) { n, p in
            if let p, p.color == color, p.type == .bishop { n += 1 }
        }
    }

    /// キングの前のポーンの壁。中盤にキングを裸で放置しないための最小限の見立て。
    func kingShield(_ pos: ChessPosition, _ color: ChessColor) -> Int {
        guard let k = pos.kingSquare(color) else { return 0 }
        let kf = ChessSquare.file(k), kr = ChessSquare.rank(k)
        var s = 0
        for df in [-1, 0, 1] {
            let f = kf + df, r = kr + color.forward
            guard ChessSquare.onBoard(file: f, rank: r) else { continue }
            if let p = pos.squares[ChessSquare.index(file: f, rank: r)],
               p.color == color, p.type == .pawn { s += 14 }
        }
        return s
    }
}
