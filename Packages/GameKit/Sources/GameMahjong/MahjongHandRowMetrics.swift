import CoreGraphics
import Core

/// 卓の下の手牌の行（`MahjongView.handOnTable`）の寸法（#715）。
///
/// 河の牌は卓の幅から決まる（`MahjongTableLayout.riverTileWidth`）ので iPad では卓と一緒に大きくなるが、
/// この行は固定 pt のままだったため、iPad では**CPU の捨て牌より自分の手牌のほうが小さく**見えていた。
/// 狭い画面では従来の値そのまま、広い画面でだけ牌・間隔・ツモ牌の隙間を同じ倍率で相似に広げる
/// （`PlayingCardMetrics.scaled(by:)` と同じ考え方）。
///
/// `MahjongView` の `static let` は MainActor に隔離されてテストから読みにくいので、値はここに置く。
public struct MahjongHandRowMetrics: Equatable, Sendable {
    public var tileWidth: CGFloat
    public var tileHeight: CGFloat
    /// 牌どうしの間隔（`HStack` の spacing）。
    public var spacing: CGFloat
    /// 手牌とツモ牌のあいだの隙間。
    public var drawnGap: CGFloat

    /// iPhone の値（#715 以前の固定値）。
    public static let phone = MahjongHandRowMetrics(tileWidth: 34, tileHeight: 46, spacing: 3, drawnGap: 8)

    /// 行の左右の余白の合計（牌台の `padding(.horizontal, 6)` と、スクロールの中身の `padding(.horizontal, 6)`）。
    static let horizontalInsets: CGFloat = 24

    /// 手牌 13 枚 + ツモ牌 1 枚。
    static let tileCount = 14

    /// 手牌 13 枚・隙間・ツモ牌を 1 行に並べたときの幅（左右の余白は含まない）。
    /// `HStack` には手牌 13 枚・隙間・ツモ牌の枠の 15 要素が並ぶので、間隔は 14 個。
    public var rowContentWidth: CGFloat {
        tileWidth * CGFloat(Self.tileCount) + spacing * CGFloat(Self.tileCount) + drawnGap
    }

    public func scaled(by factor: CGFloat) -> MahjongHandRowMetrics {
        guard factor != 1 else { return self }
        return MahjongHandRowMetrics(
            tileWidth: tileWidth * factor,
            tileHeight: tileHeight * factor,
            spacing: spacing * factor,
            drawnGap: drawnGap * factor
        )
    }

    /// 画面の広さから行の寸法を決める。
    ///
    /// - 狭い画面（`AdaptiveLayout.isWide == false`）: `phone` のまま。
    /// - 広い画面: `elementScale` 倍を基本に、**卓が取りうる最大の一辺での河の牌の幅**を下回らないよう広げ、
    ///   14 枚が卓の幅（= 行の幅）に収まる倍率で頭打ちにする。卓の一辺は画面の内幅以下で、河の牌は
    ///   縮尺 1 以下で描かれるので、ここで河の牌の幅以上にしておけば実際のどの捨て牌よりも小さくならない。
    ///   幅 700pt 以上では、頭打ちの倍率でも河の牌の幅を下回らない（`MahjongHandRowMetricsTests` で検査）。
    public static func make(layout: AdaptiveLayout) -> MahjongHandRowMetrics {
        guard layout.isWide else { return phone }
        // 卓（`MahjongView.mahjongTable`）は画面の内幅（左右 `Theme.pad`）を幅の上限にする縦長の長方形
        // （#927）。河の牌の幅は卓の幅だけで決まる
        let tableWidth = layout.width - Theme.pad * 2
        let river = MahjongTableLayout(size: CGSize(width: tableWidth, height: tableWidth * MahjongTableLayout.aspect)).riverTileWidth
        let fit = (tableWidth - horizontalInsets) / phone.rowContentWidth
        let scale = min(max(layout.elementScale, river / phone.tileWidth), fit)
        return phone.scaled(by: scale)
    }
}
