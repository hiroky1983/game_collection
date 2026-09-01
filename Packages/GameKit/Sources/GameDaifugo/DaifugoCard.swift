import Foundation
import Core

/// 大富豪のスート。ジョーカーはスートを持たない（`nil`）。
public enum DaifugoSuit: Int, CaseIterable, Codable, Sendable {
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

/// 大富豪の1枚。`rank` は A=1 / 2=2 / 3〜10 / J=11 / Q=12 / K=13、ジョーカーは `DaifugoRules.jokerRank`（0）。
///
/// ポーカー（`PokerCard`）は A=14 の数値をそのまま強さに使えるが、大富豪は 3 が最弱・2 が最強で
/// 革命による反転もあるため、**数値と強さを分離**して `DaifugoRules.strength` 側に寄せている。
public struct DaifugoCard: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: Int              // 0–53（52, 53 がジョーカー）
    public let suit: DaifugoSuit?   // nil = ジョーカー
    public let rank: Int

    public init(id: Int, suit: DaifugoSuit?, rank: Int) {
        self.id = id
        self.suit = suit
        self.rank = rank
    }

    public var isJoker: Bool { rank == DaifugoRules.jokerRank }

    public var rankLabel: String {
        switch rank {
        case DaifugoRules.jokerRank: return "JOKER"
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// 場・手札の並べ替えに使う既定の順序（革命の影響を受けない素の強さ → スート）。
    public var sortKey: Int {
        DaifugoRules.baseStrength(rank: rank) * 10 + (suit?.rawValue ?? 0)
    }

    /// トランプ共通基盤（#397）へ渡す面の内容。`rank` は既に A=1 表記なのでそのまま渡す。
    public var figure: PlayingCardFigure {
        guard let suit else { return .joker }
        return .pip(suit: suit.playing, rank: rank)
    }
}

public extension DaifugoCard {
    /// ジョーカー2枚を含む54枚の山札（未シャッフル）。
    static func makeDeck() -> [DaifugoCard] {
        var cards: [DaifugoCard] = []
        var id = 0
        for suit in DaifugoSuit.allCases {
            for rank in 1...13 {
                cards.append(DaifugoCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        cards.append(DaifugoCard(id: id, suit: nil, rank: DaifugoRules.jokerRank))
        cards.append(DaifugoCard(id: id + 1, suit: nil, rank: DaifugoRules.jokerRank))
        return cards
    }
}
