import Core
import Foundation
import Testing
@testable import GameRunner

@Suite("チャリンコおじさん: 進行と操作")
@MainActor
struct RunnerModelTests {

    @Test("タップで走り出し、もう一度のタップで跳ぶ")
    func pressStartsThenJumps() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("press"))
        #expect(model.phase == .ready)
        model.press()
        #expect(model.phase == .running)
        model.release()

        model.press()
        #expect(!model.field.isGrounded, "走行中のタップは踏み切りになる")
    }

    @Test("押しっぱなしでは着地のたびに勝手に跳ばない")
    func holdingDoesNotAutoJump() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("hold"))
        model.press()          // スタート
        model.press()          // 押しっぱなしなので何も起きない
        #expect(model.field.isGrounded, "スタートと同じ押下では踏み切らない")
        model.release()
        model.press()
        #expect(!model.field.isGrounded)
        // 押したまま着地しても、離して押し直すまでは跳ばない。
        var frames = 0
        while !model.field.isGrounded, frames < 300 {
            frames += 1
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.field.isGrounded)
        model.press()
        #expect(model.field.isGrounded, "離していないので踏み切らない")
    }

    @Test("ミスするとステージの頭から何度でもやり直せる")
    func retryIsFreeAndUnlimited() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("retry"))
        for _ in 0..<3 {
            failCurrentStage(model)
            #expect(model.phase == .failed)
            let generation = model.runGeneration
            model.retryStage()
            #expect(model.phase == .ready)
            #expect(model.field.distance == 0, "コースの頭に戻る")
            #expect(model.runGeneration == generation + 1)
        }
        #expect(model.stageNumber == 1, "ミスでステージは戻らない")
    }

    @Test("クリアすると次のステージへ進める")
    func clearingAdvances() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("advance"))
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        model.advanceToNextStage()
        #expect(model.stageNumber == 2)
        #expect(model.phase == .ready)
        #expect(model.field.stage.number == 2)
    }

    @Test("最終ステージをクリアすると全ステージクリアになる")
    func finalStageEndsTheRun() {
        let model = RunnerModel(
            startingAt: RunnerRules.stageCount, preference: makePreference("final")
        )
        autoPlayCurrentStage(model)
        #expect(model.phase == .allCleared)
        model.advanceToNextStage()
        #expect(model.stageNumber == RunnerRules.stageCount, "その先は無い")
    }

    @Test("クリア済みのステージをタイムアタックで周回できる")
    func canReplayClearedStage() {
        let model = RunnerModel(startingAt: 3, preference: makePreference("replay"))
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        model.replayCurrentStage()
        #expect(model.stageNumber == 3, "同じステージのまま")
        #expect(model.phase == .ready)
        #expect(model.field.distance == 0)
    }

    @Test("ベストタイムはステージごとに残り、縮んだときだけ更新される")
    func keepsBestTimePerStage() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("best"))
        autoPlayCurrentStage(model)
        guard let first = model.best(forStage: 1) else { Issue.record("記録されていない"); return }
        #expect(model.best(forStage: 2) == nil, "遊んでいないステージには記録が無い")

        #expect(model.didSetBestTime, "初クリアは必ず更新")

        // ゆっくりモードで走ると同じ操作でも実時間は伸びる。遅いタイムで上書きされないこと。
        model.replayCurrentStage()
        model.setSlowMode(true)
        autoPlayCurrentStage(model)
        #expect(model.best(forStage: 1) == first, "遅いタイムでは更新しない")
        #expect(!model.didSetBestTime, "更新していないのにバッジを出さない")
    }

    /// 画面の「0:22」と記録の「23秒」が食い違わないこと（最初の実機確認で見つかった不整合）。
    @Test("ベストタイムは画面のタイム表示と同じ切り捨てで記録する")
    func bestTimeMatchesDisplayedTime() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("best-round"))
        autoPlayCurrentStage(model)
        #expect(model.best(forStage: 1) == max(1, Int(model.elapsed)))
    }
}

@Suite("チャリンコおじさん: チェックポイント再開")
@MainActor
struct RunnerCheckpointTests {

    /// チェックポイントを通過したあとでミスさせる。
    private func failAfterCheckpoint(_ model: RunnerModel) {
        failCurrentStage(model, stopAfterCheckpoint: true)
    }

    @Test("チェックポイント通過後のミスだけ広告での再開を出せる")
    func offeredOnlyAfterCheckpoint() {
        let before = RunnerModel(startingAt: 1, preference: makePreference("cp-before"))
        failCurrentStage(before)
        #expect(before.phase == .failed)
        #expect(!before.field.passedCheckpoint)
        #expect(!before.canResumeFromCheckpoint, "手前でのミスでは出さない")

        let after = RunnerModel(startingAt: 1, preference: makePreference("cp-after"))
        failAfterCheckpoint(after)
        #expect(after.phase == .failed)
        #expect(after.field.passedCheckpoint)
        #expect(after.canResumeFromCheckpoint)
    }

