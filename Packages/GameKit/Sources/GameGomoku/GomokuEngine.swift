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

// MARK: - 手の選び方（#1463）

/// 段階ごとの「最善手を打つ確率」（会長決裁 2026-09-26・将棋 #1461 と同じ形）。
///
/// 難易度は**考える時間**（`SimpleGomokuEngine.timeLimit`）・読む深さの上限（`depth`）と、この確率で決める。
/// 確率が外れた手番は、同じ探索で最善から `slipMargin` 以内の手に正確な評価値を付け（`scoreWindow`）、
/// 最善以外のうち損が `slipMargin` 以内の手から乱択する。自分の五・相手の四を止める手は探索の前に
/// 決まる（外さない）ので、相手の五を止めない手は選ばれない。相手に五を作られる読み筋の手
/// （評価値 `losingScore` 以下）も選ばない。
struct GomokuMovePolicy: Equatable {
    /// 探索が出した最善手をそのまま打つ確率（0...1）。
    var bestMoveProbability: Double
    /// 外したときに許す損の幅（評価値の差）。
    var slipMargin: Int

    /// 最善手だけを選ぶ（むずかしい）。
    static let exact = GomokuMovePolicy(bestMoveProbability: 1, slipMargin: 0)
    /// 探索を素直に回すだけでよいか。
    var isExact: Bool { bestMoveProbability >= 1 }

    /// この値以下の評価値の手は、読みの中で相手に五（か止められない四）を作られる手。外しの候補に入れない。
    static let losingScore = -50_000

