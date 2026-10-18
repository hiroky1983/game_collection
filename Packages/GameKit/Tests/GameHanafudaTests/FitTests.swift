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
        return HanafudaFit.fixedHeight + gaps + 2 * m.stripHeight + CGFloat(fieldRows + handRows) * cardH
    }

    @Test("十分に高い画面では縮めない（8 枚なら 4 列 2 段で大きく取る・#2336）")
    func tallScreenKeepsNaturalSize() {
        let m = HanafudaFit.metrics(availableWidth: 361, availableHeight: 900, stripHeight: 40,
                                    fieldCount: 8, handCount: 8)
        #expect(m.columnCount == 4)
        #expect(m.stripHeight == 40)
        #expect(abs(m.cardWidth - (361 - 20 - 3 * HanafudaFit.gap) / 4) < 0.001)
    }

    @Test("低い画面では残りの高さに収まる大きさまで縮む")
    func shortScreenFitsAvailableHeight() {
        for height in [400.0, 450, 520] {
            let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: height, stripHeight: 40,
                                        fieldCount: 8, handCount: 8)
            let rows = (8 + m.columnCount - 1) / m.columnCount
            #expect(totalHeight(m, fieldRows: rows, handRows: rows) <= height + 0.001,
                    "高さ \(height) に収まらない: \(m)")
        }
    }

    @Test("狭くて低い画面では 8 列 1 段のほうが札を大きく取れる")
    func veryShortScreenPrefersOneRow() {
        let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: 400, stripHeight: 40,
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
        for column in m.columns {
            guard case .fixed(let width) = column.size else {
                Issue.record("固定幅でない列がある")
                continue
            }
            #expect(width == m.cardWidth)
        }
    }

    /// 見出し 3 行（16pt）＋ 取り札の見出し 2 つ（18pt）＋ めくり札で伸びる分（24）＋ 3 カードの上下余白（60）＋ カード内の縦の間隔 4 か所（24）＋ カード間 2 か所（16）。
    /// 実装と同じ式をテストが参照すると、式を壊しても収まりテストが一緒に動いて緑のまま残るため、値で固定する。
    @Test("縮められない高さの見積もりは 208pt")
    func fixedHeightIsPinned() {
        #expect(HanafudaFit.fixedHeight == 208)
        #expect(HanafudaCardArt.aspectRatio == 1.5)
    }

    @Test("手札が減って 1 段になると札が大きくなる（下の空きを使う・#2336）")
    func fewerCardsMakeBiggerCards() {
        let full = HanafudaFit.metrics(availableWidth: 361, availableHeight: 560, stripHeight: 52,
                                       fieldCount: 8, handCount: 8)
        let late = HanafudaFit.metrics(availableWidth: 361, availableHeight: 560, stripHeight: 52,
                                       fieldCount: 4, handCount: 3)
        #expect(late.cardWidth > full.cardWidth)
    }

    @Test("取り札の 4 列は光・タネ・短冊・カスの順で、空の種別も残る")
    func capturedGroupsKeepAllFourKinds() {
        let deck = HanafudaCard.fullDeck
        let cards = [deck.first { $0.kind == .kasu }!, deck.first { $0.kind == .hikari }!]
        let groups = HanafudaCapturedGroup.groups(of: cards)
        #expect(groups.map(\.kind) == [.hikari, .tane, .tanzaku, .kasu])
        #expect(groups.map { $0.cards.count } == [1, 0, 0, 1])
        #expect(groups.map(\.goal) == [3, 5, 5, 10])
        #expect(groups.allSatisfy { !$0.isComplete })
    }

    @Test("取り札の列幅: どの列も札 1 枚ぶんは取り、合計は枠を超えない")
    func capturedGroupWidthsAndStep() {
        let cardWidth: CGFloat = 34
        let widths = HanafudaFit.groupWidths(total: 300, cardWidth: cardWidth, counts: [0, 0, 0, 12])
        #expect(widths.allSatisfy { $0 >= cardWidth })
        #expect(widths[3] > widths[0])
        #expect(HanafudaFit.overlapStep(groupWidth: widths[3], cardWidth: cardWidth, count: 12) >= 4)
        for counts in [[1, 5, 5, 10], [3, 8, 10, 24], [0, 0, 0, 24], [2, 5, 5, 16], [0, 0, 0, 0]] {
            let w = HanafudaFit.groupWidths(total: 323, cardWidth: cardWidth, counts: counts)
            #expect(w.allSatisfy { $0 >= cardWidth - 0.001 })
            #expect(w.reduce(0, +) + 3 * HanafudaFit.groupSpacing <= 323 + 0.001, "\(counts): \(w)")
            // 列に収まる間隔なので、札の右端が列からはみ出さない。
            for (i, n) in counts.enumerated() {
                let step = HanafudaFit.overlapStep(groupWidth: w[i], cardWidth: cardWidth, count: n)
                #expect(cardWidth + CGFloat(max(0, n - 1)) * step <= w[i] + 0.001)
            }
        }
        #expect(HanafudaFit.overlapStep(groupWidth: 80, cardWidth: cardWidth, count: 1) == 0)
        // 広い列でも札の幅の 0.9 倍を超えて離さない。
        #expect(HanafudaFit.overlapStep(groupWidth: 300, cardWidth: cardWidth, count: 2) == cardWidth * 0.9)
    }

    @Test("下限に張り付く低い画面では、同じ札幅なら背の低い並べ方を選ぶ")
    func floorPrefersShorterLayout() {
        for height in [250.0, 300, 340] {
            let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: height, stripHeight: 52,
                                        fieldCount: 8, handCount: 8)
            #expect(m.columnCount == 8, "高さ \(height): \(m)")
        }
    }

    /// iPhone SE（375×667pt）の残り高さは約 373pt、幅は約 343pt（#2452）。
    @Test("iPhone SE: 局の途中・配り直後とも、札の幅が今（25.5pt）より大きくなり、高さに収まる")
    func smallScreenGivesCardsMoreRoom() {
        for (field, hand) in [(6, 5), (8, 8)] {
            let m = HanafudaFit.metrics(availableWidth: 343, availableHeight: 373, stripHeight: 52,
                                        fieldCount: field, handCount: hand)
            // 局の途中（6/5）は 25.5 → 30 台、配り直後（8/8）は 8 列 1 段で高さが律速し、27.7pt まで。44pt には届かない。
            #expect(m.cardWidth > (field == 6 ? 30 : 27), "\(field)/\(hand): \(m)")
            #expect(m.stripHeight >= 52 * HanafudaFit.shortScreenMinStripScale - 0.001)
            let rows = (field + m.columnCount - 1) / m.columnCount + (hand + m.columnCount - 1) / m.columnCount
            let used = HanafudaFit.fixedHeight + 2 * m.stripHeight
                + CGFloat(rows) * m.cardWidth * HanafudaCardArt.aspectRatio + CGFloat(rows - 2) * HanafudaFit.gap
            #expect(used <= 373 + 0.001, "\(field)/\(hand): \(m)")
        }
    }

    @Test("iPhone 17 の高さ（560pt）では取り札の下限は今のまま 0.85")
    func tallScreenKeepsStripFloor() {
        #expect(HanafudaFit.stripFloor(availableHeight: 560) == HanafudaFit.minStripScale)
        #expect(HanafudaFit.stripFloor(availableHeight: 373) == HanafudaFit.shortScreenMinStripScale)
        let m = HanafudaFit.metrics(availableWidth: 370, availableHeight: 560, stripHeight: 52,
                                    fieldCount: 6, handCount: 5)
        // 今（#2336 反映後）の局の途中の札幅 53.3pt を割らない。
        #expect(m.cardWidth >= 53.3, "\(m)")
    }
}
