import Foundation
import Core

/// VoiceOver の読み上げ文（Issue #1884: 自分の手札・場の札・各人の得点が読める）。
/// 純関数にして View を組まずにテストできるようにする（大富豪 #188・いろリレーと同じ形）。
public enum HeartsAccessibility {
    /// 席の呼び名（0 = あなた、1〜3 = CPU1〜3）。
    public static func playerName(_ index: Int) -> String {
        index == HeartsRules.humanIndex ? tr("あなた") : "CPU\(index)"
    }

    /// 札 1 枚の呼び名（例: 「スペードのQ」）。記号のままだと読み上げが端末設定に左右されるので文字にする。
    public static func cardName(_ card: HeartsCard) -> String {
        card.figure.spokenLabel
    }

    /// 手札 1 枚の読み上げ文。点・選択中・受け取った札・出せる / 出せないを文字で足す。
    public static func handCardLabel(
        _ card: HeartsCard, isSelected: Bool, isReceived: Bool = false, hint: HeartsCardHint = .none
    ) -> String {
        var parts = [cardName(card)]
        if card.points > 0 { parts.append(tr("%lld点", card.points)) }
        if isReceived { parts.append(tr("受け取った札")) }
        if isSelected { parts.append(tr("選択中")) }
        switch hint {
        case .none:       break
        case .playable:   parts.append(tr("出せます"))
        case .unplayable: parts.append(tr("いまは出せません"))
        case .recommendedPass: parts.append(tr("渡すのがおすすめ"))
        }
        return parts.joined(separator: tr("、"))
    }

    /// 渡す場面のヒントボタンの読み上げ文。使い切ったあとは広告が要ることまで読む。
    public static func passHintLabel(remaining: Int, needsAd: Bool) -> String {
        if needsAd { return tr("ヒント、無料の回数は使い切りました。広告を見ると1回追加") }
        return remaining > 0 ? tr("ヒント、残り%lld回", remaining) : tr("ヒント、残りなし")
    }

    /// 場の読み上げ文。出た順に「誰が何を出したか」と、いま取りそうな人。
    public static func trickLabel(_ trick: [HeartsPlay]) -> String {
        guard !trick.isEmpty else { return tr("場に札はありません") }
        let plays = trick.map { tr("%1$@が%2$@", playerName($0.player), cardName($0.card)) }
            .joined(separator: tr("、"))
        guard let winner = HeartsRules.trickWinner(trick) else { return plays }
        let key = trick.count == HeartsRules.playerCount ? tr("%@が取ります", playerName(winner)) : tr("いまは%@がいちばん強い", playerName(winner))
        return tr("場の札、%1$@。%2$@", plays, key)
    }

    /// 1 人ぶんの得点の読み上げ文（例: 「CPU1、この手3点、合計12点」）。
    public static func scoreLabel(name: String, handPoints: Int, total: Int) -> String {
        tr("%1$@、この手%2$lld点、合計%3$lld点", name, handPoints, total)
    }
}
