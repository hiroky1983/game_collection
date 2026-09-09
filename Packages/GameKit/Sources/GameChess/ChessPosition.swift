import Foundation

/// 局面。盤・手番・キャスリング権・アンパッサン標的・50手ルールの計数を保持する。
/// 値型で make/unmake により可逆に更新する（将棋の `Position` と同じ設計）。
public struct ChessPosition: Equatable, Sendable {
    /// 64 マス。nil = 空。
    public var squares: [ChessPiece?]
    public var sideToMove: ChessColor
    public var castling: ChessCastlingRights
    /// アンパッサンで**取りに行けるマス**（通過されたマス）。直前手が 2 マス進みでなければ nil。
    public var enPassant: Int?
    /// 50手ルールの半手計数。ポーンの移動と駒取りで 0 に戻る。
    public var halfmoveClock: Int
    /// 手数（黒が指し終えるたびに 1 増える。FEN の 6 番目のフィールド）。
    public var fullmoveNumber: Int

    public init(
        squares: [ChessPiece?],
        sideToMove: ChessColor,
        castling: ChessCastlingRights,
        enPassant: Int?,
        halfmoveClock: Int,
        fullmoveNumber: Int
    ) {
        self.squares = squares
        self.sideToMove = sideToMove
        self.castling = castling
        self.enPassant = enPassant
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    /// 標準初期局面。
    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    public static func start() -> ChessPosition { fromFEN(startFEN)! }

    // MARK: - キャスリングの定位置

    /// キングの初期マス。
    @inline(__always) static func kingHome(_ color: ChessColor) -> Int {
        ChessSquare.index(file: 4, rank: color == .white ? 7 : 0)
    }

    /// ルークの初期マス。
    @inline(__always) static func rookHome(_ color: ChessColor, kingside: Bool) -> Int {
        ChessSquare.index(file: kingside ? 7 : 0, rank: color == .white ? 7 : 0)
    }

    /// この移動がキャスリングか（キングが横に 2 マス動く）。
    func isCastling(_ move: ChessMove) -> Bool {
        guard let piece = squares[move.from], piece.type == .king else { return false }
        return abs(ChessSquare.file(move.to) - ChessSquare.file(move.from)) == 2
    }

    /// この移動がアンパッサンか（ポーンが斜めに空きマスへ動く）。
    func isEnPassant(_ move: ChessMove) -> Bool {
        guard let piece = squares[move.from], piece.type == .pawn else { return false }
        return ChessSquare.file(move.to) != ChessSquare.file(move.from) && squares[move.to] == nil
    }

    // MARK: - make / unmake

    /// make の巻き戻し情報。
    ///
    /// アンパッサンでは取った駒が `to` に居ないため、**捕獲駒の位置も一緒に控える**
    /// （`captured` だけでは戻せない）。キャスリング権・アンパッサン標的・50手計数も
    /// 手が進むと不可逆に潰れるので、ここに退避しておく。
    public struct Undo: Sendable {
        let move: ChessMove
        let captured: ChessPiece?
        let capturedSquare: Int
        let prevSide: ChessColor
        let prevCastling: ChessCastlingRights
        let prevEnPassant: Int?
        let prevHalfmoveClock: Int
        let prevFullmoveNumber: Int
    }

    /// 指し手を適用し、巻き戻し情報を返す。合法性は呼び出し側が保証する。
    @discardableResult
    public mutating func make(_ move: ChessMove) -> Undo {
        let side = sideToMove
        let piece = squares[move.from]!

        let castlingMove = isCastling(move)
        let enPassantMove = isEnPassant(move)

        // 捕獲駒。アンパッサンだけは `to` ではなく「通過されたポーンのマス」に居る。
        let capturedSquare = enPassantMove
            ? ChessSquare.index(file: ChessSquare.file(move.to), rank: ChessSquare.rank(move.from))
            : move.to
        let captured = squares[capturedSquare]

        let undo = Undo(
            move: move,
            captured: captured,
            capturedSquare: capturedSquare,
            prevSide: side,
            prevCastling: castling,
            prevEnPassant: enPassant,
            prevHalfmoveClock: halfmoveClock,
            prevFullmoveNumber: fullmoveNumber
        )

        squares[capturedSquare] = nil
        squares[move.from] = nil
        squares[move.to] = ChessPiece(type: move.promotion ?? piece.type, color: side)

        if castlingMove {
            // ルークも一緒に動かす。king side なら h筋 → f筋、queen side なら a筋 → d筋。
            let kingside = ChessSquare.file(move.to) > ChessSquare.file(move.from)
            let rookFrom = Self.rookHome(side, kingside: kingside)
            let rookTo = ChessSquare.index(file: kingside ? 5 : 3, rank: ChessSquare.rank(move.from))
            squares[rookTo] = squares[rookFrom]
            squares[rookFrom] = nil
        }

        // キャスリング権: 動いた駒・取られた駒がキング/ルークの定位置に関わるなら失う。
        if piece.type == .king { castling.subtract(ChessCastlingRights.both(side)) }
        revokeCastlingRight(touching: move.from)
        revokeCastlingRight(touching: capturedSquare)

        // アンパッサン標的: ポーンの 2 マス進みの直後だけ立つ。
        if piece.type == .pawn, abs(ChessSquare.rank(move.to) - ChessSquare.rank(move.from)) == 2 {
            enPassant = ChessSquare.index(
                file: ChessSquare.file(move.from),
                rank: (ChessSquare.rank(move.from) + ChessSquare.rank(move.to)) / 2
            )
        } else {
            enPassant = nil
        }

        // 50手ルール: ポーンの移動と駒取りで 0 に戻る。
        halfmoveClock = (piece.type == .pawn || captured != nil) ? 0 : halfmoveClock + 1
        if side == .black { fullmoveNumber += 1 }
        sideToMove = side.opponent
        return undo
    }

    /// make を巻き戻す。
    public mutating func unmake(_ undo: Undo) {
        let side = undo.prevSide
        let move = undo.move

        sideToMove = side
        castling = undo.prevCastling
        enPassant = undo.prevEnPassant
        halfmoveClock = undo.prevHalfmoveClock
        fullmoveNumber = undo.prevFullmoveNumber

        let moved = squares[move.to]!
        // プロモーションしていたらポーンに戻す。
        squares[move.from] = ChessPiece(type: move.promotion == nil ? moved.type : .pawn, color: side)
        squares[move.to] = nil
        squares[undo.capturedSquare] = undo.captured

        // キャスリングならルークも戻す。`castling` を復元済みなので `isCastling` は使えず
        // （盤上のキングも既に移動元へ戻っている）、移動距離から直接判定する。
        if moved.type == .king, abs(ChessSquare.file(move.to) - ChessSquare.file(move.from)) == 2 {
            let kingside = ChessSquare.file(move.to) > ChessSquare.file(move.from)
            let rookFrom = Self.rookHome(side, kingside: kingside)
            let rookTo = ChessSquare.index(file: kingside ? 5 : 3, rank: ChessSquare.rank(move.from))
            squares[rookFrom] = squares[rookTo]
            squares[rookTo] = nil
        }
    }

    /// そのマスがキング/ルークの定位置なら、対応するキャスリング権を落とす。
    /// 「そこから動いた」「そこの駒を取られた」のどちらでも権利は消えるので、両方をここに集約する。
    private mutating func revokeCastlingRight(touching square: Int) {
        switch square {
        case Self.rookHome(.white, kingside: true):   castling.remove(.whiteKingside)
        case Self.rookHome(.white, kingside: false):  castling.remove(.whiteQueenside)
        case Self.rookHome(.black, kingside: true):   castling.remove(.blackKingside)
        case Self.rookHome(.black, kingside: false):  castling.remove(.blackQueenside)
        case Self.kingHome(.white):                   castling.subtract(ChessCastlingRights.both(.white))
        case Self.kingHome(.black):                   castling.subtract(ChessCastlingRights.both(.black))
        default: break
        }
    }

    // MARK: - FEN

    /// FEN 文字列をパースする。
    public static func fromFEN(_ fen: String) -> ChessPosition? {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 4 else { return nil }

        var squares = [ChessPiece?](repeating: nil, count: 64)
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }
        for (rank, row) in rows.enumerated() {
            var file = 0
            for ch in row {
                if let empties = ch.wholeNumberValue {
                    guard empties >= 1, empties <= 8 else { return nil }
                    file += empties
                    continue
                }
                guard file < 8,
                      let type = ChessPieceType.from(fenLetter: Character(ch.uppercased())) else { return nil }
                squares[ChessSquare.index(file: file, rank: rank)] =
                    ChessPiece(type: type, color: ch.isUppercase ? .white : .black)
                file += 1
            }
            guard file == 8 else { return nil }
        }

        let side: ChessColor = fields[1] == "b" ? .black : .white
        let castling = ChessCastlingRights.fromFEN(fields[2])
        let enPassant = fields[3] == "-" ? nil : ChessSquare.fromName(fields[3])
        let halfmove = fields.count >= 5 ? (Int(fields[4]) ?? 0) : 0
        let fullmove = fields.count >= 6 ? (Int(fields[5]) ?? 1) : 1

        return ChessPosition(
            squares: squares,
            sideToMove: side,
            castling: castling,
            enPassant: enPassant,
            halfmoveClock: halfmove,
            fullmoveNumber: fullmove
        )
    }

    /// 局面を FEN 文字列へ。`ChessEngine`（UCI 境界）へ渡すために使う。
    public func toFEN() -> String {
        var rows: [String] = []
        for rank in 0..<8 {
            var row = ""
            var empties = 0
            for file in 0..<8 {
                if let p = squares[ChessSquare.index(file: file, rank: rank)] {
                    if empties > 0 { row += String(empties); empties = 0 }
                    row.append(p.fenCharacter)
                } else {
                    empties += 1
                }
            }
            if empties > 0 { row += String(empties) }
            rows.append(row)
        }
        let ep = enPassant.map(ChessSquare.name) ?? "-"
        return "\(rows.joined(separator: "/")) \(sideToMove == .white ? "w" : "b") "
            + "\(castling.fenField) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }
}
