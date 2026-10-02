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

// MARK: - 手の選び方（#1461）

/// 段階ごとの「最善手を打つ確率」（会長決裁 2026-09-26）。
///
/// 難易度は**考える時間**（`SimpleMinimaxEngine.timeLimit`）・読む深さの上限（`depth`）と、この確率で決める。
/// 確率が外れたときは、1 手読み（＋静止探索）で全候補に点を付け、最善から `slipMargin` 以内の損で済む手
/// （次の一手で詰まされる手は除く）のうち、最善以外から乱択する。
/// 玉を取らせる手は合法手にならないので、どの段階でも選ばれない。
struct ShogiMovePolicy: Equatable {
    /// 探索が出した最善手をそのまま指す確率（0...1）。
    var bestMoveProbability: Double
    /// 外したときに許す損の幅（駒の価値の点数）。
    var slipMargin: Int

    /// 最善手だけを選ぶ（むずかしい）。
    static let exact = ShogiMovePolicy(bestMoveProbability: 1, slipMargin: 0)
    /// 外しを起こさず、探索の最善手だけを指す（テストが「読み」だけを固定するための口）。
    var withoutSlip: ShogiMovePolicy { .exact }
    /// 探索を素直に回すだけでよいか。
    var isExact: Bool { bestMoveProbability >= 1 }
}

// MARK: - Engine（公開 API）

public struct SimpleMinimaxEngine: ShogiEngine {
    let depth: Int
    let usePositional: Bool
    let useQuiescence: Bool
    let useBook: Bool
    /// 1 手の考える時間の上限（秒）。読み終われば早く指す。段階の差は、この時間・`depth`（深さの上限）と
    /// `policy.bestMoveProbability` だけで付ける（#1461）。
    let timeLimit: TimeInterval
    /// 読む局面数の上限（`nil` なら無し）。出荷値では使わない（計測・テスト用の口）。
    let nodeLimit: Int?
    let policy: ShogiMovePolicy
    /// 乱数の種。`nil` なら実プレイ用に毎回違う乱数を使う（テストだけが種を渡して再現する）。
    /// `policy` が乱数を使わない段階（むずかしい）は、この値を見ない。
    let seed: UInt64?

    /// 難易度。**表示している強さの文言と中身が一致していること**（#416 の教訓）:
    ///
    /// | level | 表示 | 考える時間 | 読む深さの上限 | 最善手を打つ確率 | 定跡 |
    /// |---|---|---|---|---|---|
    /// | -1 | 入門 | 0.02 秒 | 1 手先 | `noviceBestMoveProbability` | 無し |
    /// | 0 | かんたん | 0.1 秒 | 2 手先 | `easyBestMoveProbability` | 無し |
    /// | 1 | ふつう | 0.5 秒 | 3 手先 | 80% | 無し |
    /// | 2 | むずかしい | 2 秒 | 無し（`maxDepth`） | 100% | 有り |
    ///
    /// 探索（反復深化・静止探索・位置評価）は全段階で同じで、時間が来るか深さの上限まで読み終えたら指す。
    /// 確率の根拠は PR #1461 の段階表（`docs/analytics/shogi-1461-ladder.md`: 上の段の得点率 90% 以上で
    /// 最も高い値）。
    ///
    /// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
    public init(level: Int = CPUStrength.standard.rawValue) {
        self.init(level: level, seed: nil)
    }

    init(level: Int, seed: UInt64?, timeLimit overrideTime: TimeInterval? = nil) {
        let strength = CPUStrength.strength(for: level)
        (usePositional, useQuiescence) = (true, true)
        useBook = strength == .hard
        let shippedTime: TimeInterval
        switch strength {
        case .novice: (shippedTime, depth, policy) = (0.02, 1, Self.policy(Self.noviceBestMoveProbability))
        case .easy:   (shippedTime, depth, policy) = (0.1, 2, Self.policy(Self.easyBestMoveProbability))
        case .normal: (shippedTime, depth, policy) = (0.5, 3, Self.policy(Self.normalBestMoveProbability))
        case .hard:   (shippedTime, depth, policy) = (2.0, Self.maxDepth, .exact)
        }
        self.timeLimit = overrideTime ?? shippedTime   // ヒント用: 考える時間だけ差し替える（#1739）
        self.nodeLimit = nil
        self.seed = seed
    }

