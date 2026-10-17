import Foundation
import CoreEngine

// MARK: - ビットボード

/// 探索用の盤（ビットボード）。列 `c` の段 `r`（下から）を bit `c * 7 + r` に置く。各列の 7 段目は番兵で常に空。
///
/// `current` は**次に打つ側**の石、`mask` は両者の石。1 手打つと `current` が相手側に入れ替わる
/// （自分の石 = `current ^ mask` になる）。値型なのでコピーで子局面を作る。
struct YonmokuBits: Sendable {
    static let height = YonmokuBoard.rows
    static let width = YonmokuBoard.columns
    static let stride = height + 1

    var current: UInt64
    var mask: UInt64
    var moves: Int

    static let bottomAll: UInt64 = (0..<width).reduce(0) { $0 | bottom($1) }
    static let boardMask: UInt64 = bottomAll &* ((1 << UInt64(height)) - 1)

    static func bottom(_ col: Int) -> UInt64 { 1 << UInt64(col * stride) }
    static func top(_ col: Int) -> UInt64 { 1 << UInt64(col * stride + height - 1) }
    static func column(_ col: Int) -> UInt64 { ((1 << UInt64(height)) - 1) << UInt64(col * stride) }

    init(board: YonmokuBoard, toMove disc: YonmokuDisc) {
        var current: UInt64 = 0, mask: UInt64 = 0
        for col in 0..<Self.width {
            for row in 0..<Self.height {
                guard let d = board[col, row] else { continue }
                let bit: UInt64 = 1 << UInt64(col * Self.stride + row)
                mask |= bit
                if d == disc { current |= bit }
            }
        }
        self.current = current
        self.mask = mask
        moves = board.discCount
    }

    /// 同じ局面で同じ値になる鍵（`current + mask` は局面ごとに一意）。
    var key: UInt64 { current &+ mask }

    func canPlay(_ col: Int) -> Bool { mask & Self.top(col) == 0 }

    /// `col` に打ったら次に打つ側（いまの相手）から見た局面。
    func played(_ col: Int) -> YonmokuBits {
        var next = self
        next.current ^= mask
        next.mask |= mask &+ Self.bottom(col)
        next.moves += 1
        return next
    }

    /// `col` に打つと 4 つ並ぶか。
    func isWinningMove(_ col: Int) -> Bool {
        let pos = current | ((mask &+ Self.bottom(col)) & Self.column(col))
        return Self.hasFour(pos)
    }

    /// 打てるマス（各列の一番下の空き）。
    var possible: UInt64 { (mask &+ Self.bottomAll) & Self.boardMask }

    /// 相手が置けば 4 つ並ぶ空きマス。
    var opponentWinningSpots: UInt64 { Self.winningSpots(current ^ mask, mask: mask) }

    /// 次の 1 手で負けない手（相手の即勝ちを止める・相手の勝ちマスの真下を埋めない）。
    /// 自分の即勝ちが無いことを確かめてから呼ぶ。0 なら何を打っても次に負ける。
    func nonLosingMoves() -> UInt64 {
        var possible = self.possible
        let opponentWin = opponentWinningSpots
        let forced = possible & opponentWin
        if forced != 0 {
            if forced & (forced &- 1) != 0 { return 0 }   // 止める先が 2 つ以上
            possible = forced
        }
        return possible & ~(opponentWin >> 1)
    }

    static func hasFour(_ pos: UInt64) -> Bool {
        for shift in [UInt64(1), UInt64(stride), UInt64(stride - 1), UInt64(stride + 1)] {
            let m = pos & (pos >> shift)
            if m & (m >> (2 * shift)) != 0 { return true }
        }
        return false
    }

    /// `pos` の側が置けば 4 つ並ぶ空きマス。
    static func winningSpots(_ pos: UInt64, mask: UInt64) -> UInt64 {
        // 縦
        var r = (pos << 1) & (pos << 2) & (pos << 3)
        // 横・斜め 2 方向
        for s in [UInt64(stride), UInt64(stride - 1), UInt64(stride + 1)] {
            var p = (pos << s) & (pos << (2 * s))
            r |= p & (pos << (3 * s))
            r |= p & (pos >> s)
            p = (pos >> s) & (pos >> (2 * s))
            r |= p & (pos << s)
            r |= p & (pos >> (3 * s))
        }
        return r & (boardMask ^ mask)
    }
}

