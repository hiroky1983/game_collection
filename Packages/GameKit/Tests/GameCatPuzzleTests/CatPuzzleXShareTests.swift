import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// 鍵の面を初めてクリアした結果画面の「X でポストして特典をもらう」（#3359）。
@Suite("おじさんちのねこさがしの X ポスト特典（#3359）")
@MainActor
struct CatPuzzleXShareTests {
    private func make(stage: Int, savedStage: Int? = nil, claimed: Bool = false)
        -> (model: CatPuzzleModel, spy: SpyAnalyticsService, defaults: UserDefaults) {
        let suite = "asobiba.catpuzzle.xshare.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if let savedStage { defaults.set(savedStage, forKey: CatPuzzleModel.stageProgressKey) }
        if claimed { XShareReward.markClaimed(defaults, gameID: CatPuzzleModel.gameID) }
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: [CatPuzzleModel.gameID]))
        let info = CatPuzzleStage(stage)
        let model = CatPuzzleModel(services: services, puzzle: info.makePuzzle(), size: info.size, stage: stage,
                                   stageDefaults: defaults)
        return (model, spy, defaults)
    }

    private func solve(_ model: CatPuzzleModel) {
        // 鍵の面は鍵の猫を先に見つけるまで他を置けない。
        if let key = model.keyCat { model.findCat(cell: key) }
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
    }

    @Test("鍵の面を初めてクリアすると提案が出る。鍵でない面・クリア済みの面・受け取り済みでは出ない")
    func eligibility() {
        let key = make(stage: 10, savedStage: 10)
        solve(key.model)
        #expect(key.model.xShareOfferEligible)
        #expect(key.model.xShareOffer() != nil)

        let plain = make(stage: 9, savedStage: 9)
        solve(plain.model)
        #expect(!plain.model.xShareOfferEligible)
        #expect(plain.model.xShareOffer() == nil)

        let cleared = make(stage: 10, savedStage: 15)
        solve(cleared.model)
        #expect(!cleared.model.xShareOfferEligible)

        let claimed = make(stage: 10, savedStage: 10, claimed: true)
        solve(claimed.model)
        #expect(!claimed.model.xShareOfferEligible)
    }

    @Test("ポストしたと見なせたら ヒント+2・餌+2 を足し、reward_grant(purpose=share) を 1 回だけ送る。2 回目は渡さない")
    func grantsOnce() throws {
        let (model, spy, defaults) = make(stage: 10, savedStage: 10)
        solve(model)
        let hints = model.stageHintsLeft, teaches = model.stageTeachLeft
        let offer = try #require(model.xShareOffer())
        offer.onPosted()
        #expect(model.stageHintsLeft == hints + 2)
        #expect(model.stageTeachLeft == teaches + 2)
        #expect(model.xShareGranted)
        #expect(XShareReward.isClaimed(defaults, gameID: CatPuzzleModel.gameID))
        offer.onPosted()
        #expect(model.stageHintsLeft == hints + 2)
        let grants = spy.events.filter { $0.name == "reward_grant" }
        #expect(grants.count == 1)
        #expect(grants.first?.parameters == [
            "game_id": .string("catpuzzle"), "items": .string("hint_teach"), "purpose": .string("share"),
        ])
    }

    @Test("ポストしなければ何も渡さず受け取り済みにもならない。表示・押下は share_tap(offer) で送る")
    func notPostedGrantsNothing() throws {
        let (model, spy, defaults) = make(stage: 10, savedStage: 10)
        solve(model)
        let hints = model.stageHintsLeft
        let offer = try #require(model.xShareOffer())
        offer.onShown()
        offer.onTap()
        #expect(model.stageHintsLeft == hints)
        #expect(!XShareReward.isClaimed(defaults, gameID: CatPuzzleModel.gameID))
        let taps = spy.events.filter { $0.name == "share_tap" }.map(\.parameters)
        #expect(taps == [
            ["game_id": .string("catpuzzle"), "offer": .string("shown")],
            ["game_id": .string("catpuzzle"), "offer": .string("tap")],
        ])
    }

    @Test("閉じて次の鍵の面を初めてクリアしたら、また提案が出る")
    func offeredAgainOnNextKeyStage() {
        let first = make(stage: 10, savedStage: 10)
        solve(first.model)
        #expect(first.model.xShareOfferEligible)
        let next = make(stage: 20, savedStage: 20)
        solve(next.model)
        #expect(next.model.xShareOfferEligible)
    }
}
