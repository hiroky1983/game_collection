import Testing
import GameKitTestSupport

/// 画面の組み方をソースで縛る（描画はテストから起動しないため）。
@Suite("腰痛おじさんパズルの画面")
struct OjisanPuzzleViewTests {
    @Test("画面下に共通のバナーを 1 つ置き、操作とリザルトの範囲の外に出す")
    func bannerSitsOutsidePlayArea() throws {
        let module = SourceScan.strippingComments(try SourceScan.moduleSources("GameOjisanPuzzle"))
        #expect(module.components(separatedBy: "BannerSlot(").count - 1 == 1, "バナーは 1 つだけ")
        // `body` は開始シートにもあるので、画面のファイルだけを見る。
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleView.swift"))
        // 遊ぶ部分（ジェスチャ・リザルトの重ね）を組み終えてから、外側でバナーを並べる。
        let playArea = try #require(code.range(of: "private var playArea: some View"))
        let banner = try #require(code.range(of: "BannerSlot(ads: services.ads)"))
        #expect(banner.lowerBound < playArea.lowerBound, "バナーは playArea の外（body 側）に置く")
        let body = try #require(code.range(of: "public var body: some View"))
        let outer = code[body.lowerBound..<playArea.lowerBound]
        #expect(!outer.contains(".gesture("), "バナーを含む外側でドラッグを受けない（バナー上のドラッグで荷物を動かさない）")
        #expect(!outer.contains("{ resultOverlay }"), "リザルトをバナーに重ねない")
        let inner = code[playArea.lowerBound...]
        #expect(inner.contains(".gesture(dragGesture("), "ドラッグは playArea で受ける")
        #expect(inner.contains("{ resultOverlay }"), "リザルトは playArea に重ねる")
    }
}
