import Foundation
import Core

// MARK: - Card

public enum PokerSuit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs
    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }
    public var isRed: Bool { self == .hearts || self == .diamonds }

    /// トランプ共通基盤（#397）の描画用スート。`rawValue` の一致に頼らず明示的に対応させる。
    public var playing: PlayingCardSuit {
        switch self {
        case .spades:   return .spade
        case .hearts:   return .heart
        case .diamonds: return .diamond
        case .clubs:    return .club
        }
    }
}

public struct PokerCard: Identifiable, Codable, Sendable, Equatable {
    public let id: Int           // 0–51
    public let suit: PokerSuit
    public let rank: Int         // 2–14 (A=14)

    public var rankLabel: String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        case 10: return "10"
        default: return "\(rank)"
        }
    }

    /// トランプ共通基盤（#397）へ渡す面の内容。
    /// 共通基盤は A=1 の表記なので、強さのために A=14 としている `rank` を戻して渡す。
    public var figure: PlayingCardFigure {
        .pip(suit: suit.playing, rank: rank == 14 ? 1 : rank)
    }
}

// MARK: - Hand Rank

public enum PokerHandRank: Int, Comparable, CustomStringConvertible, Sendable {
    case highCard = 0, onePair, twoPair, threeOfAKind,
         straight, flush, fullHouse, fourOfAKind, straightFlush, royalFlush

    public static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String {
        switch self {
        case .highCard:      return "ハイカード"
        case .onePair:       return "ワンペア"
        case .twoPair:       return "ツーペア"
        case .threeOfAKind:  return "スリーカード"
        case .straight:      return "ストレート"
        case .flush:         return "フラッシュ"
        case .fullHouse:     return "フルハウス"
        case .fourOfAKind:   return "フォーカード"
        case .straightFlush: return "ストレートフラッシュ"
        case .royalFlush:    return "ロイヤルフラッシュ"
        }
    }
}
