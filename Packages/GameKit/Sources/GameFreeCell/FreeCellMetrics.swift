import CoreGraphics
import Core

/// 盤面の寸法（#492）。
///
/// フリーセルは**横に 8 列**が絶対条件で、画面幅から札の大きさが決まる。上段も
/// 「フリーセル4 + 組札4 = 8 枠」なので、上下がちょうど同じ列幅に揃う。
/// 数値を View に撒くと「iPhone SE で 8 列目がはみ出す」類の破綻が各所に散るため、
/// 寸法はここに集約して純粋関数にし、View を組まずに検証できるようにする
/// （ソリティアの `SolitaireMetrics` と同じ設計）。
public enum FreeCellMetrics {
    /// 列と列の間隔。8 列なのでソリティア（7 列・5pt）より詰める。
    public static let columnGap: CGFloat = 4
    /// トランプの縦横比（実物の 63×88 に近い値）。
    public static let aspectRatio: CGFloat = 1.4
    /// 札の幅の下限・上限。下限は iPhone SE（375pt）でも 8 列が収まる値、
    /// 上限は iPad で札だけが間延びしないようにするための頭打ち。
    public static let minCardWidth: CGFloat = 30
    public static let maxCardWidth: CGFloat = 68

    /// 与えられた幅に 8 列を収める札の幅。
    ///
    /// `maxWidth` は上限の差し替え口（#458）。iPad では `AdaptiveLayout.scaled(_:)` を通した値を
    /// 渡し、他の画面と同じ倍率で札を大きくする。
    public static func cardWidth(availableWidth: CGFloat, maxWidth: CGFloat = maxCardWidth) -> CGFloat {
        let raw = (availableWidth - columnGap * CGFloat(FreeCellBoard.pileCount - 1))
            / CGFloat(FreeCellBoard.pileCount)
        return min(maxWidth, max(minCardWidth, raw))
    }

    /// 8 列ぶんの盤面の幅（列と列の隙間を含む）。
    ///
    /// 上段（フリーセル・組札）と下段（8 列）を同じ幅に揃えて中央に置くために使う。
    /// 上限に掛からない画面（iPhone）ではこの値は使える幅と一致するので、見た目は変わらない。
    public static func boardWidth(cardWidth: CGFloat) -> CGFloat {
        cardWidth * CGFloat(FreeCellBoard.pileCount)
            + columnGap * CGFloat(FreeCellBoard.pileCount - 1)
    }

    public static func cardHeight(width: CGFloat) -> CGFloat { (width * aspectRatio).rounded() }

    /// 札を重ねる段差。フリーセルは**全札が表向き**で、最長 13 枚を超える列も普通に出るため、
    /// クロンダイクの表向き段差（0.30）より詰めないと 1 列が画面から溢れる。
    public static func step(cardHeight: CGFloat) -> CGFloat { (cardHeight * 0.24).rounded() }

    /// 列 1 本の高さ（いちばん上の札の全体が見える高さまで）。
    public static func pileHeight(cardCount: Int, cardHeight: CGFloat) -> CGFloat {
        CGFloat(max(0, cardCount - 1)) * step(cardHeight: cardHeight) + cardHeight
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
