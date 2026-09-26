import Foundation
import CoreEngine

public protocol GomokuEngine: Sendable {
    func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)?
}

// MARK: - Zobrist

private enum GomokuZobrist {
    // [color 0-1][square 0-224]
    static let stone: [[UInt64]] = {
        var rng = MMIXRandom(state: 0xABCD_1234_CAFE_9876)
        var t = [[UInt64]](repeating: [UInt64](repeating: 0, count: 225), count: 2)
        for c in 0..<2 { for sq in 0..<225 { t[c][sq] = rng.next() } }
        return t
    }()
    static let sideToMove: UInt64 = {
        var rng = MMIXRandom(state: 0xDEAD_BEEF_1234_5678)
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

/// 縦・横・斜め 2 方向（探索のたびに配列を作らないよう定数にする）。
private let gomokuDirections: [(Int, Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]

/// 盤の升を「中央からの距離（マンハッタン）→ 行 → 列」の順に並べたもの。候補手をこの順に拾えば並べ替えが要らない（#812 の全順序）。
private let gomokuCenterOrder: [Int] = (0..<(gomokuBoardSize * gomokuBoardSize)).sorted { a, b in
    let center = gomokuBoardSize / 2
    let da = abs(a / gomokuBoardSize - center) + abs(a % gomokuBoardSize - center)
    let db = abs(b / gomokuBoardSize - center) + abs(b % gomokuBoardSize - center)
    return (da, a / gomokuBoardSize, a % gomokuBoardSize) < (db, b / gomokuBoardSize, b % gomokuBoardSize)
}

// MARK: - 手の選び方（#1399）

/// 探索で全候補に点を付けたあと、**段階ごとにどう選ぶか**（会長決裁 2026-09-25）。
/// 将棋 `ShogiMovePolicy`・チェス `ChessMovePolicy` と同じ形。
///
/// - `slipProbability`: 「見逃し」を起こす確率。起きたときは最善から `slipMargin` 以内の損で済む手から乱択する。
/// - `tieMargin`: 見逃しでないときに「最善と同等」とみなす幅。0 なら最善手だけ（決定的）。
///
/// 相手に五を作らせる手（評価値 -50,000 以下）は、最善がそれしか無いときを除いてどの段階でも選ばない。
/// むずかしいは当面 100%（最善手のみ）。
struct GomokuMovePolicy: Equatable {
    var slipProbability: Double
    var slipMargin: Int
    var tieMargin: Int
    /// 相手の開三（次で活四）を止める手だけを候補にする。読みが浅い（3 手）ふつうの補い。
    var forcesDefense = false

    /// 最善手だけを選ぶ（むずかしい。探索そのものが強さを決める）。
    static let exact = GomokuMovePolicy(slipProbability: 0, slipMargin: 0, tieMargin: 0)
    var isExact: Bool { self == .exact }

    /// 根の全候補の評価値から 1 手を選ぶ。`scores` は良い順に並べる必要は無い（最初に最大値をとった手が最善）。
    func choose<R: RandomNumberGenerator>(_ scores: [(move: Int, score: Int)], using rng: inout R) -> Int? {
        guard let first = scores.first else { return nil }
        let best = scores.reduce(first) { $1.score > $0.score ? $1 : $0 }
        let slip = slipProbability > 0 && Double.random(in: 0..<1, using: &rng) < slipProbability
        let margin = slip ? slipMargin : tieMargin
        guard margin > 0 else { return best.move }
        let pool = scores.filter { $0.score >= best.score - margin && ($0.score > -50_000 || best.score <= -50_000) }
        return pool[Int.random(in: 0..<pool.count, using: &rng)].move
    }
}

/// 種があれば再現できる乱数、なければ実プレイ用のシステム乱数。
private struct GomokuRandom: RandomNumberGenerator {
    private var seeded: MMIXRandom?
    init(seed: UInt64?) { seeded = seed.map { MMIXRandom(state: $0) } }
    mutating func next() -> UInt64 {
        if seeded != nil { return seeded!.next() }
        var system = SystemRandomNumberGenerator()
        return system.next()
    }
}

// MARK: - Engine（公開 API）

/// 五目並べの CPU。
///
/// | level | 表示 | 打ち方 |
/// |---|---|---|
/// | -1 | 入門 | 読まずに1手先の形だけ。相手の四を防ぐのは 20 回に 1 回・6 割は形を見ずに無作為（#1399） |
/// | 0 | 簡単 | 読まずに1手先の形だけ（#665）＋ 相手の四を防ぐのは 2 回に 1 回 |
/// | 1 | ふつう | 深さ 3 の αβ（局面数 15,000 まで）＋ 開三・二重の脅威を先に潰す・10% で形の甘い手 |
/// | 2 | むずかしい | 深さ 9 の αβ（局面数 300,000 まで・各局面は点の高い 14 手だけ読む）・最善手のみ |
///
/// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
/// **段階の強さは「読む局面数」で決め、時間は安全用に長めに残す**（#1399。時間主体だと遅い端末ほど
/// 浅くしか読めず、ふつうとむずかしいが同じ深さに潰れる）。**上の段階は下の段階に負けない**
/// （会長決裁 2026-09-25。`CPUBenchTests` で隣り合う段階どうしを先後入れ替えで計測する）。
/// 「入門」は簡単と同じ打ち方のまま、**相手の四・開三を防ぐ率**と**候補の広さ**を緩め、
/// 形を見ずに打つ回を混ぜてある（#1174・#1399。手なりに打っても偶然の連で簡単に勝たないように）。
/// 自分の五は必ず取るところは変えていないので、弱いが壊れてはいない。
public struct SimpleGomokuEngine: GomokuEngine {
    var depth: Int
    let timeLimit: TimeInterval
    /// 探索の時計。テストが「最後の根手の評価中に時間切れ」を実時間なしで再現するために差し替える（#1226）。
    let now: @Sendable () -> Date
    /// 連珠の禁じ手ルール（#441）。オンのとき、黒番では三三・四四・長連を候補から外す。
    let forbiddenMoves: Bool
    /// 「弱」か（#665）。弱は探索せず `GomokuSearchContext.weakMove` の1手先の形だけで打つ。
    /// 「入門」（#1174）も同じ打ち方なので、どちらもここが true になる。
    let isWeak: Bool
    /// 弱が相手の即勝ち（四）を防ぐ確率（#665）。残りは見逃すので、人間が五を完成できる。
    let weakBlockRate: Double
    /// 乱数の種。`nil` なら実プレイ用に毎回違う乱数を使う（テストだけが種を渡して再現する）。
    let seed: UInt64?
    /// 読まない段階が着手をどこから選ぶか。「入門」は広げて手なりに打つ（#1174）。
    let weakChoice: WeakChoice
    /// 読む局面数の上限（`nil` なら無し）。段階の強さはこれが決め、端末が遅くても変わらないようにする（#1399。
    /// 時間主体だと遅い端末ほど浅くしか読めず、ふつうとむずかしいが同じ深さに潰れる）。時間は安全用に長めに残す。
    var nodeLimit: Int?
    /// 根より先の各局面で読む手の数（点の高い順）。`nil` なら全部。強制手（勝ち・防ぎ）は点が最上位なので落ちない。
    /// 絞ると同じ局面数でずっと深く読める（#1399）。
    let breadth: Int?
    /// 四を作る手は 1 手ぶん深く読む（強制手なので分岐が少ない）。浅い探索が四三の罠を読み落とすのを補う。
    let extendsFours: Bool
    /// 探索したあとの手の選び方（#1399）。読まない段階（入門・簡単）は使わない。
    var policy: GomokuMovePolicy
    /// 相手の四四・四三・三三の形を作らせない／自分が作れるなら作る（読みが浅い段階の補い）。
    let seesDoubleThreats: Bool

    /// 弱の既定の防御率。深さ3の読みと即防ぎを持っていた旧「弱」は盤ゲーム5本で最も強かった（#665）。
    static let defaultWeakBlockRate = 0.5
    /// 「入門」の防御率（#1174）。簡単の半分以下にして、人間の四がだいたい通るようにする。
    static let noviceBlockRate = 0.05
    /// 段階の差を付ける読みの局面数（#1399）。時間は安全用に長めに残す。
    static let normalDepth = 3
    static let hardDepth = 9
    static let normalNodeLimit = 15_000
    static let hardNodeLimit = 600_000
    static let hardBreadth = 14
    /// ふつう: 10% の手番だけ「評価で 150 以内の損」の手を混ぜる（開二つぶんに満たない。形の甘い手が出る程度）。
    /// むずかしいは 100% 最善手。
    static let normalPolicy = GomokuMovePolicy(slipProbability: 0.10, slipMargin: 150, tieMargin: 0, forcesDefense: true)

    /// 読まない段階が乱択する候補の広さ。広げるほど形の良し悪しを気にしなくなる。
    struct WeakChoice: Equatable, Sendable {
        /// 形を見ずに候補から無作為に打つ確率（#1399）。手なりに打つ入門が、偶然の連を作って簡単に勝たないようにする。
        var randomRate = 0.0
        /// 点の高い順に何手まで候補にするか。
        let count: Int
        /// 最善の何分の1以上の点が付いた手までを候補にするか（2 なら半分以上）。
        let shareDenominator: Int
    }

    /// 「簡単」の広さ（#665 の実装そのまま。上位 3 手・最善の半分以上）。
    static let easyChoice = WeakChoice(count: 3, shareDenominator: 2)
    /// 「入門」の広さ（#1174）。上位 6 手・最善の 1/4 以上まで広げる。
    /// 防御率を下げるだけでは簡単と互角だったため（実測 20/40）、形の選び方も崩している。
    static let noviceChoice = WeakChoice(randomRate: 0.6, count: 8, shareDenominator: 20)

    public init(level: Int = CPUStrength.standard.rawValue, forbiddenMoves: Bool = false) {
        self.init(level: level, forbiddenMoves: forbiddenMoves, seed: nil)
    }

    init(level: Int, forbiddenMoves: Bool = false, seed: UInt64?,
         weakBlockRate: Double? = nil, maxDepth: Int? = nil, nodeLimit: Int?? = nil, policy: GomokuMovePolicy? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        let strength = CPUStrength.strength(for: level)
        switch strength {
        case .novice:  (depth, timeLimit, self.nodeLimit, self.policy) = (1, 0.4, nil, .exact)
        case .easy:    (depth, timeLimit, self.nodeLimit, self.policy) = (1, 0.4, nil, .exact)
        case .hard:    (depth, timeLimit, self.nodeLimit, self.policy) = (Self.hardDepth, 4.0, Self.hardNodeLimit, .exact)
        case .normal:  (depth, timeLimit, self.nodeLimit, self.policy) = (Self.normalDepth, 3.0, Self.normalNodeLimit, Self.normalPolicy)
        }
        seesDoubleThreats = strength == .normal
        breadth = strength == .hard ? Self.hardBreadth : nil
        extendsFours = strength == .hard
        if let nodeLimit { self.nodeLimit = nodeLimit }   // テスト用: 局面数の上限を差し替える
        if let policy { self.policy = policy }
        if let maxDepth { depth = maxDepth }   // テスト用: 反復深化の上限を絞る（#1226）
        self.forbiddenMoves = forbiddenMoves
        self.isWeak = strength == .easy || strength == .novice
        self.weakBlockRate = weakBlockRate
            ?? (strength == .novice ? Self.noviceBlockRate : Self.defaultWeakBlockRate)
        self.weakChoice = strength == .novice ? Self.noviceChoice : Self.easyChoice
        self.seed = seed
    }

    public func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)? {
        var rng = GomokuRandom(seed: seed)
        if isWeak {
            // 探索しないので置換表（約4MB）は確保しない。
            let ctx = GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit,
                                          forbiddenMoves: forbiddenMoves, transpositionTableSize: 0, now: now)
            return ctx.weakMove(board: board, stone: stone, blockRate: weakBlockRate,
                                choice: weakChoice, using: &rng)
        }
        var ctx = GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit,
                                      forbiddenMoves: forbiddenMoves, nodeLimit: nodeLimit, breadth: breadth, extendsFours: extendsFours, now: now)
        // 読みが浅いふつうの補い: 相手の開三・二重の脅威を先に潰し、自分が四を伴う二重の脅威を作れるなら作る。
        var only: [Int]? = nil
        if policy.forcesDefense {
            let candidates = ctx.legalMoves(ctx.candidateMoves(board: board), board: board, stone: stone)
            let opp = stone.opponent
            let winning = candidates.contains { var b = board; b[$0.0, $0.1] = stone; return b.checkWin(row: $0.0, col: $0.1) }
            let mustBlockFour = candidates.contains { m in
                guard !ctx.isForbidden(board, row: m.0, col: m.1, stone: opp) else { return false }
                var b = board; b[m.0, m.1] = opp; return b.checkWin(row: m.0, col: m.1)
            }
            if !winning, !mustBlockFour {
                // 1. 四を伴う二重の脅威は、相手に開三があっても先に決まる。
                // 2. 相手の開三は止める。3. 三三は相手に開三が無いときだけ。4. 相手の二重の脅威を作らせない。
                let mine = seesDoubleThreats
                    ? ctx.doubleThreatPoints(board, stone: stone, candidates: candidates) : (withFour: [], threesOnly: [])
                let threeBlocks = candidates.filter { ctx.makesOpenFour(board, row: $0.0, col: $0.1, stone: opp) }
                if let attack = mine.withFour.first {
                    return (attack / gomokuBoardSize, attack % gomokuBoardSize)
                } else if !threeBlocks.isEmpty {
                    only = threeBlocks.map { $0.0 * gomokuBoardSize + $0.1 }
                } else if let attack = mine.threesOnly.first {
                    return (attack / gomokuBoardSize, attack % gomokuBoardSize)
                } else if seesDoubleThreats {
                    let theirs = ctx.doubleThreatPoints(
                        board, stone: opp,
                        candidates: ctx.legalMoves(ctx.candidateMoves(board: board), board: board, stone: opp))
                    let points = theirs.withFour + theirs.threesOnly
                    if !points.isEmpty { only = points }
                }
            }
        }
        let best = ctx.search(board: board, stone: stone, scoreWindow: policy.slipProbability > 0 || policy.tieMargin > 0 ? max(policy.slipMargin, policy.tieMargin) : nil, only: only)
        guard !policy.isExact, !ctx.rootScores.isEmpty else { return best }
        let picked = policy.choose(ctx.rootScores, using: &rng)
        return picked.map { ($0 / gomokuBoardSize, $0 % gomokuBoardSize) } ?? best
    }

