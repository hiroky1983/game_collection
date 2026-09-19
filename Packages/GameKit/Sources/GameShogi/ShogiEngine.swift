import Foundation
import Core

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

private struct LCG: RandomNumberGenerator {
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
    let useQuiescence: Bool
    let useBook: Bool
    let timeLimit: TimeInterval
    /// 「入門」か（#1174）。読みの設定は「簡単」と同じまま、着手の選び方だけを変える
    /// （`noviceMove`）。
    let isNovice: Bool
    /// 乱数の種。`nil` なら実プレイ用に毎回違う乱数を使う（テストだけが種を渡して再現する）。
    /// 「入門」以外は乱数を使わないので、この値は見ない。
    let seed: UInt64?

    /// 難易度。**表示している強さの文言と中身が一致していること**（#416 の教訓）:
    ///
    /// | level | 表示 | 探索深さ | 静止探索 | 位置評価 | 定跡 |
    /// |---|---|---|---|---|---|
    /// | -1 | 入門（手なりで指す） | 2 | 無し | 無し | 無し |
    /// | 0 | 簡単（駒得だけ） | 2 | 無し | 無し | 無し |
    /// | 1 | ふつう（囲いを作る） | 4 | 有り | 有り | 無し |
    /// | 2 | むずかしい（定跡＋深読み） | 5 | 有り | 有り | 有り |
    /// | 3 | ガチ（とことん読む） | 7 | 有り | 有り | 有り |
    ///
    /// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
    ///
    /// level 0 は「初心者が勝てる最弱」を作るために、**深さ 2 + 静止探索なし**にしてある（#502。
    /// チェス `SimpleChessEngine` の level 0 と同じ設計）。静止探索を切ると取り合いの途中で
    /// 数え終えるので、1回の取り返しの先にある駒得・駒損が見えなくなる。深さ 2 は残すので、
    /// 「取ったら取り返されるだけ」の只捨ては避ける = 弱いが壊れてはいない、という水準になる。
    /// 深さ 1 まで落とすと只捨てを始めるため採らない（測定結果は #502 / PR に記載）。
    ///
    /// その下の「入門」（#1174）も**深さ 2 のまま**で、`noviceMove` が駒損しない手の中から
    /// 乱択する。深さを削るのではなく選び方を崩すので、只捨てを始める水準には戻らない。
    public init(level: Int = CPUStrength.standard.rawValue) {
        self.init(level: level, seed: nil)
    }

    init(level: Int, seed: UInt64?) {
        let strength = CPUStrength.strength(for: level)
        switch strength {
        case .novice:  (depth, usePositional, useQuiescence, useBook, timeLimit) = (2, false, false, false, 0.5)
        case .easy:    (depth, usePositional, useQuiescence, useBook, timeLimit) = (2, false, false, false, 0.5)
        case .hard:    (depth, usePositional, useQuiescence, useBook, timeLimit) = (5, true,  true,  true,  1.5)
        case .serious: (depth, usePositional, useQuiescence, useBook, timeLimit) = (7, true,  true,  true,  3.0)
        case .normal:  (depth, usePositional, useQuiescence, useBook, timeLimit) = (4, true,  true,  false, 1.0)
        }
        self.isNovice = strength == .novice
        self.seed = seed
    }

    /// テスト・計測用の直接指定。時間切れによる打ち切りを避けたいときは `timeLimit` を大きく取る。
    init(depth: Int, usePositional: Bool, useQuiescence: Bool, useBook: Bool, timeLimit: TimeInterval,
         isNovice: Bool = false, seed: UInt64? = nil) {
        self.depth = depth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        self.useBook = useBook
        self.timeLimit = timeLimit
        self.isNovice = isNovice
        self.seed = seed
    }

    /// 「入門」が許す駒損の幅（#1174）。**歩 1 枚に満たない差**しか許さないので、
    /// 駒を只で捨てる手・取り返される取りは候補に入らない。
    static let noviceMargin = PieceValue.base(.pawn) - 1

    public func bestMove(sfen: String) async -> String? {
        guard var pos = Position.fromSFEN(sfen) else { return nil }
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { return nil }

        if useBook, let booked = OpeningBook.move(for: sfen),
           let m = Move.fromUSI(booked), moves.contains(m) { return booked }

        if isNovice { return noviceMove(&pos, moves: moves)?.usi }

        var ctx = SearchContext(maxDepth: depth, usePositional: usePositional,
                                useQuiescence: useQuiescence, timeLimit: timeLimit)
        return ctx.search(&pos)?.usi
    }

