import Foundation
import CoreEngine

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
            case .bishop: return 1050
            case .rook: return 1550
            default: break
            }
        }
        return base(p.type)
    }
}

// MARK: - Zobrist Hashing

private enum Zobrist {
    // [pieceType 0-7][color 0-1][promoted 0-1][square 0-80]
    static let piece: [[[[UInt64]]]] = {
        var rng = MMIXRandom(state: 0xDEAD_BEEF_CAFE_BABE)
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
        var rng = MMIXRandom(state: 0xCAFE_BABE_DEAD_BEEF)
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
        var rng = MMIXRandom(state: 0x1234_5678_9ABC_DEF0)
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
    /// この局面で最善と分かっている手（#1134）。次にこの局面へ来たとき、指し手オーダリングの
    /// 最優先候補にする。反復深化の各深さ・再訪問局面の両方でベータカットの効率が上がる。
    var bestMove: Move?
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
    /// | level | 表示 | 探索深さ上限 | 静止探索 | 位置評価 | 定跡 |
    /// |---|---|---|---|---|---|
    /// | -1 | 入門（手なりで指す） | 2 | 無し | 無し | 無し |
    /// | 0 | 簡単（駒得だけ） | 2 | 無し | 無し | 無し |
    /// | 1 | ふつう（囲いを作る） | 4 | 有り | 有り | 無し |
    /// | 2 | むずかしい（定跡＋深読み） | 32 | 有り | 有り | 有り |
    /// | 3 | ガチ（とことん読む） | 7 | 有り | 有り | 有り |
    ///
    /// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
    ///
    /// 「むずかしい」の探索深さ上限は #1134 で 5 → 32 に上げた。**持ち時間 1.5 秒は変えていない**——
    /// 反復深化は深さ上限か `timeLimit` のどちらか早く来た方で打ち切るため、実測（`swiftc -O`）では
    /// 旧設定（深さ 5 固定）が 0.007〜0.63 秒で探索を終え、残りの持ち時間を使い切っていなかった。
    /// 上限を外して時間いっぱい反復深化を続けさせることで、同じ持ち時間のまま深く読む（詳細は PR）。
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
        case .hard:    (depth, usePositional, useQuiescence, useBook, timeLimit) = (32, true,  true,  true,  1.5)
        case .serious: (depth, usePositional, useQuiescence, useBook, timeLimit) = (7, true,  true,  true,  3.0)
        case .normal:  (depth, usePositional, useQuiescence, useBook, timeLimit) = (4, true,  true,  false, 1.0)
        }
        self.isNovice = strength == .novice
        self.seed = seed
    }

    /// テスト・計測用の直接指定。時間切れによる打ち切りを構造的に無くしたいときは
    /// `timeLimit: .infinity` を渡す（`.distantFuture` を締切にする。#1187）。
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
    /// 時間切れでも最低限これだけは評価してから選ぶ（#1196）。1件も評価できないまま
    /// `orderedMoves.first`（安全性未確認）へ逃げると `noviceMargin` の駒損しない保証を
    /// すり抜ける。1件だけ評価しても自分自身としか比較できず実質フォールバックと変わらない
    /// ため、比較に足る数（負けている手を弾ける最低限）を確保する。depth 1 の negamax なので
    /// 数手ぶんの追加コストは無視できる。
    static let minNoviceEvaluations = 3

    func noviceMove(_ pos: inout Position, moves: [Move]) -> Move? {
        var ctx = SearchContext(maxDepth: 1, usePositional: usePositional,
                                useQuiescence: useQuiescence, timeLimit: timeLimit)
        // 先にオーダリング（MVV-LVA）しておく。時間切れで1手も読めなかった／全滅した場合の
        // フォールバックに使う（「簡単」の反復深化が時間切れ時に使うのと同じ考え方 = 只捨てではない手）。
        let orderedMoves = ctx.orderMoves(moves, pos: pos, killers: [nil, nil], ttMove: nil)
        var scored: [(move: Move, score: Int)] = []
        let originalDeadline = ctx.deadline
        for (index, move) in orderedMoves.enumerated() {
            let withinSafetyFloor = index < Self.minNoviceEvaluations
            // 期限切れなら打ち切る。ここでチェックしないと、期限切れ後の `negamax` が
            // 「自分の手を指した直後の駒得」だけを返し続け、`noviceMargin` の判定が
            // 取り返しを見ない只捨てを弾けなくなる（#1174 検証指摘）。ただし安全フロアの
            // 範囲内は期限を無視して必ず評価する（#1196）。
            if !withinSafetyFloor, Date() > originalDeadline { break }
            // 安全フロアの範囲内は `negamax`（と内部で呼ぶ `quiesce`）の期限判定も無効化する。
            // `deadline` だけ外側で無視しても、`negamax` は自分の先頭で期限切れなら
            // `evaluate(pos)`（相手の応手を読まない静的評価）を即返すため、取り返される
            // 駒取りが安全フロアの候補に残ってしまう（CodeRabbit 指摘）。
            ctx.deadline = withinSafetyFloor ? .distantFuture : originalDeadline
            let undo = pos.make(move)
            // 全幅で読む（αβ の窓を狭めると「最善から〜以内」を判定できる値が返らない）。
            let score = -ctx.negamax(&pos, depth: depth - 1, alpha: Int.min + 1, beta: Int.max, ply: 1)
            pos.unmake(undo)
            ctx.deadline = originalDeadline
            // negamax の探索中に期限切れになった場合、返る値は不完全な評価（中断時点の
            // evaluate(pos)）なので候補に入れない（CodeRabbit 指摘・PR #1190）。安全フロアの
            // 範囲内は不完全でも比較材料として使う（同上の理由）。
            if !withinSafetyFloor, Date() > originalDeadline { break }
            scored.append((move, score))
        }
        guard let best = scored.map(\.score).max() else { return orderedMoves.first }
        let pool = scored.filter { $0.score >= best - Self.noviceMargin }.map(\.move)
        guard !pool.isEmpty else { return orderedMoves.first }
        if let seed {
            var rng = SplitMix64(seed: seed)
            return pool[Int.random(in: 0..<pool.count, using: &rng)]
        }
        var rng = SystemRandomNumberGenerator()
        return pool[Int.random(in: 0..<pool.count, using: &rng)]
    }

    /// 囲いの堅さ（shelter）だけ。自己対戦テストが「囲いが進んだか」を見るための口で、
    /// 攻め駒の接近（`kingDanger`）は含めない。
    func kingSafety(_ pos: Position, _ color: Side) -> Int {
        SearchContext(maxDepth: depth, usePositional: usePositional,
                      useQuiescence: useQuiescence, timeLimit: 0).kingShelter(pos, color)
    }

    func kingDanger(_ pos: Position, _ color: Side) -> Int {
        SearchContext(maxDepth: depth, usePositional: usePositional,
                      useQuiescence: useQuiescence, timeLimit: 0).kingDanger(pos, color)
    }
}

