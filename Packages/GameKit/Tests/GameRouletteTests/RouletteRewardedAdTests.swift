import Testing
import Foundation
import SwiftUI
import Core
@testable import GameRoulette
import CoreTestSupport

// MARK: - Mocks

/// 視聴完了・未完了を制御できる広告スタブ。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    /// 視聴のあいだに起きること（ハブへ戻る・やり直す等）。広告のロード中も画面は操作できる（#653）。
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool {
        rewardedCount += 1
        duringAd?()
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
}

/// 出目を決め打ちにした「回転中」の中断データで、全額を外れの口に置いた状態から起こす。
/// 待ち時間 0 なので復帰した瞬間に精算され、必ず破産する。
@MainActor
private func makeBustedModel(
    rewardEarned: Bool = true,
    chips: Int = 100,
    hasRevived: Bool = false,
    store: MemorySnapshotStore = MemorySnapshotStore(),
    gameCenter: GameCenterReporter? = nil,
    screenGeneration: GameScreenGeneration = GameScreenGeneration()
) -> (RouletteModel, StubAdService, MemorySnapshotStore) {
    let snapshot = RouletteSnapshot(
        chips: chips,
        bets: [RouletteBet(id: 0, kind: .straight(7), amount: chips)],
        phase: .spinning,
        winningNumber: 8,
        history: [],
        hasRevivedThisSession: hasRevived
    )
    try? store.save(snapshot, for: "roulette")
    let ads = StubAdService(rewardEarned: rewardEarned)
    let model = RouletteModel(
        services: GameServices(snapshots: store, ads: ads, gameCenter: gameCenter, screenGeneration: screenGeneration),
        seed: 20260924
    )
    #expect(model.chips == 0)
    #expect(model.sessionOver, "全額を失ったのでセッションは終了している")
    return (model, ads, store)
}

// MARK: - Tests

@Suite("ルーレットのチップ切れ復活（#1318）")
@MainActor
struct RouletteRewardedAdTests {

