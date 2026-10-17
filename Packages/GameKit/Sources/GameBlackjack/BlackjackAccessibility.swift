import Foundation
import Core

/// カードと点数の VoiceOver 読み上げ文（#1044。大富豪 #188・ポーカー #710 と同じ形）。
///
/// 表の札は共通部品 `PlayingCardFace` が `spokenLabel` を読ませるが、**裏の札**は
/// `PlayingCardBack` のスート印（SF Symbols）がそのまま読まれ、伏せたディーラーの札が
/// 「スペード」のように中身があるかのように聞こえてしまう。表裏どちらも 1 枚 1 要素にまとめ、
/// 読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum BlackjackAccessibility {

    /// 札 1 枚の読み上げ文（例: "ハートの7" / "伏せたカード"）。
    ///
    /// 伏せているあいだは中身を読まない（見た目で隠している情報を音声で漏らさない）。
    public static func cardLabel(card: BlackjackCard, faceUp: Bool) -> String {
        faceUp ? card.figure.spokenLabel : tr("伏せたカード")
    }

    /// 伏せ札があるあいだのディーラーの点数（例: "見えているカードの合計7、1枚は伏せています"）。
    ///
    /// 画面の「7 + ?」は記号のままだと「プラス、クエスチョン」と読まれて意味が伝わらない。
    public static func dealerPartialValueLabel(visibleValue: Int) -> String {
        tr("見えているカードの合計%lld、1枚は伏せています", visibleValue)
    }

    /// 手札の合計の読み上げ文（例: "あなたの合計17" / "ディーラーの合計22、バスト"）。
    ///
    /// 画面の合計は数字だけで、誰の手かは隣のラベルとの位置関係、バストは赤色でしか伝わらない（#2162）。
    /// 誰の・何点・バストかを 1 つの文にまとめ、ラベルの要素は読ませない。
    public static func totalLabel(owner: String, value: Int) -> String {
        let base = tr("%@の合計%lld", owner, value)
        return value > 21 ? tr("%@、バスト", base) : base
    }

    /// 勝敗が決まったときの読み上げ文（#1574）。画面の勝敗バッジと同じ言葉で読ませる。
    ///
    /// - Parameter isSplit: スプリットしたラウンドか。手ごとに勝敗が割れうるので、
    ///   バッジに出るのは収支のまとめであることを添える。
    public static func outcomeAnnouncement(outcome: BlackjackOutcome, isSplit: Bool = false) -> String {
        let result: String
        switch outcome {
        case .playerBlackjack: result = tr("ブラックジャック！勝ちです")
        case .win:             result = tr("勝ちです")
        case .push:            result = tr("引き分けです")
        case .lose:            result = tr("負けです")
        case .bust:            result = tr("バストして負けです")
        }
        return isSplit ? tr("全体の結果は、%@", result) : result
    }
}
