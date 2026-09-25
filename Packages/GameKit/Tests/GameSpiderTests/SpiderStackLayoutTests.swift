import Testing
import Foundation
import CoreGraphics
import Core
import GameKitTestSupport
@testable import GameSpider

/// 札が小さすぎて遊びにくい問題の試作（段差を縦の余りに合わせる・列の下の空きも押せる・
/// 帯の見出しを大きく・盤の余白を詰める）。フリーセル（`FreeCellStackLayoutTests`）と対になる。
@Suite("スパイダーの段差と見出し")
struct SpiderStackLayoutTests {

    typealias Metrics = SpiderMetrics

    private static let phoneWidths: [CGFloat] = [375, 393, 402, 430, 440]

    private static func availableWidth(screenWidth: CGFloat) -> CGFloat {
        screenWidth - Metrics.boardSideInset * 2
    }

    private static func pile(down: Int, up: Int) -> SpiderPile {
        let cards = (0..<(down + up)).map { SpiderCard(id: $0, suit: .spade, rank: 13 - ($0 % 13)) }
        return SpiderPile(cards: cards, faceDownCount: down)
    }

    /// 最初の配札（左 4 列が伏せ 5 + 表 1、右 6 列が伏せ 4 + 表 1）。
    private static var initialPiles: [SpiderPile] {
        (0..<4).map { _ in pile(down: 5, up: 1) } + (0..<6).map { _ in pile(down: 4, up: 1) }
    }

    // MARK: - 盤の幅（④）

    @Test("盤の余白は 4pt（フリーセルと同じ）・列の間隔は 2pt")
    func insetsAreTightened() {
        #expect(Metrics.boardSideInset == 4)
        #expect(Metrics.columnGap == 2)
    }

    @Test("どの iPhone でも 10 列目が画面をはみ出さない（iPhone SE を含む）", arguments: phoneWidths)
    func theLastColumnFitsOnScreen(_ screenWidth: CGFloat) {
        let card = Metrics.cardWidth(availableWidth: Self.availableWidth(screenWidth: screenWidth))
        let used = Metrics.boardWidth(cardWidth: card) + Metrics.boardSideInset * 2
        #expect(used <= screenWidth, "盤が画面をはみ出している（\(used)pt > \(screenWidth)pt）")
        #expect(card > Metrics.minCardWidth, "下限に張り付いていると計算上だけ収まっている可能性がある")
    }

    // MARK: - 段差（①）

    static let measured: [(screen: CGFloat, width: CGFloat, height: CGFloat,
                           minUp: CGFloat, maxUp: CGFloat, minDown: CGFloat, maxDown: CGFloat, font: CGFloat)] = [
        (375, 34.9, 49, 12, 22, 6, 11, 15),
        (402, 37.6, 53, 13, 23, 7, 12, 16),
    ]

