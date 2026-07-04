import Foundation

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

// MARK: - Transposition Table

private enum TTFlag: UInt8 { case exact, lower, upper }

/// Move の 16bit エンコード（TT に best move を格納するため）。
/// board: bit0-6=from, bit7-13=to, bit14=promote / drop: bit0-6=to, bit7-9=type, bit15=1
private enum MoveCode {
    static let none: UInt16 = 0xFFFF

    static func encode(_ m: Move) -> UInt16 {
        switch m {
        case let .board(from, to, promote):
            return UInt16(from) | (UInt16(to) << 7) | (promote ? 1 << 14 : 0)
        case let .drop(type, to):
            return UInt16(to) | (UInt16(type.rawValue) << 7) | (1 << 15)
        }
    }

    static func decode(_ c: UInt16) -> Move? {
        guard c != none else { return nil }
        if c & (1 << 15) != 0 {
            guard let type = PieceType(rawValue: Int((c >> 7) & 0x7)) else { return nil }
            return .drop(type: type, to: Int(c & 0x7F))
        }
        return .board(from: Int(c & 0x7F), to: Int((c >> 7) & 0x7F), promote: c & (1 << 14) != 0)
    }
}

private struct TTEntry {
    var hash: UInt64 = 0
    var score: Int32 = 0
    var move: UInt16 = MoveCode.none
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
    let useBook: Bool
    let timeLimit: TimeInterval
    let useHistory: Bool
    let useHangingEval: Bool
    let useOpeningEval: Bool

    public init(level: Int = 1) {
        switch level {
        case 0:  (depth, usePositional, useBook, timeLimit) = (3, false, false, 0.5)
        case 2:  (depth, usePositional, useBook, timeLimit) = (10, true, true, 3.0)
        default: (depth, usePositional, useBook, timeLimit) = (6, true,  true,  1.0)
        }
        (useHistory, useHangingEval, useOpeningEval) = (true, true, true)
    }

    /// テスト・調整用: パラメータを直接指定する。
    init(depth: Int, usePositional: Bool, useBook: Bool, timeLimit: TimeInterval,
         useHistory: Bool = true, useHangingEval: Bool = true, useOpeningEval: Bool = true) {
        self.depth = depth
        self.usePositional = usePositional
        self.useBook = useBook
        self.timeLimit = timeLimit
        self.useHistory = useHistory
        self.useHangingEval = useHangingEval
        self.useOpeningEval = useOpeningEval
    }

    public func bestMove(sfen: String) async -> String? {
        guard var pos = Position.fromSFEN(sfen) else { return nil }
        let moves = pos.legalMoves()
        guard !moves.isEmpty else { return nil }

        if useBook, let booked = OpeningBook.move(for: sfen),
           let m = Move.fromUSI(booked), moves.contains(m) { return booked }

        var ctx = SearchContext(maxDepth: depth, usePositional: usePositional, timeLimit: timeLimit,
                                useHistory: useHistory, useHangingEval: useHangingEval,
                                useOpeningEval: useOpeningEval)
        return ctx.search(&pos)?.usi
    }

    func kingSafety(_ pos: Position, _ color: Side) -> Int {
        SearchContext(maxDepth: depth, usePositional: usePositional, timeLimit: 0).kingSafety(pos, color)
    }

    /// データ生成用: 静的評価値を返す（手番視点の正規化済みスコア）
    public func staticEval(sfen: String) -> Float? {
        guard let pos = Position.fromSFEN(sfen) else { return nil }
        let ctx = SearchContext(maxDepth: depth, usePositional: usePositional, timeLimit: 0)
        return Float(ctx.evaluate(pos)) / 1000.0
    }
}

// MARK: - SearchContext（探索の可変状態）

private struct SearchContext {
    let maxDepth: Int
    let usePositional: Bool
    let useHistory: Bool
    let useHangingEval: Bool
    let useOpeningEval: Bool
    let deadline: TimeInterval  // ProcessInfo.systemUptime 基準
    var killers: [[Move?]]   // killers[ply][0..1]
    var tt: [TTEntry]
    var nodes: Int = 0
    var stopped = false
    // ヒストリーヒューリスティック: βカットを起こした静かな手の実績値
    var histBoard = [Int](repeating: 0, count: 81 * 81)  // from * 81 + to
    var histDrop = [Int](repeating: 0, count: 7 * 81)    // type * 81 + to

