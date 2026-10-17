import Foundation
import Core

/// 札の VoiceOver 読み上げ文。面は色と記号だけで 1 枚を表しているので、文字にして補う。
/// 純関数にして View を組まずにテストできるようにする（大富豪 #188 と同じ形）。
public enum ColorRelayAccessibility {
    /// 種類の読み。
    public static func kindName(_ kind: RelayKind) -> String {
        switch kind {
        case .number(let n):  return "\(n)"
        case .skip:           return tr("とばし")
        case .reverse:        return tr("ぎゃく")
        case .drawTwo:        return tr("プラス2")
        case .wild:           return tr("いろがえ")
        case .wildDrawFour:   return tr("いろがえプラス4")
        }
    }

    /// 札 1 枚の呼び名（例: "あかの5"、"いろがえ"）。
    public static func cardName(_ card: RelayCard) -> String {
        guard let color = card.color else { return kindName(card.kind) }
        return tr("%1$@の%2$@", color.name, kindName(card.kind))
    }

    /// 手札 1 枚の読み上げ文。選択中・出せる / 出せないを文字で足す。
    public static func handCardLabel(
        _ card: RelayCard, isSelected: Bool, hint: RelayCardHint = .none
    ) -> String {
        var parts = [cardName(card)]
        if isSelected { parts.append(tr("選択中")) }
        switch hint {
        case .none:       break
        case .playable:   parts.append(tr("出せます"))
        case .unplayable: parts.append(tr("いまは出せません"))
        }
        return parts.joined(separator: tr("、"))
    }

    /// 場の読み上げ文（いまの札と、いまの色）。
    public static func fieldLabel(top: RelayCard?, activeColor: RelayColor, drawPileCount: Int) -> String {
        guard let top else { return tr("場に札はありません") }
        if top.isWild {
            return tr("場の札、%1$@。いまの色は%2$@。山は残り%3$lld枚", cardName(top), activeColor.name, drawPileCount)
        }
        return tr("場の札、%1$@。山は残り%2$lld枚", cardName(top), drawPileCount)
    }
}
