import Foundation

/// スパイダーソリティアのスート（#717）。
///
/// トランプ共通基盤の `PlayingCardSuit`（Core）を写さず独自に持つのは、**盤・配札・ソルバーを
/// Core 非依存の純粋ロジックに保つため**（クロンダイクの `SolitaireCard` と同じ判断）。
/// 種の事前計算は `swiftc -O` で純ロジックのファイルだけを 1 バイナリにして回すので、
/// ここに SwiftUI を引き込むと計測も生成もできなくなる。描画へは `SpiderCard.figure`
/// （`SpiderCardFigure.swift`）で写す。`rawValue` は `PlayingCardSuit` と同じ並びにしてある。
public enum SpiderSuit: Int, CaseIterable, Sendable, Equatable, Hashable {
    case spade = 0, heart = 1, diamond = 2, club = 3

    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }

    public var isRed: Bool { self == .heart || self == .diamond }

    /// VoiceOver 用の読み。
    public var spokenName: String { ["スペード", "ハート", "ダイヤ", "クラブ"][rawValue] }
}

/// スパイダーソリティアで扱う 1 枚（#717）。
///
/// 2 組 104 枚を使うので**同じスート・同じランクの札が複数ある**（1 スートなら ♠ が 8 組）。
/// ルール上は区別しないが、画面の移動の補間（`matchedGeometryEffect`）は札ごとに同一性が要るため、
/// `id` は 104 枚の中で一意にする（未シャッフルの山での並び順）。
public struct SpiderCard: Identifiable, Equatable, Hashable, Sendable {
    /// 0〜103。同じスート・ランクでも組が違えば別の値になる。
    public let id: Int
    public let suit: SpiderSuit
    /// 1 = A 〜 13 = K。
    public let rank: Int

    public init(id: Int, suit: SpiderSuit, rank: Int) {
        self.id = id
        self.suit = suit
        self.rank = rank
    }

    public var isRed: Bool { suit.isRed }

    /// 面の中央に出す数字・絵札の文字。
    public var rankLabel: String {
        switch rank {
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    /// ログ・デバッグ用の短い表記（例: "♠A"）。
    public var label: String { "\(suit.symbol)\(rankLabel)" }
}

public extension SpiderCard {
    /// 104 枚の山札（未シャッフル）。
    ///
    /// スート数ごとに顔ぶれが変わる: 1 スートは ♠ ×8 組、2 スートは ♠♥ ×4 組、4 スートは 4 種 ×2 組。
    /// 並びは「組 → スート → ランク」で、`id` はこの並びの添字。
    static func makeDeck(suits: SpiderSuitCount) -> [SpiderCard] {
        var deck: [SpiderCard] = []
        deck.reserveCapacity(SpiderBoard.deckSize)
        for _ in 0..<suits.copiesPerSuit {
            for suit in suits.suits {
                for rank in 1...13 {
                    deck.append(SpiderCard(id: deck.count, suit: suit, rank: rank))
                }
            }
        }
        return deck
    }
}
