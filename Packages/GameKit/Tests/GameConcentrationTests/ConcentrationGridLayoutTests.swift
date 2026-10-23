import Testing
import CoreGraphics
import Core
@testable import GameConcentration

/// 札の並びの寸法（レイアウトパターン A・#2531）。札の並びが画面にいちばん大きく見え、どの画面でも枠に収まること。
@Suite("神経衰弱の札の並び")
struct ConcentrationGridLayoutTests {
    /// 札の並びに回る幅・高さ（全画面の枠の中身から、左右の余白・上下の余白・「⋯」の行と間隔を引いたもの）。
    private static func gridArea(screenWidth: CGFloat, screenHeight: CGFloat,
                                 safeTop: CGFloat, safeBottom: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let content = FullScreenGameLayoutMetrics.contentHeight(screenHeight: screenHeight, safeAreaTop: safeTop,
                                                                safeAreaBottom: safeBottom)
        let controls = BoardGameControlMetrics.minTapTarget + 2 * 8 + 10
        return (screenWidth - FullScreenGameLayoutMetrics.sideInset * 2, content - 2 * 2 - controls)
    }

    private static let iPhone17 = gridArea(screenWidth: 402, screenHeight: 874, safeTop: 62, safeBottom: 34)
    private static let iPhoneSE = gridArea(screenWidth: 375, screenHeight: 667, safeTop: 20, safeBottom: 0)

    @Test("8 ペア・18 ペアは以前と同じ列の数（4 列・6 列）")
    func fixedColumns() {
        for area in [Self.iPhone17, Self.iPhoneSE] {
            #expect(ConcentrationGridLayout.columns(pairCount: .small, width: area.width, height: area.height) == 4)
            #expect(ConcentrationGridLayout.columns(pairCount: .large, width: area.width, height: area.height) == 6)
        }
    }

    @Test("12 ペアは縦長の iPhone 17 で 4 列（札が大きくなる）、SE では以前の 6 列のまま")
    func mediumColumnsFollowTheScreen() {
        #expect(ConcentrationGridLayout.columns(pairCount: .medium, width: Self.iPhone17.width, height: Self.iPhone17.height) == 4)
        #expect(ConcentrationGridLayout.columns(pairCount: .medium, width: Self.iPhoneSE.width, height: Self.iPhoneSE.height) == 6)
    }

    @Test("どの盤も枠の幅・高さに収まり、札は基準比より横長にならない",
          arguments: [8, 12, 18])
    func gridFitsTheArea(pairs: Int) {
        let pairCount = ConcentrationPairCount(rawValue: pairs)!
        for area in [Self.iPhone17, Self.iPhoneSE] {
            let cols = ConcentrationGridLayout.columns(pairCount: pairCount, width: area.width, height: area.height)
            let rows = (pairCount.rawValue * 2 + cols - 1) / cols
            let size = ConcentrationGridLayout.cardSize(cardCount: pairCount.rawValue * 2, columns: cols,
                                                        width: area.width, height: area.height)
            let spacing = ConcentrationGridLayout.spacing
            #expect(size.width * CGFloat(cols) + spacing * CGFloat(cols - 1) <= area.width + 0.5)
            #expect(size.height * CGFloat(rows) + spacing * CGFloat(rows - 1) <= area.height + 0.5)
            #expect(size.width / size.height <= ConcentrationGridLayout.cardAspect + 0.001)
        }
    }

    @Test("縦が余るときは札の並びが枠の高さをほぼ使い切る（「⋯」の下に大きな空きを残さない・iPhone 17）",
          arguments: [8, 12, 18])
    func gridUsesTheHeight(pairs: Int) {
        let pairCount = ConcentrationPairCount(rawValue: pairs)!
        let area = Self.iPhone17
        let cols = ConcentrationGridLayout.columns(pairCount: pairCount, width: area.width, height: area.height)
        let rows = (pairCount.rawValue * 2 + cols - 1) / cols
        let size = ConcentrationGridLayout.cardSize(cardCount: pairCount.rawValue * 2, columns: cols,
                                                    width: area.width, height: area.height)
        let used = size.height * CGFloat(rows) + ConcentrationGridLayout.spacing * CGFloat(rows - 1)
        #expect(area.height - used < 40, "札の並びの下に \(area.height - used)pt 空いている")
    }

    @Test("大きさ 0 の枠（GeometryReader の初回）でも 0 や負の大きさにならない")
    func zeroSize() {
        let size = ConcentrationGridLayout.cardSize(cardCount: 24, columns: 6, width: 0, height: 0)
        #expect(size.width >= 1 && size.height >= 1)
        #expect(ConcentrationGridLayout.columns(pairCount: .medium, width: 0, height: 0) == 6)
    }
}
