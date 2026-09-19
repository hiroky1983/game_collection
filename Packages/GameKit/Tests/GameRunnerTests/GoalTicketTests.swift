import Foundation
import SpriteKit
import Testing
import Core
@testable import GameRunner
import CoreTestSupport
import GameRunnerTestSupport

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
        // 動きを見るので Reduce Motion は明示的にオフ（既定は OS の設定で、CI では有効なことがある）。
        scene.reduceMotionOverride = false
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
        scene.reduceMotionOverride = false
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

    /// 演出が明けたら走者は画面の中央へ戻らない（半透明のリザルトの裏で瞬間移動して見えるため）。
    /// 飛ばした場合も同じ画にする——飛ばす経路は `sync` を 1 度も通らないことがある
    /// （撮影シナリオ `-simulateRunner cleared`）ので、`RunnerModel.didFinishGoalChase` で判断する。
    @Test("演出のあとのリザルトでは、走者も宝くじも走り去った先に残る（飛ばしても同じ）", arguments: [false, true])
    func theResultKeepsTheRiderOffScreen(skipped: Bool) throws {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-after-\(skipped)"))
        let scene = RunnerScene(model: model)
        scene.reduceMotionOverride = false
        scene.rebuildCourse()
        #expect(runToGoal(model))

        if skipped {
            // 1 フレームも `sync` を通さずに飛ばす（撮影シナリオと同じ道）。
            model.skipGoalChase()
        } else {
            model.tick(dt: RunnerRules.goalChaseDuration)
        }
        #expect(model.phase == .cleared)
        #expect(model.didFinishGoalChase)

        scene.sync()
        #expect(scene.player.position.x > RunnerField.Metrics.width, "走者が画面の中央へ戻っている")
        let ticket = try #require(scene.goalTicket)
        #expect(ticket.position.x > scene.goalTicketBase.x, "宝くじがゴールの位置に残っている")
        #expect(ticket.action(forKey: RunnerScene.loopActionKey) == nil, "飛んだあとも揺れ続けている")

        // 次の面・やり直しでは元に戻る。
        model.replayCurrentStage()
        #expect(!model.didFinishGoalChase)
        scene.sync()
        #expect(abs(scene.player.position.x - RunnerField.Metrics.playerX) < 0.001)
    }

    @Test("空中でゴールしても、走者は地面へ降りて漕ぐコマで走り去る")
    func theRiderLandsBeforeRunningAway() {
        // コマの選び方は純関数で固定する（空中＝`isGrounded == false` でも `jump` にしない）。
        #expect(RunnerRider.frame(phase: .chasing, isGrounded: false, pedalPhase: 0) == .ride0)
        #expect(RunnerRider.frame(phase: .chasing, isGrounded: false, pedalPhase: .pi) == .ride1)
        // 比較対象: 走行中の空中は今までどおり `jump`。
        #expect(RunnerRider.frame(phase: .running, isGrounded: false, pedalPhase: 0) == .jump)

        // 足元の高さは純関数で固定する（空中でゴールする局面は自動操縦では狙って作れない）。
        let ground = RunnerField.Metrics.groundY
        let air = ground + 12
        #expect(RunnerScene.goalChaseRiderY(startY: air, progress: 0) == air, "演出の頭は着いた高さのまま")
        let mid = RunnerScene.goalChaseRiderY(startY: air, progress: RunnerScene.goalChaseLandingRatio / 2)
        #expect(mid > ground && mid < air, "降りている途中でない（\(mid)）")
        #expect(RunnerScene.goalChaseRiderY(startY: air, progress: RunnerScene.goalChaseLandingRatio) == ground)
        #expect(RunnerScene.goalChaseRiderY(startY: air, progress: 1) == ground, "降りたあとに浮き直している")
        // 接地したままゴールしたふつうの場合は、最初から最後まで地面のまま。
        for p in [0.0, 0.2, 0.5, 1.0] {
            #expect(RunnerScene.goalChaseRiderY(startY: ground, progress: p) == ground)
        }
    }

    /// VoiceOver のヒント（`RunnerView` のコース）。演出中のダブルタップはジャンプではなく
    /// **演出を飛ばす**操作なので、`RunnerModel.press` の分岐と 1:1 で文言も入れ替える
    /// （CodeRabbit の指摘・PR #1121）。
    @Test("演出中のダブルタップのヒントは「演出をスキップ」に入れ替わる")
    func theHintSwitchesDuringTheCutscene() {
        #expect(RunnerAccessibility.courseHint(phase: .chasing) == "ダブルタップで演出をスキップ")
        for phase in [RunnerPhase.ready, .running, .paused, .falling, .failed, .cleared, .allCleared] {
            #expect(RunnerAccessibility.courseHint(phase: phase) == "ダブルタップでジャンプ", "\(phase)")
        }
    }

    // MARK: Reduce Motion

    /// **`Motion.override`（プロセス全体）ではなくシーンごとの注入口を使う。**
    /// Swift Testing はスイートを並行実行するので、グローバルを立てると他のスイートの
    /// 判断まで書き換わる（#828 と同型の揺れ。実際に CI のフルスイートで踏んだ）。
    @Test("Reduce Motion がオンなら、宝くじは揺れず、その場で消える")
    func reduceMotionStillsTheTicket() throws {
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-reduce-motion"))
        let scene = RunnerScene(model: model)
        scene.reduceMotionOverride = true
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
        let model = RunnerModel(startingAt: 1, preference: makePreference("goal-sway"))
        let scene = RunnerScene(model: model)
        scene.reduceMotionOverride = false
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
