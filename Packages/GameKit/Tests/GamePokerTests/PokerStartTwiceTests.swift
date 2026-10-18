import Testing
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GamePoker

private final class NoopAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

/// 局の開始が連続で 2 回届いても 1 回ぶんのまま（#2416）。`startingTwiceIsIgnored`（ダブルアップ）と同じ型。
@MainActor
@Suite("ポーカー 局の開始の連打（#2416）")
struct PokerStartTwiceTests {

    private func makeModel() -> (PokerModel, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["poker"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        return (PokerModel(services: services), spy)
    }

    @Test("開始を連続で 2 回呼んでも、チップ・ポット・手札・game_start は 1 回ぶん")
    func startingTwiceIsIgnored() {
        let (model, spy) = makeModel()
        model.startGame()
        let chips = model.playerChips
        let cpuChips = model.cpuChips
        let pot = model.pot
        let hand = model.playerHand
        let starts = spy.starts.count
        #expect(starts == 1)
        #expect(chips + cpuChips + pot == PokerModel.initialChips * 2)

        model.startGame()               // 連打
        #expect(model.playerChips == chips, "アンティが二重に引かれない")
        #expect(model.cpuChips == cpuChips)
        #expect(model.pot == pot, "1 回目のアンティがポットから消えない")
        #expect(model.playerHand == hand, "配り直されない")
        #expect(model.phase == .betting1)
        #expect(spy.starts.count == starts, "game_start が二重に数えられない")
    }

    @Test("局が終わった後の「次のゲーム」は通常どおり始まる")
    func nextRoundStillStarts() {
        // 2 巡目のベッティングを中断データとして注入し、チェックで決着させる。
        var id = 0
        func c(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
            defer { id += 1 }
            return PokerCard(id: id, suit: suit, rank: rank)
        }
        let store = MemorySnapshotStore()
        try? store.save(PokerSnapshot(
            playerHand: [c(11, .spades), c(11, .diamonds), c(8, .clubs), c(4, .spades), c(2, .hearts)],
            cpuHand: [c(14, .hearts), c(10, .clubs), c(7, .diamonds), c(5, .clubs), c(3, .spades)],
            deck: [],
            playerChips: 100, cpuChips: 100, pot: 40,
            phase: .betting2, currentBet: 0,
            playerBetInRound: 0, cpuBetInRound: 0,
            cpuFolded: false, cpuAction: "", rules: .standard
        ), for: "poker")
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["poker"])
        let model = PokerModel(services: GameServices(snapshots: store, ads: NoopAdService(), analytics: analytics))
        model.bet2Action(.check)
        #expect(model.phase == .result)
        model.startGame()
        #expect(model.phase == .betting1)
        #expect(spy.starts.count == 1)
    }
}
