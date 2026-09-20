import SwiftUI

/// バカラの演出の長さと形。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// ブラックジャック（`BlackjackMotion`・#209）と同じ方針で、長さは秒の定数として持ち
/// `Animation` はそこから組む。`Animation` からは長さを読み出せないため、定数を経由しないと
/// 「配りは勝敗の表示より先」のような**長さの大小関係をテストで固定できない**。
///
/// Reduce Motion への追従は `gameAnimation(_:value:)` / `withGameAnimation(_:_:)` 側が持つ。
enum BaccaratMotion {

    // MARK: - 配布

    /// 1 つの手に最初に配られる枚数。段差の総量を求めるのに使う。
    static let initialCardsPerHand = 2

    /// カード 1 枚が置かれるまでの長さ（秒）。
    static let dealCardDuration: TimeInterval = 0.22

    /// 次の 1 枚が置かれ始めるまでの遅れ（秒）。
    /// 「プレイヤー → バンカー → プレイヤー → バンカー」の順に置くので 4 枚ぶんの段差になる。
    static let dealStagger: TimeInterval = 0.09

    /// 最初の 4 枚すべてが置き終わるまでの長さ（秒）。
    static var dealTotalDuration: TimeInterval {
        dealCardDuration + dealStagger * Double(initialCardsPerHand * 2 - 1)
    }

    /// カードが置かれる前の位置（上に持ち上げた量・pt）。ここから手元へ落ちてくる。
    static let dealOffset: CGFloat = -26

    /// カードが置かれる前の大きさ（1 = 実寸）。遠くから来たように見せる。
    static let dealStartScale: CGFloat = 0.82

    /// `index` 枚目（0 始まり）が置かれ始めるまでの遅れ（秒）。
    ///
    /// 最初の 2 枚だけ段差をつけ、**引き足しの 3 枚目は遅らせない**
    /// （3 枚目は決着の直前なので、ここで待たせると結果だけが遅れて見える）。
    static func dealDelay(index: Int, isBanker: Bool) -> TimeInterval {
        guard index >= 0, index < initialCardsPerHand else { return 0 }
        return dealStagger * Double(index * 2 + (isBanker ? 1 : 0))
    }

    /// `index` 枚目（0 始まり）が置かれる動き。
    static func dealAppear(index: Int, isBanker: Bool) -> Animation {
        .easeOut(duration: dealCardDuration)
            .delay(dealDelay(index: index, isBanker: isBanker))
    }

    // MARK: - 勝敗バッジ

    /// 勝敗バッジが現れるまでの長さ（秒）。
    static let outcomeBadgeDuration: TimeInterval = 0.2

    /// 勝敗バッジの出現。**札が出そろってから**薄く現れる（答えを先に見せない）。
    static let outcomeBadge: Animation = .easeIn(duration: outcomeBadgeDuration)
        .delay(dealTotalDuration)
}