    @Test("再開はステージごとに 1 回だけ")
    func onlyOncePerStage() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("cp-once"))
        failAfterCheckpoint(model)
        #expect(model.resumeFromCheckpoint(forRun: model.runGeneration))
        #expect(model.field.distance == model.stage.checkpoint)

        failAfterCheckpoint(model)
        #expect(!model.canResumeFromCheckpoint, "2 回目は出せない")
        #expect(!model.resumeFromCheckpoint(forRun: model.runGeneration))
    }

    /// ソリティアの補充（#509）と同じ契約。広告のロード中にコースが作り直されたら適用しない。
    @Test("広告のあいだに別のコースが始まっていたら適用しない")
    func rejectsStaleRun() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("cp-stale"))
        failAfterCheckpoint(model)
        let stale = model.runGeneration
        model.retryStage()                                  // 広告のロード中に「もう一度」
        #expect(!model.resumeFromCheckpoint(forRun: stale))
    }

    @Test("再開したステージのクリアはベストタイムに残さない")
    func resumedClearIsNotRecorded() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("cp-record"))
        failAfterCheckpoint(model)
        #expect(model.resumeFromCheckpoint(forRun: model.runGeneration))
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(model.best(forStage: 1) == nil, "半分だけ走った回はベストにしない")

        // 通しで走れば記録される。
        model.replayCurrentStage()
        autoPlayCurrentStage(model)
        #expect(model.best(forStage: 1) != nil)
    }

    @Test("次のステージへ進むと再開権が戻る")
    func resetsOnNextStage() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("cp-reset"))
        failAfterCheckpoint(model)
        #expect(model.resumeFromCheckpoint(forRun: model.runGeneration))
        autoPlayCurrentStage(model)
        model.advanceToNextStage()
        failAfterCheckpoint(model)
        #expect(model.canResumeFromCheckpoint, "ステージが変われば 1 回ぶん戻る")
    }
}

@Suite("チャリンコおじさん: 中断と復元")
@MainActor
struct RunnerSnapshotTests {

    @Test("次に開いたときは同じステージの頭から始まる")
    func resumesAtStageHead() {
        let store = MemorySnapshotStore()
        let first = RunnerModel(services: makeServices(store: store), startingAt: 1,
                                preference: makePreference("snap-1"))
        autoPlayCurrentStage(first)
        first.advanceToNextStage()
        autoPlayCurrentStage(first)          // ステージ 2 もクリア
        #expect(first.phase == .cleared)

        let second = RunnerModel(services: makeServices(store: store),
                                 preference: makePreference("snap-1b"))
        #expect(second.stageNumber == 3, "クリア表示中に中断したら進み先から始まる")
        #expect(second.field.distance == 0, "フレーム単位では保存しない")
    }

    @Test("ベストタイムは決着しても消えない")
    func bestTimesSurviveFinish() {
        let store = MemorySnapshotStore()
        let first = RunnerModel(services: makeServices(store: store),
                                startingAt: RunnerRules.stageCount,
                                preference: makePreference("snap-2"))
        autoPlayCurrentStage(first)
        #expect(first.phase == .allCleared)
        let best = first.best(forStage: RunnerRules.stageCount)
        #expect(best != nil)

        let second = RunnerModel(services: makeServices(store: store),
                                 preference: makePreference("snap-2b"))
        #expect(second.best(forStage: RunnerRules.stageCount) == best)
    }

    @Test("壊れた中断データは捨てて新規開始に倒す")
    func rejectsCorruptSnapshot() {
        for broken in [
            #"{"stage":0,"bestSeconds":[]}"#,                       // ステージ番号が範囲外
            #"{"stage":99,"bestSeconds":[]}"#,                      // 同上
        ] {
            let store = MemorySnapshotStore()
            store.inject(Data(broken.utf8), for: "runner")
            let model = RunnerModel(services: makeServices(store: store),
                                    preference: makePreference("snap-broken"))
            #expect(model.stageNumber == 1)
        }
    }

