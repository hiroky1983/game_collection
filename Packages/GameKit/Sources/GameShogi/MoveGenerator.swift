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

    private func movement(of piece: Piece) -> Movement {
        var steps: [(Int, Int)] = []
        var slides: [(Int, Int)] = []
        if piece.promoted {
            switch piece.type {
            case .pawn, .lance, .knight, .silver:
                steps = Self.goldSteps
            case .bishop: // 馬: 角の動き + 上下左右 1
                steps = Self.rookDirs
                slides = Self.bishopDirs
            case .rook: // 龍: 飛の動き + 斜め 1
                steps = Self.bishopDirs
                slides = Self.rookDirs
            case .gold, .king:
                break
            }
        } else {
            switch piece.type {
            case .pawn: steps = [(0, -1)]
            case .lance: slides = [(0, -1)]
            case .knight: steps = [(1, -2), (-1, -2)]
            case .silver: steps = Self.silverSteps
            case .gold: steps = Self.goldSteps
            case .king: steps = Self.kingSteps
            case .bishop: slides = Self.bishopDirs
            case .rook: slides = Self.rookDirs
            }
        }
        if piece.color == .white {
            steps = steps.map { ($0.0, -$0.1) }
            slides = slides.map { ($0.0, -$0.1) }
        }
        return Movement(steps: steps, slides: slides)
    }

    // MARK: - 利き判定

    /// from に居る駒が target を攻撃しているか。
    private func pieceAttacks(from: Int, _ piece: Piece, target: Int) -> Bool {
        let ff = Sq.file(from), fr = Sq.rank(from)
        let m = movement(of: piece)
        for (df, dr) in m.steps {
            if Sq.onBoard(file: ff + df, rank: fr + dr),
               Sq.index(file: ff + df, rank: fr + dr) == target {
                return true
            }
        }
        for (df, dr) in m.slides {
            var f = ff + df, r = fr + dr
            while Sq.onBoard(file: f, rank: r) {
                let idx = Sq.index(file: f, rank: r)
                if idx == target { return true }
                if squares[idx] != nil { break } // 駒に遮られる
                f += df; r += dr
            }
        }
        return false
    }

    /// target が color の駒に攻撃されているか。
    public func isAttacked(_ target: Int, by color: Side) -> Bool {
        for i in 0..<Sq.count {
            if let p = squares[i], p.color == color, pieceAttacks(from: i, p, target: target) {
                return true
            }
        }
        return false
    }

    /// 指定色の玉が王手されているか。
    public func isKingInCheck(_ color: Side) -> Bool {
        guard let king = squares.firstIndex(where: { $0?.type == .king && $0?.color == color }) else {
            return false
        }
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
