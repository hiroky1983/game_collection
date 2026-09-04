import Foundation

extension ChessPosition {

    // MARK: - 駒の利き定義

    static let knightOffsets: [(Int, Int)] = [
        (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2),
    ]
    static let bishopDirs: [(Int, Int)] = [(1, 1), (1, -1), (-1, -1), (-1, 1)]
    static let rookDirs: [(Int, Int)] = [(0, 1), (1, 0), (0, -1), (-1, 0)]
    static let kingOffsets: [(Int, Int)] = bishopDirs + rookDirs

    // MARK: - 利き判定

    /// target が color の駒に攻撃されているか。
    ///
    /// 盤の全マスを走査するのではなく、**target から外へ放射して**駒を探す。
    /// 合法手生成は着手のたびにこれを呼ぶので、ここの計算量がそのまま探索速度になる。
    public func isAttacked(_ target: Int, by color: ChessColor) -> Bool {
        let tf = ChessSquare.file(target), tr = ChessSquare.rank(target)

        // ポーン。color のポーンは forward 方向へ斜めに取るので、
        // target を攻撃しているポーンは target から見て forward の**逆**側に居る。
        let pawnRank = tr - color.forward
        for df in [-1, 1] {
            let f = tf + df
            guard ChessSquare.onBoard(file: f, rank: pawnRank) else { continue }
            if let p = squares[ChessSquare.index(file: f, rank: pawnRank)],
               p.color == color, p.type == .pawn { return true }
        }

        // ナイト。
        for (df, dr) in Self.knightOffsets {
            let f = tf + df, r = tr + dr
            guard ChessSquare.onBoard(file: f, rank: r) else { continue }
            if let p = squares[ChessSquare.index(file: f, rank: r)],
               p.color == color, p.type == .knight { return true }
        }

        // キング（隣接 1 マス）。
        for (df, dr) in Self.kingOffsets {
            let f = tf + df, r = tr + dr
            guard ChessSquare.onBoard(file: f, rank: r) else { continue }
            if let p = squares[ChessSquare.index(file: f, rank: r)],
               p.color == color, p.type == .king { return true }
        }

        // 長距離駒。斜めはビショップ／クイーン、直線はルーク／クイーン。
        if slidingAttacker(from: target, dirs: Self.bishopDirs, by: color, types: (.bishop, .queen)) { return true }
        if slidingAttacker(from: target, dirs: Self.rookDirs, by: color, types: (.rook, .queen)) { return true }
        return false
    }

    private func slidingAttacker(
        from target: Int,
        dirs: [(Int, Int)],
        by color: ChessColor,
        types: (ChessPieceType, ChessPieceType)
    ) -> Bool {
        let tf = ChessSquare.file(target), tr = ChessSquare.rank(target)
        for (df, dr) in dirs {
            var f = tf + df, r = tr + dr
            while ChessSquare.onBoard(file: f, rank: r) {
                if let p = squares[ChessSquare.index(file: f, rank: r)] {
                    if p.color == color, p.type == types.0 || p.type == types.1 { return true }
                    break // 味方でも敵でも、駒に遮られたらその方向は終わり
                }
                f += df; r += dr
            }
        }
        return false
    }

    /// 指定色のキングの居るマス。盤に居なければ nil（テスト用の部分局面で起こりうる）。
    public func kingSquare(_ color: ChessColor) -> Int? {
        squares.firstIndex { $0?.type == .king && $0?.color == color }
    }

    /// 指定色のキングが王手されているか。
    public func isKingInCheck(_ color: ChessColor) -> Bool {
        guard let king = kingSquare(color) else { return false }
        return isAttacked(king, by: color.opponent)
    }

    // MARK: - 疑似合法手生成（自玉が取られる手を除かない）

    public func pseudoLegalMoves() -> [ChessMove] {
        var moves: [ChessMove] = []
        moves.reserveCapacity(48)
        let side = sideToMove

        for from in 0..<ChessSquare.count {
            guard let piece = squares[from], piece.color == side else { continue }
            switch piece.type {
            case .pawn:   appendPawnMoves(from: from, side: side, into: &moves)
            case .knight: appendStepMoves(from: from, side: side, offsets: Self.knightOffsets, into: &moves)
            case .king:   appendStepMoves(from: from, side: side, offsets: Self.kingOffsets, into: &moves)
            case .bishop: appendSlideMoves(from: from, side: side, dirs: Self.bishopDirs, into: &moves)
            case .rook:   appendSlideMoves(from: from, side: side, dirs: Self.rookDirs, into: &moves)
            case .queen:  appendSlideMoves(from: from, side: side, dirs: Self.kingOffsets, into: &moves)
            }
        }
        appendCastlingMoves(side: side, into: &moves)
        return moves
    }

    private func appendStepMoves(
        from: Int, side: ChessColor, offsets: [(Int, Int)], into moves: inout [ChessMove]
    ) {
        let ff = ChessSquare.file(from), fr = ChessSquare.rank(from)
        for (df, dr) in offsets {
            let f = ff + df, r = fr + dr
            guard ChessSquare.onBoard(file: f, rank: r) else { continue }
            let to = ChessSquare.index(file: f, rank: r)
            if let occ = squares[to], occ.color == side { continue }
            moves.append(ChessMove(from: from, to: to))
        }
    }