// MARK: - 手の選び方

/// 段階ごとの「最善手を打つ確率」と、外したときに許す損（五目並べ #1463 と同じ形）。
struct YonmokuMovePolicy: Equatable, Sendable {
    /// 探索が出した最善手をそのまま打つ確率（0...1）。
    var bestMoveProbability: Double
    /// 外したときに許す損の幅（評価値の差）。nil なら幅を問わない（入門）。
    var slipMargin: Int?
    /// 外しの候補に「読みの中で負けが決まる手」を入れるか（入門だけ true）。
    var allowsLosingSlip: Bool

    static let exact = YonmokuMovePolicy(bestMoveProbability: 1, slipMargin: 0, allowsLosingSlip: false)
    var isExact: Bool { bestMoveProbability >= 1 }

    /// 外したときの手。最善手以外で条件に合う手から乱択する。候補が無ければ nil（最善手を打つ）。
    func slip<R: RandomNumberGenerator>(_ scores: [(col: Int, score: Int)], best: Int,
                                        using rng: inout R) -> Int? {
        guard let bestScore = scores.first(where: { $0.col == best })?.score else { return nil }
        // 勝ちが読み切れているときは外さない（入門を除く）。外すと「勝てるのに遠回りする」手が混ざり、
        // 1 手遅い勝ちの手（評価値が 1 しか違わない）を選んで、すぐ勝てるのに勝たない CPU に見える。
        if slipMargin != nil, bestScore >= YonmokuEngine.decisiveScore { return nil }
        let pool = scores.filter { entry in
            guard entry.col != best else { return false }
            if !allowsLosingSlip, entry.score <= -YonmokuEngine.decisiveScore { return false }
            if let slipMargin, entry.score < bestScore - slipMargin { return false }
            return true
        }
        guard !pool.isEmpty else { return nil }
        return pool[Int(rng.next() % UInt64(pool.count))].col
    }
}

// MARK: - Engine

/// 四目並べの CPU。`CPUStrength` の 4 段階に対応する。
///
/// | level | 表示 | 考える時間 | 読む深さの上限 | 最善手を打つ確率 | 外したときの手 |
/// |---|---|---|---|---|---|
/// | -1 | 入門 | 0.3 秒 | 1 手先 | 60% | どの列でも（止めるべき列・勝てる列を見のがすこともある） |
/// | 0 | かんたん | 0.5 秒 | 1 手先 | 60% | 負けが見えない手のうち、損の小さい手（読み切った勝ちは外さない） |
/// | 1 | ふつう | 1 秒 | 3 手先 | 75% | 同上 |
/// | 2 | むずかしい | 2 秒 | 無し（盤が埋まるまで） | 100% | — |
///
/// 探索は全段階で同じ（反復深化の αβ・置換表・中央の列から読む・相手の即勝ちを止めない手は読まない）。
/// 時間が来るか深さの上限まで読み終えたら打つ。読み切った局面（勝ち・負けが確定）では早く打つ。
/// 開始シートの説明（`YonmokuNewGameSheet`）はこの表と一致させること（#416）。
///
/// 実装時（2026-10-17・#1738）に自己対戦で測った「上の段の得点率」（勝ち 1・引き分け 0.5。先後を入れ替え）:
/// かんたん対入門 0.76（60 局）・ふつう対かんたん 0.83（80 局）・むずかしい対ふつう 1.0（6 局）。
/// 隣の段 60〜70% の目安（#1566）より開いているので、QA の手応えを見て調整する。
///
/// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存の盤ゲームと同じ番号）。
public struct YonmokuEngine: Sendable {
    /// 勝ちの評価値の基準。`decisiveScore` 以上は読みの中で勝ちが決まった手。
    static let winScore = 10_000
    static let decisiveScore = winScore - 100
    /// 中央の列から読む（枝刈りが効き、同点なら中央を選ぶ）。
    static let centerOrder = [3, 2, 4, 1, 5, 0, 6]

