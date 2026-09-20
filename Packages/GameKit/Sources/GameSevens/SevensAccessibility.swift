import Foundation

/// カード・場の VoiceOver 読み上げ文（#1198）。
///
/// `SevensCardView` はランク文字とスート記号（♠♥♦♣）だけで1枚を表しており、
/// 記号は読み上げても意味が伝わらない。読み上げ文はここに集約して純関数にし、
/// View を組まずにテストできるようにする。
public enum SevensAccessibility {
    private static let suitNames = ["スペード", "ハート", "ダイヤ", "クラブ"]

    public static func suitName(_ suit: SevensSuit) -> String { suitNames[suit.rawValue] }

    /// ランクの読み（A / J / Q / K は記号のままだと読みが安定しない）。
    public static func rankName(_ card: SevensCard) -> String {
        switch card.rank {
        case 1:  return "エース"
        case 11: return "ジャック"
        case 12: return "クイーン"
        case 13: return "キング"
        default: return "\(card.rank)"
        }
    }

    /// カード1枚の呼び名（例: "ハートの7"）。
    public static func cardName(_ card: SevensCard) -> String {
        "\(suitName(card.suit))の\(rankName(card))"
    }

    /// 手札1枚の読み上げ文。出せるかどうかは見た目では枠色と明度でしか表していない。
    public static func handCardLabel(_ card: SevensCard, canPlay: Bool) -> String {
        canPlay ? "\(cardName(card))、出せます" : "\(cardName(card))、いまは出せません"
    }

    /// スート1行の場の読み上げ文（例: "ハート、7から9まで"）。未着手なら「まだ出ていません」。
    public static func suitRowLabel(_ suit: SevensSuit, range: SevensSuitRange) -> String {
        guard let low = range.low, let high = range.high else {
            return "\(suitName(suit))、まだ出ていません"
        }
        if low == high { return "\(suitName(suit))、\(low)だけ" }
        return "\(suitName(suit))、\(low)から\(high)まで"
    }
}
