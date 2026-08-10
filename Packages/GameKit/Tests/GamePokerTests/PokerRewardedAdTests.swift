import Testing
import Foundation
import SwiftUI
import Core
@testable import GamePoker

// MARK: - Mocks

private final class MockSnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]

    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// 視聴完了・未完了を制御できる広告スタブ。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    private(set) var interstitialCount = 0

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView() -> AnyView? { nil }
    @MainActor func showInterstitial() async { interstitialCount += 1 }
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        return rewardEarned
    }
}

/// アンティを引かせて「チップが初期値から減った」状態を作る。
@MainActor
private func makeStartedModel(rewardEarned: Bool) -> (PokerModel, StubAdService) {
    let ads = StubAdService(rewardEarned: rewardEarned)
    let services = GameServices(snapshots: MockSnapshotStore(), ads: ads)
    let model = PokerModel(services: services)
    model.startGame()
    return (model, ads)
}

// MARK: - Tests

@Suite("チップ回復のリワード広告")
@MainActor
struct PokerRewardedAdTests {

    @Test("視聴完了ならチップが回復する")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads) = makeStartedModel(rewardEarned: true)
        #expect(model.playerChips == 90, "アンティ10が引かれた状態から始める")

        let recovered = await model.recoverChipsAfterAd()

        #expect(recovered)
        #expect(model.playerChips == 100)
        #expect(model.cpuChips == 100)
        #expect(!model.sessionOver)
        #expect(model.sessionWinner == nil)
        #expect(ads.rewardedCount == 1)
    }

    @Test("視聴未完了・ロード失敗ならチップは回復しない")
    func doesNotRecoverChipsWhenRewardNotEarned() async {
        let (model, ads) = makeStartedModel(rewardEarned: false)
        let playerBefore = model.playerChips
        let cpuBefore = model.cpuChips

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.playerChips == playerBefore, "報酬なしなのでチップは1枚も増えない")
        #expect(model.cpuChips == cpuBefore)
        #expect(ads.rewardedCount == 1)
    }

    @Test("報酬付きの回復にインタースティシャルは使わない")
    func doesNotUseInterstitialForReward() async {
        let (model, ads) = makeStartedModel(rewardEarned: true)

        _ = await model.recoverChipsAfterAd()

        #expect(ads.interstitialCount == 0)
    }
}
