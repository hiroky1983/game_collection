import Testing
import Foundation
import SwiftUI
import Core
@testable import GamePoker
import CoreTestSupport

private final class NoopAdService: AdService, @unchecked Sendable {
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { true }
}

/// 2 巡目のベッティング。CPU はツーペア（チェックされると 20 ベットする）。
@MainActor
private func makeModel() -> PokerModel {
    var nextCardID = 0
    func c(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
        defer { nextCardID += 1 }
        return PokerCard(id: nextCardID, suit: suit, rank: rank)
    }
    let store = MemorySnapshotStore()
    let snap = PokerSnapshot(
        playerHand: [c(11, .spades), c(9, .diamonds), c(8, .clubs), c(4, .spades), c(2, .hearts)],
        cpuHand: [c(14, .hearts), c(14, .clubs), c(7, .diamonds), c(7, .clubs), c(3, .spades)],
        deck: [],
        playerChips: 100, cpuChips: 100, pot: 40,
        phase: .betting2, currentBet: 0,
        playerBetInRound: 0, cpuBetInRound: 0,
        cpuFolded: false, cpuAction: "", rules: .standard,
        handStartChips: 110
    )
    try? store.save(snap, for: "poker")
    return PokerModel(services: GameServices(snapshots: store, ads: NoopAdService()))
}

@Suite("ポーカー 2 巡目: CPU のベット後は check/bet を受けない（#2448）")
@MainActor
struct PokerBet2GuardTests {

    @Test("CPU のベット後の check は何も変えない")
    func checkIgnoredAfterCPUBet() {
        let model = makeModel()
        model.bet2Action(.check)
        #expect(model.currentBet > 0)
        #expect(model.phase == .betting2)
        let pot = model.pot, cpuChips = model.cpuChips, playerChips = model.playerChips
        let cpuBet = model.cpuBetInRound, current = model.currentBet

        model.bet2Action(.check)

        #expect(model.pot == pot)
        #expect(model.cpuChips == cpuChips)
        #expect(model.playerChips == playerChips)
        #expect(model.cpuBetInRound == cpuBet)
        #expect(model.currentBet == current)
        #expect(model.phase == .betting2)
    }

    @Test("CPU のベット後の bet も何も変えない")
    func betIgnoredAfterCPUBet() {
        let model = makeModel()
        model.bet2Action(.check)
        let pot = model.pot, cpuChips = model.cpuChips, playerChips = model.playerChips
        let cpuBet = model.cpuBetInRound, playerBet = model.playerBetInRound

        model.bet2Action(.bet(20))

        #expect(model.pot == pot)
        #expect(model.cpuChips == cpuChips)
        #expect(model.playerChips == playerChips)
        #expect(model.cpuBetInRound == cpuBet)
        #expect(model.playerBetInRound == playerBet)
        #expect(model.phase == .betting2)
    }

    @Test("CPU のベット後でもフォールドは有効")
    func foldStillWorks() {
        let model = makeModel()
        model.bet2Action(.check)
        model.bet2Action(.fold)
        #expect(model.phase != .betting2)
        #expect(model.pot == 0)
    }
}
