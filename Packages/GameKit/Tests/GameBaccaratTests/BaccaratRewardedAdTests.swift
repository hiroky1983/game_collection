import Testing
import Foundation
import SwiftUI
import Core
import CoreTestSupport
@testable import GameBaccarat

// MARK: - Mocks

/// 視聴完了・未完了を制御できる広告スタブ。
private final class StubAdService: AdService, @unchecked Sendable {
    private let rewardEarned: Bool
    private(set) var rewardedCount = 0
    /// 視聴のあいだに起きること（ハブへ戻る等）。広告のロード中も画面は操作できる（#653）。
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

/// 全額をタイに賭け続けて破産させる。タイはめったに当たらないので数局で必ず尽きる。
@MainActor
private func playAllInUntilBust(_ model: BaccaratModel, maxRounds: Int = 300) {
    model.select(.tie)
    for _ in 0..<maxRounds {
        if model.sessionOver { return }
        if model.phase == .result { model.nextRound() }
        guard model.phase == .betting, model.chips >= BaccaratModel.minimumBet else { return }
        model.placeBet(model.chips)
    }
}

/// チップ切れのモデルを作る。中断データを差し込まず、**実際に賭けて破産させる**。
@MainActor
private func makeBustedModel(
    rewardEarned: Bool = true,
    store: MemorySnapshotStore = MemorySnapshotStore(),
    seed: UInt64 = 20260921,
    screenGeneration: GameScreenGeneration = GameScreenGeneration()
) -> (BaccaratModel, StubAdService, MemorySnapshotStore) {
    let ads = StubAdService(rewardEarned: rewardEarned)
    let model = BaccaratModel(
        services: GameServices(snapshots: store, ads: ads, screenGeneration: screenGeneration),
        seed: seed
    )
    playAllInUntilBust(model)
    #expect(model.sessionOver, "全額を賭け続けたのでセッションは終了している")
    return (model, ads, store)
}

// MARK: - Tests

@Suite("バカラのチップ切れ復活（#499 と同じ作法）")
@MainActor
struct BaccaratRewardedAdTests {

    @Test("視聴完了なら 2000 枚で復活する")
    func recoversChipsWhenRewardEarned() async {
        let (model, ads, _) = makeBustedModel()

        let recovered = await model.recoverChipsAfterAd()

        #expect(recovered)
        #expect(model.chips == BaccaratModel.reviveChips)
        #expect(model.chips == 2000)
        #expect(!model.sessionOver)
        #expect(model.phase == .betting)
        #expect(ads.rewardedCount == 1)
    }

    /// 広告を見る理由を「チップが増える」で作る（#523）。どちらかの定数を触っても逆転させない。
    @Test("復活のチップは、無料で最初からやり直すより必ず多い")
    func reviveGivesMoreChipsThanFreeRestart() async {
        #expect(BaccaratModel.reviveChips > BaccaratModel.initialChips)

        let (revived, _, _) = makeBustedModel()
        #expect(await revived.recoverChipsAfterAd())
        let (restarted, _, _) = makeBustedModel()
        restarted.restartSession()
        #expect(restarted.chips == BaccaratModel.initialChips)
        #expect(revived.chips > restarted.chips)
    }

    @Test("視聴しなかったらチップは戻らない")
    func doesNotRecoverWhenRewardNotEarned() async {
        let (model, ads, _) = makeBustedModel(rewardEarned: false)
        let before = model.chips

        #expect(await model.reviveAfterAd() == .notEarned)
        #expect(model.chips == before)
        #expect(model.sessionOver)
        #expect(model.canReviveAfterBust, "見なかっただけなので回数は減らない")
        #expect(ads.rewardedCount == 1)
    }

    @Test("復活は 1 セッション 1 回まで")
    func reviveIsOncePerSession() async {
        let (model, ads, _) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        #expect(!model.canReviveAfterBust)

        playAllInUntilBust(model)
        #expect(model.sessionOver)
        #expect(await model.reviveAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 1, "2 回目は広告も出さない")
    }

    @Test("最初からやり直すと復活の回数も戻る")
    func restartRestoresTheRevival() async {
        let (model, _, _) = makeBustedModel()
        #expect(await model.recoverChipsAfterAd())
        model.restartSession()
        playAllInUntilBust(model)
        #expect(model.canReviveAfterBust, "新しいセッションなので使える")
    }

