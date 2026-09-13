import CoreGraphics
import Foundation
import SwiftUI
import Core

/// スパイダーの演出の長さと形（#717）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// フリーセル（`FreeCellMotion`）と同じ方針で、長さは秒の定数として持ち `Animation` はそこから組む。
/// Reduce Motion への追従は `gameAnimation(_:value:)` 側が持つ。
enum SpiderMotion {

    // MARK: - 配札

    /// 最初に場札へ配られる枚数（54 枚）。
    static let dealtCardCount = 54

    /// 札 1 枚が飛んで収まるまでの長さ（秒）。
    static let dealCardDuration: TimeInterval = 0.2

    /// 次の 1 枚が飛び始めるまでの遅れ（秒）。54 枚あるのでフリーセル（52 枚）と同じ段差。
    static let dealStagger: TimeInterval = 0.012

    /// 54 枚すべてが置き終わるまでの長さ（秒）。
    static var dealTotalDuration: TimeInterval {
        dealCardDuration + dealStagger * Double(dealtCardCount - 1)
    }

    /// 配られる順（0 始まり）。`SpiderDealer.deal` が**10 列へ 1 枚ずつ順に**配るので、演出もその順。
    static func dealOrder(pile: Int, depth: Int) -> Int {
        max(0, depth) * SpiderBoard.pileCount + max(0, pile)
    }

    static func dealDelay(pile: Int, depth: Int) -> TimeInterval {
        dealStagger * Double(dealOrder(pile: pile, depth: depth))
    }

    static func dealAppear(pile: Int, depth: Int) -> Animation {
        .easeOut(duration: dealCardDuration).delay(dealDelay(pile: pile, depth: depth))
    }

    /// 山札から配る 10 枚の遅れ。列の順に飛ぶ。
    static func stockDealAppear(pile: Int) -> Animation {
        .easeOut(duration: dealCardDuration).delay(dealStagger * 2 * Double(max(0, pile)))
    }

    /// 上段（山札・完成した組）と場札の間隔（pt）。View の `VStack(spacing:)` と同じ値を持つ。
    static let topRowSpacing: CGFloat = 12

    /// 配られる前の位置（置かれる場所から見た配り元のずれ）。配り元は上段のいちばん左（山札）。
    static func dealStartOffset(pile: Int, restY: CGFloat, metrics: PlayingCardMetrics) -> CGSize {
        CGSize(
            width: -CGFloat(max(0, pile)) * (metrics.width + SpiderMetrics.columnGap),
            height: -(max(0, restY) + metrics.height + topRowSpacing)
        )
    }

    // MARK: - 移動

    /// 札が行き先へ滑るまでの長さ（秒）。
    static let moveDuration: TimeInterval = 0.18

    /// 盤面の移動（場札 ↔ 場札・並びの取り除き・選択の強調）。
    static let move: Animation = .easeOut(duration: moveDuration)
}
