import Foundation

extension Position {

    // MARK: - 駒の利き定義（先手向き。後手は rank 方向を反転）

    /// (dFile, dRank) のステップ移動（単発）とスライド移動（連続）。
    private struct Movement {
        var steps: [(Int, Int)]
        var slides: [(Int, Int)]
    }

    // 先手から見た方向（forward = rank -1）。
    private static let goldSteps = [(0, -1), (1, -1), (-1, -1), (1, 0), (-1, 0), (0, 1)]
    private static let kingSteps = [(0, -1), (1, -1), (-1, -1), (1, 0), (-1, 0), (0, 1), (1, 1), (-1, 1)]
    private static let silverSteps = [(0, -1), (1, -1), (-1, -1), (1, 1), (-1, 1)]
    private static let bishopDirs = [(1, -1), (-1, -1), (1, 1), (-1, 1)]
    private static let rookDirs = [(0, -1), (0, 1), (1, 0), (-1, 0)]

    /// [type 0-7][promoted 0-1][color 0-1] → Movement。毎回のアロケートを避けるため事前計算。
    private static let movementTable: [Movement] = {
        var table = [Movement](repeating: Movement(steps: [], slides: []), count: 8 * 2 * 2)
        for type in PieceType.allCases {
            for promoted in 0..<2 {
                var steps: [(Int, Int)] = []
                var slides: [(Int, Int)] = []
                if promoted == 1 {
                    switch type {
                    case .pawn, .lance, .knight, .silver:
                        steps = goldSteps
                    case .bishop: // 馬: 角の動き + 上下左右 1
                        steps = rookDirs
                        slides = bishopDirs
                    case .rook: // 龍: 飛の動き + 斜め 1
                        steps = bishopDirs
                        slides = rookDirs
                    case .gold, .king:
                        break
                    }
                } else {
                    switch type {
                    case .pawn: steps = [(0, -1)]
                    case .lance: slides = [(0, -1)]
                    case .knight: steps = [(1, -2), (-1, -2)]
                    case .silver: steps = silverSteps
                    case .gold: steps = goldSteps
                    case .king: steps = kingSteps
                    case .bishop: slides = bishopDirs
                    case .rook: slides = rookDirs
                    }
                }
                for color in 0..<2 {
                    let s = color == 0 ? steps : steps.map { ($0.0, -$0.1) }
                    let sl = color == 0 ? slides : slides.map { ($0.0, -$0.1) }
                    table[(type.rawValue << 2) | (promoted << 1) | color] = Movement(steps: s, slides: sl)
                }
            }
        }
        return table
    }()

    private func movement(of piece: Piece) -> Movement {
        Self.movementTable[(piece.type.rawValue << 2) | ((piece.promoted ? 1 : 0) << 1) | piece.color.rawValue]
    }

    // MARK: - 利き判定（target から外向きに走査。全81マス走査を避ける）

    /// target が color の駒に攻撃されているか。
    public func isAttacked(_ target: Int, by color: Side) -> Bool {
        let tf = Sq.file(target), tr = Sq.rank(target)

        // 桂馬（跳び駒なので別扱い）。黒の桂は (±1, -2) へ跳ぶので攻撃元は (±1, +2)。
        let nr = tr + (color == .black ? 2 : -2)
        if nr >= 0 && nr < 9 {
            for df in [-1, 1] {
                let f = tf + df
                if f >= 0 && f < 9,
                   let p = squares[Sq.index(file: f, rank: nr)],
                   p.color == color, p.type == .knight, !p.promoted {
                    return true
                }
            }
        }

        // 8方向へ走査し、最初に見つかった駒が target を攻撃できるか判定する。
        for (df, dr) in Self.kingSteps {
            var f = tf + df, r = tr + dr
            var dist = 1
            while Sq.onBoard(file: f, rank: r) {
                if let p = squares[Sq.index(file: f, rank: r)] {
                    if p.color == color {
                        // 攻撃方向（attacker → target）を黒基準に正規化。
                        let adf = -df
                        let adr = color == .black ? -dr : dr
                        if dist == 1, stepAttacks(p, adf: adf, adr: adr) { return true }
                        if slideAttacks(p, adf: adf, adr: adr) { return true }
                    }
                    break // 駒に遮られる
                }
                f += df; r += dr; dist += 1
            }
        }
        return false
    }

    /// 隣接マス (adf, adr) 方向（黒基準・attacker→target）へのステップ利きがあるか。
    private func stepAttacks(_ p: Piece, adf: Int, adr: Int) -> Bool {
        // 金の利き: 前3方向・横2方向・真後ろ
        func goldStep() -> Bool { adr == -1 || adr == 0 || (adf == 0 && adr == 1) }

        if p.promoted {
            switch p.type {
            case .pawn, .lance, .knight, .silver, .gold: return goldStep()
            case .bishop: return adf == 0 || adr == 0  // 馬の上下左右1
            case .rook: return adf != 0 && adr != 0    // 龍の斜め1
            case .king: return true
            }
        }
        switch p.type {
        case .pawn: return adf == 0 && adr == -1
        case .silver: return adr == -1 || (adf != 0 && adr == 1)
        case .gold: return goldStep()
        case .king: return true
        case .knight, .lance, .bishop, .rook: return false // 桂は別扱い、走り駒は slideAttacks
        }
    }

    /// (adf, adr) 単位方向（黒基準・attacker→target、経路は空き）へのスライド利きがあるか。
    private func slideAttacks(_ p: Piece, adf: Int, adr: Int) -> Bool {
        switch p.type {
        case .lance: return !p.promoted && adf == 0 && adr == -1
        case .bishop: return adf != 0 && adr != 0
        case .rook: return adf == 0 || adr == 0
        default: return false
        }
    }

