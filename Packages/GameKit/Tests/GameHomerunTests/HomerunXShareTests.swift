import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
import HomerunCore
@testable import GameHomerun

/// 合計飛距離 1,000m 以上の結果画面の「X でポストして特典をもらう」（#3359）。
@Suite("柵越えおじさんの X ポスト特典（#3359）")
@MainActor
struct HomerunXShareTests {
    private func make(claimed: Bool = false) -> (model: HomerunModel, spy: SpyAnalyticsService, defaults: UserDefaults) {
        let suite = "asobiba.homerun.xshare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if claimed { XShareReward.markClaimed(defaults, gameID: HomerunModel.gameID) }
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: [HomerunModel.gameID]))
        return (HomerunModel(services: services, defaults: defaults), spy, defaults)
    }

    @Test("ポストしたと見なせたらその日のプレイ回数が +1。reward_grant(purpose=share) は 1 回だけで、2 回目は渡さない")
    func grantsOnce() {
        let (model, spy, defaults) = make()
        model.xShareOfferEligible = true
        let before = model.ledger.allowance
        model.grantXShareReward()
        #expect(model.ledger.allowance == before + 1)
        #expect(model.xShareGranted)
        #expect(XShareReward.isClaimed(defaults, gameID: HomerunModel.gameID))
        model.grantXShareReward()
        #expect(model.ledger.allowance == before + 1)
        let grants = spy.events.filter { $0.name == "reward_grant" }
        #expect(grants.count == 1)
        #expect(grants.first?.parameters == [
            "game_id": .string("homerun"), "items": .string("challenge"), "purpose": .string("share"),
        ])
    }

    @Test("提案の対象でないとき（基準未満・受け取り済み）は渡さない")
    func noGrantWhenNotEligible() {
        let (model, spy, _) = make()
        let before = model.ledger.allowance
        model.grantXShareReward()
        #expect(model.ledger.allowance == before)
        #expect(model.xShareOffer() == nil)
        #expect(spy.events.filter { $0.name == "reward_grant" }.isEmpty)

        let (claimed, _, _) = make(claimed: true)
        claimed.updateXShareEligibility(for: HomerunChallenge(pitches: HomerunPitch.standardSequence))
        #expect(!claimed.xShareOfferEligible)
    }

    @Test("基準は合計 1,000m 以上")
    func threshold() {
        #expect(HomerunXShare.thresholdMeters == 1000)
        let (model, _, _) = make()
        model.updateXShareEligibility(for: HomerunChallenge(pitches: HomerunPitch.standardSequence))
        #expect(!model.xShareOfferEligible)  // 0m
    }
}
