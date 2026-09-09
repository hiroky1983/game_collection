import CoreGraphics
import Foundation
import SwiftUI
import Core

/// ソリティアの演出の長さと形（#421）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// ブラックジャック（`BlackjackMotion`）・ポーカー（`PokerMotion`）・将棋（`ShogiMotion`）と同じ方針で、
/// 長さは秒の定数として持ち `Animation` はそこから組む。`Animation` からは長さを読み出せないため、
/// 定数を経由しないと「移動は配りの 1 枚より短い」のような**長さの大小関係をテストで固定できない**。
///
/// Reduce Motion への追従は `gameAnimation(_:value:)` / `withGameAnimation(_:_:)` 側が持つ。
/// ON のときは補間が起きず、札は遅れなく置かれ、伏せ札は即座に表になり、移動は瞬時に反映される。
/// 配る・返す・動かすという**盤面の変化そのものは従来どおり必ず起きる**。
enum SolitaireMotion {

    // MARK: - 配札

    /// 場札に配られる枚数（7 列に 1+2+…+7）。段差の総量を求めるのに使う。
    static let dealtCardCount = SolitaireBoard.pileCount * (SolitaireBoard.pileCount + 1) / 2

    /// 札 1 枚が山札から場札へ飛んで収まるまでの長さ（秒）。
    static let dealCardDuration: TimeInterval = 0.22

    /// 次の 1 枚が飛び始めるまでの遅れ（秒）。
    ///
    /// 28 枚あるので、ブラックジャック（4 枚で 0.09）と同じ段差では配り終わるまで 2 秒を超える。
    /// 「順に配られている」と読める最小限まで詰める。
    static let dealStagger: TimeInterval = 0.022

    /// 28 枚すべてが置き終わるまでの長さ（秒）。
    static var dealTotalDuration: TimeInterval {
        dealCardDuration + dealStagger * Double(dealtCardCount - 1)
    }

    /// 配られる順（0 始まり）。
    ///
    /// `SolitaireDealer.deal` が**列ごとにまとめて**配る（1 列目に 1 枚 → 2 列目に 2 枚 → …）ので、
    /// 演出もその順に揃える。`depth` は列の下から数えた位置で、伏せ札が先・表向きの 1 枚が最後に来る。
    static func dealOrder(pile: Int, depth: Int) -> Int {
        let pile = max(0, pile)
        return pile * (pile + 1) / 2 + max(0, depth)
    }

    /// `pile` 列の `depth` 枚目が飛び始めるまでの遅れ（秒）。
    static func dealDelay(pile: Int, depth: Int) -> TimeInterval {
        dealStagger * Double(dealOrder(pile: pile, depth: depth))
    }

    /// `pile` 列の `depth` 枚目が置かれる動き。
    static func dealAppear(pile: Int, depth: Int) -> Animation {
        .easeOut(duration: dealCardDuration).delay(dealDelay(pile: pile, depth: depth))
    }

    /// 山札の行と場札の間隔（pt）。View の `VStack(spacing:)` と同じ値を持つ。
    static let topRowSpacing: CGFloat = 12

    /// 配られる前の位置（置かれる場所から見た山札のずれ）。
    ///
    /// 山札は上の行のいちばん左にあるので、**左上へ戻すぶんだけ**ずらした位置から飛ばす。
    /// `restY` は列の上端から測ったその札の落ち着き先。
    /// 札が画面幅の上限（`SolitaireMetrics.maxCardWidth`）で頭打ちになる iPad では場札が
    /// 中央寄せになり山札より少し右から始まるが、飛んでくる向きは変わらないので許容する。
    static func dealStartOffset(pile: Int, restY: CGFloat, metrics: PlayingCardMetrics) -> CGSize {
        CGSize(
            width: -CGFloat(max(0, pile)) * (metrics.width + SolitaireMetrics.columnGap),
            height: -(max(0, restY) + metrics.height + topRowSpacing)
        )
    }

    // MARK: - めくり

    /// 札が裏から表へ返りきるまでの長さ（秒）。
    ///
    /// 山札をめくる・伏せ札が出るのはこのゲームで唯一「新しい情報が出る」瞬間なので、
    /// 配りの 1 枚（`dealCardDuration`）より長く取り、そこが山場に見えるようにする。
    static let flipDuration: TimeInterval = 0.3

    /// 裏から表への反転。
    static let flip: Animation = .easeInOut(duration: flipDuration)

    /// 反転の進捗（0 = 裏 / 1 = 表）から、札を表として描くかどうか。
    ///
    /// 真横を向く 0.5 で入れ替えることで、裏面が縮んで消えた瞬間に表面が現れる。
    static func showsFace(progress: Double) -> Bool { progress >= 0.5 }

    /// 反転の進捗から、札の Y 軸まわりの回転角（度）。
    static func flipDegrees(progress: Double) -> Double {
        min(max(progress, 0), 1) * 180
    }

    // MARK: - 移動

    /// 札が行き先へ滑るまでの長さ（秒）。
    ///
    /// 1 手ごとに何度も起きる日常の動きなので、めくり・配りより短く取る。
    static let moveDuration: TimeInterval = 0.2

    /// 盤面の移動（場札 ↔ 場札・組札へ送る・選択の強調）。
    static let move: Animation = .easeOut(duration: moveDuration)
}