    let maxDepth: Int
    let timeLimit: TimeInterval
    let policy: YonmokuMovePolicy
    /// 乱数の種。nil なら毎回変わる（テストだけが種を渡して再現する）。
    let seed: UInt64?
    /// 探索の時計（テストが差し替えられるように）。
    let now: @Sendable () -> Date

    public init(level: Int, seed: UInt64? = nil) {
        let strength = CPUStrength.strength(for: level)
        let (depth, time, policy) = Self.settings(for: strength)
        self.init(maxDepth: depth, timeLimit: time, policy: policy, seed: seed)
    }

    init(maxDepth: Int, timeLimit: TimeInterval, policy: YonmokuMovePolicy, seed: UInt64? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.maxDepth = maxDepth
        self.timeLimit = timeLimit
        self.policy = policy
        self.seed = seed
        self.now = now
    }

    static func settings(for strength: CPUStrength) -> (depth: Int, time: TimeInterval, policy: YonmokuMovePolicy) {
        switch strength {
        case .novice:
            return (1, 0.3, YonmokuMovePolicy(bestMoveProbability: 0.6, slipMargin: nil, allowsLosingSlip: true))
        case .easy:
            return (1, 0.5, YonmokuMovePolicy(bestMoveProbability: 0.6, slipMargin: 40, allowsLosingSlip: false))
        case .normal:
            return (3, 1.0, YonmokuMovePolicy(bestMoveProbability: 0.75, slipMargin: 30, allowsLosingSlip: false))
        case .hard:
            return (YonmokuBoard.cellCount, 2.0, .exact)
        }
    }

    /// 打つ列（0〜6）。打てる列が無ければ nil。
    public func bestMove(board: YonmokuBoard, disc: YonmokuDisc) -> Int? {
        let playable = board.playableColumns
        guard !playable.isEmpty else { return nil }
        if playable.count == 1 { return playable[0] }
        let root = YonmokuBits(board: board, toMove: disc)
        let search = YonmokuSearch(deadline: now().addingTimeInterval(timeLimit), now: now)

        var completed: [(col: Int, score: Int)]?
        let remaining = YonmokuBoard.cellCount - root.moves
        for depth in 1...max(1, min(maxDepth, remaining)) {
            guard let scores = search.rootScores(root, depth: depth, exact: policy.isExact) else { break }
            completed = scores
            // 勝ち負けが読み切れたら、それ以上深く読んでも手は変わらない。
            if let top = scores.map(\.score).max(), abs(top) >= Self.decisiveScore { break }
            if depth == 1, scores.allSatisfy({ $0.score <= -Self.decisiveScore }) { break }
        }
        // 1 手目の読みも時間内に終わらなかったときの保険（実際には起きない）。
        let scores = completed ?? Self.centerOrder.filter { root.canPlay($0) }.map { ($0, 0) }
        var best = scores[0]
        for entry in scores where entry.score > best.score { best = entry }

        guard !policy.isExact else { return best.col }
        var rng = SplitMix64(seed: seed ?? UInt64.random(in: 0...UInt64.max))
        let roll = Double(rng.next() % 1_000_000) / 1_000_000
        if roll < policy.bestMoveProbability { return best.col }
        return policy.slip(scores, best: best.col, using: &rng) ?? best.col
    }
}

/// 1 回の手選びの探索（置換表と時計を持つ）。
final class YonmokuSearch {
    private let deadline: Date
    private let now: () -> Date
    private var nodes = 0
    private(set) var timedOut = false

    private static let tableBits = 18
    private var keys: [UInt64]
    private var values: [Int32]
    private var depths: [Int8]
    private var flags: [UInt8]   // 0 = exact, 1 = lower, 2 = upper

    init(deadline: Date, now: @escaping () -> Date) {
        self.deadline = deadline
        self.now = now
        let size = 1 << Self.tableBits
        keys = Array(repeating: 0, count: size)
        values = Array(repeating: 0, count: size)
        depths = Array(repeating: -1, count: size)
        flags = Array(repeating: 0, count: size)
    }

