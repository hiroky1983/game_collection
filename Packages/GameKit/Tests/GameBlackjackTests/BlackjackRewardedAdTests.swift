import Testing
import Foundation
import SwiftUI
import Core
@testable import GameBlackjack

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

@MainActor
private func makeModel(rewardEarned: Bool) -> (BlackjackModel, StubAdService) {
    let ads = StubAdService(rewardEarned: rewardEarned)
    let services = GameServices(snapshots: MockSnapshotStore(), ads: ads)
    return (BlackjackModel(services: services), ads)
}

// MARK: - Tests

@Suite("チップ回復のリワード広告")
@MainActor
struct BlackjackRewardedAdTests {

    @Test("視聴完了ならチップが回復する")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads) = makeModel(rewardEarned: true)

        let recovered = await model.recoverChipsAfterAd()

        #expect(recovered)
        #expect(model.chips == 500)
        #expect(!model.sessionOver)
        #expect(model.phase == .betting)
        #expect(ads.rewardedCount == 1)
    }

    @Test("視聴未完了・ロード失敗ならチップは回復しない")
    func doesNotRecoverChipsWhenRewardNotEarned() async {
        let (model, ads) = makeModel(rewardEarned: false)
        let chipsBefore = model.chips

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.chips == chipsBefore, "報酬なしなのでチップは1枚も増えない")
        #expect(ads.rewardedCount == 1)
    }

    @Test("報酬付きの回復にインタースティシャルは使わない")
    func doesNotUseInterstitialForReward() async {
        let (model, ads) = makeModel(rewardEarned: true)

        _ = await model.recoverChipsAfterAd()

        #expect(ads.interstitialCount == 0)
    }
}
