import Foundation

/// 札の VoiceOver 読み上げ文。面は色と記号だけで 1 枚を表しているので、文字にして補う。
/// 純関数にして View を組まずにテストできるようにする（大富豪 #188 と同じ形）。
public enum ColorRelayAccessibility {
    /// 種類の読み。
    public static func kindName(_ kind: RelayKind) -> String {
        switch kind {
        case .number(let n):  return "\(n)"
        case .skip:           return "とばし"
        case .reverse:        return "ぎゃく"
        case .drawTwo:        return "プラス2"
        case .wild:           return "いろがえ"
        case .wildDrawFour:   return "いろがえプラス4"
        }
    }

    /// 札 1 枚の呼び名（例: "あかの5"、"いろがえ"）。
    public static func cardName(_ card: RelayCard) -> String {
        guard let color = card.color else { return kindName(card.kind) }
        return "\(color.name)の\(kindName(card.kind))"
    }

    /// 手札 1 枚の読み上げ文。選択中・出せる / 出せないを文字で足す。
    public static func handCardLabel(
        _ card: RelayCard, isSelected: Bool, hint: RelayCardHint = .none
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

    /// 場の読み上げ文（いまの札と、いまの色）。
    public static func fieldLabel(top: RelayCard?, activeColor: RelayColor, drawPileCount: Int) -> String {
        guard let top else { return "場に札はありません" }
        let colorText = top.isWild ? "。いまの色は\(activeColor.name)" : ""
        return "場の札、\(cardName(top))\(colorText)。山は残り\(drawPileCount)枚"
    }
}
