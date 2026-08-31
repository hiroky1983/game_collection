import Testing
import Foundation
import SwiftUI
import Core
import MahjongTiles
@testable import GameMahjong

// MARK: - Mocks

private final class MemoryStore: SnapshotStore, @unchecked Sendable {
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

/// 視聴完了・未完了を制御できる広告スタブ（ポーカーの `PokerRewardedAdTests` と同じ形）。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    private(set) var interstitialCount = 0

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async { interstitialCount += 1 }
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        return rewardEarned
    }
}

/// 何を切っても和了に絡まない手（`MahjongModelTests` の `junkHand` と同じ意図）。
/// 全員に配れば流局しても聴牌者ゼロ = 点棒が動かないので、狙った持ち点のまま終局させられる。
@MainActor
private func junkHand() -> MahjongHand { MahjongNotation.hand("159m159p159s1234z") }

/// 記録（`PlayLog`）の増え方を見るための、テストごとに独立した UserDefaults。
@MainActor
private func makeIsolatedPlayLog() -> (PlayLog, UserDefaults, String) {
    let name = "mahjong.revive.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (PlayLog(defaults: defaults), defaults, name)
}

/// 指定した持ち点で流局させ、東風戦を終局まで進める。
@MainActor
private func concludeGame(
    _ model: MahjongModel, scores: [Int], dealer: Int = 0, roundNumber: Int = 1
) {
    model.configureForTesting(
        hands: Array(repeating: junkHand(), count: MahjongModel.playerCount),
        wall: [],
        dealer: dealer,
        scores: scores,
        roundNumber: roundNumber
    )
    model.exhaustWallForTesting()
    model.advanceToNextHand()
}

@MainActor
private func makeModel(
    rewardEarned: Bool, playLog: PlayLog? = nil, store: SnapshotStore = MemoryStore()
) -> (MahjongModel, StubAdService) {
    let ads = StubAdService(rewardEarned: rewardEarned)
    let model = MahjongModel(
        services: GameServices(snapshots: store, ads: ads, playLog: playLog),
        cpuDelay: .zero,
        seed: 2026
    )
    model.startGame()
    return (model, ads)
}

// MARK: - Tests

@Suite("トビ終了からのリワード広告復活")
@MainActor
struct MahjongRewardedAdTests {

