import Foundation
import Core

/// ババ抜きの VoiceOver 読み上げ文。純関数にして View を組まずにテストできるようにする（大富豪 #188 と同じ形）。
public enum OldMaidAccessibility {
    /// 札 1 枚の呼び名（例: "ハートの5"・"ジョーカー"）。共通基盤の読みをそのまま使う。
    public static func cardName(_ card: OldMaidCard) -> String {
        card.figure.spokenLabel
    }

    /// 顔の読み。
    public static func faceName(_ face: OldMaidFace) -> String {
        switch face {
        case .neutral: return tr("ふつうの顔")
        case .smile:   return tr("にやりとした顔")
        case .worried: return tr("ひやりとした顔")
        }
    }

    /// 相手の伏せた札 1 枚の読み上げ文（左から何枚目か・指をかけているか）。
    /// - Parameter revealedIsJoker: 広告で正体が見えている札なら、ジョーカーかどうか（#3251）。
    public static func targetCardLabel(position: Int, count: Int, isSelected: Bool, revealedIsJoker: Bool? = nil) -> String {
        var parts = [tr("伏せた札、左から%1$lld枚目（全%2$lld枚）", position + 1, count)]
        if isSelected { parts.append(tr("選択中")) }
        if let revealedIsJoker { parts.append(revealedIsJoker ? tr("ジョーカー") : tr("ジョーカーではない")) }
        return parts.joined(separator: tr("、"))
    }

    /// 手札 1 枚の読み上げ文（直前に引いた札なら添える）。
    public static func handCardLabel(_ card: OldMaidCard, isLastDrawn: Bool) -> String {
        isLastDrawn ? tr("%@、いま引いた札", cardName(card)) : cardName(card)
    }

    /// CPU が引いたときの読み上げ文（#3424）。
    /// あなたの札を引かれたときだけ札の名前まで読む（CPU 同士の伏せ札は、見えている人にも見えないので枚数だけ）。
    /// ペアができたときは捨てたペアの数字を添える。
    public static func cpuDrawAnnouncement(_ transfer: OldMaidTransfer, drawerAction: OldMaidAction) -> String {
        let drawer = playerName(transfer.to)
        var text = transfer.from == OldMaidGame.humanIndex
            ? tr("%1$@があなたの%2$@を引きました", drawer, cardName(transfer.card))
            : tr("%1$@が%2$@から1枚引きました", drawer, playerName(transfer.from))
        if transfer.paired {
            text += tr("。") + actionText(drawerAction)
        }
        return text
    }

    /// 席の呼び名（0 = あなた、1〜3 = CPU1〜3）。
    public static func playerName(_ index: Int) -> String {
        index == OldMaidGame.humanIndex ? tr("あなた") : "CPU\(index)"
    }

    /// 直近の動きの短い文（画面のバッジと読み上げで共用）。動きが無ければ空文字。
    public static func actionText(_ action: OldMaidAction) -> String {
        switch action {
        case .none:
            return ""
        case .dealtPairs(let count):
            return count == 0 ? tr("ペアなし") : tr("%lld組捨てた", count)
        case .drewPair(let rank):
            return tr("%@のペアを捨てた", PlayingCardFigure.pip(suit: .spade, rank: rank).rankLabel)
        case .drewKept:
            return tr("1枚引いた")
        }
    }
}
