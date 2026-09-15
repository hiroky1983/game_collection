import Foundation

/// トランプのスートと面に描く内容（#397）。描画を持たない純粋な値なので、`PlayingCard.swift` から
/// CoreEngine へ切り出した（#834 Step 0）。寸法・インク・描画 View は Core の `PlayingCard.swift` に残る。

// MARK: - スート

/// トランプ4スート。描画専用なので `Codable` にはしない（保存はゲーム側のカード型が持つ）。
public enum PlayingCardSuit: Int, CaseIterable, Sendable, Equatable {
    case spade = 0, heart = 1, diamond = 2, club = 3

    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }

    public var isRed: Bool { self == .heart || self == .diamond }

    /// VoiceOver 用の読み（記号のままだと読み上げが端末設定に左右されるため文字で持つ）。
    public var spokenName: String { ["スペード", "ハート", "ダイヤ", "クラブ"][rawValue] }
}

// MARK: - 面に描くもの

/// カードの表に描く内容。実カード（スート + ランク）か、ジョーカーか。
///
/// `rank` は **1 = A 〜 13 = K** に正規化する。ポーカーのように A を 14 として扱うゲームは
/// 変換して渡す（強さの表現はゲーム側の関心で、面の表記とは別物）。
public enum PlayingCardFigure: Sendable, Equatable {
    case pip(suit: PlayingCardSuit, rank: Int)
    case joker

    /// 面の中央に出す数字・絵札の文字。
    public var rankLabel: String {
        switch self {
        case .joker: return "JOKER"
        case .pip(_, let rank):
            switch rank {
            case 1:  return "A"
            case 11: return "J"
            case 12: return "Q"
            case 13: return "K"
            default: return "\(rank)"
            }
        }
    }

    /// ログ・デバッグ用の短い表記（例: "♠A"）。
    public var label: String {
        switch self {
        case .joker: return "JOKER"
        case .pip(let suit, _): return "\(suit.symbol)\(rankLabel)"
        }
    }

    /// VoiceOver 用の読み上げ文（例: "スペードのA"）。
    public var spokenLabel: String {
        switch self {
        case .joker: return "ジョーカー"
        case .pip(let suit, _): return "\(suit.spokenName)の\(rankLabel)"
        }
    }
}