    /// 根の各手の評価値（中央の列から順）。時間切れなら nil。
    ///
    /// `exact` が true（むずかしい）のときは最善手だけが正しければよいので、2 手目以降は枠を狭めて読む
    /// （最善以外の値は上限になる）。false のときは外しの候補を比べるので、全部の手を正確に読む。
    func rootScores(_ root: YonmokuBits, depth: Int, exact: Bool) -> [(col: Int, score: Int)]? {
        var result: [(col: Int, score: Int)] = []
        var alpha = -YonmokuEngine.winScore * 2
        for col in YonmokuEngine.centerOrder where root.canPlay(col) {
            let score: Int
            if root.isWinningMove(col) {
                score = YonmokuEngine.winScore - root.moves
            } else {
                let lower = exact ? alpha : -YonmokuEngine.winScore * 2
                score = -negamax(root.played(col), depth: depth - 1, alpha: -YonmokuEngine.winScore * 2, beta: -lower)
            }
            if timedOut { return nil }
            result.append((col, score))
            alpha = max(alpha, score)
        }
        return result
    }

    private func negamax(_ p: YonmokuBits, depth: Int, alpha: Int, beta: Int) -> Int {
        nodes += 1
        if nodes & 1023 == 0, now() >= deadline { timedOut = true }
        if timedOut { return 0 }
        if p.moves >= YonmokuBoard.cellCount { return 0 }
        for col in 0..<YonmokuBits.width where p.canPlay(col) && p.isWinningMove(col) {
            return YonmokuEngine.winScore - p.moves
        }
        let next = p.nonLosingMoves()
        if next == 0 { return -(YonmokuEngine.winScore - p.moves - 1) }
        if p.moves + 1 >= YonmokuBoard.cellCount { return 0 }
        if depth <= 0 { return Self.evaluate(p) }

        var alpha = alpha, beta = beta
        // 鍵の下位ビットは左の列だけで決まるので、混ぜてから上位ビットを使う（中央の列だけ違う局面が同じ場所を奪い合わない）。
        let slot = Int((p.key &* SplitMix64.goldenGamma) >> UInt64(64 - Self.tableBits))
        if keys[slot] == p.key, Int(depths[slot]) >= depth {
            let v = Int(values[slot])
            switch flags[slot] {
            case 0: return v
            case 1: alpha = max(alpha, v)
            default: beta = min(beta, v)
            }
            if alpha >= beta { return v }
        }

        // 次に作れる「あと 1 つで 4」の数が多い手から読む（同数なら中央から）。
        var candidates: [(col: Int, order: Int)] = []
        for col in YonmokuEngine.centerOrder where next & YonmokuBits.column(col) != 0 {
            let move = (p.mask &+ YonmokuBits.bottom(col)) & YonmokuBits.column(col)
            let threats = YonmokuBits.winningSpots(p.current | move, mask: p.mask | move).nonzeroBitCount
            candidates.append((col, threats))
        }
        candidates.sort { $0.order > $1.order }   // 安定ソートなので同数は中央からの順のまま

        let originalAlpha = alpha
        var best = -YonmokuEngine.winScore * 2
        for (col, _) in candidates {
            let score = -negamax(p.played(col), depth: depth - 1, alpha: -beta, beta: -alpha)
            if timedOut { return 0 }
            if score > best { best = score }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }

        keys[slot] = p.key
        values[slot] = Int32(best)
        depths[slot] = Int8(min(depth, Int(Int8.max)))
        flags[slot] = best <= originalAlpha ? 2 : (best >= beta ? 1 : 0)
        return best
    }

    /// 次に打つ側から見た局面の点（読みの末端）。「あと 1 つで 4」の空きマスの数の差と、中央の列の石の差。
    static func evaluate(_ p: YonmokuBits) -> Int {
        let me = p.current, opponent = p.current ^ p.mask
        let mine = YonmokuBits.winningSpots(me, mask: p.mask).nonzeroBitCount
        let theirs = YonmokuBits.winningSpots(opponent, mask: p.mask).nonzeroBitCount
        let center = YonmokuBits.column(3)
        return 8 * (mine - theirs) + 3 * ((me & center).nonzeroBitCount - (opponent & center).nonzeroBitCount)
    }
}