    @Test("iPhone SE と iPhone 17 の寸法", arguments: measured)
    func measuredValues(_ row: (screen: CGFloat, width: CGFloat, height: CGFloat,
                                minUp: CGFloat, maxUp: CGFloat, minDown: CGFloat, maxDown: CGFloat, font: CGFloat)) {
        let width = Metrics.cardWidth(availableWidth: Self.availableWidth(screenWidth: row.screen))
        let height = Metrics.cardHeight(width: width)
        #expect(abs(width - row.width) < 0.0001)
        #expect(height == row.height)
        let tight = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: 0,
                                        piles: [Self.pile(down: 5, up: 20)])
        let roomy = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: 5000,
                                        piles: Self.initialPiles)
        #expect(tight.faceUpStep == row.minUp)
        #expect(tight.faceDownStep == row.minDown)
        #expect(roomy.faceUpStep == row.maxUp)
        #expect(roomy.faceDownStep == row.maxDown)
        #expect(roomy.index.rankFont == row.font)
    }

    @Test("下限は従来の固定比（表向き 0.24・伏せ札 0.13）", arguments: [CGFloat(0), 120, 200])
    func theStepNeverShrinksBelowTheOldRatio(_ boardHeight: CGFloat) {
        let height = Metrics.cardHeight(width: 37.6)
        let stack = Metrics.stackLayout(cardWidth: 37.6, cardHeight: height, boardHeight: boardHeight,
                                        piles: [Self.pile(down: 5, up: 18)] + Self.initialPiles)
        #expect(stack.faceUpStep == (height * 0.24).rounded())
        #expect(stack.faceDownStep == (height * 0.13).rounded())
    }

    @Test("伏せ札の段差は表向きより狭いまま", arguments: [CGFloat(0), 250, 330, 400, 500, 2000])
    func faceDownStaysNarrower(_ boardHeight: CGFloat) {
        for width in [CGFloat(34.9), 37.6, 50.7, 54.6] {
            let height = Metrics.cardHeight(width: width)
            for up in [1, 6, 12, 20] {
                let stack = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: boardHeight,
                                                piles: [Self.pile(down: 4, up: up)])
                #expect(stack.faceDownStep < stack.faceUpStep)
            }
        }
    }

    @Test("いちばん長い列が盤の下端に収まる", arguments: [CGFloat(330), 380, 420, 480])
    func theLongestColumnFitsTheBoard(_ boardHeight: CGFloat) {
        let width: CGFloat = 37.6
        let height = Metrics.cardHeight(width: width)
        let tableau = Metrics.tableauHeight(boardHeight: boardHeight, cardHeight: height)
        for (down, up) in [(5, 1), (4, 6), (3, 12), (2, 18), (0, 24)] {
            let piles = [Self.pile(down: down, up: up)] + Self.initialPiles
            let stack = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: boardHeight, piles: piles)
            let column = Metrics.pileHeight(faceDownCount: down, faceUpCount: up, cardHeight: height,
                                            faceDownStep: stack.faceDownStep, faceUpStep: stack.faceUpStep)
            let atFloor = stack.faceUpStep == Metrics.faceUpStep(cardHeight: height)
                || stack.faceDownStep == Metrics.faceDownStep(cardHeight: height)
            if !atFloor {
                #expect(column <= tableau - CardStackLayout.bottomMargin,
                        "伏せ \(down) + 表 \(up) の列が盤の下端をはみ出している（\(column)pt > \(tableau)pt）")
            }
            #expect(stack.reachHeight == tableau)
        }
    }

    // MARK: - 見出し（③）

    @Test("「10♥」が札の幅に収まる（拡大モードも）", arguments: phoneWidths)
    func theTenIndexFitsTheCardWidth(_ screenWidth: CGFloat) {
        let available = Self.availableWidth(screenWidth: screenWidth)
        for width in [Metrics.cardWidth(availableWidth: available), Metrics.zoomedCardWidth(availableWidth: available)] {
            let height = Metrics.cardHeight(width: width)
            for boardHeight in stride(from: CGFloat(0), through: 900, by: 30) {
                let index = Metrics.stackLayout(cardWidth: width, cardHeight: height, boardHeight: boardHeight,
                                                piles: Self.initialPiles).index
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
                                            piles: [Self.pile(down: 3, up: 14)] + Self.initialPiles)
            let index = stack.index
            #expect(index.rankFont >= old.rounded(.down))
            let baseline = index.top + index.rankFont * 0.967
            #expect(baseline <= stack.faceUpStep, "数字が次の札の下に潜る（\(baseline)pt > \(stack.faceUpStep)pt）")
        }
    }

    /// 見出しは札の幅と帯（表向きの段差）だけで決まる共通の計算を通す。フリーセルも同じ関数なので、
    /// 同じ幅・同じ帯なら 1pt も違わない（同じ役割の UI は同じ見た目）。
    @Test("見出しは札の幅と帯だけで決まる共通の計算を通す")
    func theIndexComesFromTheSharedCalculation() {
        for boardHeight in [CGFloat(0), 300, 420, 5000] {
            let stack = Metrics.stackLayout(cardWidth: 37.6, cardHeight: 53, boardHeight: boardHeight,
                                            piles: [Self.pile(down: 2, up: 9)] + Self.initialPiles)
            #expect(stack.index == CardStackIndexMetrics.make(cardWidth: 37.6, faceUpStep: stack.faceUpStep))
        }
    }

    // MARK: - ソース（② 押せる範囲）

    @Test("列の押せる範囲は盤の下端まで伸び、空きを押すと一番下の札を押したことになる")
    func thePileReachesTheBoardBottom() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameSpider"))
        let pile = try #require(SourceScan.declaration(of: "private func pileView", in: source))
        #expect(pile.contains("max(height, stack.reachHeight)"), "列の枠が盤の下端まで伸びていない")
        #expect(pile.contains(".onTapGesture { tapBelowPile(pile) }"))
        let frame = try #require(pile.range(of: "stack.reachHeight"))
        let drop = try #require(pile.range(of: "cardDropTarget"))
        #expect(frame.lowerBound < drop.lowerBound)

        let tap = try #require(SourceScan.declaration(of: "private func tapBelowPile", in: source))
        #expect(tap.contains("model.tapPile(pile, cardIndex: count - 1)"))
        #expect(tap.contains("model.tapPile(pile)"))
    }

    @Test("盤・ドラッグ中の札・場札は同じ段差を使う")
    func theDragLayerUsesTheBoardStep() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameSpider"))
        #expect(!source.contains("SpiderMetrics.faceUpStep(cardHeight"), "固定比の段差が View に残っている")
        #expect(!source.contains("SpiderMetrics.faceDownStep(cardHeight"), "固定比の段差が View に残っている")
        let overlay = try #require(SourceScan.declaration(of: "@ViewBuilder private func dragOverlay", in: source))
        #expect(overlay.contains("step: stack.faceUpStep"))
    }
}
