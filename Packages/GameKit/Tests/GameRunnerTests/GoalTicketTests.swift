import Foundation
import SpriteKit
import Testing
@testable import Core
@testable import GameRunner
import CoreTestSupport

/// 毎面のゴール（旗 → ひらひら浮いている宝くじ）と、着いたあとの「追いかける」演出（#1092 A0）。
///
/// 決裁の要点は 3 つで、テストもその順に並べる:
/// 1. **記録・解析・順位表・中断データはゴールに着いた瞬間に確定する**（演出は結果を変えない）
/// 2. 演出中は入力（ジャンプ）・一時停止が効かず、タップは**演出を飛ばす**操作になる
/// 3. 宝くじは全ステージでゴールの位置に浮き、やり直すと戻っている
@Suite("チャリンコおじさん: ゴールの宝くじと追いかける演出（#1092）")
@MainActor
struct RunnerGoalTicketTests {
    /// ゴールに着くところまで自動操縦で走らせ、**演出の局面（`.chasing`）で止める**。
    ///
    /// `TestSupport` の `autoPlayCurrentStage` はゴールの演出も回し切ってしまう
    /// （演出中の `press` が「飛ばす」になるため）。ここでは演出そのものを見るので、
    /// `isRunning` が落ちた時点で抜け、押しっぱなしも解いておく。
    @discardableResult
    private func runToGoal(_ model: RunnerModel, maxFrames: Int = 60 * 300) -> Bool {
        if model.phase == .ready { model.press(); model.release() }
        var frames = 0
        while model.phase.isRunning, frames < maxFrames {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        // 次の `press` が「押しっぱなし」で無視されないよう指を離しておく。
        model.release()
        return model.phase == .chasing
    }

    /// 使い捨ての `PlayLog`（`UserDefaults.standard` を汚さない）。
    private func makePlayLog(_ suite: String) -> PlayLog {
        let name = "asobiba.runner.tests.playlog.goal.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    /// 到達点を最終面まで開けた状態の入口（ワールドマップから任意の面を選べる）。
    private func makeReachedAllModel(_ suite: String) throws -> (RunnerModel, SnapshotStore) {
        let store = MemorySnapshotStore()
        try store.save(
            RunnerSnapshot(stage: 1, reachedStage: RunnerRules.stageCount), for: RunnerModel.gameID
        )
        let model = RunnerModel(
            services: makeServices(store: store), preference: makePreference(suite)
        )
        return (model, store)
    }

    // MARK: 1. 記録はゴールに着いた瞬間に確定する

    @Test("ゴールに着くと演出（.chasing）に入り、記録・順位表・到達点・中断データはその瞬間に確定している")
    func recordsSettleBeforeTheCutscene() throws {
        let store = MemorySnapshotStore()
        let spy = SpyGameCenterService()
        let log = makePlayLog("records")
        let model = RunnerModel(
            services: makeServices(store: store, log: log, gameCenter: spy),
            startingAt: 1, preference: makePreference("goal-records")
        )
        #expect(runToGoal(model), "1 面をゴールできていない（テストが空振り）")

        // ここはまだ演出中。リザルトは出ていないが、結果はもう動かない。
        #expect(model.phase == .chasing)
        #expect(model.recordResult != nil, "記録が演出明けに先送りされている")
        #expect(model.reachedStage == 2, "到達点がゴールの瞬間に伸びていない")
        #expect(model.didReachNewStage)
        #expect(spy.scores.count == 1, "順位表への送信が演出明けに先送りされている")
        let record = try #require(log.record(gameID: RunnerModel.gameID, variant: nil))
        #expect(record.bestPoints == 1, "到達ステージの記録が演出明けに先送りされている")
        let saved = try #require(store.load(RunnerSnapshot.self, for: RunnerModel.gameID))
        #expect(saved.stage == 2, "中断データが次の面を指していない（演出中に閉じるとクリアが消える）")
    }

    @Test("演出を飛ばしても、記録は増えも減りもしない")
    func skippingDoesNotChangeTheRecord() throws {
        let spy = SpyGameCenterService()
        let model = RunnerModel(
            services: makeServices(log: makePlayLog("skip"), gameCenter: spy), startingAt: 1,
            preference: makePreference("goal-skip-records")
        )
        #expect(runToGoal(model))
        let before = model.recordResult
        model.press()
        model.release()
        #expect(model.phase == .cleared)
        #expect(model.recordResult == before)
        #expect(spy.scores.count == 1, "演出を飛ばすと 2 回送っている")
    }

    // MARK: 2. 演出の時間と入力

    @Test("演出は goalChaseDuration 秒で明け、その手前ではリザルトに移らない")
    func theCutsceneLastsTheApprovedDuration() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-duration"))
        #expect(runToGoal(model))
        // 決裁の「1.5 秒程度」。長くするとクリア後にその場で走り出す流れ（#941）のテンポが落ちる。
        #expect(RunnerRules.goalChaseDuration == 1.5)

        var elapsed: Double = 0
        while elapsed < RunnerRules.goalChaseDuration - 0.02 {
            model.tick(dt: 1.0 / 60)
            elapsed += 1.0 / 60
            #expect(model.phase == .chasing, "\(elapsed) 秒でもう演出が明けている")
        }
        while model.phase == .chasing, elapsed < RunnerRules.goalChaseDuration + 0.2 {
            model.tick(dt: 1.0 / 60)
            elapsed += 1.0 / 60
        }
        #expect(model.phase == .cleared)
    }

    @Test("演出の進み（goalChaseProgress）は 0 から 1 まで上がり、演出の外では 0")
    func progressRunsFromZeroToOne() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-progress"))
        #expect(model.goalChaseProgress == 0, "走り出す前から進んでいる")
        #expect(runToGoal(model))
        #expect(model.goalChaseProgress == 0, "演出の頭は 0")

        model.tick(dt: RunnerRules.goalChaseDuration / 2)
        let half = model.goalChaseProgress
        #expect(abs(half - 0.5) < 0.01, "半分で \(half)")

        model.tick(dt: RunnerRules.goalChaseDuration)
        #expect(model.phase == .cleared)
        #expect(model.goalChaseProgress == 0, "演出の外では 0 に戻る")
    }