    /// 計測用: 探索した局面数と読み切った深さ（`bestMove` と同じ設定で 1 手だけ探索する）。
    func analyze(board: GomokuBoard, stone: GomokuStone) -> (move: (Int, Int)?, nodes: Int, depth: Int) {
        var ctx = GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit,
                                      forbiddenMoves: forbiddenMoves, nodeLimit: nodeLimit, breadth: breadth, extendsFours: extendsFours, now: now)
        let move = ctx.search(board: board, stone: stone)
        return (move, ctx.nodes, ctx.completedDepth)
    }

    /// 探索が読む候補手の並び。テストが全順序になっていることを確かめる窓口（#812）。
    func candidateMoves(board: GomokuBoard) -> [(Int, Int)] {
        GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit, forbiddenMoves: forbiddenMoves,
                            transpositionTableSize: 0, now: now).candidateMoves(board: board)
    }
}

// MARK: - SearchContext

private struct GomokuSearchContext {
    let maxDepth: Int
    let deadline: Date
    let now: @Sendable () -> Date
    let forbiddenMoves: Bool
    var killers: [[Int?]]   // killers[ply][0..1]、row*15+col でエンコード
    var tt: [GomokuTTEntry]
    /// 読む局面数の上限（`nil` なら無し）。超えたら時間切れと同じに打ち切る（#1399）。
    let nodeLimit: Int?
    let breadth: Int?
    let extendsFours: Bool
    /// 深い局面ほど読む手を減らす下限（`breadth` から 1 手ずつ減らす）。
    static let minimumBreadth = 6
    private(set) var nodes = 0
    /// 最後に読み切った深さ（計測用）。
    private(set) var completedDepth = 0
    /// 最後に読み切った深さでの根の全候補の評価値（`scoreWindow` を渡したときだけ埋まる）。
    private(set) var rootScores: [(move: Int, score: Int)] = []

