import Testing
import CoreGraphics
import Core
@testable import GameSpider

/// 卓（#1501）に乗せても 10 列が iPhone SE に収まること。
///
/// 4 本のうち列がいちばん多いのがスパイダーで、卓の木枠と内側の余白ぶん札の幅が削られる。
/// 札の幅の下限（28pt）を割ると 10 列目が卓からはみ出す。
@Suite("スパイダーの卓への収まり")
struct SpiderTableFitTests {

    /// 画面幅から、卓の外の余白（`boardSideInset`）と卓の木枠 + 内側の余白を引いた、札に使える幅。
    private static func innerWidth(screenWidth: CGFloat) -> CGFloat {
        let table = screenWidth - SpiderMetrics.boardSideInset * 2
        let rim = CardTableFrame.standard.insets(width: table)
        return table - rim.leading - rim.trailing - CardTableStyle.contentInset * 2
    }

    @Test("卓の内側で 10 列が下限を割らずに収まる", arguments: [CGFloat(375), 390, 393, 402, 430, 440])
    func tenColumnsFitInsideTheTable(_ screenWidth: CGFloat) {
        let inner = Self.innerWidth(screenWidth: screenWidth)
        let card = SpiderMetrics.cardWidth(availableWidth: inner)
        #expect(card >= SpiderMetrics.minCardWidth)
        #expect(SpiderMetrics.boardWidth(cardWidth: card) <= inner,
                "10 列（\(SpiderMetrics.boardWidth(cardWidth: card))pt）が卓の内側（\(inner)pt）をはみ出す")
    }

    /// #1535 で木枠を麻雀と同じ太さ（卓の幅の 12/393）にそろえた。iPhone SE（卓の幅 367pt）で片側 17.2pt、
    /// 札は 31.5pt（下限 28pt に 3.5pt の余裕）。これより広げるなら SE の 10 列を見直す。
    @Test("卓の木枠と余白は iPhone SE で片側 18pt 以下（これより広げるなら SE の 10 列を見直す）")
    func tableInsetIsSmall() {
        let table = CGFloat(375) - SpiderMetrics.boardSideInset * 2
        let rim = CardTableFrame.standard.insets(width: table)
        #expect(rim.leading + CardTableStyle.contentInset <= 18)
        #expect(rim.leading == rim.trailing)
    }
}