    @Test("まだ遊べる残高では広告を出さない")
    func doesNotShowTheAdWhileStillPlayable() async {
        let ads = StubAdService(rewardEarned: true)
        let model = BaccaratModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: ads),
                                  seed: 20260921)
        #expect(await model.reviveAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 0)
        #expect(model.chips == BaccaratModel.initialChips)
    }

    /// 広告のロード中はハブへ戻れる。戻ると Model は捨てられ、次に開くと別の Model が動くが、
    /// 広告の完了を待つ `Task` は古い Model を強参照したまま生き残る（#653）。
    @Test("広告を見ているあいだにハブへ戻ったら、捨てられたモデルにチップは戻らない")
    func doesNotRecoverAfterLeavingTheScreen() async {
        let generation = GameScreenGeneration()
        let (model, ads, _) = makeBustedModel(screenGeneration: generation)
        let before = model.chips
        ads.duringAd = { generation.advance() }

        #expect(await model.reviveAfterAd() == .unavailable)
        #expect(model.chips == before)
        #expect(model.sessionOver)
    }

    /// 広告のロード〜視聴のあいだに「最初からやり直す」を押されたら、見終えた復活を
    /// 新しいセッションへ乗せない（#727。乗せると復活権と順位表資格まで持っていかれる）。
    @Test("広告のあいだにやり直したら、新しいセッションへ復活を乗せない")
    func doesNotApplyToARestartedSession() async {
        let (model, ads, _) = makeBustedModel()
        ads.duringAd = { model.restartSession() }

        #expect(await model.reviveAfterAd() == .unavailable)
        #expect(model.chips == BaccaratModel.initialChips, "やり直した側の残高のまま")
        #expect(!model.sessionOver)
    }

    // MARK: - 中断データ（#1104）

    @Test("復活したら、賭ける前にハブへ戻っても報酬と回数が残る")
    func revivedChipsSurviveLeavingBeforeBetting() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())
        #expect(store.exists(for: "baccarat"), "賭け待ちの中断データを残す")

        // 開き直した側。残高も「復活を使い切った」印も引き継がれる。
        let reopened = BaccaratModel(services: GameServices(snapshots: store, ads: NoopAdService()),
                                     seed: 20260921)
        #expect(reopened.chips == BaccaratModel.reviveChips)
        #expect(reopened.phase == .betting)
        playAllInUntilBust(reopened)
        #expect(!reopened.canReviveAfterBust, "中断を挟んでも回数は戻らない")
    }

    /// 復活したあとにもう一度破産したら中断データは残さない。残すと、開き直したときに
    /// 「最小ベットに届かない残高・復活権なし」という詰んだ状態がそのまま復元される。
    @Test("復活後にまた破産したら、中断データは残さない")
    func bustingAgainAfterReviveClearsTheSnapshot() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())
        #expect(store.exists(for: "baccarat"))

        playAllInUntilBust(model)
        #expect(model.sessionOver)
        #expect(!store.exists(for: "baccarat"), "詰んだ残高を持ち回らない")
    }

    @Test("中断データは「続きから」ではない（ハブの表示にも resume にも数えない）")
    func revivedSnapshotIsNotResumable() async {
        let store = MemorySnapshotStore()
        let (model, _, _) = makeBustedModel(store: store)
        #expect(await model.recoverChipsAfterAd())
        #expect(BaccaratModule().hasResumableSnapshot(in: store) == false)
    }

    @Test("復活を使っていないセッションは、決着しても中断データを残さない")
    func finishedRoundsClearTheSnapshot() {
        let store = MemorySnapshotStore()
        let model = BaccaratModel(services: GameServices(snapshots: store, ads: NoopAdService()),
                                  seed: 20260921)
        model.placeBet(100)
        #expect(!store.exists(for: "baccarat"))
    }

    /// 「復活を使い切ったか」の鍵が無い JSON（形が変わる前に書かれた中断データ）を読んでも
    /// デコードごと失敗しない。落ちると復活で戻したチップが黙って消える。
    @Test("鍵の無い古い中断データは「未使用」に倒して読む")
    func snapshotWithoutRevivalKeyDecodes() throws {
        let data = try JSONEncoder().encode(BaccaratSnapshot(chips: 800, hasRevivedThisSession: true))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "hasRevivedThisSession")
        let store = MemorySnapshotStore()
        store.inject(try JSONSerialization.data(withJSONObject: object), for: "baccarat")

        let model = BaccaratModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.chips == 800, "残高は読めている")
        #expect(!model.sessionOver)
        // 鍵が無いぶんは「まだ使っていない」に倒す（`?? true` に倒すと復活権が消える）。
        playAllInUntilBust(model)
        #expect(model.canReviveAfterBust, "鍵の無い中断データは復活を使っていない扱い")
    }
}