    init(maxDepth: Int, usePositional: Bool, timeLimit: TimeInterval,
         useHistory: Bool = true, useHangingEval: Bool = true, useOpeningEval: Bool = true) {
        self.maxDepth = maxDepth
        self.usePositional = usePositional
        self.useHistory = useHistory
        self.useHangingEval = useHangingEval
        self.useOpeningEval = useOpeningEval
        self.deadline = ProcessInfo.processInfo.systemUptime + timeLimit
        self.killers = [[Move?]](repeating: [nil, nil], count: maxDepth + 20)
        self.tt = [TTEntry](repeating: TTEntry(), count: TT_SIZE)
    }

    /// 時間切れ判定。毎ノードの時刻取得を避けるため 1024 ノードごとにチェックする。
    mutating func timeUp() -> Bool {
        if stopped { return true }
        nodes += 1
        if nodes & 1023 == 0, ProcessInfo.processInfo.systemUptime > deadline {
            stopped = true
        }
        return stopped
    }

    // MARK: 反復深化

    mutating func search(_ pos: inout Position) -> Move? {
        var orderedMoves = orderMoves(pos.legalMoves(), pos: pos, killers: [nil, nil], ttMove: nil)
        var best: Move? = orderedMoves.first

        for d in 1...maxDepth {
            if ProcessInfo.processInfo.systemUptime > deadline { break }
            var localBest: Move?
            var bestScore = Int.min + 1
            var alpha = Int.min + 1
            let beta = Int.max
            var aborted = false

            for move in orderedMoves {
                if stopped || ProcessInfo.processInfo.systemUptime > deadline { aborted = true; break }
                let undo = pos.make(move)
                let score = -negamax(&pos, depth: d - 1, alpha: -beta, beta: -alpha, ply: 1)
                pos.unmake(undo)
                // 探索中に時間切れした場合、この手のスコアは途中打ち切りのゴミなので捨てる
                if stopped { aborted = true; break }
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

    // MARK: αβ ネガマックス + 置換表 + キラー + Null Move + LMR

    mutating func negamax(_ pos: inout Position, depth: Int, alpha: Int, beta: Int, ply: Int, nullOk: Bool = true) -> Int {
        if timeUp() { return evaluate(pos) }

        // 置換表参照
        let hash = pos.hash
        let ttIdx = Int(hash & UInt64(TT_SIZE - 1))
        let entry = tt[ttIdx]
        var ttMove: Move?
        if entry.hash == hash {
            ttMove = MoveCode.decode(entry.move)
            if Int(entry.depth) >= depth {
                let s = Int(entry.score)
                switch entry.flag {
                case .exact:
                    if s >= beta  { return beta  }
                    if s <= alpha { return alpha }
                    return s
                case .lower:
                    if s >= beta  { return beta }
                case .upper:
                    if s <= alpha { return alpha }
                }
            }
        }

        if depth == 0 { return quiesce(&pos, alpha: alpha, beta: beta, qdepth: 0) }

        // 詰み専用探索（残り深さ3以下で王手がかかっていない場合のみ詰みチェック）
        if depth <= 3 {
            if let mateScore = mateSearch(&pos, depth: depth * 2 + 1, ply: ply) {
                return mateScore
            }
        }

        // Null Move Pruning（王手がかかっていない + 十分な深さ + 局面に駒がある）
        if nullOk && depth >= 3 && !pos.isInCheck() && hasNonPawnPieces(pos) {
            let R = depth >= 6 ? 3 : 2  // 削減量（深いほど大きく削減）
            let undo = pos.makeNull()
            let nullScore = -negamax(&pos, depth: depth - 1 - R, alpha: -beta, beta: -beta + 1, ply: ply + 1, nullOk: false)
            pos.unmakeNull(undo)
            if nullScore >= beta {
                return beta  // Null Move カット
            }
        }

        let moves = pos.legalMoves()
        if moves.isEmpty { return -PieceValue.base(.king) - depth }

        var alpha = alpha
        var flag: TTFlag = .upper
        var bestMove: Move?
        let killerSet = ply < killers.count ? killers[ply] : [nil, nil]
        let orderedMoves = orderMoves(moves, pos: pos, killers: killerSet, ttMove: ttMove)

        for (moveCount, move) in orderedMoves.enumerated() {
            let undo = pos.make(move)

            var score: Int
            if moveCount == 0 {
                // PV手はフル深さで探索
                score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
            } else {
                // LMR: 非キャプチャ・非昇格の後半手は削減して探索
                let isQuiet = !isCapture(move, pos) && !isPromotion(move)
                let lmrDepth: Int
                if depth >= 3 && moveCount >= 4 && isQuiet {
                    let reduction = moveCount >= 8 ? 2 : 1
                    lmrDepth = max(1, depth - 1 - reduction)
                } else {
                    lmrDepth = depth - 1
                }

                // ゼロウィンドウ探索
                score = -negamax(&pos, depth: lmrDepth, alpha: -alpha - 1, beta: -alpha, ply: ply + 1)

                // LMR 削減した手がアルファを超えたらフル深さで再探索
                if score > alpha && lmrDepth < depth - 1 {
                    score = -negamax(&pos, depth: depth - 1, alpha: -alpha - 1, beta: -alpha, ply: ply + 1)
                }
                // PVS: alpha < score < beta ならフルウィンドウで再探索
                if score > alpha && score < beta {
                    score = -negamax(&pos, depth: depth - 1, alpha: -beta, beta: -alpha, ply: ply + 1)
                }
            }

            pos.unmake(undo)

            if score >= beta {
                if !isCapture(move, pos) {
                    if ply < killers.count {
                        killers[ply][1] = killers[ply][0]
                        killers[ply][0] = move
                    }
                    if useHistory {
                        // 深い場所でのカットほど価値が高い
                        switch move {
                        case let .board(from, to, _): histBoard[from * 81 + to] += depth * depth
                        case let .drop(type, to):     histDrop[type.rawValue * 81 + to] += depth * depth
                        }
                    }
                }
                tt[ttIdx] = TTEntry(
                    hash: hash, score: Int32(clamping: beta), move: MoveCode.encode(move),
                    depth: Int8(clamping: depth), flag: .lower)
                return beta
            }
            if score > alpha {
                alpha = score
                flag = .exact
                bestMove = move
            }
        }

        tt[ttIdx] = TTEntry(
            hash: hash, score: Int32(clamping: alpha), move: bestMove.map(MoveCode.encode) ?? MoveCode.none,
            depth: Int8(clamping: depth), flag: flag)
        return alpha
    }

    // MARK: 詰み専用探索（奇数手詰めを読む）

    mutating func mateSearch(_ pos: inout Position, depth: Int, ply: Int) -> Int? {
        if timeUp() { return nil }
        let moves = pos.legalMoves()
        if moves.isEmpty { return -PieceValue.base(.king) - ply }
        if depth <= 0 { return nil }

        // 王手になる手のみ探索
        let checks = moves.filter { move in
            let undo = pos.make(move)
            let inCheck = pos.isInCheck()  // 相手が王手状態か
            pos.unmake(undo)
            return inCheck
        }
        guard !checks.isEmpty else { return nil }

        for move in checks {
            let undo = pos.make(move)
            // 相手の応手が全て詰みかどうか確認
            let replies = pos.legalMoves()
            if replies.isEmpty {
                // 詰み発見
                pos.unmake(undo)
                return PieceValue.base(.king) + ply
            }
            // 全応手を試して逃げられるか確認
            var allMate = true
            for reply in replies {
                let undo2 = pos.make(reply)
                let result = mateSearch(&pos, depth: depth - 2, ply: ply + 2)
                pos.unmake(undo2)
                if result == nil {
                    allMate = false
                    break
                }
            }
            pos.unmake(undo)
            if allMate { return PieceValue.base(.king) + ply }
        }
        return nil
    }

    // MARK: 静止探索（取り合いが落ち着くまで探索）

    mutating func quiesce(_ pos: inout Position, alpha: Int, beta: Int, qdepth: Int) -> Int {
        if qdepth >= 6 || timeUp() { return evaluate(pos) }

        let standPat = evaluate(pos)
        if standPat >= beta { return beta }
        if standPat + 1300 < alpha { return alpha }

        var alpha = max(alpha, standPat)
        let side = pos.sideToMove

        // 捕獲手のみ生成し、王手放置チェックは指した後に行う（全合法手生成を避ける）
        let captures = pos.pseudoLegalCaptures()
        for move in captures.sorted(by: { captureScore($0, pos) > captureScore($1, pos) }) {
            let undo = pos.make(move)
            if pos.isKingInCheck(side) {
                pos.unmake(undo)
                continue
            }
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

    func moveScore(_ move: Move, pos: Position, killers: [Move?], ttMove: Move?) -> Int {
        if let ttMove, move == ttMove { return 1_000_000 }  // 置換表の最善手を最優先
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
        if useHistory {
            // 静かな手はヒストリー実績順（キラーは超えない）
            switch move {
            case let .board(from, to, _): return min(3_900, histBoard[from * 81 + to])
            case let .drop(type, to):     return min(3_900, histDrop[type.rawValue * 81 + to])
            }
        }
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

    func isPromotion(_ move: Move) -> Bool {
        guard case let .board(_, _, promote) = move else { return false }
        return promote
    }

    // Null Move Pruning の適用条件: 歩以外の駒が盤上にあるか
    func hasNonPawnPieces(_ pos: Position) -> Bool {
        pos.squares.contains { p in
            guard let p else { return false }
            return p.color == pos.sideToMove && p.type != .pawn && p.type != .king
        }
    }

    // MARK: 静的評価

    func evaluate(_ pos: Position) -> Int {
        // NOTE: CoreML 評価 (ShogiEvalModel) は探索では使わない。
        // 現行の 95 次元特徴量は玉位置を持たず（king=0.0）駒種の区別も弱いため
        // ハンドクラフト評価より精度が低く、かつ葉ノードごとの ML 推論は
        // NPS を数桁落とす。特徴量と訓練データを刷新するまで無効化する。

        var score = 0

        for sq in 0..<Sq.count {
            guard let p = pos.squares[sq] else { continue }
            let v = PieceValue.onBoard(p)
            let sign = p.color == .black ? 1 : -1
            score += sign * v

            // 浮き駒: 敵の利きに晒され味方の紐がない駒はペナルティ
            // （タダ取られ・両取りを静的に検出。歩は安いので対象外）
            if usePositional && useHangingEval && p.type != .king && p.type != .pawn,
               pos.isAttacked(sq, by: p.color.opponent),
               !pos.isAttacked(sq, by: p.color) {
                score -= sign * (v / 3)
            }

            if usePositional && !p.promoted {
                let rank = Sq.rank(sq)
                let advance = p.color == .black ? (8 - rank) : rank
                var adv = advanceTable[p.type.rawValue][advance]
                // 序盤は歩の深追いより駒組みを優先させる。端歩の前進は得が薄いので無効化
                if useOpeningEval, pos.moveNumber < 30, p.type == .pawn {
                    let f = Sq.file(sq)
                    adv = (f == 0 || f == 8) ? 0 : adv / 2
                }
                score += sign * adv

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
            var safety = kingSafety(pos, .black) - kingSafety(pos, .white)
            safety += castleBonus(pos, .black) - castleBonus(pos, .white)
            // 序盤は囲い・玉の安全を重視させ、駒組みが終わる前の乱戦を抑制する
            if useOpeningEval && pos.moveNumber < 40 { safety = safety * 3 / 2 }
            score += safety

            // 序盤（25手目未満）に角が5五にいるとペナルティ（角を早出しすぎ）
            if pos.moveNumber < 25 {
                let sq55 = Sq.index(file: 4, rank: 4)
                if let p = pos.squares[sq55], p.type == .bishop, !p.promoted {
                    let sign = p.color == .black ? 1 : -1
                    score -= sign * 90
                }
            }
        }

        return pos.sideToMove == .black ? score : -score
    }

    func slidingMobility(_ pos: Position, sq: Int, color: Side, dirs: [(Int, Int)]) -> Int {
        var count = 0
        for (df, dr) in dirs {
            var f = Sq.file(sq) + df
            var r = Sq.rank(sq) + dr
            while Sq.onBoard(file: f, rank: r) {
                let idx = Sq.index(file: f, rank: r)
                if let p = pos.squares[idx] {
                    if p.color != color { count += 1 }
                    break
                }
                count += 1
                f += df; r += dr
            }
        }
        return count
    }

    func kingSafety(_ pos: Position, _ color: Side) -> Int {
        guard let k = pos.kingSquare(color) else { return 0 }
        let kf = Sq.file(k), kr = Sq.rank(k)
        let enemy = color.opponent
        var s = 0
        for (df, dr) in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)] {
            let f = kf + df, r = kr + dr
            guard Sq.onBoard(file: f, rank: r) else { continue }
            let sq = Sq.index(file: f, rank: r)
            if let p = pos.squares[sq], p.color == color,
               p.type == .gold || p.type == .silver {
                s += 30
            }
            // 玉の周囲に敵の利きが通っているとペナルティ（寄せられている度合い）
            if pos.isAttacked(sq, by: enemy) { s -= 18 }
        }
        // 玉自身のマスに利きが当たっている（王手 or 直前の受け漏れ）はさらに重い
        if pos.isAttacked(k, by: enemy) { s -= 40 }
        s += abs(kf - 4) * 15
        let homeRank = color == .black ? 8 : 0
        s += max(0, 2 - abs(kr - homeRank)) * 10

        if useOpeningEval {
            // 居玉ペナルティ: 12手目以降も初期位置(5九/5一)のままなら減点し、囲いを促す
            let startSq = Sq.index(file: 4, rank: color == .black ? 8 : 0)
            if k == startSq && pos.moveNumber >= 12 { s -= 45 }
            // 距離2圏の金銀にも小さなボーナス（囲い形成途中を評価）
            for df in -2...2 {
                for dr in -2...2 where max(abs(df), abs(dr)) == 2 {
                    let f = kf + df, r = kr + dr
                    guard Sq.onBoard(file: f, rank: r),
                          let p = pos.squares[Sq.index(file: f, rank: r)],
                          p.color == color, p.type == .gold || p.type == .silver else { continue }
                    s += 10
                }
            }
        }
        return s
    }

    // 囲い形状ボーナス: 美濃囲い・矢倉形を検出して加点する
    // 座標系: file 8=9筋(左端), file 0=1筋(右端), rank 8=9段(先手本陣), rank 0=1段(後手本陣)
    func castleBonus(_ pos: Position, _ color: Side) -> Int {
        guard let k = pos.kingSquare(color) else { return 0 }
        let kf = Sq.file(k), kr = Sq.rank(k)
        let homeRank = color == .black ? 8 : 0
        // 先手は上方向(rank-1)が前、後手は下方向(rank+1)が前
        let fwd = color == .black ? -1 : 1

        func hasOwn(f: Int, r: Int, _ type: PieceType) -> Bool {
            guard Sq.onBoard(file: f, rank: r) else { return false }
            guard let p = pos.squares[Sq.index(file: f, rank: r)] else { return false }
            return p.color == color && p.type == type && !p.promoted
        }

        var bonus = 0
        // 玉が本陣付近(homeRankから2マス以内)にいる場合のみ判定
        guard abs(kr - homeRank) <= 2 else { return 0 }

        // 美濃囲い: 玉が端筋(file=8 or file=0)、銀が斜め前、金が隣
        if kf == 8 {
            if hasOwn(f: 7, r: kr + fwd, .silver) { bonus += 70 }  // 銀が斜め前(美濃の特徴)
            if hasOwn(f: 6, r: kr,        .gold)   { bonus += 55 }  // 金が隣のさらに隣
            if hasOwn(f: 7, r: kr,        .gold)   { bonus += 45 }  // 金が隣
        } else if kf == 0 {
            if hasOwn(f: 1, r: kr + fwd, .silver) { bonus += 70 }
            if hasOwn(f: 2, r: kr,        .gold)   { bonus += 55 }
            if hasOwn(f: 1, r: kr,        .gold)   { bonus += 45 }
        }

        // 矢倉囲い: 玉がfile=7(8八相当)またはfile=1(2八相当)、金銀で三角を作る
        if kf == 7 {
            if hasOwn(f: 6, r: kr,        .gold)   { bonus += 60 }  // 金が玉の隣
            if hasOwn(f: 6, r: kr + fwd,  .silver) { bonus += 60 }  // 銀が斜め前
            if hasOwn(f: 5, r: kr + fwd,  .gold)   { bonus += 50 }  // 金がさらに前
        } else if kf == 1 {
            if hasOwn(f: 2, r: kr,        .gold)   { bonus += 60 }
            if hasOwn(f: 2, r: kr + fwd,  .silver) { bonus += 60 }
            if hasOwn(f: 3, r: kr + fwd,  .gold)   { bonus += 50 }
        }

        return bonus
    }
}