// MARK: - SearchContext（探索の可変状態）

private struct SearchContext {
    let maxDepth: Int
    let usePositional: Bool
    let useQuiescence: Bool
    var deadline: Date
    var killers: [[Move?]]   // killers[ply][0..1]
    var tt: [TTEntry]
    /// クワイエット手（駒を取らない手）がベータカットを引き起こした回数（#1134）。
    /// 盤上の移動は `from * 81 + to`、打ちは `81*81 + type.rawValue*81 + to` に積む。
    /// 反復深化の途中で消さない（深い反復ほど過去の実績を活かせる）。
    var history: [Int]

    init(maxDepth: Int, usePositional: Bool, useQuiescence: Bool, timeLimit: TimeInterval) {
        self.maxDepth = maxDepth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        // `timeLimit: .infinity` は「打ち切りを構造的に無くす」ための特別値（#1187）。
        // `Date().addingTimeInterval(.infinity)` の結果に依存せず、明示的に `.distantFuture` にする。
        self.deadline = timeLimit.isFinite ? Date().addingTimeInterval(timeLimit) : .distantFuture
        self.killers = [[Move?]](repeating: [nil, nil], count: maxDepth + 10)
        self.tt = [TTEntry](repeating: TTEntry(), count: TT_SIZE)
        self.history = [Int](repeating: 0, count: 81 * 81 + 8 * 81)
    }

    private func historyIndex(_ move: Move) -> Int {
        switch move {
        case let .board(from, to, _): return from * 81 + to
        case let .drop(type, to): return 81 * 81 + type.rawValue * 81 + to
        }
    }

    // MARK: 反復深化

