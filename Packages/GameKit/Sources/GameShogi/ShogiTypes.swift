import Foundation

/// 手番／駒の所有者。先手(black)は盤下段に居り rank が小さくなる方向（'a' 側）へ進む。
public enum Side: Int, Sendable, CaseIterable {
    case black, white

    public var opponent: Side { self == .black ? .white : .black }
}

/// 駒種（基本形）。成りは `Piece.promoted` フラグで表す。
public enum PieceType: Int, Sendable, CaseIterable {
    case pawn, lance, knight, silver, gold, bishop, rook, king

    /// 成れる駒か（金・玉は成れない）。
    public var canPromote: Bool {
        switch self {
        case .pawn, .lance, .knight, .silver, .bishop, .rook: return true
        case .gold, .king: return false
        }
    }

    /// 持ち駒として保持できるか（玉は不可）。持ち駒配列のインデックスは rawValue を流用。
    public var isDroppable: Bool { self != .king }

    /// USI / SFEN で使う 1 文字（大文字 = 駒種記号、先後は表示側で大小化）。
    public var usiLetter: Character {
        switch self {
        case .pawn: return "P"
        case .lance: return "L"
        case .knight: return "N"
        case .silver: return "S"
        case .gold: return "G"
        case .bishop: return "B"
        case .rook: return "R"
        case .king: return "K"
        }
    }

    public static func from(usiLetter c: Character) -> PieceType? {
        PieceType.allCases.first { $0.usiLetter == c }
    }
}

/// 盤上の 1 駒。
public struct Piece: Equatable, Sendable {
    public var type: PieceType
    public var color: Side
    public var promoted: Bool

    public init(type: PieceType, color: Side, promoted: Bool = false) {
        self.type = type
        self.color = color
        self.promoted = promoted
    }
}
