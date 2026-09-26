import Foundation
import Core
import CoreEngine

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
///
/// `private` にせず module 内に公開しているのは、テストが「詰みを詰みとして返しているか」を
/// **正確な値**で確かめられるようにするため。大小の比較だけだと、探索が
/// 何も読まずに `alpha` を返しているだけでも通ってしまう（実測で確認済み）。
let chessMateScore = 1_000_000

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

private enum ChessZobrist {
    // [pieceType 0-5][color 0-1][square 0-63]
    static let piece: [[[UInt64]]] = {
        // 種は SplitMix64 の増分と同じ値（#1074 で定数の書き写しをやめて参照に変えた。表の値は変わらない）。
        var rng = MMIXRandom(state: SplitMix64.goldenGamma)
        var t = [[[UInt64]]](
            repeating: [[UInt64]](repeating: [UInt64](repeating: 0, count: 64), count: 2),
            count: 6)
        for pt in 0..<6 { for c in 0..<2 { for sq in 0..<64 { t[pt][c][sq] = rng.next() } } }
        return t
    }()

    static let castling: [UInt64] = {
        var rng = MMIXRandom(state: 0xC2B2_AE3D_27D4_EB4F)
        return (0..<16).map { _ in rng.next() }
    }()

    /// アンパッサン標的は**筋だけ**を混ぜる（同じ筋なら効果は同じで、段は手番から決まる）。
    static let enPassantFile: [UInt64] = {
        var rng = MMIXRandom(state: 0x1656_67B1_9E37_79F9)
        return (0..<8).map { _ in rng.next() }
    }()