    mutating func search(_ pos: inout Position) -> Move? {
        var orderedMoves = orderMoves(pos.legalMoves(), pos: pos, killers: [nil, nil], ttMove: nil)
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
        let ttMove: Move? = entry.hash == hash ? entry.bestMove : nil
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
        var bestMoveHere: Move?
        let killerSet = ply < killers.count ? killers[ply] : [nil, nil]

        for move in orderMoves(moves, pos: pos, killers: killerSet, ttMove: ttMove) {
            let undo = pos.make(move)
            let score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            pos.unmake(undo)

            if score >= beta {
                if ply < killers.count && !isCapture(move, pos) {
                    killers[ply][1] = killers[ply][0]
                    killers[ply][0] = move
                    history[historyIndex(move)] += depth * depth
                }
                tt[ttIdx] = TTEntry(hash: hash, score: Int32(beta), depth: Int8(clamping: depth), flag: .lower, bestMove: move)
                return beta
            }
            if score > alpha {
                alpha = score
                flag = .exact
                bestMoveHere = move
            }
        }

        tt[ttIdx] = TTEntry(hash: hash, score: Int32(alpha), depth: Int8(clamping: depth), flag: flag, bestMove: bestMoveHere)
        return alpha
    }

    // MARK: 静止探索（取り合いが落ち着くまで探索）

