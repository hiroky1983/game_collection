import Testing
import CoreGraphics
import Core
@testable import GameOldMaid
import GameKitTestSupport

/// レイアウトパターン A（全画面・#2531）の寸法。会長 QA（2026-10-23）「ババ抜きも全画面、卓 UI に」。
@Suite("ババ抜きのレイアウトパターン A")
struct OldMaidLayoutTests {
    private static let seContentHeight = FullScreenGameLayoutMetrics.contentHeight(
        screenHeight: 667, safeAreaTop: 20, safeAreaBottom: 0)

    @Test("札は列幅 − 4pt まで大きくなり、タップ判定は列いっぱい（SE で 44pt 以上）")
    func cardsFillTheColumn() {
        for width: CGFloat in [375, 402, 440] {
            let m = OldMaidLayoutA.metrics(screenWidth: width)
            #expect(abs(m.card.width - (OldMaidLayoutA.columnWidth(screenWidth: width) - OldMaidLayoutA.handGap)) < 0.01)
            #expect(m.card.width > PlayingCardMetrics.compact.width, "A にしても札が以前（42pt）より大きくならない")
        }
        #expect(OldMaidHandLayout.tapWidth(screenWidth: 375) >= OldMaidHandLayout.minimumTapTarget)
        // iPad では列幅のまま広げず、上限（1.5 × elementScale）で止める。
        #expect(OldMaidLayoutA.cardScale(screenWidth: 1024, elementScale: 1.3) <= OldMaidLayoutA.maxCardScale * 1.3)
    }

    @Test("伏せ札・手札とも 2 段（crowded）でも、1 段ずつに縮めれば SE の高さに収まる（#2685 の再発防止）")
    func crowdedFitsOnSE() {
        #expect(Self.seContentHeight == 537)
        #expect(OldMaidLayoutA.estimatedMinimumHeight(screenWidth: 375, contentHeight: Self.seContentHeight)
                <= Self.seContentHeight + 0.01)
        // SE でも札は以前（42pt）より小さくしない。
        #expect(OldMaidLayoutA.metrics(screenWidth: 375, contentHeight: Self.seContentHeight).card.width
                >= PlayingCardMetrics.compact.width)
    }

    @Test("iPhone 17 は高さに余裕があるので、札は幅いっぱいのまま（高さで抑えない）")
    func iPhone17KeepsWidthScale() {
        let height = FullScreenGameLayoutMetrics.contentHeight(screenHeight: 874, safeAreaTop: 62, safeAreaBottom: 34)
        #expect(OldMaidLayoutA.metrics(screenWidth: 402, contentHeight: height) == OldMaidLayoutA.metrics(screenWidth: 402))
        #expect(OldMaidLayoutA.estimatedMinimumHeight(screenWidth: 402, contentHeight: height) <= height)
    }

    @Test("縮むのは伏せ札・手札とも 1 段ぶんまで（下限を残し、上限は全段ぶん）")
    func scrollAreasKeepOneRow() throws {
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameOldMaid/OldMaidView.swift"))
        #expect(code.contains("minHeight: targetGridHeight(rows: 1, metrics)"))
        #expect(code.contains("minHeight: handGridHeight(rows: 1, metrics)"))
        #expect(code.contains(".layoutPriority(2)") && code.contains(".layoutPriority(1)"),
                "伏せ札 → 手札 の順に高さを取る優先度が無い")
        #expect(OldMaidHandLayout.rows(0) == 1 && OldMaidHandLayout.rows(7) == 1 && OldMaidHandLayout.rows(8) == 2
                && OldMaidHandLayout.rows(14) == 2)
    }

    @Test("CPU の席は大富豪・いろリレーと同じ共通部品（OpponentSeat）で、左右は全画面の枠の余白")
    func seatsUseSharedParts() throws {
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameOldMaid/OldMaidView.swift"))
        #expect(code.contains("OpponentSeat(") && code.contains("OpponentCardFan("))
        #expect(code.contains("FullScreenGameLayoutMetrics.sideInset"))
        #expect(!code.contains(".padding(Theme.pad)"), "A の左右の余白（8pt）ではなく 16pt のまま")
    }
}
