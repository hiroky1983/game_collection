import Foundation
import Core

/// 七並べのスート。ジョーカーは使わない（#1198）。
public enum SevensSuit: Int, CaseIterable, Codable, Sendable {
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

/// 七並べの1枚。`rank` は A=1 / 2〜10 / J=11 / Q=12 / K=13（ジョーカー無し）。
public struct SevensCard: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: Int              // 0–51
    public let suit: SevensSuit
    public let rank: Int

    public init(id: Int, suit: SevensSuit, rank: Int) {
        self.id = id
        self.suit = suit
        self.rank = rank
    }

    public var rankLabel: String {
        switch rank {
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// 手札の並べ替えに使う既定の順序（スート → ランク）。
    public var sortKey: Int { suit.rawValue * 100 + rank }

    /// トランプ共通基盤（#397）へ渡す面の内容。
    public var figure: PlayingCardFigure { .pip(suit: suit.playing, rank: rank) }
}

public extension SevensCard {
    /// ジョーカーを除いた52枚の山札（未シャッフル）。
    static func makeDeck() -> [SevensCard] {
        var cards: [SevensCard] = []
        var id = 0
        for suit in SevensSuit.allCases {
            for rank in 1...13 {
                cards.append(SevensCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        return cards
    }
}
