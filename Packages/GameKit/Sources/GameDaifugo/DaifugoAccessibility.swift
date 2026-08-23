import Foundation

/// カードの VoiceOver 読み上げ文（#188）。
///
/// `DaifugoCardView` はランク文字とスート記号（♠♥♦♣）だけで 1 枚を表しており、
/// 記号は読み上げても意味が伝わらない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum DaifugoAccessibility {
    private static let suitNames = ["スペード", "ハート", "ダイヤ", "クラブ"]

    /// スートの読み（ジョーカーは nil）。
    public static func suitName(_ suit: DaifugoSuit?) -> String? {
        suit.map { suitNames[$0.rawValue] }
    }

    /// ランクの読み（A / J / Q / K は記号のままだと読みが安定しない）。
    public static func rankName(_ card: DaifugoCard) -> String {
        switch card.rank {
        case DaifugoRules.jokerRank: return "ジョーカー"
        case 1:  return "エース"
        case 11: return "ジャック"
        case 12: return "クイーン"
        case 13: return "キング"
        default: return "\(card.rank)"
        }
    }

    /// カード 1 枚の呼び名（例: "ハートの7"）。
    public static func cardName(_ card: DaifugoCard) -> String {
        guard let suit = suitName(card.suit) else { return rankName(card) }
        return "\(suit)の\(rankName(card))"
    }

    /// 手札 1 枚の読み上げ文。選択中かどうかは見た目では浮き上がりと枠色でしか分からない。
    /// ヒント表示（#190）も枠色と明度でしか表していないので、状態を文字にして補う。
    public static func handCardLabel(
        _ card: DaifugoCard,
        isSelected: Bool,
        hint: DaifugoCardHint = .none
    ) -> String {
        var parts = [cardName(card)]
        if isSelected { parts.append("選択中") }
        switch hint {
        case .none:       break
        case .playable:   parts.append("出せます")
        case .unplayable: parts.append("いまは出せません")
        }
        return parts.joined(separator: "、")
    }

    /// 場に出ている組の読み上げ文。空なら「場は流れています」。
    ///
    /// 出し手（`ownerName`）は画面ではバッジで示しているだけなので、読み上げにも足す（#193）。
    public static func fieldLabel(_ cards: [DaifugoCard], ownerName: String? = nil) -> String {
        guard !cards.isEmpty else { return "場は流れています" }
        let cardsText = "場のカード、" + cards.map(cardName).joined(separator: "、")
        guard let ownerName else { return cardsText }
        return "\(cardsText)。\(ownerName)が出しました"
    }
}
