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

// MARK: - Engine（公開 API）

/// 五目並べの CPU。
///
/// | level | 表示 | 打ち方 |
/// |---|---|---|
/// | -1 | 入門 | 読まずに1手先の形だけ（簡単と同じ）＋ 相手の四を防ぐのは 5 回に 1 回・候補も広め |
/// | 0 | 簡単 | 読まずに1手先の形だけ（#665）＋ 相手の四を防ぐのは 2 回に 1 回 |
/// | 1 | ふつう | 深さ 4 の αβ（1 手 0.8 秒） |
/// | 2 | むずかしい | 深さ 5 の αβ（1 手 1.5 秒） |
/// | 3 | ガチ | 深さ 7 の αβ（1 手 3.0 秒・#1174） |
///
/// **番号は強さの順だが 0 始まりではない**（`CPUStrength`。既存 3 段階の番号を動かさないため）。
/// 「入門」は簡単と同じ打ち方のまま、**相手の四を防ぐ率**と**候補の広さ**だけを緩めてある（#1174）。
/// 防御率を下げるだけでは簡単と互角だった（自己対戦 20/40。どちらも四をそもそも作りにくいため）ので、
/// 形の選び方も広げて手なりに打たせている。自分の五は必ず取るところは変えていないので、
/// 弱いが壊れてはいない（簡単に 10/40・でたらめな相手には 40/40。実測は PR）。
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

    /// 弱の既定の防御率。深さ3の読みと即防ぎを持っていた旧「弱」は盤ゲーム5本で最も強かった（#665）。
    static let defaultWeakBlockRate = 0.5
    /// 「入門」の防御率（#1174）。簡単の半分以下にして、人間の四がだいたい通るようにする。
    static let noviceBlockRate = 0.2

    /// 読まない段階が乱択する候補の広さ。広げるほど形の良し悪しを気にしなくなる。
    struct WeakChoice: Equatable, Sendable {
        /// 点の高い順に何手まで候補にするか。
        let count: Int
        /// 最善の何分の1以上の点が付いた手までを候補にするか（2 なら半分以上）。
        let shareDenominator: Int
    }

    /// 「簡単」の広さ（#665 の実装そのまま。上位 3 手・最善の半分以上）。
    static let easyChoice = WeakChoice(count: 3, shareDenominator: 2)
    /// 「入門」の広さ（#1174）。上位 6 手・最善の 1/4 以上まで広げる。
    /// 防御率を下げるだけでは簡単と互角だったため（実測 20/40）、形の選び方も崩している。
    static let noviceChoice = WeakChoice(count: 6, shareDenominator: 4)

    public init(level: Int = CPUStrength.standard.rawValue, forbiddenMoves: Bool = false) {
        self.init(level: level, forbiddenMoves: forbiddenMoves, seed: nil)
    }

    init(level: Int, forbiddenMoves: Bool = false, seed: UInt64?,
         weakBlockRate: Double? = nil, maxDepth: Int? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        let strength = CPUStrength.strength(for: level)
        switch strength {
        case .novice:  (depth, timeLimit) = (1, 0.4)
        case .easy:    (depth, timeLimit) = (1, 0.4)
        case .hard:    (depth, timeLimit) = (5, 1.5)
        case .normal:  (depth, timeLimit) = (4, 0.8)
        }
        if let maxDepth { depth = maxDepth }   // テスト用: 反復深化の上限を絞る（#1226）
        self.forbiddenMoves = forbiddenMoves
        self.isWeak = strength == .easy || strength == .novice
        self.weakBlockRate = weakBlockRate
            ?? (strength == .novice ? Self.noviceBlockRate : Self.defaultWeakBlockRate)
        self.weakChoice = strength == .novice ? Self.noviceChoice : Self.easyChoice
        self.seed = seed
    }

    public func bestMove(board: GomokuBoard, stone: GomokuStone) async -> (row: Int, col: Int)? {
        if isWeak {
            // 探索しないので置換表（約4MB）は確保しない。
            let ctx = GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit,
                                          forbiddenMoves: forbiddenMoves, transpositionTableSize: 0, now: now)
            if let seed {
                var rng = MMIXRandom(state: seed)
                return ctx.weakMove(board: board, stone: stone, blockRate: weakBlockRate,
                                    choice: weakChoice, using: &rng)
            }
            var rng = SystemRandomNumberGenerator()
            return ctx.weakMove(board: board, stone: stone, blockRate: weakBlockRate,
                                choice: weakChoice, using: &rng)
        }
        var ctx = GomokuSearchContext(maxDepth: depth, timeLimit: timeLimit,
                                      forbiddenMoves: forbiddenMoves, now: now)
        return ctx.search(board: board, stone: stone)
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

    init(maxDepth: Int, timeLimit: TimeInterval, forbiddenMoves: Bool,
         transpositionTableSize: Int = GOMOKU_TT_SIZE, now: @escaping @Sendable () -> Date = { Date() }) {
        self.maxDepth = maxDepth
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

    mutating func search(board: GomokuBoard, stone: GomokuStone) -> (Int, Int)? {
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

        var orderedEncoded = orderMoves(candidates.map { $0.0 * gomokuBoardSize + $0.1 },
                                        board: board, stone: stone, killers: [nil, nil], ttMove: nil)
        guard let first = orderedEncoded.first else { return candidates.first }
        var best: (Int, Int) = (first / gomokuBoardSize, first % gomokuBoardSize)

        for d in 1...maxDepth {
            if now() > deadline { break }
            var localBest: Int? = nil
            var bestScore = Int.min + 1
            var alpha = Int.min + 1
            let beta = Int.max
            var aborted = false
            var b = board

            for encoded in orderedEncoded {
                if now() > deadline { aborted = true; break }
                let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
                b[r, c] = stone
                let score: Int
                if b.checkWin(row: r, col: c) {
                    score = 100_000 + d
                } else {
                    score = -negamax(&b, stone: opp, depth: d - 1,
                                     alpha: -beta, beta: -alpha, ply: 1)
                }
                b[r, c] = nil
                if score > bestScore { bestScore = score; localBest = encoded }
                if score > alpha { alpha = score }
            }

            // 最後の根手の評価中に期限切れになっていた場合もここで拾う。ループ先頭のチェックだけだと、
            // 全ての根手を一応は評価しているのに「読み切った」と誤採用する（`negamax` は期限切れで
            // 静的評価を即返すため、その深さの評価値が不完全になる。#1226）。
            if now() > deadline { aborted = true }
            if !aborted, let lb = localBest {
                best = (lb / gomokuBoardSize, lb % gomokuBoardSize)
                orderedEncoded.removeAll { $0 == lb }
                orderedEncoded.insert(lb, at: 0)
            }
            if aborted { break }
        }
        return best
    }

    // MARK: αβ ネガマックス + 置換表 + キラー

    mutating func negamax(_ board: inout GomokuBoard, stone: GomokuStone, depth: Int,
                          alpha: Int, beta: Int, ply: Int) -> Int {
        if now() > deadline { return evaluate(board, for: stone) }

        let hash = board.zobristHash(stone: stone)
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
                                  board: board, stone: stone, killers: killerSet, ttMove: ttMove) {
            let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
            board[r, c] = stone
            let score: Int
            if board.checkWin(row: r, col: c) {
                score = 100_000 + depth
            } else {
                score = -negamax(&board, stone: stone.opponent, depth: depth - 1,
                                 alpha: -beta, beta: -alpha, ply: ply + 1)
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
        encoded.sorted { a, b in
            moveScore(a, board: board, stone: stone, killers: killers, ttMove: ttMove) >
            moveScore(b, board: board, stone: stone, killers: killers, ttMove: ttMove)
        }
    }

    func moveScore(_ encoded: Int, board: GomokuBoard, stone: GomokuStone,
                   killers: [Int?], ttMove: Int?) -> Int {
        if let tm = ttMove, tm == encoded { return 300_000 }
        let r = encoded / gomokuBoardSize, c = encoded % gomokuBoardSize
        var b = board
        b[r, c] = stone
        let myThreat = localThreatScore(b, row: r, col: c, stone: stone)
        if myThreat >= 100_000 { return 200_000 }
        b[r, c] = stone.opponent
        let oppThreat = localThreatScore(b, row: r, col: c, stone: stone.opponent)
        if oppThreat >= 100_000 { return 190_000 }
        if killers.contains(where: { $0 == encoded }) { return 100_000 }
        return myThreat + oppThreat
    }

    // 指定升に置いたときの局所的連続カウント（自分視点）
    func localThreatScore(_ board: GomokuBoard, row: Int, col: Int, stone: GomokuStone) -> Int {
        guard let s = board[row, col], s == stone else { return 0 }
        var score = 0
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
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

    func evaluate(_ board: GomokuBoard, for stone: GomokuStone) -> Int {
        staticEval(board, for: stone) - staticEval(board, for: stone.opponent)
    }

    func staticEval(_ board: GomokuBoard, for stone: GomokuStone) -> Int {
        var score = 0
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize {
                guard board[row, col] == stone else { continue }
                for (dr, dc) in dirs {
                    let pr = row - dr, pc = col - dc
                    if pr >= 0 && pr < gomokuBoardSize && pc >= 0 && pc < gomokuBoardSize
                        && board[pr, pc] == stone { continue }
                    var count = 1
                    var r = row + dr, c = col + dc
                    while r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize
                            && board[r, c] == stone { count += 1; r += dr; c += dc }
                    let openFront = r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize
                        && board[r, c] == nil
                    let br = row - dr, bc = col - dc
                    let openBack = br >= 0 && br < gomokuBoardSize && bc >= 0 && bc < gomokuBoardSize
                        && board[br, bc] == nil
                    score += patternScore(count: count,
                                          open: (openFront ? 1 : 0) + (openBack ? 1 : 0))
                }
            }
        }
        return score
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
        if board.cells.allSatisfy({ $0 == nil }) {
            return [(gomokuBoardSize / 2, gomokuBoardSize / 2)]
        }
        var seen = Set<Int>()
        for row in 0..<gomokuBoardSize {
            for col in 0..<gomokuBoardSize {
                guard board[row, col] != nil else { continue }
                for dr in -2...2 {
                    for dc in -2...2 {
                        let r = row + dr, c = col + dc
                        guard r >= 0 && r < gomokuBoardSize && c >= 0 && c < gomokuBoardSize,
                              board[r, c] == nil else { continue }
                        seen.insert(r * gomokuBoardSize + c)
                    }
                }
            }
        }
        let center = gomokuBoardSize / 2
        // Set の走査順は呼び出し・プロセスごとに変わるので、距離が同じ升は座標で並べて全順序にする（#812）。
        // 同点を残すと即勝ち・防ぎ点の選び方が揺れ、種を固定しても CPU の手が再現しない。
        return seen.map { ($0 / gomokuBoardSize, $0 % gomokuBoardSize) }
            .sorted { a, b in
                let da = abs(a.0 - center) + abs(a.1 - center)
                let db = abs(b.0 - center) + abs(b.1 - center)
                return (da, a.0, a.1) < (db, b.0, b.1)
            }
    }
}