    /// ヒント専用のエンジン（#1739）。「むずかしい」と同じ設定で、考える時間だけ
    /// `BoardHintBudget.extraThinkingTime` 長い。対局 CPU の「むずかしい」は変えない。
    static func hint() -> SimpleMinimaxEngine {
        let base = SimpleMinimaxEngine(level: BoardHintBudget.engineLevel, seed: nil)
        return SimpleMinimaxEngine(level: BoardHintBudget.engineLevel, seed: nil,
                  timeLimit: base.timeLimit + BoardHintBudget.extraThinkingTime)
    }

    /// 反復深化の深さの上限（むずかしい）。実際に止めるのは時間（読み終わる終盤だけ早く終わる）。
    /// 下の段は `depth` に 3 / 2 / 1 手先の上限を持つ（会長決裁 2026-09-27）。
    static let maxDepth = 32

    /// 最善手を打つ確率（#1461 の実測。上の段の得点率が 90% 以上になる、10% 刻みで最も高い値。
    /// ふつうは会長決裁の 80%、かんたん・入門は上から順に計測で決めた: ふつう 80% に対しかんたん 70%、
    /// かんたん 70% に対し入門 100%。入門は外しを使わず、0.02 秒・1 手先の読みの浅さだけで弱くなる）。
    static let noviceBestMoveProbability = 1.0
    static let easyBestMoveProbability = 0.7
    static let normalBestMoveProbability = 0.8

    /// 外したときに許す損の幅（銀 1 枚ぶん）。歩・香・桂・銀を只で失う手までが入り、金・角・飛は入らない。
    /// 300（歩 3 枚ぶん）だと外した手が強すぎて、ふつうが 40% まで下がり、かんたん・入門に割り当てる
    /// 確率が残らなかった（PR #1461 の勝率表）。
    static let slipMargin = 500

    static func policy(_ probability: Double) -> ShogiMovePolicy {
        ShogiMovePolicy(bestMoveProbability: probability, slipMargin: slipMargin)
    }

    /// テスト・計測用の直接指定。時間切れによる打ち切りを構造的に無くしたいときは
    /// `timeLimit: .infinity` を渡す（`.distantFuture` を締切にする。#1187）。
    init(depth: Int, usePositional: Bool, useQuiescence: Bool, useBook: Bool, timeLimit: TimeInterval,
         nodeLimit: Int? = nil, policy: ShogiMovePolicy = .exact, seed: UInt64? = nil) {
        self.depth = depth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        self.useBook = useBook
        self.timeLimit = timeLimit
        self.nodeLimit = nodeLimit
        self.policy = policy
        self.seed = seed
    }

    public func bestMove(sfen: String) async -> String? {
        guard var pos = Position.fromSFEN(sfen) else { return nil }
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { return nil }

        if useBook, let booked = OpeningBook.move(for: sfen),
           let m = Move.fromUSI(booked), moves.contains(m) { return booked }

        let startedAt = Date()
        if !policy.isExact {
            var rng = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
            let slipDeadline = timeLimit.isFinite
                ? startedAt.addingTimeInterval(timeLimit * Self.slipTotalShare) : Date.distantFuture
            if Double.random(in: 0..<1, using: &rng) >= policy.bestMoveProbability,
               let slip = slipMove(&pos, moves: moves, using: &rng, deadline: slipDeadline) {
                return slip.usi
            }
        }

        // 外しの手が見つからず探索に回るときも、1 手の合計が上限に収まるよう、使った時間を引いて読む。
        var ctx = SearchContext(
            maxDepth: depth, usePositional: usePositional, useQuiescence: useQuiescence,
            timeLimit: Self.searchTime(limit: timeLimit, elapsed: Date().timeIntervalSince(startedAt)),
            nodeLimit: nodeLimit)
        return ctx.search(&pos)?.usi
    }

    /// 計測用: 手に加えて、読んだ局面数と完了した反復深化の深さを返す。
    /// 定跡・`policy` は通さず、探索そのものだけを見る。
    func analyze(sfen: String) -> (usi: String?, nodes: Int, depth: Int)? {
        guard var pos = Position.fromSFEN(sfen), !pos.legalMoves().isEmpty else { return nil }
        var ctx = SearchContext(maxDepth: depth, usePositional: usePositional,
                                useQuiescence: useQuiescence, timeLimit: timeLimit, nodeLimit: nodeLimit)
        let move = ctx.search(&pos)
        return (move?.usi, ctx.nodes, ctx.completedDepth)
    }

