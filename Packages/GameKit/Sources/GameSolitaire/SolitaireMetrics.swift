import CoreGraphics
import Core

/// 盤面の寸法（#397）。
///
/// クロンダイクは**横に 7 列**が絶対条件で、画面幅から札の大きさが決まる。View に数値を撒くと
/// 「iPhone SE で 7 列目がはみ出す」類の破綻がレイアウトの各所に散るため、寸法はここに集約して
/// 純粋関数にし、View を組まずに検証できるようにする（麻雀ソリティアの `BoardMetrics` と同じ設計）。
public enum SolitaireMetrics {
    /// 列と列の間隔。
    public static let columnGap: CGFloat = 5
    /// トランプの縦横比（実物の 63×88 に近い値）。
    public static let aspectRatio: CGFloat = 1.4
    /// 札の幅の下限・上限。下限は iPhone SE（375pt）でも 7 列が収まる値、
    /// 上限は iPad で札だけが間延びしないようにするための頭打ち。
    public static let minCardWidth: CGFloat = 34
    public static let maxCardWidth: CGFloat = 76

    /// 与えられた幅に 7 列を収める札の幅。
    ///
    /// `maxWidth` は上限の差し替え口（#458）。iPad では `AdaptiveLayout.scaled(_:)` を通した値を
    /// 渡し、他の画面と同じ倍率で札を大きくする。既定値は従来どおり `maxCardWidth` なので、
    /// 引数を省いた呼び出し（テスト・iPhone）の結果は 1pt も変わらない。
    public static func cardWidth(availableWidth: CGFloat, maxWidth: CGFloat = maxCardWidth) -> CGFloat {
        let raw = (availableWidth - columnGap * CGFloat(SolitaireBoard.pileCount - 1))
            / CGFloat(SolitaireBoard.pileCount)
        return min(maxWidth, max(minCardWidth, raw))
    }

    /// 7 列ぶんの盤面の幅（列と列の隙間を含む）。
    ///
    /// 上段（山札・捨て札・組札）は `Spacer` で左右いっぱいに広がるのに対し、下段の 7 列は
    /// 札の幅の上限で頭打ちになる。画面が広い iPad では上段だけが伸びて**組札と 7 列目が
    /// 縦に揃わなくなる**ため、両方をこの幅に揃えて中央に置く（#458）。
    /// 上限に掛からない画面（iPhone）ではこの値は使える幅と一致するので、見た目は変わらない。
    public static func boardWidth(cardWidth: CGFloat) -> CGFloat {
        cardWidth * CGFloat(SolitaireBoard.pileCount)
            + columnGap * CGFloat(SolitaireBoard.pileCount - 1)
    }

    public static func cardHeight(width: CGFloat) -> CGFloat { (width * aspectRatio).rounded() }

    /// 3枚めくりで捨て札を横にずらして重ねる幅（#498）。
    ///
    /// 上段は「山札 + 捨て札 + 組札4」で 6 枚ぶんしか使っておらず、7 列に揃えた盤幅との差
    /// （＝札 1 枚ぶん）が扇に使える全余白になる。ずらしは 2 回ぶん入るので、**札の幅の半分を
    /// 超えると 7 列目からはみ出す**。0.45 はその上限のすぐ内側で、隠れる 2 枚の左上の
    /// ランクとスートが読める幅。
    public static func wasteFanStep(cardWidth: CGFloat) -> CGFloat { (cardWidth * 0.45).rounded() }

    /// 捨て札の枠の幅（扇の枚数ぶん広がる）。1 枚しか見せないときは札の幅そのもの。
    public static func wasteWidth(cardWidth: CGFloat, visibleCount: Int) -> CGFloat {
        cardWidth + CGFloat(max(0, visibleCount - 1)) * wasteFanStep(cardWidth: cardWidth)
    }

    /// 伏せ札を重ねる段差。伏せ札は枚数が見えれば十分なので詰める。
    public static func faceDownStep(cardHeight: CGFloat) -> CGFloat { (cardHeight * 0.13).rounded() }

    /// 表向き札を重ねる段差。ランクとスートの 2 行が見える高さを確保する。
    public static func faceUpStep(cardHeight: CGFloat) -> CGFloat { (cardHeight * 0.30).rounded() }

    /// 列 1 本の高さ（いちばん上の札の全体が見える高さまで）。
    public static func pileHeight(
        faceDownCount: Int,
        faceUpCount: Int,
        cardHeight: CGFloat
    ) -> CGFloat {
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