    @Test("視聴完了なら 2000 枚で復活し、賭け中に戻る")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads, _) = makeBustedModel()

        let outcome = await model.reviveAfterAd()

        #expect(outcome == .granted)
        #expect(model.chips == 2000)
        #expect(model.chips == RouletteModel.reviveChips)
        #expect(!model.sessionOver)
        #expect(model.phase == .betting)
        #expect(model.bets.isEmpty)
        #expect(model.winningNumber == nil)
        #expect(ads.rewardedCount == 1)
    }

    /// 広告を見る理由を「チップが増える」で作る（#523 会長決裁 C 案）。将来どちらかの定数を触っても逆転させない。
    @Test("復活のチップは、無料で最初からやり直すより必ず多い")
    func reviveGivesMoreChipsThanFreeRestart() async {
        #expect(RouletteModel.reviveChips > RouletteModel.initialChips)
        let (revived, _, _) = makeBustedModel()
        #expect(await revived.reviveAfterAd() == .granted)
        let (restarted, _, _) = makeBustedModel()
        restarted.restartSession()
        #expect(restarted.chips == RouletteModel.initialChips)
        #expect(revived.chips > restarted.chips)
    }

    @Test("視聴しなかったら何も変わらない")
    func keepsBustWhenRewardNotEarned() async {
        let (model, ads, _) = makeBustedModel(rewardEarned: false)
        let outcome = await model.reviveAfterAd()
        #expect(outcome == .notEarned)
        #expect(model.chips == 0)
        #expect(model.sessionOver)
        #expect(model.canReviveAfterBust, "復活の回数は減らない")
        #expect(ads.rewardedCount == 1)
    }

    @Test("チップが尽きていなければ広告を出さない")
    func doesNotShowAdWhileChipsRemain() async {
        let ads = StubAdService(rewardEarned: true)
        let model = RouletteModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: ads))
        #expect(!model.canReviveAfterBust)
        let outcome = await model.reviveAfterAd()
        #expect(outcome == .unavailable)
        #expect(ads.rewardedCount == 0)
        #expect(model.chips == 1000)
    }

    @Test("1 セッション 1 回まで。2 回目は広告すら出さない")
    func onlyOncePerSession() async {
        let (model, ads, _) = makeBustedModel()
        #expect(await model.reviveAfterAd() == .granted)
        // 復活後の 2000 枚を全額外れに置いて再び破産させる。
        model.selectedChip = 500
        for _ in 0..<4 { model.placeBet(.straight(0)) }
        #expect(model.totalBet == 2000)
        model.spin()
        if model.winningNumber == 0 {
            // 種は固定だが念のため。0 が出たら当たっているので判定はここまで。
            return
        }
        #expect(model.sessionOver)
        #expect(!model.canReviveAfterBust)
        let outcome = await model.reviveAfterAd()
        #expect(outcome == .unavailable)
        #expect(ads.rewardedCount == 1, "2 回目は広告を出さない")
        #expect(model.chips == 0)
    }

    @Test("復活を使い切った中断データから戻っても、回数は復活しない")
    func usedReviveSurvivesRelaunch() async {
        let (model, ads, _) = makeBustedModel(hasRevived: true)
        #expect(!model.canReviveAfterBust)
        #expect(await model.reviveAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 0)
    }

    @Test("復活直後の残高は中断データに残り、戻っても報酬と「使い切った」印が保たれる（#1104）")
    func revivedBalanceIsPersisted() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.reviveAfterAd() == .granted)
        #expect(store.exists(for: "roulette"), "次のスピンの前にハブへ戻られても報酬が消えない")

        let restored = RouletteModel(services: GameServices(snapshots: store, ads: StubAdService(rewardEarned: true)))
        #expect(restored.chips == 2000)
        #expect(restored.phase == .betting)
        #expect(!restored.sessionOver)
        // 全額外れに置いて破産させると、復活は使い切っているので出ない。
        restored.selectedChip = 500
        for _ in 0..<4 { restored.placeBet(.straight(0)) }
        restored.spin()
        if restored.winningNumber != 0 {
            #expect(restored.sessionOver)
            #expect(!restored.canReviveAfterBust)
        }
    }

    @Test("最初からやり直すと復活の回数が戻る")
    func restartResetsRevive() async {
        let (model, ads, _) = makeBustedModel(hasRevived: true)
        #expect(!model.canReviveAfterBust)
        model.restartSession()
        #expect(model.chips == RouletteModel.initialChips)
        // もう一度破産させる（全額を外れの数字へ）。
        model.selectedChip = 500
        model.placeBet(.straight(0))
        model.placeBet(.straight(0))
        model.spin()
        if model.winningNumber != 0 {
            #expect(model.sessionOver)
            #expect(model.canReviveAfterBust, "新しいセッションなので復活できる")
            #expect(await model.reviveAfterAd() == .granted)
            #expect(ads.rewardedCount == 1)
        }
    }

    @Test("広告のあいだにハブへ戻られていたら適用しない（#653）")
    func doesNotApplyWhenScreenGenerationChanged() async {
        let generation = GameScreenGeneration()
        let (model, ads, _) = makeBustedModel(screenGeneration: generation)
        ads.duringAd = { generation.advance() }
        let outcome = await model.reviveAfterAd()
        #expect(outcome == .unavailable)
        #expect(model.chips == 0)
        #expect(model.sessionOver)
        #expect(model.canReviveAfterBust, "復活の回数は減らない")
    }

    @Test("広告のあいだに「最初からやり直す」されていたら新しいセッションへ乗せない（#727）")
    func doesNotApplyWhenSessionRestartedDuringAd() async {
        let (model, ads, _) = makeBustedModel()
        ads.duringAd = { model.restartSession() }
        let outcome = await model.reviveAfterAd()
        #expect(outcome == .unavailable)
        #expect(model.chips == RouletteModel.initialChips, "やり直した 1000 枚のまま")
        #expect(!model.sessionOver)
    }

    @Test("復活直後の口の無い中断データは「続きから」に数えない。回転中・口ありは数える（#809）")
    func resumableSnapshotExcludesRevivedWaiting() async throws {
        let module = RouletteModule()
        let store = MemorySnapshotStore()
        #expect(!module.hasResumableSnapshot(in: store), "中断データが無い")

        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.reviveAfterAd() == .granted)
        #expect(store.exists(for: "roulette"), "前提が崩れた: 復活のチップだけの中断データが残るはず")
        #expect(!module.hasResumableSnapshot(in: store), "口の無い賭け待ちを「続き」に数えている")

        model.selectedChip = 10
        model.placeBet(.red)
        #expect(module.hasResumableSnapshot(in: store), "口を置いたら続きがある")

        try store.save(
            RouletteSnapshot(chips: 500, bets: [RouletteBet(id: 0, kind: .red, amount: 100)],
                             phase: .spinning, winningNumber: 3, history: [], hasRevivedThisSession: false),
            for: "roulette"
        )
        #expect(module.hasResumableSnapshot(in: store), "回転中は続きがある")
    }

    /// 保存時の通知（`notifyRoundWaitingSnapshot`）は `ResumeReminder` の**メモリ上の**決着済みの印に
    /// しか効かず、再起動で消える。復元側でも伝えないと、起動し直してから開いて戻ったときだけ
    /// 続きの無い局に「途中のままです」が予約される（#1145）。
    @Test("再起動後に開いて戻っても「途中のままです」を予約しない（#1145）")
    func revivedSnapshotSchedulesNoReminderAfterRelaunch() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.reviveAfterAd() == .granted)
        #expect(model.phase == .betting && model.bets.isEmpty, "賭ける前で止まっている")
        #expect(store.exists(for: "roulette"), "前提が崩れた: 復活のチップだけの中断データが残るはず")

        // アプリを終了して起動し直し、ハブから開いて何も賭けずに戻る。
        let (services, reminders, spy) = makeRelaunchedServices(
            store: store, ads: StubAdService(rewardEarned: true),
            reminderTitle: { $0 == "roulette" ? "ルーレット" : nil }
        )
        _ = RouletteModel(services: services)
        services.gameDidLeave(gameID: "roulette")
        await reminders.pendingWork?.value

        #expect(spy.reminders.isEmpty, "続きの無い局に「途中のままです」を予約した")
    }

    /// 上の対照。口が残っている中断データまで黙らせていたら、本物の中断が知らされなくなる。
    @Test("口を置いたまま離れたときは、再起動後でも従来どおり予約する（#1145）")
    func betsOnTableStillScheduleReminderAfterRelaunch() async throws {
        let store = MemorySnapshotStore()
        try store.save(
            RouletteSnapshot(chips: 2000, bets: [RouletteBet(id: 0, kind: .black, amount: 50)],
                             phase: .betting, winningNumber: nil, history: [], hasRevivedThisSession: true),
            for: "roulette"
        )
        let (services, reminders, spy) = makeRelaunchedServices(
            store: store, ads: StubAdService(rewardEarned: true),
            reminderTitle: { $0 == "roulette" ? "ルーレット" : nil }
        )
        let model = RouletteModel(services: services)
        #expect(model.bets.count == 1, "前提が崩れた: 置いた口を復元しているはず")
        services.gameDidLeave(gameID: "roulette")
        await reminders.pendingWork?.value

        #expect(spy.reminders["roulette"] != nil, "口が残っているのに予約しなかった")
    }

    @Test("復活を使ったセッションの記録は順位表へ送らない（ローカルの自己ベストには残る）")
    func revivedSessionIsNotEligibleForLeaderboard() async {
        let spy = SpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["roulette"])
        let (model, _, _) = makeBustedModel(gameCenter: reporter)
        #expect(spy.scores.count == 1, "破産したスピンは通常どおり送る（0 枚）")
        #expect(spy.scores.first?.leaderboardID == GameCenterLeaderboard.rouletteChips)

        #expect(await model.reviveAfterAd() == .granted)
        model.selectedChip = 10
        model.placeBet(.red)
        model.spin()
        #expect(model.phase == .result)
        #expect(spy.scores.count == 1, "復活後のスピンは送らない")
    }
}