    /// 最善手を外すときの手（#1461）。全候補に 1 手だけ読んで（自分の手のあと、取り合いが落ち着くまで）
    /// 点を付け、点の最も高い手を除いたうち、最善から `slipMargin` 以内の損の手から乱択する。
    /// 大駒を只で取られる手・取り返される取りは幅の外に出る。候補が無い・選んだ手が詰まされる手だけなら
    /// `nil`（呼び出し側が探索して最善手を指す）。`deadline` を過ぎても確認が終わらなければ同じく `nil`。
    /// 全候補を深く読むと 1 手に何秒もかかる（実測: 平均 1.7 秒・最大 16 秒）ので、採点は浅くし、
    /// 詰まされないことだけを選んだ手について確かめる（`allowsMateInOne`）。
    func slipMove(_ pos: inout Position, moves: [Move], using rng: inout SplitMix64,
                  deadline: Date = .distantFuture) -> Move? {
        var pool = slipPool(&pos, moves: moves)
        while !pool.isEmpty, Date() <= deadline {
            let i = Int.random(in: 0..<pool.count, using: &rng)
            let move = pool.remove(at: i)
            if !Self.allowsMateInOne(&pos, after: move) { return move }
        }
        return nil
    }

    /// 外しの手を探す全体（採点＋詰みの確認）に使う時間の割合（考える時間に対する）。超えたら探索に回る。
    static let slipTotalShare = 0.4

    /// 探索に使える残りの時間。使った時間と、置換表の確保・後始末ぶん（`searchOverhead`）を引く。
    static func searchTime(limit: TimeInterval, elapsed: TimeInterval) -> TimeInterval {
        limit.isFinite ? max(minSearchTime, limit - elapsed - searchOverhead) : limit
    }

    /// 探索の時間から引く、置換表の確保・返り値の後始末ぶん（秒）。上限を超えないための余裕。
    static let searchOverhead = 0.03
    /// どれだけ引いても探索に残す最低限の時間（秒）。
    static let minSearchTime = 0.02

    /// 外しの採点に使う時間の割合（考える時間に対する）。
    static let slipBudgetShare = 0.2
    /// 時間切れでも最低限採点する手数（比較の相手が要る）。
    static let minSlipEvaluations = 8

    /// 外しの候補（詰みの確認前）。最善（1 手読みの点が最も高い手）を除く。
    func slipPool(_ pos: inout Position, moves: [Move]) -> [Move] {
        var ctx = SearchContext(maxDepth: 1, usePositional: usePositional,
                                useQuiescence: useQuiescence, timeLimit: .infinity, nodeLimit: nil)
        // 取る手・成る手が先に並ぶ順に採点し、上限（考える時間の 2 割）で打ち切る。打ち切った残りの手は
        // 候補に入らない（安全側）。持ち駒が多い局面は合法手が数百あり、全部採点すると何秒もかかる。
        let deadline = timeLimit.isFinite ? Date().addingTimeInterval(timeLimit * Self.slipBudgetShare) : .distantFuture
        // 局面数で読みを区切る計測用の設定（`nodeLimit`）でも、同じ割合で採点を打ち切る。
        let nodeBudget = nodeLimit.map { Int(Double($0) * Self.slipBudgetShare) } ?? .max
        var scored: [(move: Move, score: Int)] = []
        for (index, move) in ctx.orderMoves(moves, pos: pos, killers: [nil, nil], ttMove: nil).enumerated() {
            if index >= Self.minSlipEvaluations, Date() > deadline || ctx.nodes >= nodeBudget { break }
            let undo = pos.make(move)
            // 全幅で読む（αβ の窓を狭めると「最善から〜以内」を判定できる値が返らない）。
            let score = -ctx.negamax(&pos, depth: 0, alpha: Int.min + 1, beta: Int.max, ply: 1)
            pos.unmake(undo)
            scored.append((move, score))
        }
        guard let best = scored.map(\.score).max(), let top = scored.firstIndex(where: { $0.score == best })
        else { return [] }
        scored.remove(at: top)
        return scored.filter { $0.score >= best - policy.slipMargin }.map(\.move)
    }

