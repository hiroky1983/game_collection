import Testing
import Foundation
import GameKitTestSupport

@Suite("柵越えおじさんの打席のナビバー")
struct HomerunAtBatNavBarTests {
    @Test("打席はナビバーの背景を隠す（結果画面のスクロール後に共通色が残らない・#1789）")
    func atBatHidesNavigationBarBackground() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunAtBatView.swift"))
        #expect(SourceScan.matchCount(of: #"\.gameNavigationBarBackgroundHidden\(\)"#, in: source) == 1)
    }
}