    /// 外したときの手。根の全候補の評価値から、`best` を除き、最善から `slipMargin` 以内の損で負けにならない手を
    /// 乱択する。候補が無ければ `nil`（呼び出し側は最善手を打つ）。
    func slip<R: RandomNumberGenerator>(_ scores: [(move: Int, score: Int)], best: Int,
                                        using rng: inout R) -> Int? {
        guard let bestScore = scores.first(where: { $0.move == best })?.score else { return nil }
        let pool = scores.filter {
            $0.move != best && $0.score >= bestScore - slipMargin && $0.score > Self.losingScore
        }
        guard !pool.isEmpty else { return nil }
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
/// | level | 表示 | 考える時間 | 読む深さの上限 | 最善手を打つ確率 |
/// |---|---|---|---|---|
/// | -1 | 入門 | 0.3 秒 | 3 手先 | `noviceBestMoveProbability` |
/// | 0 | かんたん | 0.5 秒 | 4 手先 | `easyBestMoveProbability` |
/// | 1 | ふつう | 1 秒 | 5 手先 | `normalBestMoveProbability` |
/// | 2 | むずかしい | 2 秒 | 無し（`maxDepth`） | 100% |
///
/// 探索（反復深化の αβ・各局面は点の高い `breadth` 手だけ読む・四を作る手は 1 手延長）は全段階で同じで、
/// 時間が来るか深さの上限まで読み終えたら打つ（#1463。会長決裁 2026-09-26・社長決定 2026-09-27）。
/// 確率の根拠は段階表（`docs/analytics/gomoku-1463-ladder.md`: 上の段の得点率 90% 以上で最も高い値）。
///
/// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
public struct SimpleGomokuEngine: GomokuEngine {
    var depth: Int
    /// 1 手の考える時間の上限（秒）。読み終われば早く打つ。
    let timeLimit: TimeInterval
    /// 探索の時計。テストが「最後の根手の評価中に時間切れ」を実時間なしで再現するために差し替える（#1226）。
    let now: @Sendable () -> Date
    /// 連珠の禁じ手ルール（#441）。オンのとき、黒番では三三・四四・長連を候補から外す。
    let forbiddenMoves: Bool
    /// 乱数の種。`nil` なら実プレイ用に毎回違う乱数を使う（テストだけが種を渡して再現する）。
    let seed: UInt64?
    /// 読む局面数の上限（`nil` なら無し）。出荷値では使わない（計測・テストが探索量を揃えるための口）。
    var nodeLimit: Int?
    var policy: GomokuMovePolicy

    /// 反復深化の深さの上限（むずかしい）。実際に止めるのは時間。
    static let maxDepth = 32
    /// 根より先の各局面で読む手の数（点の高い順）。強制手（勝ち・防ぎ）は点が最上位なので落ちない。
    /// 全段階で同じ（#1463。全幅で読むと深さ 5 で 1 秒を超える）。
    static let breadth = 14

    /// 最善手を打つ確率（#1463 の実測。上の段の得点率が 90% 以上になる、10% 刻みで最も高い値）。
    static let noviceBestMoveProbability = 1.0
    static let easyBestMoveProbability = 1.0
    static let normalBestMoveProbability = 1.0

    /// 外したときに許す損の幅（評価値の差）。開三 1 本（`patternScore` の 500）ぶん。
    /// 相手に活四を許す手（1 万以上）や、自分の開三を逃して相手に先手を渡す手は入らず、
    /// 形が 1 段甘い手（開二・止め三の置き場所の違い）までが入る。
    static let slipMargin = 500

    static func policy(_ probability: Double) -> GomokuMovePolicy {
        GomokuMovePolicy(bestMoveProbability: probability, slipMargin: slipMargin)
    }

    public init(level: Int = CPUStrength.standard.rawValue, forbiddenMoves: Bool = false) {
        self.init(level: level, forbiddenMoves: forbiddenMoves, seed: nil)
    }

    /// `timeLimit` / `nodeLimit` / `policy` / `maxDepth` はテスト・計測用の差し替え。
    /// 時間切れによる打ち切りを無くしたいときは `timeLimit: .infinity` を渡す（`.distantFuture` を締切にする）。
    init(level: Int, forbiddenMoves: Bool = false, seed: UInt64?,
         timeLimit: TimeInterval? = nil, maxDepth: Int? = nil, nodeLimit: Int? = nil, policy: GomokuMovePolicy? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        let shippedTime: TimeInterval
        switch CPUStrength.strength(for: level) {
        case .novice: (shippedTime, depth, self.policy) = (0.3, 3, Self.policy(Self.noviceBestMoveProbability))
        case .easy:   (shippedTime, depth, self.policy) = (0.5, 4, Self.policy(Self.easyBestMoveProbability))
        case .normal: (shippedTime, depth, self.policy) = (1.0, 5, Self.policy(Self.normalBestMoveProbability))
        case .hard:   (shippedTime, depth, self.policy) = (2.0, Self.maxDepth, .exact)
        }
        self.timeLimit = timeLimit ?? shippedTime
        if let policy { self.policy = policy }
        if let maxDepth { depth = maxDepth }   // テスト用: 反復深化の上限を絞る（#1226）
        self.nodeLimit = nodeLimit
        self.forbiddenMoves = forbiddenMoves
        self.seed = seed
    }

    public func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)? {
        var rng = GomokuRandom(seed: seed)
        // 外すかどうかを先に決める。外す手番だけ、最善から `slipMargin` 以内の手に正確な評価値を付けて読む。
        let slips = !policy.isExact && Double.random(in: 0..<1, using: &rng) >= policy.bestMoveProbability
        var ctx = makeContext()
        guard let best = ctx.search(board: board, stone: stone, scoreWindow: slips ? policy.slipMargin : nil)
        else { return nil }
        guard slips, let picked = policy.slip(ctx.rootScores, best: best.0 * gomokuBoardSize + best.1, using: &rng)
        else { return best }
        return (picked / gomokuBoardSize, picked % gomokuBoardSize)
    }

    /// 計測用: 探索した局面数と読み切った深さ（`bestMove` と同じ設定で、外さずに 1 手だけ探索する）。
    func analyze(board: GomokuBoard, stone: GomokuStone) -> (move: (Int, Int)?, nodes: Int, depth: Int) {
        var ctx = makeContext()
        let move = ctx.search(board: board, stone: stone)
        return (move, ctx.nodes, ctx.completedDepth)
    }

    /// 探索が読む候補手の並び。テストが全順序になっていることを確かめる窓口（#812）。
    func candidateMoves(board: GomokuBoard) -> [(Int, Int)] {
        GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit, forbiddenMoves: forbiddenMoves,
                            transpositionTableSize: 0, now: now).candidateMoves(board: board)
    }

    /// 探索の締切から引く、置換表の確保・後始末ぶん（秒）。1 手の合計が `timeLimit` を超えないための余裕。
    static let searchOverhead = 0.02

    private func makeContext() -> GomokuSearchContext {
        let searchTime = timeLimit.isFinite ? max(Self.searchOverhead, timeLimit - Self.searchOverhead) : timeLimit
        return GomokuSearchContext(maxDepth: depth, timeLimit: searchTime, forbiddenMoves: forbiddenMoves,
                            nodeLimit: nodeLimit, breadth: Self.breadth, extendsFours: true, now: now)
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
        self.deadline = timeLimit.isFinite ? now().addingTimeInterval(timeLimit) : .distantFuture
        self.forbiddenMoves = forbiddenMoves
        self.killers = [[Int?]](repeating: [nil, nil], count: maxDepth + 10)
        self.tt = [GomokuTTEntry](repeating: GomokuTTEntry(), count: transpositionTableSize)
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
    /// 自分の五・相手の四を止める手は探索せずに返す（`rootScores` は空のまま＝外さない）。
    mutating func search(board: GomokuBoard, stone: GomokuStone, scoreWindow: Int? = nil) -> (Int, Int)? {
        let candidates = legalMoves(candidateMoves(board: board), board: board, stone: stone)
        guard !candidates.isEmpty else { return (gomokuBoardSize / 2, gomokuBoardSize / 2) }

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