    init(maxDepth: Int, timeLimit: TimeInterval, forbiddenMoves: Bool,
         transpositionTableSize: Int = GOMOKU_TT_SIZE, nodeLimit: Int? = nil, breadth: Int? = nil, extendsFours: Bool = false,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.maxDepth = maxDepth
        self.nodeLimit = nodeLimit
        self.breadth = breadth
        self.extendsFours = extendsFours
        self.now = now
        self.deadline = now().addingTimeInterval(timeLimit)
        self.forbiddenMoves = forbiddenMoves
        self.killers = [[Int?]](repeating: [nil, nil], count: maxDepth + 10)
        self.tt = [GomokuTTEntry](repeating: GomokuTTEntry(), count: transpositionTableSize)
    }

    // MARK: 弱の着手（#665）

    /// 「弱」の着手: 読まずに1手先の形（`moveScore`）だけを見て打つ。
    ///
    /// - 自分の即勝ちは必ず取る（取らないと「勝てるのに打たない」不自然な CPU になる）。
    /// - 相手の即勝ちを防ぐのは `blockRate` の確率だけ。見逃した回は防ぐ手を候補から外す
    ///   （外さないと `moveScore` が防ぐ手を最上位に置くので、結局そこへ打って穴にならない）。
    /// - それ以外は、最善に近い点が付いた手（`choice` の広さ）から乱択する。
    ///   「簡単」は最善の半分以上・最大3手なので、形の良い手がある局面で無意味な手を打つほどは
    ///   崩さない。「入門」はここを広げて手なりに打つ（#1174）。
    func weakMove<R: RandomNumberGenerator>(
        board: GomokuBoard, stone: GomokuStone, blockRate: Double,
        choice: SimpleGomokuEngine.WeakChoice, using rng: inout R
    ) -> (Int, Int)? {
        let candidates = legalMoves(candidateMoves(board: board), board: board, stone: stone)
        guard !candidates.isEmpty else { return (gomokuBoardSize / 2, gomokuBoardSize / 2) }

        for (r, c) in candidates {
            var b = board; b[r, c] = stone
            if b.checkWin(row: r, col: c) { return (r, c) }
        }

        let opp = stone.opponent
        let blocks = candidates.filter { move in
            guard !isForbidden(board, row: move.0, col: move.1, stone: opp) else { return false }
            var b = board; b[move.0, move.1] = opp
            return b.checkWin(row: move.0, col: move.1)
        }
        var pool = candidates
        if !blocks.isEmpty {
            if Double.random(in: 0..<1, using: &rng) < blockRate { return blocks[0] }
            let rest = candidates.filter { m in !blocks.contains { $0 == m } }
            if !rest.isEmpty { pool = rest }
        }

        // 相手の開三（置かれると活四になる点）を防ぐのも `blockRate` の確率だけ（#1399）。
        // 四を止めるだけだと、開三を放置しても四を作られてから止める形になり、見逃しが弱さに効かない。
        let openFourPoints = pool.filter { makesOpenFour(board, row: $0.0, col: $0.1, stone: opp) }
        if !openFourPoints.isEmpty, Double.random(in: 0..<1, using: &rng) >= blockRate {
            let rest = pool.filter { m in !openFourPoints.contains { $0 == m } }
            if !rest.isEmpty { pool = rest }
        }

        if choice.randomRate > 0, Double.random(in: 0..<1, using: &rng) < choice.randomRate {
            return pool[Int.random(in: 0..<pool.count, using: &rng)]
        }
        let scored = pool
            .map { (move: $0, score: moveScore($0.0 * gomokuBoardSize + $0.1, board: board, stone: stone,
                                                killers: [nil, nil], ttMove: nil)) }
            // 同点は座標順に並べる。候補は Set 由来で並びが実行ごとに変わるため、種が同じなら同じ手になるようにする。
            .sorted { $0.score != $1.score ? $0.score > $1.score
                                           : ($0.move.0, $0.move.1) < ($1.move.0, $1.move.1) }
        let best = scored[0].score
        let choices = scored.prefix(choice.count).filter { $0.score * choice.shareDenominator >= best }
        return choices[Int.random(in: 0..<choices.count, using: &rng)].move
    }

