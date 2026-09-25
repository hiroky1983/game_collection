import Testing
import Foundation
import CoreGraphics
import Core
import GameKitTestSupport
@testable import GameFreeCell

/// 札が小さすぎて遊びにくい問題の試作（段差を縦の余りに合わせる・列の下の空きも押せる・
/// 帯の見出しを大きく・盤の余白を詰める）。
///
/// 見た目そのものはシミュレータでしか確認できないので、**寸法の算術**と**ソース**の 2 方向から固定する。
/// 計算はスパイダーと共通の `CardStackLayout`（Core）で、`SpiderStackLayoutTests` と対になる。
@Suite("フリーセルの段差と見出し")
struct FreeCellStackLayoutTests {

    typealias Metrics = FreeCellMetrics

    private static let phoneWidths: [CGFloat] = [375, 393, 402, 430, 440]

    private static func availableWidth(screenWidth: CGFloat) -> CGFloat {
        screenWidth - Metrics.boardSideInset * 2
    }

    // MARK: - 盤の幅（④）

    @Test("盤の余白は 4pt・列の間隔は 3pt")
    func insetsAreTightened() {
        #expect(Metrics.boardSideInset == 4)
        #expect(Metrics.columnGap == 3)
    }

    @Test("どの iPhone でも 8 列目が画面をはみ出さない（iPhone SE を含む）", arguments: phoneWidths)
    func theLastColumnFitsOnScreen(_ screenWidth: CGFloat) {
        let card = Metrics.cardWidth(availableWidth: Self.availableWidth(screenWidth: screenWidth))
        let used = Metrics.boardWidth(cardWidth: card) + Metrics.boardSideInset * 2
        #expect(used <= screenWidth, "盤が画面をはみ出している（\(used)pt > \(screenWidth)pt）")
        #expect(card > Metrics.minCardWidth, "下限に張り付いていると計算上だけ収まっている可能性がある")
    }

    // MARK: - 段差（①）

    /// 画面幅ごとの札の幅・高さ・段差の下限/上限・見出しの文字（帯が最も広いとき）。報告値の固定。
    static let measured: [(screen: CGFloat, width: CGFloat, height: CGFloat,
                           minStep: CGFloat, maxStep: CGFloat, font: CGFloat)] = [
        (375, 43.25, 61, 15, 27, 19),
        (402, 46.625, 65, 16, 29, 20),
    ]