    static let whiteToMove: UInt64 = {
        var rng = MMIXRandom(state: 0x8521_4F35_2A7C_11D3)
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

// MARK: - 手の選び方（#1398）

/// 1 手目の候補すべてに点数を付けたあと、**段階ごとにどう選ぶか**（会長決裁 2026-09-25）。
/// 将棋 `ShogiMovePolicy` と同じ形。
///
/// - `slipProbability`: 「見逃し」を起こす確率。起きたときは最善から `slipMargin` 以内の損で済む手から乱択する
///   （只の駒を取り損ねる・取り返される手を指す、が初心者らしい間違いとして出る）。
/// - `tieMargin`: 見逃しでないときに「最善と同等」とみなす幅。0 なら同点でも最初の最善手（決定的）。
///
/// キングを只で取らせる手は合法手にならない（王手放置は指せない）ので、どの段階でも選ばれない。
/// 見逃しで許す損は最大でも駒 1 枚ぶん（`slipMargin`）。ただし深さ 1 の入門は相手の応手を読まないため、
/// 見逃しでない手番でも大駒を只で取られる手を「同等」とみなすことがある（初心者らしい悪手として意図したもの）。
/// むずかしいは当面 100%（最善手のみ）。
struct ChessMovePolicy: Equatable {
    var slipProbability: Double
    var slipMargin: Int
    var tieMargin: Int

    /// 最善手だけを選ぶ（ふつう・むずかしい。探索そのものが強さを決める）。
    static let exact = ChessMovePolicy(slipProbability: 0, slipMargin: 0, tieMargin: 0)
    /// 見逃しを起こさず、選び方だけ各段階のまま（テストが「読み」だけを固定するための口）。
    var withoutSlip: ChessMovePolicy {
        ChessMovePolicy(slipProbability: 0, slipMargin: 0, tieMargin: tieMargin)
    }
    /// 探索を素直に回すだけでよいか（全候補の採点が要らない）。
    var isExact: Bool { self == .exact }
}

// MARK: - Engine（公開 API）

public struct SimpleChessEngine: ChessEngine {
    let depth: Int
    let usePositional: Bool
    let useQuiescence: Bool
    let useBook: Bool
    /// 安全用の時間の上限。段階の強さは `nodeLimit`（読む局面数）が決め、端末が遅くても
    /// 強さが変わらないようにする（#1398。時間主体だと遅い端末ほど浅くしか読めない）。
    let timeLimit: TimeInterval
    /// 読む局面数の上限（`nil` なら無し）。
    let nodeLimit: Int?
    let policy: ChessMovePolicy
    /// 「入門」か（#1174）。読みの設定は「簡単」と同じまま、着手の選び方だけを変える。
    var isNovice: Bool { policy.tieMargin > 0 }
    /// 乱数の種。`nil` なら実プレイ用に毎回違う乱数を使う（テストだけが種を渡して再現する）。
    /// `policy` が乱数を使わない段階（ふつう・むずかしい）は、この値を見ない。
    let seed: UInt64?

    /// 難易度。**表示している強さの文言と中身が一致していること**（#416 の教訓）:
    ///
    /// | level | 表示 | 探索深さ上限 | 静止探索 | 位置評価 | 定跡 |
    /// |---|---|---|---|---|---|
    /// | -1 | 入門（手なりで指す） | 1 | 無し | 無し | 無し |
    /// | 0 | 簡単（駒の損得だけ） | 2 | 無し | 無し | 無し |
    /// | 1 | ふつう（駒の働きも見る） | 4（局面数 `normalNodeLimit` まで） | 有り | 有り | 無し |
    /// | 2 | むずかしい（定跡＋深読み） | 6（局面数 `hardNodeLimit` まで） | 有り | 有り | 有り |
    ///
    /// **段階の強さは「読む局面数」で決め、時間は安全用に長めに残す**（#1398。時間主体だと、
    /// 遅い端末ほど浅くしか読めず段階の差が消える）。**上の段階は下の段階に負けない**
    /// （会長決裁 2026-09-25。`CPUBenchTests` で隣り合う段階どうしを先後入れ替えで計測する）。
    /// 入門・簡単・ふつうは一定の確率で「見逃し」（`ChessMovePolicy`）を起こす。
    ///
    /// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
    ///
    /// level 0 で静止探索を切っているのは「初心者が勝てる最弱」を作るため。
    /// 静止探索が無いと取り合いの途中で数え終えるので、駒の只捨てを見落とす。
    /// その下の「入門」（#1174）は**自分の手 1 手だけを読む**（#1398。深さ 2 のままだと簡単との対戦で
    /// 簡単が詰まされる局が残り、「上の段階は下の段階に負けない」を満たせなかった。将棋 #1397 と同じ）。
    /// 全候補に点を付け、ポーン 1 枚に満たない差の手から乱択し、35% は駒 1 枚ぶんまでの損を許す。
    /// 取り返される取りを指すことがあるが、それが「初心者が勝てる」水準の中身（会長決裁 2026-09-25）。
    public init(level: Int = CPUStrength.standard.rawValue) {
        self.init(level: level, seed: nil)
    }

    init(level: Int, seed: UInt64?) {
        let strength = CPUStrength.strength(for: level)
        switch strength {
        case .novice:  (depth, usePositional, useQuiescence, useBook, timeLimit) = (1, false, false, false, 0.5)
        case .easy:    (depth, usePositional, useQuiescence, useBook, timeLimit) = (2, false, false, false, 0.5)
        case .hard:    (depth, usePositional, useQuiescence, useBook, timeLimit) = (Self.hardDepth, true, true, true, Self.hardTimeLimit)
        case .normal:  (depth, usePositional, useQuiescence, useBook, timeLimit) = (Self.normalDepth, true, true, false, Self.normalTimeLimit)
        }
        switch strength {
        case .novice: (nodeLimit, policy) = (nil, Self.novicePolicy)
        case .easy:   (nodeLimit, policy) = (nil, Self.easyPolicy)
        case .normal: (nodeLimit, policy) = (Self.normalNodeLimit, Self.normalPolicy)
        case .hard:   (nodeLimit, policy) = (Self.hardNodeLimit, .exact)
        }
        self.seed = seed
    }

    /// 入門: 3 割強は「駒 1 枚ぶん（ナイト・ビショップまで）損する手」から選ぶ。見逃さない手番でも
    /// ポーン 1 枚未満の差は同等とみなして乱択する（#1174）。
    static let novicePolicy = ChessMovePolicy(
        slipProbability: 0.35, slipMargin: 350, tieMargin: ChessPieceValue.base(.pawn) - 1)
    /// 簡単: 8% で「ポーン〜ナイト 1 枚ぶん損する手」を混ぜる。ほかは最善手（決定的）。
    static let easyPolicy = ChessMovePolicy(slipProbability: 0.08, slipMargin: 300, tieMargin: 0)
    /// ふつう: 10% の手番だけ浅く読んで「ポーン〜ナイト 1 枚ぶん損する手」を混ぜる（むずかしいは 100% 最善手）。
    static let normalPolicy = ChessMovePolicy(slipProbability: 0.10, slipMargin: 300, tieMargin: 0)

    /// 段階の差を付ける読みの局面数（#1398）。時間は安全用に長めに残す。
    static let normalDepth = 3
    static let hardDepth = 5
    static let normalNodeLimit = 6_000
    static let hardNodeLimit = 200_000
    static let normalTimeLimit: TimeInterval = 3.0
    static let hardTimeLimit: TimeInterval = 8.0

    /// テスト・計測用の直接指定。時間切れによる打ち切りを構造的に無くしたいときは
    /// `timeLimit: .infinity` を渡す（`.distantFuture` を締切にする）。
    init(depth: Int, usePositional: Bool, useQuiescence: Bool, useBook: Bool, timeLimit: TimeInterval,
         nodeLimit: Int? = nil, policy: ChessMovePolicy = .exact, seed: UInt64? = nil) {
        self.depth = depth
        self.usePositional = usePositional
        self.useQuiescence = useQuiescence
        self.useBook = useBook
        self.timeLimit = timeLimit
        self.nodeLimit = nodeLimit
        self.policy = policy
        self.seed = seed
    }

    /// 全候補に点を付けて選ぶ浅い読みの深さ（簡単、およびふつうの見逃しの手番）。
    static let shallowDepth = 2
    /// 「入門」が見逃し以外で許す駒損の幅（#1174）。**ポーン 1 枚に満たない差**しか許さない。
    static let noviceMargin = ChessPieceValue.base(.pawn) - 1

    public func bestMove(fen: String) async -> String? {
        guard var pos = ChessPosition.fromFEN(fen) else { return nil }
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { return nil }

        if useBook, let booked = ChessOpeningBook.move(for: fen),
           let m = ChessMove.fromUCI(booked), moves.contains(m) { return booked }

        // 入門・簡単（深さ 2 以下）は毎手、全候補に点を付けて選ぶ。ふつう以上は探索で最善手を出し、
        // 見逃しの手番だけ浅い読み（深さ 2）で全候補に点を付けて損の幅の中から選ぶ。
        let scoresEveryMove = depth <= Self.shallowDepth
        if scoresEveryMove || !policy.isExact {
            var rng = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
            let slips = policy.slipProbability > 0 && Double.random(in: 0..<1, using: &rng) < policy.slipProbability
            if scoresEveryMove || slips {
                return policyMove(&pos, moves: moves, scoringDepth: min(depth, Self.shallowDepth),
                                  slips: slips, using: &rng)?.uci
            }
        }

        var ctx = ChessSearchContext(
            maxDepth: depth, usePositional: usePositional,
            useQuiescence: useQuiescence, timeLimit: timeLimit, nodeLimit: nodeLimit
        )
        return ctx.search(&pos)?.uci
    }

    /// 計測用: 手に加えて、読んだ局面数と完了した反復深化の深さを返す（#1398）。
    /// 定跡・`policy` は通さず、探索そのものだけを見る。
    func analyze(fen: String) -> (uci: String?, nodes: Int, depth: Int)? {
        guard var pos = ChessPosition.fromFEN(fen), !pos.legalMoves().isEmpty else { return nil }
        var ctx = ChessSearchContext(
            maxDepth: depth, usePositional: usePositional,
            useQuiescence: useQuiescence, timeLimit: timeLimit, nodeLimit: nodeLimit
        )
        let move = ctx.search(&pos)
        return (move?.uci, ctx.nodes, ctx.completedDepth)
    }

    /// 入門・簡単の着手（#1174・#1398）。全候補に点を付けて `policy` で選ぶ。入門は
    /// **最善からポーン 1 枚ぶんも損しない手の中から乱択**し、さらに一定の確率で駒 1 枚ぶんまでの損を許す（見逃し）。
    ///
    /// 「簡単」は同じ評価で並んだ手を指し手オーダリング（取る手が先）で選ぶので、駒得の機会は
    /// 逃さず攻めの手が先に出る。「入門」はそこを崩して手なりに指す。
    ///
    /// 時間切れでも最低限これだけは評価してから選ぶ（#1196）。1件も評価できないまま
    /// `orderedMoves.first`（安全性未確認）へ逃げると駒損しない保証をすり抜ける。
    /// 1件だけ評価しても自分自身としか比較できず実質フォールバックと変わらない
    /// ため、比較に足る数（負けている手を弾ける最低限）を確保する。
    static let minNoviceEvaluations = 3

    func policyMove(_ pos: inout ChessPosition, moves: [ChessMove], scoringDepth: Int, slips: Bool,
                    using rng: inout SplitMix64) -> ChessMove? {
        var ctx = ChessSearchContext(
            maxDepth: 1, usePositional: usePositional,
            useQuiescence: useQuiescence, timeLimit: timeLimit
        )
        // 先にオーダリング（MVV-LVA）しておく。時間切れで1手も読めなかった／全滅した場合の
        // フォールバックに使う（「簡単」の反復深化が時間切れ時に使うのと同じ考え方 = 只捨てではない手）。
        let orderedMoves = ctx.orderMoves(moves, pos: pos, killers: [nil, nil])
        var scored: [(move: ChessMove, score: Int)] = []
        let originalDeadline = ctx.deadline
        for (index, move) in orderedMoves.enumerated() {
            let withinSafetyFloor = index < Self.minNoviceEvaluations
            // 期限切れなら打ち切る。ここでチェックしないと、期限切れ後の `negamax` が
            // 「自分の手を指した直後の駒得」だけを返し続け、取り返しを見ない只捨てを弾けなくなる
            // （#1174 検証指摘）。ただし安全フロアの範囲内は期限を無視して必ず評価する（#1196）。
            if !withinSafetyFloor, Date() > originalDeadline { break }
            // 安全フロアの範囲内は `negamax`（と内部で呼ぶ `quiesce`）の期限判定も無効化する。
            // `deadline` だけ外側で無視しても、`negamax` は自分の先頭で期限切れなら
            // `evaluate(pos)`（相手の応手を読まない静的評価）を即返すため、取り返される
            // 駒取りが安全フロアの候補に残ってしまう（CodeRabbit 指摘）。
            ctx.deadline = withinSafetyFloor ? .distantFuture : originalDeadline
            let undo = pos.make(move)
            // 全幅で読む（αβ の窓を狭めると「最善から〜以内」を判定できる値が返らない）。
            let score = -ctx.negamax(&pos, depth: scoringDepth - 1,
                                     alpha: -chessMateScore * 2, beta: chessMateScore * 2, ply: 1)
            pos.unmake(undo)
            ctx.deadline = originalDeadline
            // negamax の探索中に期限切れになった場合、返る値は不完全な評価（中断時点の
            // evaluate(pos)）なので候補に入れない（CodeRabbit 指摘・PR #1190）。安全フロアの
            // 範囲内は不完全でも比較材料として使う（同上の理由）。
            if !withinSafetyFloor, Date() > originalDeadline { break }
            scored.append((move, score))
        }
        guard let best = scored.map(\.score).max() else { return orderedMoves.first }
        return Self.pick(scored, best: best, margin: slips ? policy.slipMargin : policy.tieMargin, using: &rng)
            ?? orderedMoves.first
    }

    /// 採点済みの候補から 1 手選ぶ。`margin` 以内の損の手から乱択し、0 なら最初の最善手。
    static func pick<G: RandomNumberGenerator>(
        _ scored: [(move: ChessMove, score: Int)], best: Int, margin: Int, using rng: inout G
    ) -> ChessMove? {
        if margin == 0 { return scored.first { $0.score == best }?.move }
        let pool = scored.filter { $0.score >= best - margin }.map(\.move)
        guard !pool.isEmpty else { return nil }
        return pool[Int.random(in: 0..<pool.count, using: &rng)]
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
    var deadline: Date
    var killers: [[ChessMove?]]
    private var tt: [ChessTTEntry]
    /// 読む局面数の上限（#1398）。`nil` なら無し。時間の上限は安全用で、強さはこちらで決める。
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
        self.killers = [[ChessMove?]](repeating: [nil, nil], count: maxDepth + 10)
        self.tt = [ChessTTEntry](repeating: ChessTTEntry(), count: chessTTSize)
        // 締切は置換表の確保が済んでから決める（#1398）。先に決めると、遅い端末では
        // 確保にかかった時間が持ち時間から削られる。
        // `timeLimit: .infinity` は「打ち切りを構造的に無くす」ための特別値。
        self.deadline = timeLimit.isFinite ? Date().addingTimeInterval(timeLimit) : .distantFuture
    }

    /// 時間切れ、または読む局面数の上限に達した。
    private var isExhausted: Bool {
        if let nodeLimit, nodes >= nodeLimit { return true }
        return Date() > deadline
    }

    // MARK: 反復深化

    mutating func search(_ pos: inout ChessPosition) -> ChessMove? {
        var orderedMoves = orderMoves(pos.legalMoves(), pos: pos, killers: [nil, nil])
        var best: ChessMove? = orderedMoves.first

        for d in 1...maxDepth {
            if isExhausted { break }
            var localBest: ChessMove?
            var bestScore = -chessMateScore * 2
            var alpha = -chessMateScore * 2
            let beta = chessMateScore * 2
            var aborted = false

            for move in orderedMoves {
                if isExhausted { aborted = true; break }
                let undo = pos.make(move)
                let score = -negamax(&pos, depth: d - 1, alpha: -beta, beta: -alpha, ply: 1)
                pos.unmake(undo)
                // 最後の根の手を読み終えた直後に時間切れ・上限到達になっていたら、この深さの
                // 結果は途中で打ち切られた探索の値が混ざる。採用しない（#1398。将棋 #1397・
                // 五目並べ #1226・オセロ #1133 と同じ対策）。
                if isExhausted { aborted = true; break }
                if score > bestScore { bestScore = score; localBest = move }
                if score > alpha { alpha = score }
            }

            if !aborted, let lb = localBest {
                completedDepth = d
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
        nodes += 1
        if isExhausted { return evaluate(pos) }

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
            return pos.isKingInCheck(pos.sideToMove) ? -(chessMateScore - ply) : 0
        }

        if depth <= 0 {
            return useQuiescence
                ? quiesce(&pos, alpha: alpha, beta: beta, qdepth: 0, ply: ply)
                : evaluate(pos)
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

    /// 静止探索。**終局と王手を `negamax` と同じ精度で扱う**（CodeRabbit 指摘・Major）。
    ///
    /// 素朴な静止探索は「取り合いだけを読む」ので、次の 2 つを取りこぼす:
    /// 1. 取る手で詰んだ局面。合法手ゼロを見ないと `evaluate` の駒得だけが返り、詰みを見落とす
    /// 2. **王手されている局面での stand-pat**。「何も指さなければこの評価値」は王手中には
    ///    成り立たない（必ず何か指さなければならない）。取る手しか読まないので、
    ///    静かな王手回避（逃げる・合駒）が見えず、実際より悪い評価が返る
    ///
    /// そのため、王手中は取る手に絞らず**全ての合法手**を読む。`qdepth` の上限で必ず止まる。
    mutating func quiesce(
        _ pos: inout ChessPosition, alpha: Int, beta: Int, qdepth: Int, ply: Int
    ) -> Int {
        nodes += 1
        if isExhausted { return evaluate(pos) }

        let moves = pos.legalMoves()
        let inCheck = pos.isKingInCheck(pos.sideToMove)
        // 終局は深さ上限より先に見る。上限で打ち切ると詰みを駒得として数えてしまう。
        if moves.isEmpty { return inCheck ? -(chessMateScore - ply) : 0 }
        if qdepth >= 6 { return evaluate(pos) }

        var alpha = alpha
        if inCheck {
            for move in orderMoves(moves, pos: pos, killers: [nil, nil]) {
                let undo = pos.make(move)
                let score = -quiesce(&pos, alpha: -beta, beta: -alpha,
                                     qdepth: qdepth + 1, ply: ply + 1)
                pos.unmake(undo)
                if score >= beta { return beta }
                if score > alpha { alpha = score }
            }
            return alpha
        }

        let standPat = evaluate(pos)
        if standPat >= beta { return beta }
        // デルタ枝刈り: 最大の取り駒（クイーン 900）を足しても alpha に届かないなら見る意味がない。
        if standPat + ChessPieceValue.base(.queen) < alpha { return alpha }

        alpha = max(alpha, standPat)
        let captures = moves.filter { isCapture($0, pos) || $0.promotion != nil }
        for move in captures.sorted(by: { captureScore($0, pos) > captureScore($1, pos) }) {
            let undo = pos.make(move)
            let score = -quiesce(&pos, alpha: -beta, beta: -alpha,
                                 qdepth: qdepth + 1, ply: ply + 1)
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
