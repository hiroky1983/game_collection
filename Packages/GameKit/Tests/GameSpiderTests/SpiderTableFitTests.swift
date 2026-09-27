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
        screenWidth
            - SpiderMetrics.boardSideInset * 2
            - (CardTableStyle.rimWidth + CardTableStyle.contentInset) * 2
    }

    @Test("卓の内側で 10 列が下限を割らずに収まる", arguments: [CGFloat(375), 390, 393, 402, 430, 440])
    func tenColumnsFitInsideTheTable(_ screenWidth: CGFloat) {
        let inner = Self.innerWidth(screenWidth: screenWidth)
        let card = SpiderMetrics.cardWidth(availableWidth: inner)
        #expect(card >= SpiderMetrics.minCardWidth)
        #expect(SpiderMetrics.boardWidth(cardWidth: card) <= inner,
                "10 列（\(SpiderMetrics.boardWidth(cardWidth: card))pt）が卓の内側（\(inner)pt）をはみ出す")
    }

    @Test("卓の木枠と余白は片側 9pt（これより広げるなら SE の 10 列を見直す）")
    func tableInsetIsSmall() {
        #expect(CardTableStyle.rimWidth + CardTableStyle.contentInset == 9)
    }
}
