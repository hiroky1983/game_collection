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

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async { interstitialCount += 1 }
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        return rewardEarned
    }
}

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
private final class SpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) { completion(true) }
    /// 「ここから先の送信だけを見たい」ための仕切り直し。
    func reset() { scores.removeAll() }
}

/// 配りが乱数のブラックジャックでは破産局面を狙って作れないので、中断データを注入して
/// 「全額を賭けた 15 対 ディーラー 20」を再現する（#439 と同じ手口）。`stand()` すれば必ず破産する。
///
/// - Parameters:
///   - chips: 破産させたい残高。この額を丸ごと賭けた手が入っている状態から始まる。
///   - hasRevived: 中断データに書かれている「復活を使い切ったか」。再開後の 2 回目を試すのに使う。
///   - seed: 復活後に遊ぶラウンドの配りを決定的にする種。
@MainActor
private func makeBustedModel(
    rewardEarned: Bool = true,
    chips: Int = 100,
    hasRevived: Bool = false,
    store: MockSnapshotStore = MockSnapshotStore(),
    gameCenter: GameCenterReporter? = nil,
    playLog: PlayLog? = nil,
    seed: UInt64 = 20260909
) -> (BlackjackModel, StubAdService, MockSnapshotStore) {
    var nextID = 0
    func make(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.map { rank in
            defer { nextID += 1 }
            return BlackjackCard(id: nextID, suit: BlackjackSuit.allCases[nextID % 4], rank: rank)
        }
    }
    let playerCards = make([10, 5])
    let snapshot = BlackjackSnapshot(
        playerHand: playerCards,
        dealerHand: make([10, 10]),
        deck: make([2, 2]),
        chips: chips,
        bet: chips,
        phase: .playerTurn,
        hands: [BlackjackHand(id: 0, cards: playerCards, bet: chips)],
        activeHandIndex: 0,
        hasRevivedThisSession: hasRevived
    )
    try? store.save(snapshot, for: "blackjack")
    let ads = StubAdService(rewardEarned: rewardEarned)
    let model = BlackjackModel(
        services: GameServices(
            snapshots: store, ads: ads, playLog: playLog, gameCenter: gameCenter
        ),
        seed: seed
    )
    model.stand()
    #expect(model.chips == 0)
    #expect(model.sessionOver, "全額を失ったのでセッションは終了している")
    return (model, ads, store)
}

/// 残高を全額賭け続けて、負けた時点で破産させる。1 回でも負ければ残高 0 になるので必ず止まる。
@MainActor
private func playAllInUntilBust(_ model: BlackjackModel, maxRounds: Int = 40) {
    for _ in 0..<maxRounds {
        // 中断から復元した直後は手が進行中なので、まずその手を決着させる。
        while model.phase == .playerTurn { model.stand() }
        if model.sessionOver { return }
        if model.phase == .result { model.nextRound() }
        guard model.phase == .betting, model.chips > 0 else { return }
        model.placeBet(model.chips)
    }
}

// MARK: - Tests

@Suite("チップ切れ復活のリワード広告（#499）")
@MainActor
struct BlackjackRewardedAdTests {

