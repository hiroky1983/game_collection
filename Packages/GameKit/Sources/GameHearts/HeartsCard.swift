import Foundation

/// ハーツのスート。並び（`rawValue`）は手札を並べる順（クラブ → ダイヤ → スペード → ハート）。
/// ハートを右端に寄せると、点になる札がどれだけあるかが手札の端で一目で分かる。
public enum HeartsSuit: Int, Codable, CaseIterable, Sendable, Comparable {
    case club = 0, diamond, spade, heart

    public static func < (lhs: HeartsSuit, rhs: HeartsSuit) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// ハーツの札 1 枚。`rank` は **2〜14（A = 14 がいちばん強い）**。
///
/// トランプの描画は Core の共通基盤（`PlayingCardFace`・#397）に写して描く。ハーツは A を最強に扱うので、
/// 大富豪・ポーカーと同じくゲーム側で専用の型を持ち、描画の値（A = 1）へは `figure` で変換する。
public struct HeartsCard: Codable, Hashable, Identifiable, Sendable {
    public let suit: HeartsSuit
    public let rank: Int

    public init(_ suit: HeartsSuit, _ rank: Int) {
        self.suit = suit
        self.rank = rank
    }

    /// 0〜51 の通し番号。保存・選択・同じ札の判定に使う。
    public var id: Int { suit.rawValue * 13 + (rank - 2) }

    /// この札を取ったときの点。ハートは 1 点、スペードのクイーンは 13 点、ほかは 0 点。
    public var points: Int {
        if suit == .heart { return 1 }
        if isQueenOfSpades { return 13 }
        return 0
    }

    public var isQueenOfSpades: Bool { suit == .spade && rank == 12 }

    /// 最初に出す札（クラブの 2）。
    public static let twoOfClubs = HeartsCard(.club, 2)
    public static let queenOfSpades = HeartsCard(.spade, 12)

    /// 手札を並べる順（スート → 数字）。
    public var sortKey: Int { id }

    /// 52 枚ひと組（並びは通し番号の順）。
    public static func makeDeck() -> [HeartsCard] {
        HeartsSuit.allCases.flatMap { suit in (2...14).map { HeartsCard(suit, $0) } }
    }
}

/// 場に出された札 1 枚（誰が出したか付き）。
public struct HeartsPlay: Codable, Equatable, Sendable {
    public let player: Int
    public let card: HeartsCard

    public init(player: Int, card: HeartsCard) {
        self.player = player
        self.card = card
    }
}