    /// 「入門」の着手（#1174）。読みの深さは「簡単」と同じ（自分の手＋相手の応手＝深さ 2）まま、
    /// **最善から歩 1 枚ぶんも損しない手の中から乱択する**。
    ///
    /// 「簡単」は同じ評価で並んだ手を指し手オーダリング（取る手・成る手が先）で選ぶので、
    /// 駒得の機会は逃さず攻めの手が先に出る。「入門」はそこを崩して手なりに指す。
    /// 駒を只で捨てる手・取り返されるだけの取りは歩 1 枚より大きく損をするため候補に入らず、
    /// 「損はしないが得も狙わない」水準に収まる（弱いが壊れてはいない・#502 と同じ物差し）。
    func noviceMove(_ pos: inout Position, moves: [Move]) -> Move? {
        var ctx = SearchContext(maxDepth: 1, usePositional: usePositional,
                                useQuiescence: useQuiescence, timeLimit: timeLimit)
        // 先にオーダリング（MVV-LVA）しておく。時間切れで1手も読めなかった／全滅した場合の
        // フォールバックに使う（「簡単」の反復深化が時間切れ時に使うのと同じ考え方 = 只捨てではない手）。
        let orderedMoves = ctx.orderMoves(moves, pos: pos, killers: [nil, nil])
        var scored: [(move: Move, score: Int)] = []
        for move in orderedMoves {
            // 期限切れなら打ち切る。ここでチェックしないと、期限切れ後の `negamax` が
            // 「自分の手を指した直後の駒得」だけを返し続け、`noviceMargin` の判定が
            // 取り返しを見ない只捨てを弾けなくなる（#1174 検証指摘）。
            if Date() > ctx.deadline { break }
            let undo = pos.make(move)
            // 全幅で読む（αβ の窓を狭めると「最善から〜以内」を判定できる値が返らない）。
            let score = -ctx.negamax(&pos, depth: depth - 1, alpha: Int.min + 1, beta: Int.max, ply: 1)
            pos.unmake(undo)
            scored.append((move, score))
        }
        guard let best = scored.map(\.score).max() else { return orderedMoves.first }
        let pool = scored.filter { $0.score >= best - Self.noviceMargin }.map(\.move)
        guard !pool.isEmpty else { return orderedMoves.first }
        if let seed {
            var rng = LCG(state: seed)
            return pool[Int.random(in: 0..<pool.count, using: &rng)]
        }
        var rng = SystemRandomNumberGenerator()
        return pool[Int.random(in: 0..<pool.count, using: &rng)]
    }

    func kingSafety(_ pos: Position, _ color: Side) -> Int {
        SearchContext(maxDepth: depth, usePositional: usePositional,
                      useQuiescence: useQuiescence, timeLimit: 0).kingSafety(pos, color)
    }
}

// MARK: - SearchContext（探索の可変状態）

private struct SearchContext {
    let maxDepth: Int
    let usePositional: Bool
    let useQuiescence: Bool
    let deadline: Date
    var killers: [[Move?]]   // killers[ply][0..1]
    var tt: [TTEntry]

    init(maxDepth: Int, usePositional: Bool, useQuiescence: Bool, timeLimit: TimeInterval) {
        self.maxDepth = maxDepth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        self.deadline = Date().addingTimeInterval(timeLimit)
        self.killers = [[Move?]](repeating: [nil, nil], count: maxDepth + 10)
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

    // MARK: αβ ネガマックス + 置換表 + キラー

    mutating func negamax(_ pos: inout Position, depth: Int, alpha: Int, beta: Int, ply: Int) -> Int {
        if Date() > deadline { return evaluate(pos) }

        // 置換表参照
        let hash = pos.zobristHash()
        let ttIdx = Int(hash & UInt64(TT_SIZE - 1))
        let entry = tt[ttIdx]
        if entry.hash == hash && Int(entry.depth) >= depth {
            let s = Int(entry.score)
            switch entry.flag {
            case .exact:
                // fail-hard: bounds 外のスコアをクランプして返す（バグ修正）
                if s >= beta  { return beta  }
                if s <= alpha { return alpha }
                return s
            case .lower:
                if s >= beta  { return beta }
                // 下界でアルファを締める
                // alpha = max(alpha, s)  // 必要なら有効化
            case .upper:
                if s <= alpha { return alpha }
            }
        }

        if depth == 0 {
            return useQuiescence ? quiesce(&pos, alpha: alpha, beta: beta, qdepth: 0) : evaluate(pos)
        }

        let moves = pos.legalMoves()
        if moves.isEmpty { return -PieceValue.base(.king) - depth }

        var alpha = alpha
        var flag: TTFlag = .upper
        let killerSet = ply < killers.count ? killers[ply] : [nil, nil]

        for move in orderMoves(moves, pos: pos, killers: killerSet) {
            let undo = pos.make(move)
            let score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
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

    // MARK: 静止探索（取り合いが落ち着くまで探索）

    mutating func quiesce(_ pos: inout Position, alpha: Int, beta: Int, qdepth: Int) -> Int {
        // 深さ上限と時間チェックで暴走防止
        if qdepth >= 6 || Date() > deadline { return evaluate(pos) }

        let standPat = evaluate(pos)
        if standPat >= beta { return beta }

        // デルタ枝刈り: 最高の取り駒（竜=1300）を加えても alpha に届かない場合はスキップ
        // alpha - 1300 はオーバーフローするので standPat + 1300 < alpha の形にする
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
                let advance = p.color == .black ? (8 - rank) : rank  // 0=自陣、8=相手陣
                score += sign * advanceTable[p.type.rawValue][advance]

                // 長距離駒のモビリティ（角道・飛車先が開いているほど高評価）
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

    // 長距離駒が dirs 方向へ進める升目数（取れる相手駒も1カウント）
    func slidingMobility(_ pos: Position, sq: Int, color: Side, dirs: [(Int, Int)]) -> Int {
        var count = 0
        for (df, dr) in dirs {
            var f = Sq.file(sq) + df
            var r = Sq.rank(sq) + dr
            while Sq.onBoard(file: f, rank: r) {
                let idx = Sq.index(file: f, rank: r)
                if let p = pos.squares[idx] {
                    if p.color != color { count += 1 }  // 取れる相手駒
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