    @Test("自分がトビて終わったら復活を提示する")
    func offersReviveWhenPlayerBusts() {
        let (model, _) = makeModel(rewardEarned: true)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])

        #expect(model.phase == .gameResult)
        #expect(model.canReviveAfterBust)
    }

    @Test("CPU だけがトビたときは提示しない（自分は続ける動機が無い）")
    func doesNotOfferWhenOnlyCPUBusts() {
        let (model, _) = makeModel(rewardEarned: true)
        concludeGame(model, scores: [60_000, -1_000, 20_000, 21_000])

        #expect(model.phase == .gameResult)
        #expect(!model.canReviveAfterBust)
    }

    @Test("東 4 局を終えていたら提示しない（復活しても続ける局が無い）")
    func doesNotOfferAfterFinalRound() {
        let (model, _) = makeModel(rewardEarned: true)
        // 東 4 局・親は自分ではない = 流局で局が進んで 5 局目に入り、そこで終局する。
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000], dealer: 3, roundNumber: 4)

        #expect(model.phase == .gameResult)
        #expect(model.roundNumber > MahjongModel.playerCount, "東風戦を打ち切る側の条件が立っている")
        #expect(!model.canReviveAfterBust)
    }

    @Test("視聴完了なら 25,000 点で復活して対局が続く")
    func revivesWhenRewardEarned() async {
        let (model, ads) = makeModel(rewardEarned: true)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])

        let revived = await model.reviveAfterAd()

        #expect(revived)
        #expect(ads.rewardedCount == 1)
        #expect(model.scores[0] == MahjongModel.startingScore, "マイナスの持ち点だけが初期値へ戻る")
        #expect(model.scores[1] == 30_000)
        #expect(model.phase == .playing, "次の局が配られて対局が続く")
        #expect(model.ranking.isEmpty)
        #expect(!model.canReviveAfterBust)
    }

    @Test("視聴未完了・ロード失敗なら何も変わらず、もう一度試せる")
    func doesNotReviveWhenRewardNotEarned() async {
        let (model, ads) = makeModel(rewardEarned: false)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])

        let revived = await model.reviveAfterAd()

        #expect(!revived)
        #expect(ads.rewardedCount == 1)
        #expect(model.scores[0] == -1_000, "報酬なしなので持ち点は 1 点も戻らない")
        #expect(model.phase == .gameResult)
        #expect(model.canReviveAfterBust, "失敗しても導線は残す（もう一度押せる）")
    }

    @Test("報酬付きの復活にインタースティシャルは使わない")
    func doesNotUseInterstitial() async {
        let (model, ads) = makeModel(rewardEarned: true)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])

        _ = await model.reviveAfterAd()

        #expect(ads.interstitialCount == 0)
    }

    @Test("復活は 1 半荘 1 回まで。同じ半荘で再びトビても提示しない")
    func revivesOncePerGame() async {
        let (model, ads) = makeModel(rewardEarned: true)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])
        #expect(await model.reviveAfterAd())

        // 復活後の局でまたトビて終局させる。
        concludeGame(model, scores: [-2_000, 30_000, 35_000, 37_000])

        #expect(model.phase == .gameResult)
        #expect(!model.canReviveAfterBust)
        #expect(await model.reviveAfterAd() == false)
        #expect(ads.rewardedCount == 1, "2 回目は広告を出さない")
    }

    @Test("「もう一度」で次の半荘を始めれば復活枠は戻る")
    func reviveBudgetResetsOnNewGame() async {
        let (model, _) = makeModel(rewardEarned: true)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])
        #expect(await model.reviveAfterAd())

        model.startGame()
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])

        #expect(model.canReviveAfterBust)
    }

    @Test("中断から復元しても、使い切った復活枠は戻らない")
    func reviveBudgetSurvivesRestore() async {
        let store = MemoryStore()
        let (model, _) = makeModel(rewardEarned: true, store: store)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])
        #expect(await model.reviveAfterAd())
        #expect(store.exists(for: "mahjong4"), "復活後の局は中断データとして保存されている")

        let restored = MahjongModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true)),
            cpuDelay: .zero
        )
        concludeGame(restored, scores: [-1_000, 30_000, 35_000, 36_000])

        #expect(!restored.canReviveAfterBust)
    }

    // MARK: - 記録・Game Center への送信（受け入れ条件2）

    @Test("復活したら、トビで記録した負けを取り消して 1 半荘 = 1 プレイに保つ")
    func cancelsRecordedLossWhenRevived() async {
        let (log, defaults, name) = makeIsolatedPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let (model, _) = makeModel(rewardEarned: true, playLog: log)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])

        #expect(log.record(gameID: "mahjong4")?.plays == 1, "決着の通知は従来どおりその場で行う")
        #expect(log.record(gameID: "mahjong4")?.losses == 1)

        #expect(await model.reviveAfterAd())

        #expect(log.record(gameID: "mahjong4")?.plays == 0, "同じ半荘の続きなので負けを巻き戻す")
        #expect(log.record(gameID: "mahjong4")?.losses == 0)
        #expect(model.recordResult == nil, "リザルトの記録行も消す")

        // 復活後に終局すれば、その 1 回だけが残る。
        concludeGame(model, scores: [10_000, 30_000, 30_000, 30_000], dealer: 3, roundNumber: 4)
        #expect(log.record(gameID: "mahjong4")?.plays == 1)
    }

    @Test("復活せずに終われば、トビの負けはそのまま残る")
    func keepsRecordedLossWithoutRevive() {
        let (log, defaults, name) = makeIsolatedPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let (model, _) = makeModel(rewardEarned: true, playLog: log)
        concludeGame(model, scores: [-1_000, 30_000, 35_000, 36_000])

        model.startGame()

        #expect(log.record(gameID: "mahjong4")?.plays == 1)
        #expect(log.record(gameID: "mahjong4")?.losses == 1)
    }

    @Test("トビ以外の終局は従来どおりその場で記録する")
    func recordsNormalEndImmediately() {
        let (log, defaults, name) = makeIsolatedPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let (model, _) = makeModel(rewardEarned: true, playLog: log)
        concludeGame(model, scores: [40_000, 20_000, 20_000, 20_000], dealer: 3, roundNumber: 4)

        #expect(model.phase == .gameResult)
        #expect(!model.canReviveAfterBust)
        #expect(log.record(gameID: "mahjong4")?.plays == 1)
        #expect(model.recordResult != nil)
    }

    @Test("自分がマイナスでも最下位でなければ提示しない（負けの巻き戻しが効かないため）")
    func doesNotOfferWhenBustButNotLast() {
        let (model, _) = makeModel(rewardEarned: true)
        // 自分（-1,000）より下に CPU1（-5,000）がいる = 自分は 3 位で終わる。
        concludeGame(model, scores: [-1_000, -5_000, 50_000, 56_000])

        #expect(model.phase == .gameResult)
        #expect(model.playerPlace == 2)
        #expect(!model.canReviveAfterBust)
    }
}
