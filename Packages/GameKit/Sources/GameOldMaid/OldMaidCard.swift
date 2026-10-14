import Foundation
import CoreEngine

/// ババ抜きのスート。ジョーカーはスートを持たない（`OldMaidCard.suit == nil`）。
public enum OldMaidSuit: Int, CaseIterable, Codable, Sendable, Hashable {
    case spades, hearts, diamonds, clubs

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

/// ババ抜きの 1 枚。52 枚の数字札 + ジョーカー 1 枚の 53 枚で遊ぶ。
///
/// 強さの概念は無く、同じ数字（`rank`）の 2 枚がそろえば捨てられることだけを見る。
/// `rank` は A=1 / 2〜10 / J=11 / Q=12 / K=13。ジョーカーは 0 で、どの札ともペアにならない。
public struct OldMaidCard: Identifiable, Codable, Sendable, Hashable {
    /// 0〜51 が数字札（スート順 × ランク順）、52 がジョーカー。
    public let id: Int
    public let suit: OldMaidSuit?
    public let rank: Int

    public init(id: Int, suit: OldMaidSuit?, rank: Int) {
        self.id = id
        self.suit = suit
        self.rank = rank
    }

    /// ジョーカーの ID。
    public static let jokerID = 52

    /// ジョーカー（ババ）。
    public static let joker = OldMaidCard(id: jokerID, suit: nil, rank: 0)

    public var isJoker: Bool { suit == nil }

    /// トランプ共通基盤（#397）へ渡す面の内容。ジョーカーは共通部品の図案（道化帽）で描く。
    public var figure: PlayingCardFigure {
        guard let suit else { return .joker }
        return .pip(suit: suit.playing, rank: rank)
    }

    /// ログ・デバッグ用の短い表記（例: "♥5"・"JOKER"）。
    public var label: String { figure.label }

    /// 手札を数字順に並べるときの鍵。ジョーカーは最後。
    public var sortKey: Int { isJoker ? 1_000 : rank * 4 + (suit?.rawValue ?? 0) }

    /// 53 枚の山（未シャッフル）。数字札の id はスート順 × ランク順で 0 から振り、最後にジョーカー。
    public static func makeDeck() -> [OldMaidCard] {
        var cards: [OldMaidCard] = []
        var id = 0
        for suit in OldMaidSuit.allCases {
            for rank in 1...13 {
                cards.append(OldMaidCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        cards.append(joker)
        return cards
    }
}
