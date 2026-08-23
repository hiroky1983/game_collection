import Testing
import CoreGraphics
@testable import GameMahjongSolitaire

/// 盤面の大きさ（#196）。牌のタップ標的が Apple HIG の 44pt を満たすかを、
/// シミュレータを立てずに実寸で検証する。
///
/// 盤面領域の実寸は `docs/ui-review/148/README.md` の実測値（#148 の修正後）を使う。
/// 対応 OS は iOS 17 以上なので、いちばん狭い実機は **iPhone SE 第2/第3世代（375pt 幅）**。
@Suite("麻雀ソリティアの盤面の大きさ")
struct MahjongSolitaireBoardMetricsTests {

    /// #148 で実測した盤面領域（ステータスバーの下端〜操作カードの上端）。
    static let iPhoneSE = CGSize(width: 375, height: 349.5)
    static let iPhone17 = CGSize(width: 402, height: 469.7)

    typealias Metrics = MahjongSolitaireBoardMetrics

    @Test("盤面は横 15.56 枚・縦 8.56 枚ぶんの広さ")
    func canvasExtent() {
        #expect(abs(Metrics.canvasWidthInTiles - 15.56) < 0.001)
        #expect(abs(Metrics.canvasHeightInTiles - 8.56) < 0.001)
    }

    @Test(
        "既定の牌は最小タップ標的 44pt 以上",
        arguments: [iPhoneSE, iPhone17]
    )
    func comfortableTileMeetsTapTarget(size: CGSize) {
        let width = Metrics.comfortableTileWidth(in: size)
        #expect(width >= 44)
        // 縦横比のぶん高さはさらに大きい。
        #expect(width * Metrics.tileAspect >= 44)
    }

    @Test(
        "全体表示にすると牌は 44pt を割る（両立しないことの記録）",
        arguments: [iPhoneSE, iPhone17]
    )
    func fittingTileIsBelowTapTargetOnPhones(size: CGSize) {
        // 44pt の牌で盤面全体を出すには 684.6pt の幅が要る。iPhone では成立しないため
        // 「全体表示を既定に戻す」と #196 の受け入れ条件を満たせなくなる。この関係が崩れたら気づけるようにする。
        #expect(Metrics.fittingTileWidth(in: size) < 44)
        #expect(44 * Metrics.canvasWidthInTiles > 680)
    }

    @Test("全体表示では盤面が与えられた領域に収まる", arguments: [iPhoneSE, iPhone17])
    func fittingCanvasFitsInside(size: CGSize) {
        let canvas = Metrics.canvasSize(tileWidth: Metrics.fittingTileWidth(in: size))
        #expect(canvas.width <= size.width + 0.001)
        #expect(canvas.height <= size.height + 0.001)
    }

    @Test("画面が広ければ既定の牌は全体表示と同じ大きさ（44pt へ切り下げない）")
    func comfortableNeverShrinksBelowFitting() {
        // iPad 相当。全体表示のままで 44pt を超えるので、拡大が縮小になってはいけない。
        let iPad = CGSize(width: 1024, height: 1200)
        let fitting = Metrics.fittingTileWidth(in: iPad)
        #expect(fitting > 44)
        #expect(Metrics.comfortableTileWidth(in: iPad) == fitting)
    }

    @Test("既定の牌の幅は全体表示を下回らない", arguments: [iPhoneSE, iPhone17])
    func comfortableIsNeverSmallerThanFitting(size: CGSize) {
        #expect(Metrics.comfortableTileWidth(in: size) >= Metrics.fittingTileWidth(in: size))
    }

    @Test("同じ段の牌どうしは重ならない（44pt の枠がそのままタップ標的になる）")
    func tilesOnTheSameLayerDoNotOverlap() {
        let tileWidth = Metrics.comfortableTileWidth(in: Self.iPhoneSE)
        let layout = MahjongSolitaireRules.layout
        for i in layout.indices {
            let a = Metrics.tileFrame(index: i, tileWidth: tileWidth)
            #expect(a.width >= 44)
            for j in layout.indices where j > i && layout[j].layer == layout[i].layer {
                let b = Metrics.tileFrame(index: j, tileWidth: tileWidth)
                // 接するのは可（幅ちょうどで隣り合う）。食い込んだら別の牌を押してしまう。
                #expect(a.insetBy(dx: 0.001, dy: 0.001).intersects(b) == false)
            }
        }
    }

    @Test("牌の矩形は盤面の枠に収まる")
    func tileFramesStayInsideCanvas() {
        let tileWidth: CGFloat = 44
        let canvas = Metrics.canvasSize(tileWidth: tileWidth)
        for index in MahjongSolitaireRules.layout.indices {
            let frame = Metrics.tileFrame(index: index, tileWidth: tileWidth)
            #expect(frame.minX >= -0.001)
            #expect(frame.minY >= -0.001)
            #expect(frame.maxX <= canvas.width + 0.001)
            #expect(frame.maxY <= canvas.height + 0.001)
        }
    }
}