    @Test("演出中はタップが飛ばす操作になり、ジャンプにはならない")
    func tapSkipsInsteadOfJumping() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-tap"))
        #expect(runToGoal(model))
        let jumps = model.field.jumpCount
        model.press()
        #expect(model.phase == .cleared, "タップで飛ばせていない")
        #expect(model.field.jumpCount == jumps, "演出中のタップで跳んでいる")
        model.release()
    }

    @Test("演出中は一時停止できない")
    func pauseIsIgnoredDuringTheCutscene() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-pause"))
        #expect(runToGoal(model))
        model.pause()
        #expect(model.phase == .chasing)
    }

    @Test("最終面のゴールも演出を挟んでから全ステージクリアになる")
    func theLastStageAlsoChases() throws {
        let (model, _) = try makeReachedAllModel("goal-last")
        #expect(model.newGame(startingAtStage: RunnerRules.stageCount))
        #expect(runToGoal(model))
        #expect(model.phase == .chasing)
        // 演出中はまだ「1 回が終わった」扱いにならない（レコメンドの出し分けが動かない）。
        #expect(!model.isRunOver)
        model.tick(dt: RunnerRules.goalChaseDuration)
        #expect(model.phase == .allCleared)
        #expect(model.isRunOver)
    }

    @Test("エンドレスにはゴールが無いので、宝くじも置かれず演出も入らない")
    func endlessNeverChases() throws {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-endless"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        #expect(try #require(scene.goalTicket).parent === scene.courseLayer, "ステージ制には在る（空振り防止）")

        model.newGame(mode: .endless)
        scene.rebuildCourse()
        // 控えを消し忘れると、コース層から外した宙ぶらりんのノードを掴んだままになる。
        #expect(scene.goalTicket == nil, "エンドレスにゴールの宝くじが残っている")

        failCurrentStage(model)
        #expect(model.phase == .failed)
        #expect(model.goalChaseProgress == 0)
    }

    // MARK: 3. 宝くじの絵と置き場

    @Test("1〜30 面すべてで、ゴールの位置に宝くじが浮いている")
    func everyStageHasATicketAtTheGoal() throws {
        let (model, _) = try makeReachedAllModel("goal-all-stages")
        let scene = RunnerScene(model: model)
        for number in 1...RunnerRules.stageCount {
            #expect(model.newGame(startingAtStage: number))
            scene.rebuildCourse()
            let ticket = try #require(scene.goalTicket, "\(number) 面に宝くじが無い")
            #expect(ticket.parent === scene.courseLayer, "\(number) 面: コース層に載っていない")
            #expect(ticket.texture === scene.lotteryTicketTexture, "\(number) 面: 別の絵が貼られている")
            #expect(
                abs(ticket.position.x - model.field.stage.length) < 0.001,
                "\(number) 面: ゴール \(model.field.stage.length) に対し \(ticket.position.x)"
            )
            #expect(abs(ticket.position.y - RunnerScene.goalTicketY) < 0.001, "\(number) 面の高さ")
        }
    }

    /// 決裁の「跳んで取らないといけないと誤解させない高さ」。券の上端が走者の頭
    /// （`RunnerRider.visualHeight`）より下に収まり、下端は地面から浮いていること。
    @Test("宝くじは走者の高さに浮き、頭より上へは出ない")
    func theTicketFloatsAtRunnerHeight() {
        let sprite = RunnerPixelArt.lotteryTicket()
        let half = Double(sprite.height) * RunnerScene.riderPlacement.unit / 2
        let top = RunnerScene.goalTicketY + half - RunnerField.Metrics.groundY
        let bottom = RunnerScene.goalTicketY - half - RunnerField.Metrics.groundY
        #expect(bottom > 0, "券の下端が地面に埋まっている（\(bottom)）")
        #expect(top < RunnerRider.visualHeight, "券の上端が走者の頭より上（\(top)）")
    }

    @Test("同じ面をやり直すと、宝くじがゴールの位置に戻っている")
    func retryPutsTheTicketBack() throws {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-retry"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        let home = try #require(scene.goalTicket).position

        #expect(runToGoal(model))
        model.tick(dt: RunnerRules.goalChaseDuration / 2)
        scene.sync()
        #expect(try #require(scene.goalTicket).position != home, "演出で飛んでいない（空振り）")

        model.skipGoalChase()
        model.replayCurrentStage()
        scene.sync()
        let again = try #require(scene.goalTicket)
        #expect(again.position == home)
        #expect(again.alpha == 1)
        #expect(again.zRotation == 0)
    }

    @Test("演出は宝くじを画面の外へ飛ばし、走者を画面の右の外まで走らせる")
    func theCutsceneMovesTicketAndRiderOffScreen() throws {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-motion"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        #expect(runToGoal(model))

        scene.sync()
        let startX = scene.player.position.x
        #expect(abs(startX - RunnerField.Metrics.playerX) < 0.001, "演出の頭は走者の定位置")

        model.tick(dt: RunnerRules.goalChaseDuration * 0.5)
        scene.sync()
        let ticket = try #require(scene.goalTicket)
        #expect(ticket.position.x > scene.goalTicketBase.x, "宝くじが右へ飛んでいない")
        #expect(ticket.position.y > scene.goalTicketBase.y, "宝くじが上がっていない")
        #expect(scene.player.position.x > startX, "走者が追いかけていない")

        // 演出の終わりには、どちらも画面（幅 100）の外へ出ている。
        model.tick(dt: RunnerRules.goalChaseDuration * 0.49)
        scene.sync()
        #expect(model.phase == .chasing, "この時点ではまだ演出中（空振り防止）")
        #expect(scene.player.position.x > RunnerField.Metrics.width, "走者が画面内に残っている")
    }

    // MARK: Reduce Motion

    @Test("Reduce Motion がオンなら、宝くじは揺れず、その場で消える")
    func reduceMotionStillsTheTicket() throws {
        Motion.override = true
        defer { Motion.override = nil }

        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-reduce-motion"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        let ticket = try #require(scene.goalTicket)
        #expect(ticket.action(forKey: RunnerScene.loopActionKey) == nil, "揺れの動きが掛かっている")

        #expect(runToGoal(model))
        model.tick(dt: RunnerRules.goalChaseDuration * 0.5)
        scene.sync()
        #expect(ticket.position == scene.goalTicketBase, "その場で消えず動いている")
        #expect(ticket.alpha == 0, "消えていない")
        // おじさんは走り去る（「クリアしたのに何も起きない」にしないため）。
        #expect(scene.player.position.x > RunnerField.Metrics.playerX)
    }

    @Test("Reduce Motion がオフなら、宝くじはゆらゆら揺れる")
    func theTicketSwaysWithoutReduceMotion() throws {
        Motion.override = false
        defer { Motion.override = nil }

        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-sway"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        let ticket = try #require(scene.goalTicket)
        #expect(ticket.action(forKey: RunnerScene.loopActionKey) != nil)
    }

    // MARK: 撮影シナリオ（#1092 の受け入れ条件）

    #if DEBUG
    @Test("-simulateRunner cleared は演出を飛ばしたリザルトで止まる（ASO 撮影の絵を変えない）")
    func capturedClearedSkipsTheCutscene() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-capture-cleared"))
        model.applyDebugScenario("cleared")
        #expect(model.phase == .cleared)
    }

    @Test("-simulateRunner chasing は演出の途中で止まり、そこから時間が進まない")
    func capturedChasingFreezesMidCutscene() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-capture-chasing"))
        model.applyDebugScenario("chasing")
        #expect(model.phase == .chasing)
        let progress = model.goalChaseProgress
        #expect(progress > 0.2 && progress < 0.7, "演出の途中ではない（\(progress)）")
        // 撮る前に先へ進んでしまわない（#1086 と同じ「tick を止めてから撮る」）。
        for _ in 0..<120 { model.tick(dt: 1.0 / 60) }
        #expect(model.phase == .chasing)
        #expect(model.goalChaseProgress == progress)
    }
    #endif
}
