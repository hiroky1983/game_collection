import Core
import Foundation
import Testing
@testable import GameRunner
import CoreTestSupport

/// 評価リクエストが**リザルトに移ってから**出ること（#1143）。
///
/// このゲームだけはゴールとリザルトのあいだに演出が入る（`beginGoalChase` 1.5 秒・#1121 /
/// `beginStory` 最長 4.8 秒・#1123）。記録・解析・順位表はゴールに着いた瞬間に確定させる
/// （#1092）ので、評価リクエストだけを演出のあいだ伏せる。
///
/// View を介さずモデルの遷移で確かめられるよう、`ReviewRequestService(delay: .zero)` を注入し、
/// 画面側（`reviewRequestPrompt`）が呼ぶ `performPendingRequest` を直接叩く。
@Suite("チャリンコおじさん: 評価リクエストの発火タイミング（#1143）")
@MainActor
struct RunnerReviewRequestTimingTests {
    private let appVersion = "1.1.6"

    /// 使い捨ての `PlayLog`（`UserDefaults.standard` を汚さない）。
    /// 条件2（通算5勝）まであと1勝ぶん貯めてあるので、**次の1勝＝ステージクリアで予定が立つ**。
    private func makeReadyLog(_ suite: String) -> PlayLog {
        let name = "asobiba.runner.tests.playlog.review.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        for _ in 0..<(ReviewRequestPolicy.firstRequestWins - 1) { log.recordWin() }
        return log
    }

    /// 到達点を最終面まで開け、`stage` 面から始めるモデルと、そこへ渡した評価リクエストの司令塔。
    private func makeModel(
        startingAt stage: Int, log: PlayLog, suite: String
    ) throws -> (RunnerModel, ReviewRequestService) {
        let store = MemorySnapshotStore()
        try store.save(
            RunnerSnapshot(stage: stage, reachedStage: RunnerRules.stageCount), for: RunnerModel.gameID
        )
        let review = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        let model = RunnerModel(
            services: makeServices(store: store, log: log, review: review),
            startingAt: stage,
            preference: makePreference(suite)
        )
        return (model, review)
    }

