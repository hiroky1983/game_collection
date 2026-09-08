import CoreGraphics
import Foundation
import SwiftUI
import Core

/// フリーセルの演出の長さと形（#492）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// ソリティア（`SolitaireMotion`）と同じ方針で、長さは秒の定数として持ち `Animation` はそこから組む。
/// `Animation` からは長さを読み出せないため、定数を経由しないと**長さの大小関係をテストで固定できない**。
///
/// **めくりの演出は持たない**。フリーセルは配札の時点で 52 枚すべてが表向きで、
/// 「裏から表へ返る」瞬間がゲーム中に一度も無い（クロンダイクの `flip` に相当するものが不要）。
///
/// Reduce Motion への追従は `gameAnimation(_:value:)` 側が持つ。
enum FreeCellMotion {

    // MARK: - 配札

    /// 場札に配られる枚数（52 枚すべて）。
    static let dealtCardCount = 52

    /// 札 1 枚が飛んで収まるまでの長さ（秒）。
    static let dealCardDuration: TimeInterval = 0.2

    /// 次の 1 枚が飛び始めるまでの遅れ（秒）。
    ///
    /// 52 枚あるので、ソリティア（28 枚で 0.022）と同じ段差では配り終わるまで 1.3 秒を超える。
    /// 「順に配られている」と読める最小限まで詰める。
    static let dealStagger: TimeInterval = 0.012

    /// 52 枚すべてが置き終わるまでの長さ（秒）。
    static var dealTotalDuration: TimeInterval {
        dealCardDuration + dealStagger * Double(dealtCardCount - 1)
    }

    /// 配られる順（0 始まり）。
    ///
    /// `FreeCellDealer.deal` が**8 列へ 1 枚ずつ順に**配るので、演出もその順に揃える
    /// （クロンダイクが列ごとにまとめて配るのとはここが違う）。
    static func dealOrder(pile: Int, depth: Int) -> Int {
        max(0, depth) * FreeCellBoard.pileCount + max(0, pile)
    }

    /// `pile` 列の `depth` 枚目が飛び始めるまでの遅れ（秒）。
    static func dealDelay(pile: Int, depth: Int) -> TimeInterval {
        dealStagger * Double(dealOrder(pile: pile, depth: depth))
    }

    /// `pile` 列の `depth` 枚目が置かれる動き。
    static func dealAppear(pile: Int, depth: Int) -> Animation {
        .easeOut(duration: dealCardDuration).delay(dealDelay(pile: pile, depth: depth))
    }

    /// 上段（フリーセル・組札）と場札の間隔（pt）。View の `VStack(spacing:)` と同じ値を持つ。
    static let topRowSpacing: CGFloat = 12

    /// 配られる前の位置（置かれる場所から見た配り元のずれ）。
    ///
    /// 配り元は上段のいちばん左（フリーセルの1つめ）に置く。`restY` は列の上端から測った
    /// その札の落ち着き先。
    static func dealStartOffset(pile: Int, restY: CGFloat, metrics: PlayingCardMetrics) -> CGSize {
        CGSize(
            width: -CGFloat(max(0, pile)) * (metrics.width + FreeCellMetrics.columnGap),
            height: -(max(0, restY) + metrics.height + topRowSpacing)
        )
    }

    // MARK: - 移動

    /// 札が行き先へ滑るまでの長さ（秒）。
    ///
    /// 1 手ごとに何度も起きる日常の動きなので、配りの 1 枚より短く取る。
    static let moveDuration: TimeInterval = 0.18

    /// 盤面の移動（場札 ↔ 場札・セル・組札へ送る・選択の強調）。
    static let move: Animation = .easeOut(duration: moveDuration)
}