    /// `stone` がそこに打つと、両端が空いた四（活四）ができるか。相手の開三を防ぐ点の判定に使う（#1399）。
    func makesOpenFour(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone) -> Bool {
        var b = board; b[row, col] = stone
        for (dr, dc) in gomokuDirections {
            var count = 1
            var ends = 0
            for sign in [-1, 1] {
                var r = row + dr * sign, c = col + dc * sign
                while r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize && b[r, c] == stone {
                    count += 1; r += dr * sign; c += dc * sign
                }
                if r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize && b[r, c] == nil { ends += 1 }
            }
            if count == 4 && ends == 2 { return true }
        }
        return false
    }

    // MARK: 開三・二重の脅威

    /// `stone` の開三（連続 3・両端が空き）の遮断点。線ごとに、両端とその外側 1 点までの空き点を返す。
    func openThreeLines(_ board: GomokuBoard, stone: GomokuStone) -> [[Int]] {
        var lines: [[Int]] = []
        func empty(_ r: Int, _ c: Int) -> Bool {
            r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize && board[r, c] == nil
        }
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize where board[row, col] == stone {
                for (dr, dc) in gomokuDirections {
                    let (pr, pc) = (row - dr, col - dc)
                    if pr >= 0 && pr < gomokuBoardSize && pc >= 0 && pc < gomokuBoardSize && board[pr, pc] == stone { continue }
                    var count = 0
                    var (r, c) = (row, col)
                    while r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize && board[r, c] == stone {
                        count += 1; r += dr; c += dc
                    }
                    guard count == 3, empty(r, c), empty(pr, pc) else { continue }
                    var pts = [r * gomokuBoardSize + c, pr * gomokuBoardSize + pc]
                    if empty(r + dr, c + dc) { pts.append((r + dr) * gomokuBoardSize + c + dc) }
                    if empty(pr - dr, pc - dc) { pts.append((pr - dr) * gomokuBoardSize + pc - dc) }
                    lines.append(pts)
                }
            }
        }
        return lines
    }

    /// `stone` が打つと、相手が 1 手では止められない形になる空き点。四を伴うもの（四四・活四・四三）と、
    /// 開三 2 本だけのもの（三三）に分ける。相手に四がある局面（先に五を打たれる）では空。
    func doubleThreatPoints(_ board: GomokuBoard, stone: GomokuStone,
                            candidates: [(Int, Int)]) -> (withFour: [Int], threesOnly: [Int]) {
        guard fiveSquares(board, stone: stone.opponent).isEmpty else { return ([], []) }
        let before = openThreeLines(board, stone: stone).count
        var withFour: [Int] = [], threesOnly: [Int] = []
        for (r, c) in candidates {
            var b = board; b[r, c] = stone
            guard fiveSquares(b, stone: stone.opponent).isEmpty else { continue }
            let fives = fiveSquares(b, stone: stone).count
            let threes = openThreeLines(b, stone: stone).count - before
            if fives >= 2 || (fives == 1 && threes >= 1) { withFour.append(r * gomokuBoardSize + c) }
            else if fives == 0 && threes >= 2 { threesOnly.append(r * gomokuBoardSize + c) }
        }
        return (withFour, threesOnly)
    }

    /// `stone` が打つと五になる空き点（禁じ手の黒は除く）。
    func fiveSquares(_ board: GomokuBoard, stone: GomokuStone) -> [Int] {
        var out: [Int] = []
        for (r, c) in candidateMoves(board: board) {
            guard !isForbidden(board, row: r, col: c, stone: stone) else { continue }
            var b = board; b[r, c] = stone
            if b.checkWin(row: r, col: c) { out.append(r * gomokuBoardSize + c) }
        }
        return out
    }

    // MARK: 禁じ手のふるい分け（#441）

    /// その手が「打ってはいけない手」か。禁じ手ルールがオフ、または白番なら常に `false`。
    func isForbidden(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone) -> Bool {
        guard forbiddenMoves, stone == .black else { return false }
        return board.renjuForbidden(row: row, col: col) != nil
    }

    /// 候補手から禁じ手を落とす。近傍の候補が全滅したときだけ、盤全体から打てる交点を拾う
    /// （打つ場所が無くなって CPU が固まるのを防ぐ。禁じ手は黒自身の形の近くにしか出ないため、
    /// 離れた交点はほぼ確実に打てる）。
    func legalMoves(_ candidates: [(Int, Int)], board: GomokuBoard, stone: GomokuStone) -> [(Int, Int)] {
        guard forbiddenMoves, stone == .black else { return candidates }
        let legal = candidates.filter { !isForbidden(board, row: $0.0, col: $0.1, stone: stone) }
        guard legal.isEmpty else { return legal }
        var fallback: [(Int, Int)] = []
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize where board[row, col] == nil {
                if !isForbidden(board, row: row, col: col, stone: stone) { fallback.append((row, col)) }
            }
        }
        return fallback
    }

    // MARK: 反復深化

    /// 時間か局面数の上限に達したか。
    private var expired: Bool {
        if let nodeLimit, nodes >= nodeLimit { return true }
        return now() > deadline
    }

    /// `scoreWindow` を渡すと、最善から `scoreWindow` 以内の手はすべて正確な評価値を持つように根を探索し、
    /// `rootScores` に残す（手の選び方 `GomokuMovePolicy` の材料。窓の外の手は上限値になるので選ばれない）。
    /// `only` を渡すと、根の候補をその手（row*15+col）だけに絞り、即勝ち・即防ぎの自動選択もしない（簡単の防御見逃しの材料）。
    mutating func search(board: GomokuBoard, stone: GomokuStone, scoreWindow: Int? = nil,
                         only: [Int]? = nil) -> (Int, Int)? {
        let candidates = legalMoves(candidateMoves(board: board), board: board, stone: stone)
        guard !candidates.isEmpty else { return (gomokuBoardSize / 2, gomokuBoardSize / 2) }
        if let only, !only.isEmpty {
            return searchRoot(board: board, stone: stone, roots: only, scoreWindow: scoreWindow)
        }

        // 即勝ち（候補は禁じ手を除いてあるので、黒の 6 連は最初から入っていない）
        for (r, c) in candidates {
            var b = board; b[r, c] = stone
            if b.checkWin(row: r, col: c) { return (r, c) }
        }
        // 相手の即勝ちをブロック。相手が打てない手（禁じ手）は脅威ではないので数えない。
        let opp = stone.opponent
        for (r, c) in candidates where !isForbidden(board, row: r, col: c, stone: opp) {
            var b = board; b[r, c] = opp
            if b.checkWin(row: r, col: c) { return (r, c) }
        }

        return searchRoot(board: board, stone: stone, roots: candidates.map { $0.0 * gomokuBoardSize + $0.1 },
                          scoreWindow: scoreWindow)
    }

    private mutating func searchRoot(board: GomokuBoard, stone: GomokuStone, roots: [Int],
                                     scoreWindow: Int?) -> (Int, Int)? {
        let opp = stone.opponent
        let rootHash = board.zobristHash(stone: stone)
        var orderedEncoded = orderMoves(roots, board: board, stone: stone, killers: [nil, nil], ttMove: nil)
        guard let first = orderedEncoded.first else { return nil }
        var best: (Int, Int) = (first / gomokuBoardSize, first % gomokuBoardSize)

        for d in 1...maxDepth {
            if expired { break }
            var localBest: Int? = nil
            var scores: [(move: Int, score: Int)] = []
            var bestScore = Int.min + 1
            var alpha = Int.min + 1
            let beta = Int.max
            var aborted = false
            var b = board

            for encoded in orderedEncoded {
                if expired { aborted = true; break }
                let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
                b[r, c] = stone
                let score: Int
                if b.checkWin(row: r, col: c) {
                    score = 100_000 + d
                } else {
                    score = -negamax(&b, stone: opp, depth: d - 1 + fourExtension(b, row: r, col: c, stone: stone, ply: 0),
                                     alpha: -beta, beta: -alpha, ply: 1,
                                     hash: rootHash ^ GomokuZobrist.stone[stone.rawValue][encoded] ^ GomokuZobrist.sideToMove)
                }
                b[r, c] = nil
                if score > bestScore { bestScore = score; localBest = encoded }
                if let scoreWindow { alpha = max(alpha, bestScore - scoreWindow - 1) } else if score > alpha { alpha = score }
                scores.append((encoded, score))
            }

            // 最後の根手の評価中に期限切れになっていた場合もここで拾う。ループ先頭のチェックだけだと、
            // 全ての根手を一応は評価しているのに「読み切った」と誤採用する（`negamax` は期限切れで
            // 静的評価を即返すため、その深さの評価値が不完全になる。#1226）。
            if expired { aborted = true }
            if !aborted, let lb = localBest {
                completedDepth = d
                if scoreWindow != nil { rootScores = scores }
                best = (lb / gomokuBoardSize, lb % gomokuBoardSize)
                orderedEncoded.removeAll { $0 == lb }
                orderedEncoded.insert(lb, at: 0)
            }
            if aborted { break }
        }
        return best
    }

    /// 四を作った手の分だけ深さを延ばす（延長は先の手数の上限までに限る）。
    func fourExtension(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone, ply: Int) -> Int {
        guard extendsFours, ply < maxDepth + 4, localThreatScore(board, row: row, col: col, stone: stone) >= 10_000 else { return 0 }
        return 1
    }

    // MARK: αβ ネガマックス + 置換表 + キラー

    mutating func negamax(_ board: inout GomokuBoard, stone: GomokuStone, depth: Int,
                          alpha: Int, beta: Int, ply: Int, hash: UInt64) -> Int {
        nodes += 1
        if expired { return evaluate(board, for: stone) }

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

        let candidates = legalMoves(candidateMoves(board: board), board: board, stone: stone)
        if candidates.isEmpty { return 0 }

        var alpha = alpha
        var flag: GomokuTTFlag = .upper
        var bestMoveEncoded = 0xFFFF
        let killerSet = ply < killers.count ? killers[ply] : [nil, nil]

        for encoded in orderMoves(candidates.map { $0.0 * gomokuBoardSize + $0.1 },
                                  board: board, stone: stone, killers: killerSet, ttMove: ttMove)
            .prefix(breadth.map { max(Self.minimumBreadth, $0 - (ply - 1)) } ?? Int.max) {
            let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
            board[r, c] = stone
            let score: Int
            if board.checkWin(row: r, col: c) {
                score = 100_000 + depth
            } else {
                score = -negamax(&board, stone: stone.opponent,
                                 depth: depth - 1 + fourExtension(board, row: r, col: c, stone: stone, ply: ply),
                                 alpha: -beta, beta: -alpha, ply: ply + 1,
                                 hash: hash ^ GomokuZobrist.stone[stone.rawValue][encoded] ^ GomokuZobrist.sideToMove)
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
        // 点は 1 手につき 1 回だけ求める（比較のたびに求めると盤の複製が手数×log 回走って探索が遅い）。
        encoded.map { (move: $0, score: moveScore($0, board: board, stone: stone, killers: killers, ttMove: ttMove)) }
            .sorted { $0.score > $1.score }
            .map(\.move)
    }

    func moveScore(_ encoded: Int, board: GomokuBoard, stone: GomokuStone,
                   killers: [Int?], ttMove: Int?) -> Int {
        if let tm = ttMove, tm == encoded { return 300_000 }
        let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
        // 盤を複製せずに「そこに置いたら」の値を求める（探索の最も熱い所。#1399）。
        let myThreat = threatScoreIfPlaced(board, row: r, col: c, stone: stone)
        if myThreat >= 100_000 { return 200_000 }
        let oppThreat = threatScoreIfPlaced(board, row: r, col: c, stone: stone.opponent)
        if oppThreat >= 100_000 { return 190_000 }
        if killers.contains(where: { $0 == encoded }) { return 100_000 }
        return myThreat + oppThreat
    }

    /// 空きの升 (row, col) に `stone` を置いたと仮定した `localThreatScore`（盤は変えない）。
    func threatScoreIfPlaced(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone) -> Int {
        var score = 0
        for (dr, dc) in gomokuDirections {
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

    // 指定升に置いたときの局所的連続カウント（自分視点）
    func localThreatScore(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone) -> Int {
        guard let s = board[row, col], s == stone else { return 0 }
        var score = 0
        for (dr, dc) in gomokuDirections {
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

    /// 次に打つ `stone` から見た評価（自分の形 − 相手の形）。盤を 1 回なめて両色を数える（探索の最も熱い所）。
    ///
    /// 次に打つ側の四（片端でも空いていれば次で五）と、打たない側の活四（片方しか止められない）は、
    /// ほぼ勝ちなので大きく評価する（#1399）。静的評価で見ないと、浅い探索が「相手の開三を放置すると
    /// 活四を作られて負ける」ことを読み切れない。次に打つ側の開三は次で活四になる。打たない側の開三が
    /// 2 本あると、次の一手では両方止められない。
    func evaluate(_ board: GomokuBoard, for stone: GomokuStone) -> Int {
        let n = gomokuBoardSize
        let cells = board.cells
        var mine = 0, theirs = 0
        var mineThrees = 0, theirsThrees = 0
        for row in 0..<n {
            for col in 0..<n {
                guard let s = cells[row * n + col] else { continue }
                let toMove = s == stone
                for (dr, dc) in gomokuDirections {
                    let pr = row - dr, pc = col - dc
                    if pr >= 0 && pr < n && pc >= 0 && pc < n && cells[pr * n + pc] == s { continue }
                    var count = 1
                    var r = row + dr, c = col + dc
                    while r >= 0 && r < n && c >= 0 && c < n && cells[r * n + c] == s { count += 1; r += dr; c += dc }
                    let openFront = r >= 0 && r < n && c >= 0 && c < n && cells[r * n + c] == nil
                    let openBack = pr >= 0 && pr < n && pc >= 0 && pc < n && cells[pr * n + pc] == nil
                    let open = (openFront ? 1 : 0) + (openBack ? 1 : 0)
                    if count == 3, open == 2 { if toMove { mineThrees += 1 } else { theirsThrees += 1 } }
                    let value = count == 4 && (toMove ? open >= 1 : open == 2) ? 50_000 : patternScore(count: count, open: open)
                    if toMove { mine += value } else { theirs += value }
                }
            }
        }
        if mineThrees >= 1 { mine += 20_000 }
        if theirsThrees >= 2 { theirs += 30_000 }
        return mine - theirs
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
        var marked = [Bool](repeating: false, count: gomokuBoardSize * gomokuBoardSize)
        var hasStone = false
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize where board[row, col] != nil {
                hasStone = true
                for r in max(0, row - 2)...min(gomokuBoardSize - 1, row + 2) {
                    for c in max(0, col - 2)...min(gomokuBoardSize - 1, col + 2) where board[r, c] == nil {
                        marked[r * gomokuBoardSize + c] = true
                    }
                }
            }
        }
        guard hasStone else { return [(gomokuBoardSize / 2, gomokuBoardSize / 2)] }
        // 中央に近い順・同じ距離なら座標順で拾う。走査順が実行ごとに変わると即勝ち・防ぎ点の選び方が揺れ、
        // 種を固定しても CPU の手が再現しないため、全順序にしてある（#812）。
        var out: [(Int, Int)] = []
        for sq in gomokuCenterOrder where marked[sq] { out.append((sq / gomokuBoardSize, sq % gomokuBoardSize)) }
        return out
    }
}
