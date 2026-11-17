import Foundation
import Testing
import Core

/// 狭い画面でヘッダー右のボタンを「…」にまとめる判定（#3475）。
@Suite("ヘッダーの「…」へのまとめ判定")
struct GameChromeHeaderCollapseTests {
    typealias Metrics = GameChromeHeaderMetrics

    @Test("題字が 0.6 倍まで縮んでも入らないときだけまとめる")
    func collapsesOnlyWhenTitleCannotFitAtMinScale() {
        // 利用できる幅 = 375 - 44(戻る) - 3*56(ボタン) - 60 = 103。0.6 倍して 103 を超える題字 = 本来の幅 > 171.67
        #expect(Metrics.shouldCollapse(titleWidth: 172, screenWidth: 375, buttonCount: 3))
        #expect(!Metrics.shouldCollapse(titleWidth: 171, screenWidth: 375, buttonCount: 3))
    }

    @Test("同じ題字でも広い画面では並べたまま")
    func staysWideOnLargerScreen() {
        #expect(Metrics.shouldCollapse(titleWidth: 190, screenWidth: 375, buttonCount: 3))
        #expect(!Metrics.shouldCollapse(titleWidth: 190, screenWidth: 393, buttonCount: 3))
    }

    @Test("ボタンが多いほどまとまりやすい")
    func moreButtonsCollapseSooner() {
        #expect(!Metrics.shouldCollapse(titleWidth: 150, screenWidth: 375, buttonCount: 2))
        #expect(Metrics.shouldCollapse(titleWidth: 150, screenWidth: 375, buttonCount: 4))
    }

    @Test("ボタンが 1 つ以下ならまとめない（「…」にしても幅は減らない）")
    func neverCollapsesSingleButton() {
        #expect(!Metrics.shouldCollapse(titleWidth: 10_000, screenWidth: 375, buttonCount: 1))
        #expect(!Metrics.shouldCollapse(titleWidth: 10_000, screenWidth: 375, buttonCount: 0))
    }

    @Test("戻るが無ければそのぶん広く使える")
    func noBackButtonGivesMoreRoom() {
        #expect(Metrics.shouldCollapse(titleWidth: 200, screenWidth: 375, buttonCount: 3, hasBackButton: true))
        #expect(!Metrics.shouldCollapse(titleWidth: 200, screenWidth: 375, buttonCount: 3, hasBackButton: false))
    }

    @Test("特大文字（xxl）・SE（375pt）: 題字 150pt はボタン 3 つだと「…」にまとめる（#3495・#3530）")
    func collapsesOnExtraLargeTextSE() {
        // xxl の拡大率は約 1.235。実測でボタン 3 つのカプセルは 188pt、題字の枠は約 83pt（SE・iOS 26.5）。
        #expect(!Metrics.shouldCollapse(titleWidth: 150, screenWidth: 375, buttonCount: 3))
        #expect(Metrics.shouldCollapse(titleWidth: 150, screenWidth: 375, buttonCount: 3, buttonScale: 1.235))
    }

    @Test("ボタンの幅は標準 56pt・xxl で実測の 62.7pt に合う（iOS 26 のカプセル）")
    func buttonsWidthMatchesMeasurement() {
        #expect(abs(Metrics.buttonsWidth(count: 3, scale: 1) - 168) < 0.5)
        #expect(abs(Metrics.buttonsWidth(count: 3, scale: 1.235) - 188) < 1)
        #expect(Metrics.buttonsWidth(count: 3, scale: 0.5) == Metrics.buttonsWidth(count: 3, scale: 1))
    }

    @Test("標準サイズ（拡大率 1 以下）では判定が変わらない")
    func standardScaleUnchanged() {
        #expect(Metrics.shouldCollapse(titleWidth: 172, screenWidth: 375, buttonCount: 3, buttonScale: 1))
        #expect(Metrics.shouldCollapse(titleWidth: 172, screenWidth: 375, buttonCount: 3, buttonScale: 0.5))
        #expect(!Metrics.shouldCollapse(titleWidth: 190, screenWidth: 393, buttonCount: 3, buttonScale: 1))
    }
}
