import Foundation

/// 手番／駒の所有者。白（white）は盤下段（rank index 6-7）に居り、rank index が小さくなる方向へ進む。
///
/// 将棋（`GameShogi`）と同じ「先手 = 盤下段・rank -1 方向へ前進」という座標の取り方に揃えてある。
/// 盤の向きを扱う `ChessSquare.boardIndex(row:col:flipped:)` の式をそのまま流用できる。
public enum ChessColor: Int, Sendable, CaseIterable, Codable {
    case white, black

    public var opponent: ChessColor { self == .white ? .black : .white }

    /// この色の駒が前進する rank index の向き。
    public var forward: Int { self == .white ? -1 : 1 }

    /// この色の駒が並ぶ最奥段（プロモーションが起きる rank index）。
    public var promotionRank: Int { self == .white ? 0 : 7 }

    /// ポーンの初期段（2段進みの起点）。
    public var pawnStartRank: Int { self == .white ? 6 : 1 }

    public var name: String { self == .white ? "白" : "黒" }
}

/// 駒種。
public enum ChessPieceType: Int, Sendable, CaseIterable, Codable {
    case pawn, knight, bishop, rook, queen, king

    /// FEN / UCI で使う 1 文字（大文字 = 駒種記号。先後は表示側で大小化する）。
    /// ナイトだけ King と衝突するため慣例どおり `N`。
    public var fenLetter: Character {
        switch self {
        case .pawn:   return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook:   return "R"
        case .queen:  return "Q"
        case .king:   return "K"
        }
    }

    public static func from(fenLetter c: Character) -> ChessPieceType? {
        ChessPieceType.allCases.first { $0.fenLetter == c }
    }

    /// プロモーション先になれるか（ポーンとキングは除く）。
    public var isPromotionTarget: Bool {
        self != .pawn && self != .king
    }

    /// 日本語の呼び名（UI・読み上げ・遊び方で共通に使う）。
    public var japaneseName: String {
        switch self {
        case .pawn:   return "ポーン"
        case .knight: return "ナイト"
        case .bishop: return "ビショップ"
        case .rook:   return "ルーク"
        case .queen:  return "クイーン"
        case .king:   return "キング"
        }
    }
}

/// 盤上の 1 駒。
public struct ChessPiece: Equatable, Sendable {
    public var type: ChessPieceType
    public var color: ChessColor

    public init(type: ChessPieceType, color: ChessColor) {
        self.type = type
        self.color = color
    }

    /// FEN の 1 文字（白 = 大文字 / 黒 = 小文字）。
    public var fenCharacter: Character {
        let letter = type.fenLetter
        return color == .white ? letter : Character(letter.lowercased())
    }
}

/// キャスリングの権利。FEN の `KQkq` に 1 対 1 で対応する。
public struct ChessCastlingRights: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let whiteKingside  = ChessCastlingRights(rawValue: 1 << 0)
    public static let whiteQueenside = ChessCastlingRights(rawValue: 1 << 1)
    public static let blackKingside  = ChessCastlingRights(rawValue: 1 << 2)
    public static let blackQueenside = ChessCastlingRights(rawValue: 1 << 3)

    public static let all: ChessCastlingRights = [
        .whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside,
    ]

    public static func kingside(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? .whiteKingside : .blackKingside
    }

    public static func queenside(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? .whiteQueenside : .blackQueenside
    }

    /// その色ぶんの両方の権利。
    public static func both(_ color: ChessColor) -> ChessCastlingRights {
        color == .white ? [.whiteKingside, .whiteQueenside] : [.blackKingside, .blackQueenside]
    }

    /// FEN のフィールド（例 "KQkq"、無ければ "-"）。
    public var fenField: String {
        var s = ""
        if contains(.whiteKingside)  { s += "K" }
        if contains(.whiteQueenside) { s += "Q" }
        if contains(.blackKingside)  { s += "k" }
        if contains(.blackQueenside) { s += "q" }
        return s.isEmpty ? "-" : s
    }

    public static func fromFEN(_ field: Substring) -> ChessCastlingRights {
        var r: ChessCastlingRights = []
        for ch in field {
            switch ch {
            case "K": r.insert(.whiteKingside)
            case "Q": r.insert(.whiteQueenside)
            case "k": r.insert(.blackKingside)
            case "q": r.insert(.blackQueenside)
            default: break
            }
        }
        return r
    }
}
