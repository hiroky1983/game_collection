import SwiftUI

/// ポーカーの演出の長さと形（#206）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// 将棋（`ShogiMotion`）・オセロ（`OthelloFlip`）と同じ方針で、長さは秒の定数として持ち
/// `Animation` はそこから組む。`Animation` からは長さを読み出せないため、定数を経由しないと
/// 「ポットの数値変化はショーダウンより短い」のような**長さの大小関係をテストで固定できない**。
///
/// Reduce Motion への追従は `gameAnimation(_:value:)` 側が持つ。ON のときは補間が起きず、
/// 反転の進捗は常に 1（= 表を向いた状態）になるだけで、公開そのものは従来どおり即時に反映される。
enum PokerMotion {

    /// CPU の手札 1 枚が裏から表へ返りきるまでの長さ（秒）。
    ///
    /// 短すぎると山場（ショーダウン）が目に留まらず、長いと「次のゲーム」までの待ちが伸びる。
    /// 手札の選択（`handSelectionResponse`）より気持ち長く取り、山場のほうが濃く見えるようにする。
    static let showdownFlipDuration: TimeInterval = 0.3

    /// 隣のカードが返り始めるまでの遅れ（秒）。左から順に返して 5 枚が読めるようにする。
    static let showdownStagger: TimeInterval = 0.07

    /// 5 枚すべてが返り終わるまでの長さ（秒）。
    static var showdownTotalDuration: TimeInterval {
        showdownFlipDuration + showdownStagger * Double(cardsPerHand - 1)
    }

    /// 1 人分の手札の枚数（5 カードドロー）。段差の総量を求めるのに使う。
    static let cardsPerHand = 5

    /// ポットのチップ枚数が入れ替わるときの長さ（秒）。
    /// 数字が転がるのが見えれば十分なので、ショーダウン全体より短く取る。
    static let potChangeDuration: TimeInterval = 0.24

    /// 交換するカードを選んだときの跳ね（既存の演出。トーンを揃える基準）。
    static let handSelectionResponse: TimeInterval = 0.25

    /// 交換するカードの選択。
    static let handSelection: Animation = .spring(response: handSelectionResponse)

    /// ポットの数値の入れ替え。増減がどちらの向きかは `.contentTransition(.numericText(value:))` が持つ。
    static let potChange: Animation = .easeInOut(duration: potChangeDuration)

    /// CPU の手札 `index` 枚目（0 始まり）の反転。左から順に段差をつける。
    static func showdownFlip(index: Int) -> Animation {
        .easeInOut(duration: showdownFlipDuration)
            .delay(Double(max(index, 0)) * showdownStagger)
    }

    /// 反転の進捗（0 = 裏 / 1 = 表）から、カードを表として描くかどうか。
    ///
    /// 真横を向く 0.5 で入れ替えることで、裏面が縮んで消えた瞬間に表面が現れる。
    static func showsFace(progress: Double) -> Bool { progress >= 0.5 }

    /// 反転の進捗から、カードの Y 軸まわりの回転角（度）。
    static func flipDegrees(progress: Double) -> Double {
        min(max(progress, 0), 1) * 180
    }
}
