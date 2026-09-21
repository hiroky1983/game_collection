import Foundation
import Core

/// カードと点数の VoiceOver 読み上げ文（ブラックジャック #1044・ポーカー #710 と同じ形）。
///
/// 読み上げ文はここに集約して純関数にし、View を組まずにテストできるようにする。
public enum BaccaratAccessibility {

    /// 札 1 枚の読み上げ文（例: "ハートの7"）。バカラに伏せ札は無く、配った時点で全部表になる。
    public static func cardLabel(card: BaccaratCard) -> String {
        card.figure.spokenLabel
    }

    /// 手の合計の読み上げ文（例: "プレイヤーの合計5"）。
    ///
    /// 画面は数字だけを大きく出すが、それだけだと何の数字か伝わらない。
    public static func totalLabel(side: BaccaratBet, total: Int) -> String {
        "\(side.label)の合計\(total)"
    }

    /// 賭け先ボタンの読み上げ文（例: "バンカーに賭ける、配当0.95倍"）。
    public static func betChoiceLabel(_ bet: BaccaratBet) -> String {
        "\(bet.label)に賭ける、配当\(bet.payoutLabel)"
    }
}