    @Test("視聴完了なら初期チップの半分で復活する")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads, _) = makeBustedModel()

        let recovered = await model.recoverChipsAfterAd()

        #expect(recovered)
        #expect(model.chips == 500, "初期チップ 1000 の半分")
        #expect(model.chips == BlackjackModel.initialChips / 2)
        #expect(!model.sessionOver)
        #expect(model.phase == .betting)
        #expect(ads.rewardedCount == 1)
    }

    @Test("視聴未完了・ロード失敗ならチップは回復しない")
    func doesNotRecoverChipsWhenRewardNotEarned() async {
        let (model, ads, _) = makeBustedModel(rewardEarned: false)

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.chips == 0, "報酬なしなのでチップは1枚も増えない")
        #expect(model.sessionOver, "セッション終了のまま")
        #expect(model.canReviveAfterBust, "失敗した視聴で1回ぶんを失わない")
        #expect(ads.rewardedCount == 1)
    }

    @Test("報酬付きの回復にインタースティシャルは使わない")
    func doesNotUseInterstitialForReward() async {
        let (model, ads, _) = makeBustedModel()

        _ = await model.recoverChipsAfterAd()

        #expect(ads.interstitialCount == 0)
    }

    // MARK: 1 セッション 1 回まで

    @Test("チップが残っているうちは復活できず、広告も出さない")
    func doesNotShowAdWhileChipsRemain() async {
        let ads = StubAdService(rewardEarned: true)
        let model = BlackjackModel(services: GameServices(snapshots: MockSnapshotStore(), ads: ads))
        #expect(!model.sessionOver)
        #expect(!model.canReviveAfterBust)

        let recovered = await model.recoverChipsAfterAd()

        #expect(!recovered)
        #expect(model.chips == BlackjackModel.initialChips, "残高は動かない")
        #expect(ads.rewardedCount == 0, "いつでも押せる増量ボタンにはしない")
    }

    @Test("同じセッションで2回目の復活はできず、広告も出さない")
    func revivesOnlyOncePerSession() async {
        // 中断データが「復活を使い切った」状態。再開してもう一度破産させた局面。
        let (model, ads, _) = makeBustedModel(hasRevived: true)

        #expect(!model.canReviveAfterBust, "使い切っているので導線は出ない")
        let second = await model.recoverChipsAfterAd()

        #expect(!second)
        #expect(model.chips == 0, "残高は動かない")
        #expect(ads.rewardedCount == 0, "2本目の広告は出さない")
    }

    @Test("中断から戻っても復活の回数は戻らない")
    func reviveBudgetSurvivesSuspend() async {
        let store = MockSnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())

        // 復活後の1手を playerTurn まで進めると、そこで中断データが書かれる。
        model.placeBet(100)
        #expect(model.phase == .playerTurn, "この種では初手ブラックジャックにならない")
        let saved = store.load(BlackjackSnapshot.self, for: "blackjack")
        #expect(saved?.hasRevivedThisSession == true, "使用済みの旗が中断データに乗る")

        // アプリを起動し直した想定で、同じ中断データから作り直す。
        let restored = BlackjackModel(
            services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true))
        )
        playAllInUntilBust(restored)
        #expect(restored.sessionOver)
        #expect(!restored.canReviveAfterBust, "再起動で回数が復活しない")
    }

    @Test("最初からやり直すと復活の回数も戻る")
    func restartRestoresReviveBudget() async {
        let (model, _, _) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        #expect(!model.canReviveAfterBust)

        model.restartSession()
        #expect(model.chips == BlackjackModel.initialChips)

        // 新しいセッションで破産させ直すと、また復活できる。
        playAllInUntilBust(model)
        #expect(model.sessionOver)
        #expect(model.canReviveAfterBust)
    }

    // MARK: 旧データとの互換

    @Test("復活の鍵が無い旧スナップショットも読める")
    func decodesLegacySnapshotWithoutReviveKey() throws {
        // #499 以前に保存された形（`hasRevivedThisSession` が無い JSON）。
        let legacy = """
        {"playerHand":[],"dealerHand":[],"deck":[],"chips":700,"bet":100,"phase":"playerTurn",\
        "hands":[],"activeHandIndex":0}
        """
        let snap = try JSONDecoder().decode(BlackjackSnapshot.self, from: Data(legacy.utf8))
        #expect(snap.chips == 700)
        #expect(snap.hasRevivedThisSession == nil, "鍵が無くてもデコードは通る")
    }
}

// MARK: - Game Center への送信ゲート

@Suite("復活したセッションは順位表へ送らない（#499）")
@MainActor
struct BlackjackReviveLeaderboardTests {

    /// 破産 →（復活 or やり直し）→ 1 ラウンド決着、までを走らせて送信内容を集める。
    ///
    /// - Parameter suiteName: ローカル記録の保存先。テストごとに分けて汚染を避ける。
    private func finishRound(
        usingRevive: Bool, suiteName: String
    ) async -> (SpyGameCenterService, BlackjackModel) {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["blackjack"])
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let (model, _, _) = makeBustedModel(
            gameCenter: reporter, playLog: PlayLog(defaults: defaults)
        )
        // 破産したラウンド自体も1件送っている（復活前なので対象）。ここから先だけを見たい。
        spy.reset()

        if usingRevive {
            #expect(await model.recoverChipsAfterAd())
        } else {
            model.restartSession()
        }
        model.placeBet(100)
        while model.phase == .playerTurn { model.stand() }
        #expect(model.phase == .result, "1 ラウンドは決着している")
        return (spy, model)
    }

    @Test("復活を使わずに終えたラウンドはチップを送る")
    func submitsCleanSession() async {
        let (spy, _) = await finishRound(
            usingRevive: false, suiteName: "asobiba.blackjack.revive.clean"
        )
        #expect(spy.scores.map(\.leaderboardID) == [GameCenterLeaderboard.blackjackChips])
    }

    @Test("復活を使ったセッションのラウンドは何も送らない")
    func skipsRevivedSession() async {
        let (spy, _) = await finishRound(
            usingRevive: true, suiteName: "asobiba.blackjack.revive.assisted"
        )
        #expect(spy.scores.isEmpty)
    }

    @Test("送らなくてもローカルの自己ベストには残る")
    func keepsLocalRecordEvenWhenNotSubmitted() async {
        let (spy, model) = await finishRound(
            usingRevive: true, suiteName: "asobiba.blackjack.revive.local"
        )
        #expect(spy.scores.isEmpty, "順位表へは送っていない")
        #expect(model.recordResult != nil, "順位表から外すだけで、手元の記録は残す（#397）")
    }
}
