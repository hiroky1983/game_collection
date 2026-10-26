import Testing
import CoreGraphics
import Core
@testable import GameHearts
import GameKitTestSupport

/// レイアウトパターン A（全画面・#2531）の寸法。会長 QA（2026-10-23）「ハーツも全画面、卓 UI に」。
@Suite("ハーツのレイアウトパターン A")
struct HeartsLayoutTests {
    private static let seContentHeight = FullScreenGameLayoutMetrics.contentHeight(
        screenHeight: 667, safeAreaTop: 20, safeAreaBottom: 0)

    @Test("手札の札は列幅 − 4pt まで大きくなり、タップ判定は列いっぱい（SE で 44pt 以上）")
    func cardsFillTheColumn() {
        for width: CGFloat in [375, 402, 440] {
            let m = HeartsLayoutA.metrics(screenWidth: width)
            #expect(abs(m.handCard.width - (HeartsLayoutA.columnWidth(screenWidth: width) - HeartsLayoutA.handGap)) < 0.01)
        }
        #expect(HeartsHandLayout.tapWidth(screenWidth: 375) >= HeartsHandLayout.minimumTapTarget)
        #expect(HeartsLayoutA.cardScale(screenWidth: 1024, elementScale: 1.3) <= HeartsLayoutA.maxCardScale * 1.3)
    }

    @Test("初回のミニガイドが出ていても SE の高さに収まる（場は下限の大きさ）")
    func fitsOnSE() {
        #expect(HeartsLayoutA.estimatedMinimumHeight(screenWidth: 375) <= Self.seContentHeight)
    }

    @Test("場の札は手札と同じ大きさまでで、高さが足りなければ縮める（下限あり）")
    func trickCardFitsHeight() {
        let hand = HeartsLayoutA.metrics(screenWidth: 402).handCard
        #expect(HeartsLayoutA.trickCard(hand: hand, height: 1000) == hand)
        let tight = HeartsLayoutA.trickCard(hand: hand, height: 130)
        #expect(tight.height * HeartsLayoutA.trickHeightRatio <= 130.5)
        #expect(HeartsLayoutA.trickCard(hand: hand, height: 10).height >= HeartsLayoutA.minTrickCardHeight - 0.01)
    }

    @Test("CPU の席は大富豪・いろリレーと同じ共通部品（OpponentSeat）。出せない札はフェルト用の沈め方")
    func seatsUseSharedParts() throws {
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHearts/HeartsView.swift"))
        #expect(code.contains("OpponentSeat(") && code.contains("OpponentCardFan("))
        #expect(code.contains(".tableDimmed(isDimmed"))
        #expect(!code.contains(".padding(Theme.pad)"), "A の左右の余白（8pt）ではなく 16pt のまま")
    }
}
