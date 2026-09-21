import Core
import Foundation
import Testing
@testable import GameHanafuda

@Suite("花札: 画面の高さへの収め方")
struct HanafudaFitTests {

    /// 縮めたあとの高さ（3 つのカードの中身の合計。見出しや余白も含む）。
    private func totalHeight(_ m: HanafudaFit.Metrics, fieldRows: Int, handRows: Int) -> CGFloat {
        let cardH = m.cardWidth * HanafudaCardArt.aspectRatio
        let gaps = CGFloat(fieldRows - 1 + handRows - 1) * HanafudaFit.gap
        return HanafudaFit.fixedHeight + gaps + 3 * m.stripHeight + CGFloat(fieldRows + handRows) * cardH
    }

    @Test("十分に高い画面では縮めない（これまでの 6 列 2 段）")
    func tallScreenKeepsNaturalSize() {
        let m = HanafudaFit.metrics(availableWidth: 361, availableHeight: 900, stripHeight: 40,
                                    fieldCount: 8, handCount: 8)
        #expect(m.columnCount == 6)
        #expect(m.stripHeight == 40)
        #expect(abs(m.cardWidth - (361 - 20 - 5 * HanafudaFit.gap) / 6) < 0.001)
    }

    @Test("低い画面では残りの高さに収まる大きさまで縮む")
    func shortScreenFitsAvailableHeight() {
        for height in [320.0, 380, 450, 520] {
            let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: height, stripHeight: 40,
                                        fieldCount: 8, handCount: 8)
            let rows = m.columnCount == 6 ? 2 : 1
            #expect(totalHeight(m, fieldRows: rows, handRows: rows) <= height + 0.001,
                    "高さ \(height) に収まらない: \(m)")
        }
    }

    @Test("狭くて低い画面では 8 列 1 段のほうが札を大きく取れる")
    func veryShortScreenPrefersOneRow() {
        let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: 320, stripHeight: 40,
                                    fieldCount: 8, handCount: 8)
        #expect(m.columnCount == 8)
        let sixColumns = (343 - 20 - 5 * HanafudaFit.gap) / 6 * HanafudaFit.minScale
        #expect(m.cardWidth > sixColumns)
    }

    @Test("高さが小さいほど札は小さくなり、下限は割らない")
    func scaleIsMonotonicAndBounded() {
        var previous = CGFloat.infinity
        for height in stride(from: 900.0, through: 100, by: -50) {
            let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: height, stripHeight: 40,
                                        fieldCount: 8, handCount: 8)
            #expect(m.cardWidth <= previous + 0.001)
            #expect(m.stripHeight >= 40 * HanafudaFit.minScale - 0.001)
            previous = m.cardWidth
        }
    }

    @Test("場が 8 枚を超えたら段を足して、そのぶん札を縮める")
    func overflowingFieldAddsARow() {
        let base = HanafudaFit.metrics(availableWidth: 343, availableHeight: 500, stripHeight: 40,
                                       fieldCount: 8, handCount: 8)
        let more = HanafudaFit.metrics(availableWidth: 343, availableHeight: 500, stripHeight: 40,
                                       fieldCount: 13, handCount: 8)
        #expect(more.cardWidth < base.cardWidth)
    }

    @Test("列の定義は札の幅ちょうどの固定幅")
    func columnsAreFixedWidth() {
        let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: 500, stripHeight: 40,
                                    fieldCount: 8, handCount: 8)
        #expect(m.columns.count == m.columnCount)
    }
}