    /// ゴールまで走らせ、決着の演出（`.chasing` / `.story`）に入ったところで止める。
    private func runToGoal(_ model: RunnerModel, maxFrames: Int = 60 * 300) {
        if model.phase == .ready { model.press(); model.release() }
        var frames = 0
        while model.phase.isRunning, frames < maxFrames {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        model.release()
    }

    /// 画面側（`reviewRequestPrompt`）がやることをそのままなぞる。
    /// - Returns: OS へのリクエストが呼ばれたか。
    private func performAsScreenWould(_ service: ReviewRequestService) async -> Bool {
        var requested = false
        await service.performPendingRequest { requested = true }
        return requested
    }

    @Test("ゴールの演出のあいだは出ず、リザルトに移ってから出る")
    func deferredUntilResultAfterGoalChase() async throws {
        let log = makeReadyLog("chase")
        let (model, review) = try makeModel(startingAt: 1, log: log, suite: "review-chase")

        runToGoal(model)
        #expect(model.phase == .chasing, "ゴールの演出に入っていること")

        // 予定そのものは立っている（記録・解析と同じくゴールの瞬間に確定する）が、伏せてある。
        #expect(review.isDeferredUntilResultIsVisible)
        #expect(review.pendingRequestID == nil, "演出中は画面側の `task(id:)` が起動しない")
        var requested = await performAsScreenWould(review)
        #expect(requested == false, "演出のさなかにダイアログを出さない")

        model.skipGoalChase()
        #expect(model.phase == .cleared)
        #expect(review.isDeferredUntilResultIsVisible == false)
        #expect(review.pendingRequestID != nil, "リザルトに移ったので予定が表に戻る")
        requested = await performAsScreenWould(review)
        #expect(requested, "リザルトの後に出る")
    }

    @Test("時間切れで演出が明けたときも、明けてから出る")
    func deferredUntilGoalChaseTimesOut() async throws {
        let log = makeReadyLog("chase-timeout")
        let (model, review) = try makeModel(startingAt: 1, log: log, suite: "review-chase-timeout")

        runToGoal(model)
        #expect(model.phase == .chasing)

        // 演出の尺（`RunnerRules.goalChaseDuration`）のちょうど手前まで進めても、まだ伏せたまま。
        var elapsed = 0.0
        while elapsed < RunnerRules.goalChaseDuration - 0.1 {
            model.tick(dt: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        #expect(model.phase == .chasing)
        #expect(review.pendingRequestID == nil)
        var requested = await performAsScreenWould(review)
        #expect(requested == false)

        while model.phase == .chasing { model.tick(dt: 1.0 / 60) }
        #expect(model.phase == .cleared)
        #expect(review.pendingRequestID != nil)
        requested = await performAsScreenWould(review)
        #expect(requested)
    }

    @Test("世界の締めのあいだも出ず、見終えてから出る")
    func deferredUntilResultAfterStory() async throws {
        let log = makeReadyLog("story")
        // 6 面の初回クリアは、毎面の演出の代わりに世界の締め（最長 4.8 秒）が流れる（#1123）。
        let (model, review) = try makeModel(startingAt: 6, log: log, suite: "review-story")

        runToGoal(model)
        #expect(model.phase == .story, "世界の締めに入っていること")

        #expect(review.isDeferredUntilResultIsVisible)
        #expect(review.pendingRequestID == nil)
        var requested = await performAsScreenWould(review)
        #expect(requested == false, "締めのさなかにダイアログを出さない")

        model.finishStory()
        #expect(model.phase == .cleared)
        #expect(review.pendingRequestID != nil)
        requested = await performAsScreenWould(review)
        #expect(requested)
    }

    @Test("演出の途中で「はじめから」を選んだら、その走行中には出ない")
    func stillDeferredWhenLeavingPresentation() async throws {
        let log = makeReadyLog("restart")
        let (model, review) = try makeModel(startingAt: 1, log: log, suite: "review-restart")

        runToGoal(model)
        #expect(model.phase == .chasing)

        model.newGame()
        #expect(model.phase == .ready)
        #expect(review.pendingRequestID == nil, "走り直した局面でダイアログを出さない")
        let requested = await performAsScreenWould(review)
        #expect(requested == false)
    }

    @Test("QA の起動引数で締めを被せた画面でも伏せたまま（-simulateRunner story-world1）")
    func deferredInDebugStoryScenario() async throws {
        let log = makeReadyLog("debug-story")
        let (model, review) = try makeModel(startingAt: 1, log: log, suite: "review-debug-story")

        // このシナリオはまず `skipGoalChase()` で `.cleared` を作ってから締めを被せる
        // （`RunnerModel+Debug.swift`）。伏せを決着の側ではなく局面の入口に付けてあるので、
        // その順でも締めのあいだは出ない。
        model.applyDebugScenario("story-world1")
        #expect(model.phase == .story, "締めが被さっていること")

        #expect(review.pendingRequestID == nil)
        let requested = await performAsScreenWould(review)
        #expect(requested == false)
    }

    @Test("伏せは決着のたびに上書きされるので、演出を挟まないゲームの勝ちで表に戻る")
    func deferralIsOverwrittenByNextFinish() async {
        let name = "asobiba.runner.tests.playlog.review.overwrite"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        for _ in 0..<(ReviewRequestPolicy.firstRequestWins - 1) { log.recordWin() }

        let review = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        review.gameDidFinish(outcome: .win)
        review.deferUntilResultIsVisible()
        #expect(review.pendingRequestID == nil, "演出を挟むゲームなので伏せられている")

        // 演出の途中で画面を離れたまま別のゲームで勝った場合。伏せが残り続けると
        // 以後どの画面でも二度と出なくなるため、決着のたびに上書きする。
        review.gameDidFinish(outcome: .win)
        #expect(review.isDeferredUntilResultIsVisible == false)
        #expect(review.pendingRequestID != nil)

        var requested = false
        await review.performPendingRequest { requested = true }
        #expect(requested)
    }
}