    mutating func quiesce(_ pos: inout Position, alpha: Int, beta: Int, qdepth: Int) -> Int {
        // 深さ上限と時間チェックで暴走防止
        if qdepth >= 6 || Date() > deadline { return evaluate(pos) }

        let standPat = evaluate(pos)
        if standPat >= beta { return beta }

        // デルタ枝刈り: 最高の取り駒（竜=1550）を加えても alpha に届かない場合はスキップ
        // alpha - 1550 はオーバーフローするので standPat + 1550 < alpha の形にする
        if standPat + 1550 < alpha { return alpha }

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

    func orderMoves(_ moves: [Move], pos: Position, killers: [Move?], ttMove: Move?) -> [Move] {
        moves
            .map { ($0, moveScore($0, pos: pos, killers: killers, ttMove: ttMove)) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// 置換表の最善手（#1134）を最優先にする。取る手・成る手・キラーの順位付けは変えていない。
    func moveScore(_ move: Move, pos: Position, killers: [Move?], ttMove: Move?) -> Int {
        if let ttMove, move == ttMove { return 100_000 }
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
        // ヒストリーヒューリスティック（#1134）: 取る手・キラーの帯より下に収める。
        return min(history[historyIndex(move)], 3_000)
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
            score += kingShelter(pos, .black) - kingDanger(pos, .black)
                   - kingShelter(pos, .white) + kingDanger(pos, .white)
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

    /// 玉の安全度（#1134 で駒の連携・遠くからの利きを精緻化）。
    ///
    /// 元は「隣接8マスの金銀だけ+30」という粗い判定だった。ここでは:
    /// 1. 隣接マスの守り駒を種類別に重み付け（金・銀を厚く、桂・香・歩・大駒も薄く評価）。
    /// 2. 2マス圏（美濃囲い・矢倉などの外側の金銀）も軽く評価する。
    /// 3. 金銀が2枚以上揃っている（=連携している）ときに追加ボーナス。単独の守り駒より
    ///    連携した囲いのほうが実戦的に堅いという知見を反映する。
    /// 4. 大駒（飛・角・馬・龍）の利きが玉まで素通しになっていないか（`kingExposure`）を見る。
    func kingShelter(_ pos: Position, _ color: Side) -> Int {
        guard let k = pos.squares.firstIndex(where: { $0?.type == .king && $0?.color == color }) else {
            return 0
        }
        let kf = Sq.file(k), kr = Sq.rank(k)
        var s = 0
        var strongDefenders = 0
        for (df, dr) in Self.ring1 {
            let f = kf + df, r = kr + dr
            guard Sq.onBoard(file: f, rank: r),
                  let p = pos.squares[Sq.index(file: f, rank: r)], p.color == color else { continue }
            switch p.type {
            case .gold:   s += 35; strongDefenders += 1
            case .silver: s += 30; strongDefenders += 1
            case .knight: s += 18
            case .lance:  s += 12
            case .pawn:   s += 8
            default:      s += 5
            }
        }
        for (df, dr) in Self.ring2 {
            let f = kf + df, r = kr + dr
            guard Sq.onBoard(file: f, rank: r),
                  let p = pos.squares[Sq.index(file: f, rank: r)], p.color == color else { continue }
            switch p.type {
            case .gold:   s += 12
            case .silver: s += 10
            case .knight: s += 6
            default: break
            }
        }
        if strongDefenders >= 2 { s += 15 }
        s += abs(kf - 4) * 15
        let homeRank = color == .black ? 8 : 0
        s += max(0, 2 - abs(kr - homeRank)) * 10
        s -= kingExposure(pos, color: color, kingSq: k)
        return s
    }

    /// 玉に迫る相手の攻め駒（king tropism, #1258）。棒銀・早繰り銀のように玉から距離3以内へ
    /// 攻め駒（銀・桂・角・飛と成り駒）が来ているほど減点する。囲い（shelter）は自駒しか見ないため、
    /// 攻め駒が2筋まで来た局面が leaf で「無傷」に見えていた。攻め駒1枚では効かせず、
    /// 2枚目以降から加算する（1枚だけの牽制で守りを固めすぎないため）。
    func kingDanger(_ pos: Position, _ color: Side) -> Int {
        guard let k = pos.squares.firstIndex(where: { $0?.type == .king && $0?.color == color }) else {
            return 0
        }
        let kf = Sq.file(k), kr = Sq.rank(k)
        var total = 0
        var attackers = 0
        for f in max(0, kf - 3)...min(8, kf + 3) {
            for r in max(0, kr - 3)...min(8, kr + 3) {
                guard let p = pos.squares[Sq.index(file: f, rank: r)], p.color != color else { continue }
                let weight: Int
                switch p.type {
                case .silver, .bishop, .rook: weight = 3
                case .knight: weight = 2
                default: weight = p.promoted ? 2 : 0
                }
                if weight == 0 { continue }
                let dist = max(abs(f - kf), abs(r - kr))
                total += weight * (4 - dist) * 4
                attackers += 1
            }
        }
        return attackers >= 2 ? total : 0
    }

    /// 隣接8マス（距離1のリング）。
    private static let ring1: [(Int, Int)] = [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]

    /// 距離2のリング（斜めの角を除いた16マス。美濃囲いの端の金銀・桂がここに来る）。
    private static let ring2: [(Int, Int)] = [
        (-2,-2),(-1,-2),(0,-2),(1,-2),(2,-2),
        (-2,-1),(2,-1),
        (-2,0),(2,0),
        (-2,1),(2,1),
        (-2,2),(-1,2),(0,2),(1,2),(2,2),
    ]

    /// 玉の位置から縦横・斜めへ相手の大駒（飛・龍・角・馬・香）の利きが素通しかを見る。
    /// 玉から見て最初にぶつかった駒だけを見る（間に自駒・敵駒があれば遮られる）。
    /// 距離が近いほど危険度を高くする（`isKingInCheck` は既に別で扱うので、ここは
    /// 「王手ではないが利きが素通し」という一歩手前の危険を評価するのが目的）。
    func kingExposure(_ pos: Position, color: Side, kingSq: Int) -> Int {
        let kf = Sq.file(kingSq), kr = Sq.rank(kingSq)
        let opponent = color.opponent
        var penalty = 0

        for (df, dr) in [(0,-1),(0,1),(1,0),(-1,0)] {
            var f = kf + df, r = kr + dr
            var dist = 1
            while Sq.onBoard(file: f, rank: r) {
                if let p = pos.squares[Sq.index(file: f, rank: r)] {
                    if p.color == opponent {
                        let isLanceForward = p.type == .lance && !p.promoted && df == 0
                            && ((p.color == .black && dr == 1) || (p.color == .white && dr == -1))
                        if p.type == .rook || isLanceForward {
                            penalty += max(0, 9 - dist) * 6
                        }
                    }
                    break
                }
                dist += 1
                f += df; r += dr
            }
        }

        for (df, dr) in [(1,-1),(-1,-1),(1,1),(-1,1)] {
            var f = kf + df, r = kr + dr
            var dist = 1
            while Sq.onBoard(file: f, rank: r) {
                if let p = pos.squares[Sq.index(file: f, rank: r)] {
                    if p.color == opponent, p.type == .bishop {
                        penalty += max(0, 9 - dist) * 6
                    }
                    break
                }
                dist += 1
                f += df; r += dr
            }
        }

        return penalty
    }
}