    /// `move` を指すと、相手に次の一手で詰まされる（＝即負け）か。
    static func allowsMateInOne(_ pos: inout Position, after move: Move) -> Bool {
        let undo = pos.make(move)
        defer { pos.unmake(undo) }
        for reply in pos.legalMovesInPlace() {
            let u = pos.make(reply)
            // 詰みは王手でしかありえない。王手の返答だけ、指し手が残るか数える（全返答で数えると重い）。
            let mated = pos.isKingInCheck(pos.sideToMove) && pos.legalMovesInPlace().isEmpty
            pos.unmake(u)
            if mated { return true }
        }
        return false
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

    func kingPawnShield(_ pos: Position, _ color: Side) -> Int {
        SearchContext(maxDepth: depth, usePositional: usePositional,
                      useQuiescence: useQuiescence, timeLimit: 0).kingPawnShield(pos, color)
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
    /// 読む局面数の上限。`nil` なら無し（出荷値では使わない。計測・テストが探索量を揃えるための口）。
    let nodeLimit: Int?
    /// `negamax` / `quiesce` に入った回数。
    private(set) var nodes = 0
    /// 最後まで読み切れた反復深化の深さ（計測用）。
    private(set) var completedDepth = 0

    init(maxDepth: Int, usePositional: Bool, useQuiescence: Bool, timeLimit: TimeInterval,
         nodeLimit: Int? = nil) {
        self.maxDepth = maxDepth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        self.nodeLimit = nodeLimit
        self.killers = [[Move?]](repeating: [nil, nil], count: maxDepth + 10)
        self.tt = [TTEntry](repeating: TTEntry(), count: TT_SIZE)
        self.history = [Int](repeating: 0, count: 81 * 81 + 8 * 81)
        // 締切は置換表などの確保が済んでから決める（#1397）。先に決めると、遅い端末では
        // 確保にかかった時間が持ち時間から削られる。
        // `timeLimit: .infinity` は「打ち切りを構造的に無くす」ための特別値（#1187）。
        // `Date().addingTimeInterval(.infinity)` の結果に依存せず、明示的に `.distantFuture` にする。
        self.deadline = timeLimit.isFinite ? Date().addingTimeInterval(timeLimit) : .distantFuture
    }

    /// 時間切れ、または読む局面数の上限に達した。
    private var isExhausted: Bool {
        if let nodeLimit, nodes >= nodeLimit { return true }
        return Date() > deadline
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
            if isExhausted { break }
            var localBest: Move?
            var bestScore = Int.min + 1
            var alpha = Int.min + 1
            let beta = Int.max
            var aborted = false

            for move in orderedMoves {
                if isExhausted { aborted = true; break }
                let undo = pos.make(move)
                let score = -negamax(&pos, depth: d - 1, alpha: -beta, beta: -alpha, ply: 1)
                pos.unmake(undo)
                // 最後の根の手を読み終えた直後に時間切れ・上限到達になっていたら、この深さの
                // 結果は途中で打ち切られた探索の値が混ざる。採用しない（#1397。五目並べ #1226・
                // オセロ #1133 と同じ対策）。
                if isExhausted { aborted = true; break }
                if score > bestScore { bestScore = score; localBest = move }
                if score > alpha { alpha = score }
            }

            if !aborted, let lb = localBest {
                completedDepth = d
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
        nodes += 1
        if isExhausted { return evaluate(pos) }

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
        nodes += 1
        if qdepth >= 6 || isExhausted { return evaluate(pos) }

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
            score += kingShelter(pos, .black) - kingDanger(pos, .black) + kingPawnShield(pos, .black)
                   - kingShelter(pos, .white) + kingDanger(pos, .white) - kingPawnShield(pos, .white)
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

    /// 玉頭の歩の盾と開いた筋（#1258 段階4）。shelter とは別項（自己対戦テストは shelter だけを見る）。
    /// 玉の筋と両隣で、玉の前方3マス以内に自分の歩があれば加点し、その筋に自分の歩が1枚も無ければ
    /// （相手の飛香が走れる開いた筋）減点する。相手が飛車を持っている（盤上・持ち駒とも）ときは
    /// 開いた筋の減点を倍にする。前方2マスに絞ると、7六歩を突いたあとの 6九玉が盾なしと見なされ、
    /// 囲いを進める手が選ばれなくなった（自己対戦で実測）ため3マスにしている。
    func kingPawnShield(_ pos: Position, _ color: Side) -> Int {
        guard let k = pos.squares.firstIndex(where: { $0?.type == .king && $0?.color == color }) else {
            return 0
        }
        let kf = Sq.file(k), kr = Sq.rank(k)
        let forward = color == .black ? -1 : 1
        let opponent = color.opponent
        let oppHasRook = pos.hands[opponent.rawValue][PieceType.rook.rawValue] > 0
            || pos.squares.contains { $0?.type == .rook && $0?.color == opponent }
        var s = 0
        for f in max(0, kf - 1)...min(8, kf + 1) {
            var shield = false
            var hasPawn = false
            for r in 0..<Sq.count / 9 {
                guard let p = pos.squares[Sq.index(file: f, rank: r)],
                      p.type == .pawn, !p.promoted, p.color == color else { continue }
                hasPawn = true
                let ahead = (r - kr) * forward
                if ahead >= 1 && ahead <= 3 { shield = true }
            }
            if shield { s += 5 }
            if !hasPawn { s -= oppHasRook ? 8 : 4 }
        }
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