    /// 指定色の玉が王手されているか。
    public func isKingInCheck(_ color: Side) -> Bool {
        guard let king = kingSquare(color) else { return false }
        return isAttacked(king, by: color.opponent)
    }

    // MARK: - 成り判定

    /// 移動先で不成のままだと二度と動けない（強制成り）か。
    private func mustPromote(_ piece: Piece, to: Int) -> Bool {
        let r = Sq.rank(to)
        switch piece.type {
        case .pawn, .lance:
            return piece.color == .black ? r == 0 : r == 8
        case .knight:
            return piece.color == .black ? r <= 1 : r >= 7
        default:
            return false
        }
    }

    // MARK: - 疑似合法手生成（王手放置のチェックはしない）

    public func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        let side = sideToMove

        for from in 0..<Sq.count {
            guard let piece = squares[from], piece.color == side else { continue }
            let ff = Sq.file(from), fr = Sq.rank(from)
            let m = movement(of: piece)

            func consider(_ to: Int) {
                if let occ = squares[to], occ.color == side { return } // 自駒には行けない
                appendBoardMoves(piece: piece, from: from, to: to, into: &moves)
            }

            for (df, dr) in m.steps {
                let f = ff + df, r = fr + dr
                if Sq.onBoard(file: f, rank: r) { consider(Sq.index(file: f, rank: r)) }
            }
            for (df, dr) in m.slides {
                var f = ff + df, r = fr + dr
                while Sq.onBoard(file: f, rank: r) {
                    let to = Sq.index(file: f, rank: r)
                    if let occ = squares[to] {
                        if occ.color != side { consider(to) }
                        break
                    }
                    consider(to)
                    f += df; r += dr
                }
            }
        }

        appendDrops(side: side, into: &moves)
        return moves
    }

    /// 相手駒を取る盤上手のみ生成（静止探索用）。王手放置のチェックは呼び出し側が行う。
    public func pseudoLegalCaptures() -> [Move] {
        var moves: [Move] = []
        let side = sideToMove

        for from in 0..<Sq.count {
            guard let piece = squares[from], piece.color == side else { continue }
            let ff = Sq.file(from), fr = Sq.rank(from)
            let m = movement(of: piece)

            for (df, dr) in m.steps {
                let f = ff + df, r = fr + dr
                guard Sq.onBoard(file: f, rank: r) else { continue }
                let to = Sq.index(file: f, rank: r)
                if let occ = squares[to], occ.color != side {
                    appendBoardMoves(piece: piece, from: from, to: to, into: &moves)
                }
            }
            for (df, dr) in m.slides {
                var f = ff + df, r = fr + dr
                while Sq.onBoard(file: f, rank: r) {
                    let to = Sq.index(file: f, rank: r)
                    if let occ = squares[to] {
                        if occ.color != side {
                            appendBoardMoves(piece: piece, from: from, to: to, into: &moves)
                        }
                        break
                    }
                    f += df; r += dr
                }
            }
        }
        return moves
    }

    /// 成・不成の両方を候補に出す（強制成りのときは不成を除外）。
    private func appendBoardMoves(piece: Piece, from: Int, to: Int, into moves: inout [Move]) {
        let canPromote = piece.type.canPromote && !piece.promoted
        let inZone = canPromote &&
            (Sq.isPromotionZone(rank: Sq.rank(to), color: piece.color) ||
             Sq.isPromotionZone(rank: Sq.rank(from), color: piece.color))

        if inZone {
            moves.append(.board(from: from, to: to, promote: true))
            if !mustPromote(piece, to: to) {
                moves.append(.board(from: from, to: to, promote: false))
            }
        } else {
            moves.append(.board(from: from, to: to, promote: false))
        }
    }

    /// 持ち駒打ち。打てないマス（行き所のない駒・二歩）は除外。打ち歩詰めは legal 側で判定。
    private func appendDrops(side: Side, into moves: inout [Move]) {
        let hand = hands[side.rawValue]
        // この手番が打てる駒種。
        let droppable = PieceType.allCases.filter { $0.isDroppable && hand[$0.rawValue] > 0 }
        guard !droppable.isEmpty else { return }

        // 二歩判定用: 各ファイルに自分の不成歩があるか。
        var pawnInFile = [Bool](repeating: false, count: 9)
        for i in 0..<Sq.count {
            if let p = squares[i], p.color == side, p.type == .pawn, !p.promoted {
                pawnInFile[Sq.file(i)] = true
            }
        }

        for to in 0..<Sq.count where squares[to] == nil {
            let r = Sq.rank(to)
            for type in droppable {
                switch type {
                case .pawn:
                    if (side == .black ? r == 0 : r == 8) { continue } // 行き所なし
                    if pawnInFile[Sq.file(to)] { continue }            // 二歩
                case .lance:
                    if (side == .black ? r == 0 : r == 8) { continue }
                case .knight:
                    if (side == .black ? r <= 1 : r >= 7) { continue }
                default:
                    break
                }
                moves.append(.drop(type: type, to: to))
            }
        }
    }

    // MARK: - 合法手生成

    /// 合法手（王手放置にならない手のみ。打ち歩詰めも除外）。
    public func legalMoves() -> [Move] {
        var pos = self
        return pos.legalMovesInPlace()
    }

    mutating func legalMovesInPlace() -> [Move] {
        let side = sideToMove
        var result: [Move] = []
        for move in pseudoLegalMoves() {
            let undo = make(move)
            var ok = !isKingInCheck(side)
            // 打ち歩詰め: 打った歩で相手が詰んでいたら反則。
            if ok, case .drop(.pawn, _) = move, isKingInCheck(side.opponent) {
                if legalMovesInPlace().isEmpty { ok = false }
            }
            unmake(undo)
            if ok { result.append(move) }
        }
        return result
    }
}
