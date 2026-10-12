import CoreGraphics
import Testing
@testable import GameOjisanPuzzle

@Suite("おじさんの荷物運びパズル: 荷物 5 種のドット絵（#2115）")
struct OjisanPuzzleLuggageArtTests {
    @Test("5 種すべて同梱され、24×24 ドットで読み込める")
    func allLuggageLoad() {
        for value in 1...OjisanPuzzleBoard.kindCount {
            let image = OjisanPuzzleLuggageArt.images[value]
            #expect(image != nil, "荷物 \(value) の画像が読めない")
            #expect(image?.width == OjisanPuzzleLuggageArt.dots && image?.height == OjisanPuzzleLuggageArt.dots)
        }
        #expect(OjisanPuzzleLuggageArt.resourceName(0) == nil)
        #expect(OjisanPuzzleLuggageArt.resourceName(6) == nil)
    }

    @Test("1 ドットは画面の整数 px で、マスからはみ出さない")
    func pixelsPerDotFitsCell() {
        // 盤（30pt 前後）・つぎ（26pt）・遊び方の一覧（34pt）を @2x / @3x で。
        for side in [20.0, 26.0, 29.5, 33.0, 34.0, 40.0] as [CGFloat] {
            for scale in [2.0, 3.0] as [CGFloat] {
                let ppd = OjisanPuzzleLuggageArt.pixelsPerDot(side: side, dots: 24, displayScale: scale)
                #expect(ppd >= 1)
                #expect(CGFloat(ppd * 24) <= side * scale)
                // 1 つ大きい倍率だとはみ出す（＝収まる最大の倍率）。
                #expect(CGFloat((ppd + 1) * 24) > side * scale)
            }
        }
        #expect(OjisanPuzzleLuggageArt.pixelsPerDot(side: 26, dots: 24, displayScale: 3) == 3)
        #expect(OjisanPuzzleLuggageArt.pixelsPerDot(side: 26, dots: 24, displayScale: 2) == 2)
        // GeometryReader 由来の 0 や極小のマスでも 0 にならない。
        #expect(OjisanPuzzleLuggageArt.pixelsPerDot(side: 0, dots: 24, displayScale: 3) == 1)
        #expect(OjisanPuzzleLuggageArt.pixelsPerDot(side: 5, dots: 24, displayScale: 2) == 1)
    }
}