    private func appendSlideMoves(
        from: Int, side: ChessColor, dirs: [(Int, Int)], into moves: inout [ChessMove]
    ) {
        let ff = ChessSquare.file(from), fr = ChessSquare.rank(from)
        for (df, dr) in dirs {
            var f = ff + df, r = fr + dr
            while ChessSquare.onBoard(file: f, rank: r) {
                let to = ChessSquare.index(file: f, rank: r)
                if let occ = squares[to] {
                    if occ.color != side { moves.append(ChessMove(from: from, to: to)) }
                    break
                }
                moves.append(ChessMove(from: from, to: to))
                f += df; r += dr
            }
        }
    }

    private func appendPawnMoves(from: Int, side: ChessColor, into moves: inout [ChessMove]) {
        let ff = ChessSquare.file(from), fr = ChessSquare.rank(from)
        let dir = side.forward

        // 1 マス前進（+ 空いていれば 2 マス）。
        let oneRank = fr + dir
        if ChessSquare.onBoard(file: ff, rank: oneRank) {
            let one = ChessSquare.index(file: ff, rank: oneRank)
            if squares[one] == nil {
                appendPawnDestination(from: from, to: one, side: side, into: &moves)
                if fr == side.pawnStartRank {
                    let two = ChessSquare.index(file: ff, rank: fr + dir * 2)
                    if squares[two] == nil { moves.append(ChessMove(from: from, to: two)) }
                }
            }
        }

        // 斜めの駒取り（アンパッサンを含む）。
        for df in [-1, 1] {
            let f = ff + df
            guard ChessSquare.onBoard(file: f, rank: oneRank) else { continue }
            let to = ChessSquare.index(file: f, rank: oneRank)
            if let occ = squares[to] {
                if occ.color != side { appendPawnDestination(from: from, to: to, side: side, into: &moves) }
            } else if to == enPassant {
                moves.append(ChessMove(from: from, to: to))
            }
        }
    }

    /// 最奥段ならプロモーション 4 種、そうでなければ 1 手を積む。
    private func appendPawnDestination(
        from: Int, to: Int, side: ChessColor, into moves: inout [ChessMove]
    ) {
        guard ChessSquare.rank(to) == side.promotionRank else {
            moves.append(ChessMove(from: from, to: to))
            return
        }
        for type in ChessPieceType.allCases where type.isPromotionTarget {
            moves.append(ChessMove(from: from, to: to, promotion: type))
        }
    }

    /// キャスリング。
    ///
    /// ここで「権利がある」「間が空いている」「キングが今王手でない」「通過マスが攻撃されていない」
    /// までを見る。**着地マスの安全**だけは合法手フィルタ（自玉の王手チェック）に任せる
    /// ＝ 3 マスの検査が 1 か所に散らばらない。
    private func appendCastlingMoves(side: ChessColor, into moves: inout [ChessMove]) {
        let rights = castling.intersection(ChessCastlingRights.both(side))
        guard !rights.isEmpty else { return }
        let home = Self.kingHome(side)
        // 権利が立っていてもキング・ルークが定位置に居ない局面（テスト用の FEN 等）は捨てる。
        guard squares[home] == ChessPiece(type: .king, color: side) else { return }
        guard !isAttacked(home, by: side.opponent) else { return }
        let rank = ChessSquare.rank(home)

        for kingside in [true, false] {
            guard rights.contains(kingside ? .kingside(side) : .queenside(side)) else { continue }
            let rookSquare = Self.rookHome(side, kingside: kingside)
            guard squares[rookSquare] == ChessPiece(type: .rook, color: side) else { continue }

            // 間のマスがすべて空いていること（クイーンサイドは b筋 も空きが要る）。
            let emptyFiles = kingside ? [5, 6] : [1, 2, 3]
            guard emptyFiles.allSatisfy({ squares[ChessSquare.index(file: $0, rank: rank)] == nil }) else { continue }

            // キングが通過するマスが攻撃されていないこと。
            let passFile = kingside ? 5 : 3
            guard !isAttacked(ChessSquare.index(file: passFile, rank: rank), by: side.opponent) else { continue }

            moves.append(ChessMove(from: home, to: ChessSquare.index(file: kingside ? 6 : 2, rank: rank)))
        }
    }

    // MARK: - 合法手生成

    /// **実際に取りに行けるときだけ**値を持つアンパッサン標的。
    ///
    /// 3回同形反復の「同じ局面」は、FIDE では「同じ指し手が指せること」で決まる。
    /// アンパッサン標的は 2 マス進みの直後なら**取れなくても必ず立つ**ので、そのまま比較すると
    /// 「指せる手は全く同じなのに別の局面」と読んでしまい、反復を検出し損ねる
    /// （CodeRabbit 指摘・Major）。
    ///
    /// 標的が立っていない局面では合法手を数えないので、通常の手では追加のコストが掛からない。
    public func effectiveEnPassant() -> Int? {
        guard let target = enPassant else { return nil }
        let capturable = legalMoves().contains {
            $0.to == target && squares[$0.from]?.type == .pawn
        }
        return capturable ? target : nil
    }

    /// 合法手（指したあとに自玉が取られない手のみ）。
    public func legalMoves() -> [ChessMove] {
        var pos = self
        return pos.legalMovesInPlace()
    }

    mutating func legalMovesInPlace() -> [ChessMove] {
        let side = sideToMove
        var result: [ChessMove] = []
        result.reserveCapacity(40)
        for move in pseudoLegalMoves() {
            let undo = make(move)
            let ok = !isKingInCheck(side)
            unmake(undo)
            if ok { result.append(move) }
        }
        return result
    }
}
