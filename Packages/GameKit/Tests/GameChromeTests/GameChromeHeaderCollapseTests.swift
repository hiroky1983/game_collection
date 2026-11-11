import Foundation
import Testing
import Core

/// 狭い画面でヘッダー右のボタンを「…」にまとめる判定（#3475）。
@Suite("ヘッダーの「…」へのまとめ判定")
struct GameChromeHeaderCollapseTests {
    typealias Metrics = GameChromeHeaderMetrics

    @Test("題字が 0.6 倍まで縮んでも入らないときだけまとめる")
    func collapsesOnlyWhenTitleCannotFitAtMinScale() {
        // 利用できる幅 = 375 - 44(戻る) - 3*44 - 32 = 167。0.6 倍して 167 を超える題字 = 本来の幅 > 278.3
        #expect(Metrics.shouldCollapse(titleWidth: 280, screenWidth: 375, buttonCount: 3))
        #expect(!Metrics.shouldCollapse(titleWidth: 278, screenWidth: 375, buttonCount: 3))
    }

    @Test("同じ題字でも広い画面では並べたまま")
    func staysWideOnLargerScreen() {
        #expect(Metrics.shouldCollapse(titleWidth: 300, screenWidth: 375, buttonCount: 3))
        #expect(!Metrics.shouldCollapse(titleWidth: 300, screenWidth: 393, buttonCount: 3))
    }

    @Test("ボタンが多いほどまとまりやすい")
    func moreButtonsCollapseSooner() {
        #expect(!Metrics.shouldCollapse(titleWidth: 250, screenWidth: 375, buttonCount: 2))
        #expect(Metrics.shouldCollapse(titleWidth: 250, screenWidth: 375, buttonCount: 4))
    }

    @Test("ボタンが 1 つ以下ならまとめない（「…」にしても幅は減らない）")
    func neverCollapsesSingleButton() {
        #expect(!Metrics.shouldCollapse(titleWidth: 10_000, screenWidth: 375, buttonCount: 1))
        #expect(!Metrics.shouldCollapse(titleWidth: 10_000, screenWidth: 375, buttonCount: 0))
    }

    @Test("戻るが無ければそのぶん広く使える")
    func noBackButtonGivesMoreRoom() {
        #expect(Metrics.shouldCollapse(titleWidth: 280, screenWidth: 375, buttonCount: 3, hasBackButton: true))
        #expect(!Metrics.shouldCollapse(titleWidth: 280, screenWidth: 375, buttonCount: 3, hasBackButton: false))
    }
}