    @Test("iPhone SE と iPhone 17 の寸法", arguments: measured)
    func measuredValues(_ row: (screen: CGFloat, width: CGFloat, height: CGFloat,
                                minStep: CGFloat, maxStep: CGFloat, font: CGFloat)) {
        let width = Metrics.cardWidth(availableWidth: Self.availableWidth(screenWidth: row.screen))
        let height = Metrics.cardHeight(width: width)
        #expect(width == row.width)
        #expect(height == row.height)
        let tight = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: 0,
                                        pileCounts: [20, 7, 7, 7, 6, 6, 6, 6])
        let roomy = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: 5000,
                                        pileCounts: [7, 7, 7, 7, 6, 6, 6, 6])
        #expect(tight.faceUpStep == row.minStep)
        #expect(roomy.faceUpStep == row.maxStep)
        #expect(roomy.index.rankFont == row.font)
    }

    @Test("下限は従来の固定比 0.24（今より詰めない）", arguments: [CGFloat(0), 120, 200])
    func theStepNeverShrinksBelowTheOldRatio(_ boardHeight: CGFloat) {
        let height = Metrics.cardHeight(width: 46.625)
        let stack = Metrics.stackLayout(cardWidth: 46.625, cardHeight: height, boardHeight: boardHeight,
                                        pileCounts: [19, 13, 7, 7, 6, 6, 6, 6])
        #expect(stack.faceUpStep == (height * 0.24).rounded())
        #expect(stack.faceUpStep == Metrics.step(cardHeight: height))
    }

    @Test("上限は札の高さの 0.45（広げすぎると 1 本の列に見えなくなる）")
    func theStepStopsAtTheCeiling() {
        let height = Metrics.cardHeight(width: 46.625)
        let stack = Metrics.stackLayout(cardWidth: 46.625, cardHeight: height, boardHeight: 2000,
                                        pileCounts: [8, 7, 7, 7, 6, 6, 6, 6])
        #expect(stack.faceUpStep == (height * 0.45).rounded(.down))
    }

    /// 段差は**いちばん長い列**で決まり、全列で同じ値を使う。長い列が盤の下端に収まること。
    @Test("いちばん長い列が盤の下端に収まる", arguments: [CGFloat(330), 380, 420, 480])
    func theLongestColumnFitsTheBoard(_ boardHeight: CGFloat) {
        let width: CGFloat = 46.625
        let height = Metrics.cardHeight(width: width)
        let tableau = Metrics.tableauHeight(boardHeight: boardHeight, cardHeight: height)
        for longest in 8...16 {
            let counts = [longest, 7, 7, 6, 6, 6, 5, 4]
            let stack = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: boardHeight,
                                            pileCounts: counts)
            let pile = Metrics.pileHeight(cardCount: longest, cardHeight: height, step: stack.faceUpStep)
            if stack.faceUpStep > Metrics.step(cardHeight: height) {
                #expect(pile <= tableau - CardStackLayout.bottomMargin,
                        "\(longest) 枚の列が盤の下端をはみ出している（\(pile)pt > \(tableau)pt）")
            }
            #expect(stack.reachHeight == tableau)
        }
    }

    @Test("列が長くなるほど段差は詰まる（広がることはない）")
    func longerColumnsNeverWidenTheStep() {
        let width: CGFloat = 46.625
        let height = Metrics.cardHeight(width: width)
        var previous = CGFloat.infinity
        for longest in 1...25 {
            let stack = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: 420,
                                            pileCounts: [longest, 1, 1, 1, 1, 1, 1, 1])
            #expect(stack.faceUpStep <= previous)
            previous = stack.faceUpStep
        }
    }

    @Test("段差は最も長い列だけで決まる（短い列の並びには左右されない）")
    func theStepDependsOnlyOnTheLongestColumn() {
        let height = Metrics.cardHeight(width: 46.625)
        let a = Metrics.stackLayout(cardWidth: 46.625, cardHeight: height, boardHeight: 420,
                                    pileCounts: [14, 1, 1, 1, 1, 1, 1, 1])
        let b = Metrics.stackLayout(cardWidth: 46.625, cardHeight: height, boardHeight: 420,
                                    pileCounts: [9, 14, 12, 3, 0, 7, 13, 2])
        #expect(a == b)
    }

    // MARK: - 見出し（③）

    /// 「10」+ マークが札の幅に収まる。拡大モード・帯の広さ・画面幅のどれでも。
    @Test("「10♥」が札の幅に収まる", arguments: phoneWidths)
    func theTenIndexFitsTheCardWidth(_ screenWidth: CGFloat) {
        let available = Self.availableWidth(screenWidth: screenWidth)
        for width in [Metrics.cardWidth(availableWidth: available), Metrics.zoomedCardWidth(availableWidth: available)] {
            let height = Metrics.cardHeight(width: width)
            for boardHeight in stride(from: CGFloat(0), through: 900, by: 30) {
                let index = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: boardHeight,
                                                pileCounts: [9, 7, 7, 7, 6, 6, 6, 4]).index
                #expect(index.estimatedTenWidth <= index.maxWidth,
                        "幅 \(width)pt の札で「10」が収まらない（\(index.estimatedTenWidth)pt > \(index.maxWidth)pt）")
            }
        }
    }

    @Test("見出しの数字は帯に収まり、従来（面の文字の 0.72 倍）より小さくならない", arguments: phoneWidths)
    func theIndexFitsTheBandAndIsLargerThanBefore(_ screenWidth: CGFloat) {
        let width = Metrics.cardWidth(availableWidth: Self.availableWidth(screenWidth: screenWidth))
        let height = Metrics.cardHeight(width: width)
        let old = Metrics.faceMetrics(width: width).rankFont * 0.72
        for boardHeight in stride(from: CGFloat(0), through: 900, by: 30) {
            let stack = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: boardHeight,
                                            pileCounts: [13, 7, 7, 7, 6, 6, 6, 4])
            let index = stack.index
            #expect(index.rankFont >= old.rounded(.down))
            // 数字の下端（行の上端 + ascender）が次の札の手前に収まる。
            let baseline = index.top + index.rankFont * 0.967
            #expect(baseline <= stack.faceUpStep, "数字が次の札の下に潜る（\(baseline)pt > \(stack.faceUpStep)pt）")
        }
    }

    // MARK: - ソース（② 押せる範囲）

    @Test("列の押せる範囲は盤の下端まで伸び、空きを押すと一番下の札を押したことになる")
    func thePileReachesTheBoardBottom() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameFreeCell"))
        let pile = try #require(SourceScan.declaration(of: "private func pileView", in: source))
        #expect(pile.contains("max(height, stack.reachHeight)"), "列の枠が盤の下端まで伸びていない")
        #expect(pile.contains(".onTapGesture { tapBelowPile(pile) }"))
        // 枠を伸ばしたあとでドロップ枠を測る（順序が逆だと下の空きに落とせない）。
        let frame = try #require(pile.range(of: "stack.reachHeight"))
        let drop = try #require(pile.range(of: "cardDropTarget"))
        #expect(frame.lowerBound < drop.lowerBound)

        let tap = try #require(SourceScan.declaration(of: "private func tapBelowPile", in: source))
        #expect(tap.contains("model.tapPile(pile, cardIndex: count - 1)"))
        #expect(tap.contains("model.tapPile(pile)"))
    }

    @Test("盤・ドラッグ中の札・場札は同じ段差を使う")
    func theDragLayerUsesTheBoardStep() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameFreeCell"))
        #expect(!source.contains("FreeCellMetrics.step(cardHeight"), "固定比の段差が View に残っている")
        let overlay = try #require(SourceScan.declaration(of: "@ViewBuilder private func dragOverlay", in: source))
        #expect(overlay.contains("step: stack.faceUpStep"))
    }
}
