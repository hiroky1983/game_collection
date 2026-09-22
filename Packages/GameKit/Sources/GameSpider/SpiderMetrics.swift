import CoreGraphics
import Core

/// 盤面の寸法（#717）。
///
/// スパイダーは**横に 10 列**が絶対条件で、画面幅から札の大きさが決まる。フリーセル（8 列）より
/// 札は小さくなる。数値を View に撒くと「iPhone SE で 10 列目がはみ出す」類の破綻が各所に散るため、
/// 寸法はここに集約して純粋関数にし、View を組まずに検証できるようにする。
public enum SpiderMetrics {
    /// 列と列の間隔。10 列なのでフリーセル（8 列・4pt）よりさらに詰める。
    public static let columnGap: CGFloat = 3
    /// トランプの縦横比（実物の 63×88 に近い値）。
    public static let aspectRatio: CGFloat = 1.4
    /// 札の幅の下限・上限。下限は iPhone SE（375pt。`Theme.pad` 16pt × 2 を引いた 343pt）でも
    /// 10 列が収まる値（(343 - 27) / 10 = 31.6）、上限は iPad で札だけが間延びしないようにするための頭打ち。
    public static let minCardWidth: CGFloat = 28
    public static let maxCardWidth: CGFloat = 60

    /// HIG の最小タップ標的。
    public static let minimumTapTarget: CGFloat = 44
    /// 拡大トグルの一辺（#604）。共通の `BoardToggleButton` と同じ値。
    public static let toggleButtonMinSide: CGFloat = BoardToggleMetrics.minSide
    /// 拡大モードで画面幅に収める列の数。10 列を 7 列ぶんの幅で描くので札は約 1.43 倍になり、
    /// **はみ出す 3 列は横スクロールで見る**。
    public static let zoomedVisibleColumns = 7

    /// 与えられた幅に 10 列を収める札の幅（`maxWidth` は iPad 用の上限差し替え口・#458）。
    public static func cardWidth(availableWidth: CGFloat, maxWidth: CGFloat = maxCardWidth) -> CGFloat {
        let raw = (availableWidth - columnGap * CGFloat(SpiderBoard.pileCount - 1))
            / CGFloat(SpiderBoard.pileCount)
        return min(maxWidth, max(minCardWidth, raw))
    }

    /// 拡大モードでの札の幅（#604 の横展開。等倍で入る幅も 44pt も下回らせない）。
    public static func zoomedCardWidth(availableWidth: CGFloat, maxWidth: CGFloat = maxCardWidth) -> CGFloat {
        let raw = (availableWidth - columnGap * CGFloat(zoomedVisibleColumns - 1))
            / CGFloat(zoomedVisibleColumns)
        return max(
            cardWidth(availableWidth: availableWidth, maxWidth: maxWidth),
            max(minimumTapTarget, min(maxWidth, raw))
        )
    }

    /// 10 列ぶんの盤面の幅（列と列の隙間を含む）。上段（山札・完成した組）を同じ幅に揃えて中央に置く。
    public static func boardWidth(cardWidth: CGFloat) -> CGFloat {
        cardWidth * CGFloat(SpiderBoard.pileCount)
            + columnGap * CGFloat(SpiderBoard.pileCount - 1)
    }

    public static func cardHeight(width: CGFloat) -> CGFloat { (width * aspectRatio).rounded() }

    /// 伏せ札を重ねる段差。伏せ札は枚数が見えれば十分なので詰める（クロンダイクと同じ比）。
    public static func faceDownStep(cardHeight: CGFloat) -> CGFloat { (cardHeight * 0.13).rounded() }

    /// 表向き札を重ねる段差。配りを重ねると 1 列が 20 枚を超えることも普通にあるため、
    /// フリーセル（0.24）と同じく詰める。
    public static func faceUpStep(cardHeight: CGFloat) -> CGFloat { (cardHeight * 0.24).rounded() }

    /// 列 1 本の高さ（いちばん上の札の全体が見える高さまで）。
    public static func pileHeight(faceDownCount: Int, faceUpCount: Int, cardHeight: CGFloat) -> CGFloat {
        let down = CGFloat(max(0, faceDownCount)) * faceDownStep(cardHeight: cardHeight)
        let up = CGFloat(max(0, faceUpCount - 1)) * faceUpStep(cardHeight: cardHeight)
        return down + up + cardHeight
    }

    /// 札 1 枚ぶんの面の寸法。既存の「小さい札」（大富豪の 42×60）を基準に相似で伸縮させる。
    public static func faceMetrics(width: CGFloat) -> PlayingCardMetrics {
        let scale = width / PlayingCardMetrics.compact.width
        return PlayingCardMetrics(
            width: width,
            height: cardHeight(width: width),
            cornerRadius: (6 * scale).rounded(),
            rankFont: (16 * scale).rounded(),
            suitFont: (15 * scale).rounded(),
            pipSpacing: 0,
            backMotifFont: (17 * scale).rounded()
        )
    }
}