    @Test("ベストタイムの長さと値は復元時に整えられる")
    func normalizesBestSeconds() {
        // 短すぎる配列は 0 で埋め、到達しえない値（負・上限超え）は未クリアに倒す。
        let snapshot = RunnerSnapshot(stage: 2, bestSeconds: [30, -1, 99_999_999])
        guard let restored = snapshot.validated() else { Issue.record("復元できない"); return }
        #expect(restored.bestSeconds.count == RunnerRules.stageCount)
        #expect(restored.bestSeconds[0] == 30)
        #expect(restored.bestSeconds[1] == 0, "負のタイムは二度と更新できない自己ベストになる")
        #expect(restored.bestSeconds[2] == 0)

        // 長すぎる配列は切り詰める。
        let long = RunnerSnapshot(stage: 1, bestSeconds: Array(repeating: 5, count: 100))
        #expect(long.validated()?.bestSeconds.count == RunnerRules.stageCount)
    }
}

@Suite("チャリンコおじさん: 一時停止とゆっくりモード")
@MainActor
struct RunnerPauseTests {

    @Test("いつでも一時停止でき、止めた状態からは進まない")
    func pauseStopsTheWorld() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("pause"))
        model.press()
        model.release()
        model.tick(dt: 0.5)
        let distance = model.field.distance
        model.pause()
        #expect(model.phase == .paused)
        for _ in 0..<60 { model.tick(dt: 1.0 / 60) }
        #expect(model.field.distance == distance, "止めているあいだは進まない")
        model.resume()
        #expect(model.phase == .running, "止める前の状態に戻る")
    }

    @Test("走り出す前に止めても、再開したら走り出す前のまま")
    func pauseBeforeStart() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("pause-ready"))
        model.pause()
        model.resume()
        #expect(model.phase == .ready)
    }

    @Test("ミス・クリアの表示中は一時停止しない")
    func noPauseAfterFinish() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("pause-failed"))
        failCurrentStage(model)
        model.pause()
        #expect(model.phase == .failed)
    }

    @Test("ゆっくりモードは設定へ保存され、開き直しても残る")
    func slowModePersists() {
        let preference = makePreference("slow")
        let model = RunnerModel(startingAt: 1, preference: preference)
        #expect(!model.isSlowMode, "既定はオフ")
        model.setSlowMode(true)
        #expect(preference.isEnabled)

        let reopened = RunnerModel(startingAt: 1, preference: preference)
        #expect(reopened.isSlowMode)
        // 設定画面で戻されたら取り込む。
        preference.isEnabled = false
        reopened.syncSlowModeFromPreference()
        #expect(!reopened.isSlowMode)
    }

    /// **速さではなく時間を遅くする**（`RunnerRules.slowFactor`）。速さだけを落とすと
    /// ジャンプの飛距離が縮み、易しくするはずの設定が「穴を跳び越せない」に変わる。
    @Test("ゆっくりモードでもジャンプの飛距離は変わらない")
    func slowModeKeepsJumpDistance() {
        func jumpDistance(slow: Bool) -> Double {
            let model = RunnerModel(startingAt: 1, preference: makePreference("slow-\(slow)"))
            model.setSlowMode(slow)
            model.press()
            model.release()
            model.press()
            model.release()
            let start = model.field.distance
            var frames = 0
            while !model.field.isGrounded, frames < 60 * 10 {
                frames += 1
                model.tick(dt: 1.0 / 60)
            }
            return model.field.distance - start
        }
        #expect(abs(jumpDistance(slow: true) - jumpDistance(slow: false)) < 0.6)
    }
}

@Suite("チャリンコおじさん: 読み上げ文")
struct RunnerAccessibilityTests {

    @Test("ステージと進み具合を読む")
    func stageAndProgress() {
        #expect(RunnerAccessibility.stageLabel(number: 3, total: 15) == "ステージ 3 / 15")
        #expect(RunnerAccessibility.progressLabel(0) == "ゴールまで 100パーセント")
        #expect(RunnerAccessibility.progressLabel(1) == "ゴールまで 0パーセント")
        // 5 刻みに丸める（1% ごとに変わると耳で追えない）。
        #expect(RunnerAccessibility.progressLabel(0.51) == "ゴールまで 50パーセント")
    }

    @Test("タイムは分と秒に分けて読む")
    func time() {
        #expect(RunnerAccessibility.timeLabel(seconds: 42) == "42秒")
        #expect(RunnerAccessibility.timeLabel(seconds: 65) == "1分5秒")
        #expect(RunnerAccessibility.bestLabel(seconds: nil) == "ベストタイムはまだありません")
        #expect(RunnerAccessibility.bestLabel(seconds: 30) == "ベストタイム 30秒")
    }

    @Test("状態ごとの結果を読む")
    func result() {
        #expect(RunnerAccessibility.resultLabel(phase: .failed, stageNumber: 2) == "ステージ 2 でミスしました")
        #expect(RunnerAccessibility.resultLabel(phase: .cleared, stageNumber: 2) == "ステージ 2 クリア")
        #expect(RunnerAccessibility.resultLabel(phase: .allCleared, stageNumber: 15) == "全ステージクリア")
    }
}
