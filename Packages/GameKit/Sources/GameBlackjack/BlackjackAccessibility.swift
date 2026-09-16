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
        faceUp ? card.figure.spokenLabel : "伏せたカード"
    }

    /// 伏せ札があるあいだのディーラーの点数（例: "見えているカードの合計7、1枚は伏せています"）。
    ///
    /// 画面の「7 + ?」は記号のままだと「プラス、クエスチョン」と読まれて意味が伝わらない。
    public static func dealerPartialValueLabel(visibleValue: Int) -> String {
        "見えているカードの合計\(visibleValue)、1枚は伏せています"
    }
}
