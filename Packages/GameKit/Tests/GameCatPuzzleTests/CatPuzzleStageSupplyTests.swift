import Testing
import Foundation
import SwiftUI
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// 広告の成否を制御できるスタブ。
@MainActor
private final class SupplyAdService: AdService {
    var rewardEarned: Bool
    private(set) var shownCount = 0
    init(rewardEarned: Bool) { self.rewardEarned = rewardEarned }
    func makeBannerView(width: CGFloat) -> AnyView? { nil }
    func showInterstitial() async {}
    func showRewardedAd() async -> Bool {
        shownCount += 1
        return rewardEarned
    }
}

@MainActor
private func settle() async {
    for _ in 0..<20 { await Task.yield() }
}

/// ステージのヒントと「猫を 1 匹教える」（全ステージ共通 5 回・0 で広告 1 回につき 1 回・#3203）。自由に遊ぶは従来どおり。
@Suite("おじさんちのねこさがしのステージ共通のヒント／猫を教える（#3203）")
@MainActor
struct CatPuzzleStageSupplyTests {

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "asobiba.catpuzzle.supply.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func make(
        _ name: String, defaults: UserDefaults? = nil, rewardEarned: Bool = true, store: MemorySnapshotStore = MemorySnapshotStore()
    ) -> (model: CatPuzzleModel, ads: SupplyAdService, spy: SpyAnalyticsService, services: GameServices, defaults: UserDefaults) {
        let defaults = defaults ?? makeDefaults(name)
        let ads = SupplyAdService(rewardEarned: rewardEarned)
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: store, ads: ads,
            analytics: GameAnalytics(service: spy, allowedGameIDs: [CatPuzzleModel.gameID])
        )
        let model = CatPuzzleModel(services: services, puzzle: CatPuzzleStage(1).makePuzzle(), size: .easy, stage: 1,
                                   stageDefaults: defaults)
        return (model, ads, spy, services, defaults)
    }

    private func rewardEvents(_ spy: SpyAnalyticsService) -> [String] {
        spy.events.map(\.name).filter { $0.hasPrefix("reward_") }
    }

    // MARK: - ヒント

    @Test("はじめての利用者はヒントも猫を教えるも 5 回ずつで、ステージではボタンは「あと 5 回」")
    func startsWithFiveEach() {
        let (model, _, _, _, _) = make("fresh")
        #expect(CatPuzzleModel.stageSupplyCount == 5)
        #expect(model.hintsRemaining == 5 && model.teachRemaining == 5)
        #expect(CatPuzzleView.hintBadge(for: model) == .count(5))
        #expect(CatPuzzleView.teachBadge(for: model) == .count(5))
    }

    @Test("ヒントの残りは面をまたいで共通で、新規・やり直し・ステージ移動・作り直しでも戻らない")
    func hintSupplyIsSharedAndPersistent() async {
        let (model, _, _, services, defaults) = make("shared")
        model.useHint()
        model.useHint()
        #expect(model.hintsRemaining == 3 && model.hintsUsed == 2)
        model.reset()
        #expect(model.hintsRemaining == 3)
        model.startStage(2)
        await model.stagePreparation?.value
        #expect(model.stage == 2 && model.hintsRemaining == 3 && model.hintsUsed == 0, "面が変わっても残りは共通。使った回数は局ごと")
        model.newGame()
        #expect(model.stageHintsLeft == 3, "自由に遊ぶへ切り替えても共通の残りは戻らない")
        // アプリを閉じて開き直しても残る（中断データとは別のキー）。
        let reopened = CatPuzzleModel(services: services, stageDefaults: defaults)
        #expect(reopened.stageHintsLeft == 3 && reopened.stageTeachLeft == 5)
        #expect(defaults.integer(forKey: CatPuzzleModel.stageHintsLeftKey) == 3)
    }

    @Test("0 になったら広告 1 回でヒント 1 回。何度でも、残りは 0 のまま")
    func adGivesOneHintEachTime() async {
        let (model, ads, spy, services, _) = make("hintad")
        let rescue = RewardedRescue()
        for _ in 0..<5 { model.useHint() }
        #expect(model.hintsRemaining == 0 && model.needsAdForHint && model.canHint)
        #expect(CatPuzzleView.hintBadge(for: model) == .ad(gain: 1))
        for round in 1...3 {
            CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
            await settle()
            #expect(ads.shownCount == round)
            #expect(model.hintsUsed == 5 + round)
            #expect(model.hintsRemaining == 0 && model.needsAdForHint)
        }
        #expect(!CatPuzzleView.isHintUsedUp(model), "ステージでは使い切りは無い")
        #expect(rewardEvents(spy) == Array(repeating: ["reward_request", "reward_ad"], count: 3).flatMap { $0 })
        #expect(spy.rewards.allSatisfy { $0.purpose == .hint })
    }

    @Test("広告を最後まで見なければヒントは出ない")
    func hintAdFailureGrantsNothing() async {
        let (model, ads, spy, services, _) = make("hintfail", rewardEarned: false)
        let rescue = RewardedRescue()
        for _ in 0..<5 { model.useHint() }
        let marks = model.marks
        CatPuzzleView.requestHint(model: model, hintRescue: rescue, services: services)
        await settle()
        #expect(ads.shownCount == 1 && model.marks == marks && model.hintsUsed == 5)
        #expect(rescue.showsNotEarned)
        #expect(rewardEvents(spy) == ["reward_request"])
    }

    // MARK: - 猫を 1 匹教える

    @Test("猫を教えると正解のマスに猫が固定で置かれ、戻す・やり直しでも消えない")
    func teachPlacesFixedCorrectCat() {
        let (model, _, _, _, _) = make("teach")
        model.teachCat()
        #expect(model.catCells.count == 1)
        let cell = model.catCells[0]
        #expect(model.puzzle.solutionCells.contains(cell))
        #expect(model.hintCells.contains(cell) && model.isFixed(cell: cell))
        #expect(model.teachRemaining == 4 && model.hintsRemaining == 5, "ヒントとは別の残り")
        #expect(model.hintsUsed == 1)
        model.toggleCross(cell: cell)
        #expect(model.marks[cell] == .cat, "タップでは消えない")
        model.reset()
        #expect(model.marks[cell] == .cat, "やり直しでも消えない")
        #expect(model.mistakes == 0)
    }

    @Test("教えた猫を全部置けばクリアになる（5 回の持ち分を使い切っても、広告で続けて置ける）")
    func teachingEveryCatSolves() async {
        let (model, ads, _, services, _) = make("teachall")
        let rescue = RewardedRescue()
        for _ in 0..<50 where !model.isSolved {
            CatPuzzleView.requestTeach(model: model, teachRescue: rescue, services: services)
            await settle()
        }
        #expect(model.isSolved, "教えた猫で盤が完成しなかった")
        #expect(Set(model.catCells) == Set(model.puzzle.solutionCells))
        // 6×6 は猫 6 匹。5 回ぶん使い切ったあとの 1 匹は広告。
        #expect(model.puzzle.side == 6 && ads.shownCount == 1)
        #expect(model.teachRemaining == 0)
    }

    @Test("猫を教えるも 0 で広告 1 回につき 1 匹（purpose は teach で、ヒントの残りは減らない）")
    func teachAdFlow() async {
        let (model, ads, spy, services, _) = make("teachad")
        let rescue = RewardedRescue()
        for _ in 0..<5 { model.teachCat() }
        #expect(model.teachRemaining == 0 && model.needsAdForTeach && model.canTeach)
        #expect(CatPuzzleView.teachBadge(for: model) == .ad(gain: 1))
        CatPuzzleView.requestTeach(model: model, teachRescue: rescue, services: services)
        await settle()
        #expect(ads.shownCount == 1 && model.catCells.count == 6 && model.isSolved)
        #expect(model.hintsRemaining == 5)
        #expect(rewardEvents(spy) == ["reward_request", "reward_ad"])
        #expect(spy.rewards.map(\.purpose) == [.teach] && spy.requests.map(\.purpose) == [.teach])
    }

    @Test("猫を教える広告の途中で局が入れ替わったら乗せない")
    func teachAdForReplacedGameIsRejected() {
        let (model, _, _, _, _) = make("teachstale")
        for _ in 0..<5 { model.teachCat() }
        #expect(!model.grantAdTeach(forGame: model.gameSerial + 1))
        #expect(model.catCells.count == 5)
        // 無料が残っているうちは広告の報酬を受けない。
        let (fresh, _, _, _, _) = make("teachfree")
        #expect(!fresh.grantAdTeach(forGame: fresh.gameSerial) && fresh.catCells.isEmpty)
    }

    @Test("中断データから戻しても、教えた猫は固定のまま。残りはステージ共通のキーから戻る")
    func restoreKeepsTaughtCat() {
        let store = MemorySnapshotStore()
        let (model, _, _, services, defaults) = make("restore", store: store)
        model.teachCat()
        model.useHint()
        let restored = CatPuzzleModel(services: services, stageDefaults: defaults)
        #expect(restored.stage == 1 && restored.puzzle == model.puzzle)
        #expect(restored.hintCells == model.hintCells && restored.hintsUsed == 2)
        #expect(restored.teachRemaining == 4 && restored.hintsRemaining == 4)
    }

    // MARK: - 操作の段・自由に遊ぶ

    @Test("ステージの段は「戻す」ではなく「猫を教える」。自由に遊ぶは今のまま")
    func controlsDifferByMode() {
        let (stage, _, _, _, _) = make("controls")
        let stageIDs = CatPuzzleView.playControls(for: stage).actions.map(\.id)
        #expect(stageIDs == ["teach", "hint"])
        let free = CatPuzzleModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: SupplyAdService(rewardEarned: true)),
                                  size: .normal, seed: 1, stageDefaults: makeDefaults("free"))
        #expect(CatPuzzleView.playControls(for: free).actions.map(\.id) == ["undo", "hint"])
        #expect(!free.canTeach, "自由に遊ぶでは教えられない")
        #expect(free.hintsRemaining == CatPuzzleModel.freeHints, "自由に遊ぶのヒントは 1 局 1 回＋広告 3 回のまま")
        #expect(CatPuzzleView.hintBadge(for: free) == .count(CatPuzzleModel.freeHints))
        free.useHint()
        #expect(free.needsAdForHint && free.hints.capacity == 4)
        // 自由に遊ぶの局は共通の残りを減らさない。
        #expect(free.stageHintsLeft == 5)
    }

    @Test("ステージで教える・ヒントが空でも、ボタンは広告の面で押せる。終局後は何も出ない")
    func buttonsStayEnabledWithAdBadge() {
        let (model, _, _, _, _) = make("enabled")
        for _ in 0..<5 { model.teachCat() }
        let teach = CatPuzzleView.playControls(for: model).actions.first { $0.id == "teach" }
        #expect(teach?.isEnabled == true && teach?.badge == .ad(gain: 1))
        let watching = CatPuzzleView.playControls(for: model, isWatchingAd: true).actions.first { $0.id == "teach" }
        #expect(watching?.isEnabled == false, "視聴中は押せない")
    }
}
