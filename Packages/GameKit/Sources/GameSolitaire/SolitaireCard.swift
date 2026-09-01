import Foundation

/// トランプのスート。`rawValue` はそのまま組札（foundation）の添字に使う。
public enum SolitaireSuit: Int, CaseIterable, Codable, Sendable, Hashable {
    case spade = 0, heart = 1, diamond = 2, club = 3

    public var isRed: Bool { self == .heart || self == .diamond }

    /// 同じ色のもう一方のスート。
    public var sameColorPartner: SolitaireSuit {
        switch self {
        case .spade:   return .club
        case .club:    return .spade
        case .heart:   return .diamond
        case .diamond: return .heart
        }
    }

    /// 反対色の2スート。組札の「安全な自動送り」の判定に使う。
    public var opposites: [SolitaireSuit] {
        isRed ? [.spade, .club] : [.heart, .diamond]
    }

    public var symbol: String {
        switch self {
        case .spade:   return "♠"
        case .heart:   return "♥"
        case .diamond: return "♦"
        case .club:    return "♣"
        }
    }
}

/// クロンダイクで扱う1枚。実カード52枚に加え、救済用のジョーカー（中継札・#397）を同じ型で表す。
///
/// ジョーカーは `rank == jokerRank` / `suit == nil` で、盤上では**場札の上にだけ**置ける。
/// `hasReceived` は「上に1枚受け取ったか」で、受け取り済みのジョーカーは再び露出した瞬間に
/// 自動消滅する（#397 ルール4。列の永久封鎖を防ぐ要のルール）。
public struct SolitaireCard: Identifiable, Codable, Sendable, Equatable, Hashable {
    /// ジョーカーの `rank`。実カードの 1〜13 と衝突しない値を使う。
    public static let jokerRank = 0
    /// ジョーカーの `id`。実カードは 0〜51 なので 52 を割り当てる。
    public static let jokerID = 52

    public let id: Int
    public let suit: SolitaireSuit?
    public let rank: Int
    /// ジョーカーが上に1枚受け取り済みか。実カードでは常に false。
    public var hasReceived: Bool

    public init(id: Int, suit: SolitaireSuit?, rank: Int, hasReceived: Bool = false) {
        self.id = id
        self.suit = suit
        self.rank = rank
        self.hasReceived = hasReceived
    }

    /// 実カード。`id` はスートとランクから一意に決まる。
    public init(_ suit: SolitaireSuit, _ rank: Int) {
        self.init(id: suit.rawValue * 13 + (rank - 1), suit: suit, rank: rank)
    }

    /// 未使用のジョーカー（中継札）。
    public static let joker = SolitaireCard(id: jokerID, suit: nil, rank: jokerRank)

    public var isJoker: Bool { rank == Self.jokerRank }

    /// 場札の交互色の判定に使う。ジョーカーは色を持たないので、この値だけで並びを判定してはいけない。
    public var isRed: Bool { suit?.isRed ?? false }

    public var rankLabel: String {
        switch rank {
        case Self.jokerRank: return "JOKER"
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// 読み上げ・ログ用の表記（例: "♠A"）。
    public var label: String {
        isJoker ? "JOKER" : "\(suit?.symbol ?? "")\(rankLabel)"
    }
}

public extension SolitaireCard {
    /// ジョーカーを含まない52枚の山札（未シャッフル）。
    /// クロンダイクの配札に使うのは実カードだけで、ジョーカーは救済時に外から差し込む。
    static func makeDeck() -> [SolitaireCard] {
        SolitaireSuit.allCases.flatMap { suit in (1...13).map { SolitaireCard(suit, $0) } }
    }
}
