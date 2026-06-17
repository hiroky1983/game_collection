import Foundation

/// 将棋 AI の境界（USI 風）。MVP は自前 `SimpleMinimaxEngine`、Phase 2 で本格エンジンに差し替える。
public protocol ShogiEngine: Sendable {
    /// SFEN 局面に対する最善手を USI 文字列で返す。合法手が無ければ nil。
    func bestMove(sfen: String) async -> String?
}

/// 駒の評価値（歩 = 100 を基準, centipawn 風）。成り駒・持ち駒もこの表で評価する。
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

    /// 盤上の駒（成りを加味）。
    static func onBoard(_ p: Piece) -> Int {
        if p.promoted {
            switch p.type {
            case .pawn, .lance, .knight, .silver: return 600 // 成って金相当
            case .bishop: return 1200
            case .rook: return 1300
            default: break
            }
        }
        return base(p.type)
    }
}

/// ミニマックス + αβ + 簡易評価。難易度で読みの深さ・評価・定跡の有無を切り替える。
public struct SimpleMinimaxEngine: ShogiEngine {
    let depth: Int
    let usePositional: Bool  // 玉の安全度・囲い評価を使う
    let useBook: Bool        // 定跡ブックを使う
    let timeLimit: TimeInterval // 1 手あたりの思考時間上限（秒）

    /// level 0 = 弱（駒得のみ・2手）/ 1 = 普通（囲い評価・2手）/ 2 = 強（定跡＋囲い・3手）。
    public init(level: Int = 1) {
        switch level {
        case 0:  (depth, usePositional, useBook, timeLimit) = (2, false, false, 0.3)
        case 2:  (depth, usePositional, useBook, timeLimit) = (3, true, true, 0.8)
        default: (depth, usePositional, useBook, timeLimit) = (2, true, false, 0.5)
        }
    }

    public func bestMove(sfen: String) async -> String? {
        guard var pos = Position.fromSFEN(sfen) else { return nil }
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { return nil }

        // 定跡: 現局面が登録されていれば、その手（合法なら）を指す。
        if useBook, let booked = OpeningBook.move(for: sfen),
           let m = Move.fromUSI(booked), moves.contains(m) {
            return booked
        }

        // 反復深化＋時間制限。深さ 1 から順に深め、制限時間を超えたら直前の深さの結果を使う。
        let deadline = Date().addingTimeInterval(timeLimit)
        var orderedRoot = ordered(moves, in: pos)
        var best: Move? = orderedRoot.first

        var d = 1
        while d <= depth {
            var localBest: Move?
            var bestScore = Int.min + 1
            var alpha = Int.min + 1
            let beta = Int.max
            var aborted = false
            for move in orderedRoot {
                if Date() > deadline { aborted = true; break }
                let undo = pos.make(move)
                let score = -negamax(&pos, depth: d - 1, alpha: -beta, beta: -alpha, deadline: deadline)
                pos.unmake(undo)
                if score > bestScore { bestScore = score; localBest = move }
                if score > alpha { alpha = score }
            }
            // 深さ d を最後まで読み切ったときだけ採用。最善手を次の反復で先頭に。
            if !aborted, let lb = localBest {
                best = lb
                orderedRoot.removeAll { $0 == lb }
                orderedRoot.insert(lb, at: 0)
            }
            if aborted { break }
            d += 1
        }
        return best?.usi
    }

    /// 手番側視点のスコアを返すネガマックス（αβ つき）。制限時間を超えたら静的評価で打ち切る。
    private func negamax(_ pos: inout Position, depth: Int, alpha: Int, beta: Int, deadline: Date) -> Int {
        if depth == 0 || Date() > deadline {
            return evaluate(pos, for: pos.sideToMove)
        }
        let moves = pos.legalMoves()
        if moves.isEmpty {
            return -PieceValue.base(.king) - depth // 詰み（早い詰みほど評価を強く）
        }
        var alpha = alpha
        for move in ordered(moves, in: pos) {
            let undo = pos.make(move)
            let score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, deadline: deadline)
            pos.unmake(undo)
            if score >= beta { return beta }   // βカット
            if score > alpha { alpha = score }
        }
        return alpha
    }

    /// 手の並べ替え: 駒を取る手（取る駒が大きいほど先）→ 成り → その他。αβの枝刈り効率を上げる。
    private func ordered(_ moves: [Move], in pos: Position) -> [Move] {
        moves.sorted { a, b in orderKey(a, pos) > orderKey(b, pos) }
    }

    private func orderKey(_ move: Move, _ pos: Position) -> Int {
        switch move {
        case let .board(_, to, promote):
            var key = 0
            if let cap = pos.squares[to] { key += PieceValue.onBoard(cap) }
            if promote { key += 50 }
            return key
        case .drop:
            return 0
        }
    }

    // MARK: - 評価

    /// 指定手番から見た評価（駒得＋囲い）。
    private func evaluate(_ pos: Position, for side: Side) -> Int {
        var score = 0 // 先手視点
        for sq in 0..<Sq.count {
            guard let p = pos.squares[sq] else { continue }
            let v = PieceValue.onBoard(p)
            score += p.color == .black ? v : -v
        }
        for type in PieceType.allCases where type.isDroppable {
            score += pos.hands[Side.black.rawValue][type.rawValue] * PieceValue.base(type)
            score -= pos.hands[Side.white.rawValue][type.rawValue] * PieceValue.base(type)
        }
        if usePositional {
            score += kingSafety(pos, .black) - kingSafety(pos, .white)
        }
        return side == .black ? score : -score
    }

    /// 玉の安全度（＝囲い）。玉の周囲の味方（特に金銀）と、玉が中央から離れているほど高い。
    func kingSafety(_ pos: Position, _ color: Side) -> Int {
        guard let k = pos.squares.firstIndex(where: { $0?.type == .king && $0?.color == color }) else {
            return 0
        }
        let kf = Sq.file(k), kr = Sq.rank(k)
        var s = 0
        for (df, dr) in [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)] {
            let f = kf + df, r = kr + dr
            guard Sq.onBoard(file: f, rank: r),
                  let p = pos.squares[Sq.index(file: f, rank: r)], p.color == color else { continue }
            s += (p.type == .gold || p.type == .silver) ? 30 : 15 // 金銀の守りを重く
        }
        s += abs(kf - 4) * 15 // 端寄り（5筋から離れる）ほど囲い向き
        // 玉が初期段に近い（自陣に居る）ほど安全。
        let homeRank = color == .black ? 8 : 0
        s += max(0, 2 - abs(kr - homeRank)) * 10
        return s
    }
}
