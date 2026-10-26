import Testing
import Foundation
import SwiftUI
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// 視聴完了・未完了（失敗・途中で閉じた）を制御できる広告スタブ。実際の広告は出さない。
@MainActor
private final class StubAdService: AdService {
    var rewardEarned: Bool
    private(set) var shownCount = 0
    /// 広告を見ているあいだに起きること（新規ゲーム・計時の確認など）。
    var duringAd: (@MainActor () -> Void)?

    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }

    func makeBannerView(width: CGFloat) -> AnyView? { nil }
    func showInterstitial() async {}
    func showRewardedAd() async -> Bool {
        shownCount += 1
        duringAd?()
        return rewardEarned
    }
}

/// 救済の中で立つ `Task` が終わるまで待つ。実時間は待たない（スタブの広告は中断点を持たない）。
@MainActor
private func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

@MainActor
@Suite("おじさんちのねこさがしのヒントの広告（無料 3 回のあと +1・#2250）")
struct CatPuzzleHintAdTests {

    private func make(
        rewardEarned: Bool = true, store: MemorySnapshotStore = MemorySnapshotStore()
    ) -> (CatPuzzleModel, StubAdService, SpyAnalyticsService, GameServices) {
        let ads = StubAdService(rewardEarned: rewardEarned)
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: store, ads: ads,
            analytics: GameAnalytics(service: spy, allowedGameIDs: [CatPuzzleModel.gameID])
        )
        return (CatPuzzleModel(services: services, size: .normal, seed: 1), ads, spy, services)
    }

    /// 無料ぶんを使い切る（広告は出ない）。
    private func spendFree(_ model: CatPuzzleModel, rescue: RewardedRescue, services: GameServices) async {
        for _ in 0..<CatPuzzleModel.freeHints {
            CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        }
        await settle()
    }

    private func rewardEvents(_ spy: SpyAnalyticsService) -> [String] {
        spy.events.map(\.name).filter { $0.hasPrefix("reward_") }
    }

    @Test("無料のあいだは広告を出さず、ボタンは「あと n 回」（無料ぶんだけ）")
    func freeHintsDontShowAds() async {
        let (model, ads, spy, services) = make()
        let rescue = RewardedRescue()
        #expect(CatPuzzleView.hintBadge(for: model) == .count(CatPuzzleModel.freeHints))
        CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        await settle()
        #expect(model.hintsUsed == 1 && model.lastHint != nil)
        #expect(CatPuzzleView.hintBadge(for: model) == .count(2), "広告で足せる分は数えない")
        #expect(ads.shownCount == 0)
        #expect(rewardEvents(spy).isEmpty)
    }

    @Test("無料を使い切ると「0回 ▶ 広告を見て +1」で、押せる")
    func exhaustedFreeShowsAdBadge() async {
        let (model, ads, _, services) = make()
        let rescue = RewardedRescue()
        await spendFree(model, rescue: rescue, services: services)
        #expect(model.hintsUsed == 3 && model.hintsRemaining == 0)
        #expect(model.needsAdForHint && model.canHint)
        #expect(CatPuzzleView.hintBadge(for: model) == .ad(gain: 1))
        #expect(CatPuzzleAccessibility.hintLabel(remaining: 0, needsAd: true).contains("広告"))
        let hint = CatPuzzleView.playControls(for: model).actions.first { $0.id == "hint" }
        #expect(hint?.isEnabled == true)
        #expect(ads.shownCount == 0, "広告は押すまで出さない")
    }

    @Test("広告を最後まで見るとヒントが 1 回出て、reward_request と reward_ad が送られる")
    func adSuccessGrantsOneHint() async {
        let (model, ads, spy, services) = make()
        let rescue = RewardedRescue()
        await spendFree(model, rescue: rescue, services: services)
        let marksBefore = model.marks
        CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        await settle()
        #expect(ads.shownCount == 1)
        #expect(model.hintsUsed == 4)
        #expect(model.marks != marksBefore && model.lastHint != nil, "盤が 1 歩進む")
        #expect(!rescue.showsNotEarned && !rescue.showsUnavailable && !rescue.isWatching)
        #expect(rewardEvents(spy) == ["reward_request", "reward_ad"])
        #expect(spy.events.contains {
            if case let .rewardAd(gameID, purpose) = $0 { return gameID == CatPuzzleModel.gameID && purpose == .hint }
            return false
        })
        // 広告のあとも次の 1 回は広告（無料は戻らない）。
        #expect(model.needsAdForHint && CatPuzzleView.hintBadge(for: model) == .ad(gain: 1))
    }

    @Test("広告を読み込めなかった・途中で閉じたら、ヒントは出ず回数も減らず「使えませんでした」")
    func adFailureOrCancelGrantsNothing() async {
        let (model, ads, spy, services) = make(rewardEarned: false)
        let rescue = RewardedRescue()
        await spendFree(model, rescue: rescue, services: services)
        let marksBefore = model.marks
        CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        await settle()
        #expect(ads.shownCount == 1)
        #expect(model.hintsUsed == 3 && model.marks == marksBefore)
        #expect(rescue.showsNotEarned && !rescue.showsUnavailable && !rescue.isWatching)
        #expect(rewardEvents(spy) == ["reward_request"], "視聴完了の reward_ad は送らない")
        #expect(model.needsAdForHint && model.canHint, "もう一度押せる")
    }

    @Test("広告を見ているあいだは計時を止める状態で、連打しても 2 本目は出ない")
    func watchingHoldsClockAndBlocksRepeat() async {
        let (model, ads, _, services) = make()
        let rescue = RewardedRescue()
        await spendFree(model, rescue: rescue, services: services)
        var heldDuringAd = false
        var enabledDuringAd = true
        ads.duringAd = {
            heldDuringAd = rescue.holdsClock
            enabledDuringAd = CatPuzzleView.playControls(for: model, isWatchingAd: rescue.isWatching)
                .actions.first { $0.id == "hint" }?.isEnabled ?? true
        }
        CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        await settle()
        #expect(heldDuringAd, "gameTimerLifecycle(rescues:) が計時を止める合図")
        #expect(!enabledDuringAd, "視聴中はヒントを押せない")
        #expect(ads.shownCount == 1)
        #expect(model.hintsUsed == 4)
        #expect(!rescue.holdsClock)
    }

    @Test("広告を見ているあいだに新しい局が始まったら、新しい局へは乗せず「出せませんでした」")
    func adForReplacedGameIsRejected() async {
        let (model, ads, _, services) = make()
        let rescue = RewardedRescue()
        await spendFree(model, rescue: rescue, services: services)
        ads.duringAd = { model.newGame() }
        CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        await settle()
        #expect(rescue.showsUnavailable)
        #expect(model.hintsUsed == 0 && model.lastHint == nil, "新しい局のヒントは減らない")
        #expect(model.hintsRemaining == CatPuzzleModel.freeHints)
    }

    @Test("無料が残っているうち・別の局の報酬は受け付けない")
    func grantGuards() {
        let (model, _, _, _) = make()
        #expect(!model.grantAdHint(forGame: model.gameSerial), "無料が残っているうちは広告の報酬を受けない")
        #expect(model.hintsUsed == 0)
        for _ in 0..<CatPuzzleModel.freeHints { model.useHint() }
        #expect(!model.grantAdHint(forGame: model.gameSerial + 1))
        #expect(model.hintsUsed == 3)
        #expect(model.grantAdHint(forGame: model.gameSerial))
        #expect(model.hintsUsed == 4)
    }

    @Test("広告の追加も上限まで使うと押せず、0 回のまま案内も出さない")
    func adRefillHasCap() {
        let (model, _, _, _) = make()
        for _ in 0..<CatPuzzleModel.freeHints { model.useHint() }
        for _ in 0..<BoardHintBudget.adRefillMax {
            #expect(model.grantAdHint(forGame: model.gameSerial))
        }
        #expect(!model.isSolved, "前提: 上限まで使っても解け切らない盤")
        #expect(model.hintsUsed == CatPuzzleModel.freeHints + BoardHintBudget.adRefillMax)
        #expect(!model.canHint && !model.needsAdForHint)
        #expect(!model.grantAdHint(forGame: model.gameSerial))
        #expect(CatPuzzleView.hintBadge(for: model) == .count(0))
    }

    @Test("中断データから戻しても、広告で使った分を含めて回数は戻らない")
    func restoreKeepsAdHints() {
        let store = MemorySnapshotStore()
        let (model, _, _, _) = make(store: store)
        for _ in 0..<CatPuzzleModel.freeHints { model.useHint() }
        #expect(model.grantAdHint(forGame: model.gameSerial))
        let (restored, _, _, _) = make(store: store)
        #expect(restored.puzzle == model.puzzle)
        #expect(restored.hintsUsed == 4)
        #expect(restored.needsAdForHint)
        #expect(CatPuzzleView.hintBadge(for: restored) == .ad(gain: 1))
    }

    @Test("新規ゲームで無料の 3 回に戻る")
    func newGameResetsHints() {
        let (model, _, _, _) = make()
        for _ in 0..<CatPuzzleModel.freeHints { model.useHint() }
        #expect(model.grantAdHint(forGame: model.gameSerial))
        model.newGame()
        #expect(model.hintsUsed == 0 && !model.needsAdForHint)
        #expect(CatPuzzleView.hintBadge(for: model) == .count(CatPuzzleModel.freeHints))
    }
}
