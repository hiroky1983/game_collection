import Foundation
import CoreEngine

/// スピードのスート。ジョーカーは使わない（52 枚を赤 26 枚・黒 26 枚に分けて 1 人ずつ持つ）。
public enum SpeedSuit: Int, CaseIterable, Codable, Sendable, Hashable {
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

/// スピードの 1 枚。`rank` は A=1 / 2〜10 / J=11 / Q=12 / K=13。
///
/// 強さの概念は無く、台札との「1 つ違い」（`SpeedRules.isAdjacent`）だけを見る。
public struct SpeedCard: Identifiable, Codable, Sendable, Equatable, Hashable {
    public let id: Int              // 0–51
    public let suit: SpeedSuit
    public let rank: Int

    public init(id: Int, suit: SpeedSuit, rank: Int) {
        self.id = id
        self.suit = suit
        self.rank = rank
    }

    /// トランプ共通基盤（#397）へ渡す面の内容。
    public var figure: PlayingCardFigure { .pip(suit: suit.playing, rank: rank) }

    /// ログ・デバッグ用の短い表記（例: "♥5"）。
    public var label: String { figure.label }
}

public extension SpeedCard {
    /// 52 枚の山（未シャッフル）。id はスート順 × ランク順で 0 から振る。
    static func makeDeck() -> [SpeedCard] {
        var cards: [SpeedCard] = []
        var id = 0
        for suit in SpeedSuit.allCases {
            for rank in 1...13 {
                cards.append(SpeedCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        return cards
    }

    /// 赤（♥♦）の 26 枚。あなたが使う。
    static func redHalf() -> [SpeedCard] { makeDeck().filter { $0.suit.isRed } }

    /// 黒（♠♣）の 26 枚。CPU が使う。
    static func blackHalf() -> [SpeedCard] { makeDeck().filter { !$0.suit.isRed } }
}
