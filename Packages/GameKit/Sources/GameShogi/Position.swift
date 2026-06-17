import Foundation

/// 局面。盤・持ち駒・手番・手数を保持する。値型で make/unmake により可逆に更新する。
public struct Position: Equatable, Sendable {
    /// 81 マス。nil = 空。
    public var squares: [Piece?]
    /// hands[color.rawValue][PieceType.rawValue] = 持ち駒枚数（pawn..rook の 0..6 を使用）。
    public var hands: [[Int]]
    public var sideToMove: Side
    public var moveNumber: Int

    public init(
        squares: [Piece?],
        hands: [[Int]],
        sideToMove: Side,
        moveNumber: Int
    ) {
        self.squares = squares
        self.hands = hands
        self.sideToMove = sideToMove
        self.moveNumber = moveNumber
    }

    /// 平手初期局面。
    public static let startSFEN = "lnsgkgsnl/1r5b1/ppppppppp/9/9/9/PPPPPPPPP/1B5R1/LNSGKGSNL b - 1"

    public static func start() -> Position { fromSFEN(startSFEN)! }

    // MARK: - make / unmake

    /// make の巻き戻し情報。
    public struct Undo: Sendable {
        let move: Move
        let captured: Piece?
        let prevSide: Side
    }

    /// 指し手を適用し、巻き戻し情報を返す。合法性は呼び出し側が保証する。
    @discardableResult
    public mutating func make(_ move: Move) -> Undo {
        let side = sideToMove
        var captured: Piece?
        switch move {
        case let .board(from, to, promote):
            var piece = squares[from]!
            captured = squares[to]
            if let cap = captured, cap.type.isDroppable {
                // 捕獲駒は成りを解除した基本形で自分の持ち駒へ（玉は持ち駒にならない）。
                hands[side.rawValue][cap.type.rawValue] += 1
            }
            squares[from] = nil
            if promote { piece.promoted = true }
            squares[to] = piece
        case let .drop(type, to):
            hands[side.rawValue][type.rawValue] -= 1
            squares[to] = Piece(type: type, color: side, promoted: false)
        }
        sideToMove = side.opponent
        moveNumber += 1
        return Undo(move: move, captured: captured, prevSide: side)
    }

    /// make を巻き戻す。
    public mutating func unmake(_ undo: Undo) {
        sideToMove = undo.prevSide
        moveNumber -= 1
        let side = undo.prevSide
        switch undo.move {
        case let .board(from, to, promote):
            var piece = squares[to]!
            if promote { piece.promoted = false }
            squares[from] = piece
            squares[to] = undo.captured
            if let cap = undo.captured, cap.type.isDroppable {
                hands[side.rawValue][cap.type.rawValue] -= 1
            }
        case let .drop(type, to):
            squares[to] = nil
            hands[side.rawValue][type.rawValue] += 1
        }
    }

    // MARK: - SFEN

    /// SFEN 文字列をパースする。
    public static func fromSFEN(_ sfen: String) -> Position? {
        let fields = sfen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 3 else { return nil }

        // 盤面
        var squares = [Piece?](repeating: nil, count: 81)
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 9 else { return nil }
        for (rank, row) in rows.enumerated() {
            // SFEN は各段を左端=9筋から 1筋へ並べる。fileIndex 8(=9筋) から減らす。
            var file = 8
            var promotedNext = false
            for ch in row {
                if ch == "+" { promotedNext = true; continue }
                if let empties = ch.wholeNumberValue {
                    file -= empties
                    continue
                }
                guard file >= 0 else { return nil }
                let isBlack = ch.isUppercase
                guard let type = PieceType.from(usiLetter: Character(ch.uppercased())) else { return nil }
                squares[Sq.index(file: file, rank: rank)] = Piece(
                    type: type,
                    color: isBlack ? .black : .white,
                    promoted: promotedNext
                )
                promotedNext = false
                file -= 1
            }
        }

        // 手番
        let side: Side = fields[1] == "w" ? .white : .black

        // 持ち駒
        var hands = [[Int]](repeating: [Int](repeating: 0, count: 7), count: 2)
        if fields[2] != "-" {
            var pending = 0
            for ch in fields[2] {
                if let d = ch.wholeNumberValue {
                    pending = pending * 10 + d
                    continue
                }
                guard let type = PieceType.from(usiLetter: Character(ch.uppercased())),
                      type.isDroppable else { return nil }
                let color: Side = ch.isUppercase ? .black : .white
                hands[color.rawValue][type.rawValue] += max(pending, 1)
                pending = 0
            }
        }

        let moveNumber = fields.count >= 4 ? (Int(fields[3]) ?? 1) : 1
        return Position(squares: squares, hands: hands, sideToMove: side, moveNumber: moveNumber)
    }

    /// 局面を SFEN 文字列へ。`ShogiEngine`(USI 境界) へ渡すために使う。
    public func toSFEN() -> String {
        var rows: [String] = []
        for rank in 0..<9 {
            var row = ""
            var empties = 0
            for file in stride(from: 8, through: 0, by: -1) { // 9筋 → 1筋
                if let p = squares[Sq.index(file: file, rank: rank)] {
                    if empties > 0 { row += String(empties); empties = 0 }
                    let letter = p.color == .black ? String(p.type.usiLetter) : String(p.type.usiLetter).lowercased()
                    row += (p.promoted ? "+" : "") + letter
                } else {
                    empties += 1
                }
            }
            if empties > 0 { row += String(empties) }
            rows.append(row)
        }
        let board = rows.joined(separator: "/")
        let side = sideToMove == .black ? "b" : "w"

        // 持ち駒: 先手大文字→後手小文字、枚数2以上は数値前置。順序は R,B,G,S,N,L,P が慣例。
        let handOrder: [PieceType] = [.rook, .bishop, .gold, .silver, .knight, .lance, .pawn]
        var handStr = ""
        for color in [Side.black, Side.white] {
            for type in handOrder {
                let n = hands[color.rawValue][type.rawValue]
                guard n > 0 else { continue }
                if n > 1 { handStr += String(n) }
                let letter = color == .black ? String(type.usiLetter) : String(type.usiLetter).lowercased()
                handStr += letter
            }
        }
        if handStr.isEmpty { handStr = "-" }

        return "\(board) \(side) \(handStr) \(moveNumber)"
    }
}
