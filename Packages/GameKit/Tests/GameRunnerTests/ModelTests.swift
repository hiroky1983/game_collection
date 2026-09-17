import Core
import Foundation
import Testing
@testable import GameRunner
import CoreTestSupport

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
            #expect(model.phase == .running, "スタート画面を挟まずその場で走り出す（#941）")
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
        #expect(model.phase == .running, "スタート画面を挟まずその場で走り出す（#941）")
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
        #expect(model.phase == .running, "スタート画面を挟まずその場で走り出す（#941）")
        #expect(model.field.distance == 0)
    }

    /// 秒数は廃止した（#931・会長決裁）。クリアで残るのは到達点だけで、印は初到達のときだけ。
    @Test("クリアで秒数の記録は起きず、初めて次の面に到達したときだけ印が立つ")
    func clearingMarksNewStageOnlyOnce() {
        let log = makePlayLog("new-stage")
        let model = RunnerModel(
            services: makeServices(log: log), startingAt: 1, preference: makePreference("new-stage")
        )
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(model.didReachNewStage, "初クリアで 2 面に初到達")
        #expect(model.reachedStage == 2)
        #expect(log.record(gameID: RunnerModel.gameID)?.bestSeconds == nil, "秒数はどこにも記録しない")
        #expect(log.record(gameID: RunnerModel.gameID)?.bestPoints == 1, "記録はクリアした面の番号")

        // 同じ面をもう一度クリアしても到達点は伸びないので印は出ない。
        model.replayCurrentStage()
        #expect(!model.didReachNewStage, "コースを作り直したら印は消える")
        model.setSlowMode(true)
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(!model.didReachNewStage, "到達済みの面では印を出さない")
        #expect(model.reachedStage == 2)

        // 次の面へ進んでクリアすれば、また初到達。
        model.advanceToNextStage()
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(model.didReachNewStage)
        #expect(model.reachedStage == 3)
    }

    /// 使い捨ての `PlayLog`（`UserDefaults.standard` を汚さない）。
    private func makePlayLog(_ suite: String) -> PlayLog {
        let name = "asobiba.runner.tests.playlog.model.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    /// QA用ショーケース（`-simulateRunner showcase`）は `stageNumber` を動かさない差し替えなので、
    /// クリアしても実ステージの記録・スコア送信を汚してはいけない（CodeRabbit指摘）。
    @Test("QAショーケースのクリアは通常ステージの記録を書き換えない")
    func showcaseClearDoesNotTouchRealStageRecord() {
        let gameCenter = SpyGameCenterService()
        let model = RunnerModel(
            services: makeServices(gameCenter: gameCenter),
            startingAt: 3,
            preference: makePreference("showcase")
        )
        autoPlayCurrentStage(model)
        model.replayCurrentStage()
        #expect(model.reachedStage == 4)
        let scoreCountBefore = gameCenter.scores.count

        model.applyDebugScenario("showcase")
        autoPlayCurrentStage(model)

        #expect(model.phase == .allCleared, "ショーケースのクリアは全クリア扱いで打ち切る")
        #expect(model.reachedStage == 4, "ショーケースのクリアで到達点が動いてはいけない")
        #expect(!model.didReachNewStage)
        #expect(gameCenter.scores.count == scoreCountBefore, "ショーケースのクリアでスコアを送信してはいけない")
    }

    /// 撮影用シナリオ `-simulateRunner bird` / `bird-low` / `bird-up`（#945 の
    /// 「飛び立つ前・上がっている途中・上がりきった鳥の下を走ったまま抜ける」の画）と
    /// `dog`（#955・画面の中央で向かい合う瞬間）・`boar`（#801）が、**本当に狙った状態・走行中で止まる**こと。
    /// 自動操縦が途中でミスすると `.falling` で止まる。
    @Test("撮影用シナリオ bird / bird-low / bird-up / dog / boar は狙った状態で止まる")
    func animalScenariosFreezeWhereIntended() {
        func make(_ name: String) -> RunnerModel {
            let model = RunnerModel(startingAt: 1, preference: makePreference("capture-\(name)"))
            model.applyDebugScenario(name)
            #expect(model.phase == .running, "\(name): ミスせずに到達している（\(model.phase)）")
            return model
        }
        let perched = make("bird")
        if let bird = perched.field.stage.hazards.first(where: { $0.kind == .bird }) {
            #expect(bird.birdTravel(atRunnerDistance: perched.field.distance) == 0, "まだ飛び立っていない")
            #expect(perched.field.distance >= bird.birdTakeoffDistance - RunnerRules.birdFlutterDistance, "羽ばたきの予備動作中")
        } else { Issue.record("ショーケースに鳥が無い") }

        let low = make("bird-low")
        if let bird = low.field.stage.hazards.first(where: { $0.kind == .bird }),
           let frame = bird.frame(atRunnerDistance: low.field.distance) {
            #expect(frame.advance > 0, "飛び立っている")
            #expect(frame.bottom >= RunnerHazardKind.birdLowTop && frame.bottom < RunnerField.Metrics.playerHeight, "まだ頭より低いところを上がっている途中")
            #expect(low.field.isGrounded && low.field.playerMaxX < frame.start, "おじさんはまだ手前を走っている")
        } else { Issue.record("bird-low: ショーケースに鳥が無い") }

        let up = make("bird-up")
        if let bird = up.field.stage.hazards.first(where: { $0.kind == .bird }),
           let frame = bird.frame(atRunnerDistance: up.field.distance) {
            #expect(frame.bottom >= RunnerHazardKind.birdMeetBottom, "鳥は跳んだ先の高さまで上がりきっている")
            #expect(up.field.isGrounded, "走ったまま")
            #expect(up.field.playerMaxX > frame.start && up.field.playerMinX < frame.end, "鳥の真下")
        } else { Issue.record("bird-up: ショーケースに鳥が無い") }

        let dog = make("dog")
        if let hazard = dog.field.stage.hazards.first(where: { $0.kind == .dog }),
           let frame = hazard.frame(atRunnerDistance: dog.field.distance) {
            let center = RunnerField.Metrics.width / 2 - RunnerField.Metrics.playerX
            #expect(frame.advance < 0 && frame.advance == -RunnerRules.dogAdvance, "犬は左向きに歩いている（#955）")
            #expect(dog.field.isGrounded, "走者はまだ接地して向かい合っている")
            #expect(frame.start > dog.field.playerMaxX, "犬は走者の前")
            #expect(abs(frame.start - dog.field.distance - center) < 2, "犬の鼻先は画面の中央（走者の \(center) 先）")
        } else { Issue.record("ショーケースの犬が現れていない") }

        let boar = make("boar")
        if let hazard = boar.field.stage.hazards.first(where: { $0.kind == .boar }),
           let frame = hazard.frame(atRunnerDistance: boar.field.distance) {
            #expect(frame.advance < 0, "イノシシは突進中")
            #expect(frame.start - boar.field.distance < RunnerField.Metrics.width - RunnerField.Metrics.playerX, "画面の中にいる")
        }
    }

    /// 撮影用シナリオ `-simulateRunner invincible`（#797 の受け入れ条件「実機スクショ」の画）が、
    /// **無敵のまま岩の中に居て、走行中のまま**（ミスしていない）で止まること。
    /// 無敵が効いていなければ、この位置は `.crashed` → `.falling` になっている。
    @Test("撮影用シナリオ invincible は無敵のまま岩の中で止まる")
    func invincibleScenarioFreezesInsideTheRock() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("invincible-capture"))
        model.applyDebugScenario("invincible")
        guard let rock = model.field.stage.hazards.first(where: { $0.kind != .pit }) else {
            Issue.record("ショーケースに岩が無い")
            return
        }
        #expect(model.phase == .running, "無敵なので岩に重なってもミスにならない")
        #expect(model.field.isInvincible)
        #expect(model.field.isGrounded, "跳ばずに突っ切っている")
        #expect(
            model.field.playerMaxX > rock.start && model.field.playerMinX < rock.end,
            "走者が岩の中にいる（\(model.field.distance) vs \(rock.start)〜\(rock.end)）"
        )
    }

    /// 撮影用シナリオ `-simulateRunner pedaling` が、**接地したまま左ペダルが前のコマ（`ride1`）**
    /// で止まること（#701）。`ride0` は走り出す前と同じ絵なので、そこで止まると漕ぐ画にならない。
    /// シーンは最初の反映で接地距離をまとめて位相に足すので、コマは接地距離だけで決まる。
    @Test("撮影用シナリオ pedaling は接地したまま ride1 のコマで止まる")
    func pedalingScenarioFreezesOnRide1() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("pedaling-capture"))
        model.applyDebugScenario("pedaling")
        #expect(model.phase == .running)
        #expect(model.field.isGrounded, "空中では jump のコマになる")
        #expect(model.field.distance > 34)
        let phase = RunnerRider.phase(forGroundedDistance: model.field.distance)
        #expect(RunnerRider.frame(phase: model.phase, isGrounded: model.field.isGrounded, pedalPhase: phase) == .ride1)
    }
}

@Suite("チャリンコおじさん: 落下演出")
@MainActor
struct RunnerFallingTests {

    /// 跳ばずに走らせ、`.falling` に入った直後（まだ `.failed` にはなっていない）で止める。
    private func failIntoFalling(_ model: RunnerModel) {
        model.press()
        model.release()
        var frames = 0
        while model.phase == .running, frames < 60 * 300 {
            frames += 1
            model.tick(dt: 1.0 / 60)
        }
    }

    @Test("穴に落ちる/ぶつかった直後はまず falling になり、即座には failed にならない")
    func fellGoesToFallingFirst() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("falling-enter"))
        failIntoFalling(model)
        #expect(model.phase == .falling, "ミスした直後は演出を挟む")
    }

    @Test("演出時間が経過すると failed になる")
    func fallingBecomesFailedAfterDuration() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("falling-timeout"))
        failIntoFalling(model)
        #expect(model.phase == .falling)
        // 演出時間の直前まではまだ falling のまま。
        model.tick(dt: RunnerRules.fallDuration - 0.01)
        #expect(model.phase == .falling, "演出時間の途中で failed になってはいけない")
        // 演出時間を超えたら failed へ。
        model.tick(dt: 0.02)
        #expect(model.phase == .failed)
    }

    @Test("falling のあいだはタップしても状態が変わらない")
    func fallingIgnoresPress() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("falling-press"))
        failIntoFalling(model)
        #expect(model.phase == .falling)
        model.press()
        #expect(model.phase == .falling, "演出中のタップは無効")
        model.release()
        #expect(model.phase == .falling)
    }

    @Test("falling のあいだは一時停止できない")
    func fallingIgnoresPause() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("falling-pause"))
        failIntoFalling(model)
        #expect(model.phase == .falling)
        model.pause()
        #expect(model.phase == .falling, "演出中は一時停止できない")
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

    @Test("再開は 1 回の走行につき 1 回。「もう一度」で頭から走り直せば戻る（#958）")
    func oncePerRunAndBackAfterRetry() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("cp-once"))
        failAfterCheckpoint(model)
        #expect(model.resumeFromCheckpoint(forRun: model.runGeneration))
        #expect(model.field.distance == model.stage.checkpoint)

        failAfterCheckpoint(model)
        #expect(!model.canResumeFromCheckpoint, "同じ走行の 2 回目は出せない")
        #expect(!model.resumeFromCheckpoint(forRun: model.runGeneration))

        // 再開 → ミス → もう一度 → チェックポイント通過 → ミス、でまた出る（会長決裁 2026-09-15）。
        model.retryStage()
        #expect(model.phase == .running && model.field.distance == 0)
        #expect(!model.checkpointUsed)
        failAfterCheckpoint(model)
        #expect(model.canResumeFromCheckpoint, "頭から走り直した走行では再開できる")
        #expect(model.resumeFromCheckpoint(forRun: model.runGeneration))
    }

    @Test("QA 用のショーケースは「もう一度」でも本番の面に戻らない（面を選び直せば解除される）")
    func debugShowcaseSurvivesRetry() {
        let model = RunnerModel(startingAt: 15, preference: makePreference("showcase-retry"))
        model.applyDebugScenario("showcase")
        #expect(model.isRunningDebugStage)
        let showcase = model.field.stage.pattern
        #expect(showcase == RunnerStage.debugShowcase.pattern)

        failCurrentStage(model)
        model.retryStage()
        #expect(model.isRunningDebugStage, "もう一度でショーケースが消えない")
        #expect(model.field.stage.pattern == showcase)

        // 面を選び直したら本番の面へ戻る。
        model.newGame(mode: .stages)
        #expect(!model.isRunningDebugStage)
        #expect(model.field.stage.pattern != showcase)
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

    @Test("再開したステージをクリアしても次の面には到達する")
    func resumedClearStillReachesNextStage() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("cp-record"))
        failAfterCheckpoint(model)
        #expect(model.resumeFromCheckpoint(forRun: model.runGeneration))
        #expect(model.phase == .ready)
        #expect(!model.canChooseMode, "再開の直後はスタート画面が「つづきから」だけになる")
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(model.reachedStage == 2, "半分だけ走った回でも先へは進める（順位表に送らないだけ・#406）")
        #expect(model.didReachNewStage)
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

    @Test("到達点は決着しても消えない")
    func reachedStageSurvivesFinish() {
        let store = MemorySnapshotStore()
        let first = RunnerModel(services: makeServices(store: store),
                                startingAt: RunnerRules.stageCount,
                                preference: makePreference("snap-2"))
        autoPlayCurrentStage(first)
        #expect(first.phase == .allCleared)
        #expect(first.reachedStage == RunnerRules.stageCount)

        let second = RunnerModel(services: makeServices(store: store),
                                 preference: makePreference("snap-2b"))
        #expect(second.reachedStage == RunnerRules.stageCount)
        #expect(second.stageNumber == RunnerRules.stageCount)
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

    /// 秒数の廃止（#931）で `bestSeconds` は読み捨てるが、**旧形式のデータは形を問わず読める**こと。
    /// v1.1.4 までの中断データは 18 個のタイムを必ず持っている。長さ・値がどうであれ落ちない。
    @Test("旧形式（ベストタイム入り）の中断データを読んでも落ちず、値は無視する")
    func legacyBestTimesAreIgnored() {
        for legacy in [
            #"{"stage":2,"bestSeconds":[30,-1,99999999],"reachedStage":4}"#,
            #"{"stage":2,"bestSeconds":[5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5],"reachedStage":4}"#,
            #"{"stage":2,"bestSeconds":[],"reachedStage":4}"#,
        ] {
            let store = MemorySnapshotStore()
            store.inject(Data(legacy.utf8), for: "runner")
            let model = RunnerModel(services: makeServices(store: store),
                                    preference: makePreference("snap-legacy"))
            #expect(model.stageNumber == 2, Comment(rawValue: legacy))
            #expect(model.reachedStage == 4, Comment(rawValue: legacy))
            #expect(model.phase == .ready)
        }
        #expect(RunnerSnapshot(stage: 2, bestSeconds: [30, -1]).validated()?.stage == 2)
    }

    /// 新しい形式は鍵を減らさない（旧版のアプリが読んでも落ちない）。`bestSeconds` は空で書く。
    @Test("保存する中断データは旧形式の鍵を残し、ベストタイムは空で書く")
    func savedSnapshotKeepsLegacyKeys() throws {
        let store = MemorySnapshotStore()
        let model = RunnerModel(services: makeServices(store: store), startingAt: 3,
                                preference: makePreference("snap-keys"))
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        let saved = try #require(store.load(RunnerSnapshot.self, for: RunnerModel.gameID))
        #expect(saved.stage == 4)
        #expect(saved.reachedStage == 4)
        #expect(saved.bestSeconds.isEmpty)
        // JSON の鍵そのものを見る（`Codable` の合成に任せているので、鍵が消えれば旧版が落ちる）。
        let json = try #require(store.rawData(for: RunnerModel.gameID))
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["bestSeconds"] as? [Int] == [])
        #expect(object["stage"] as? Int == 4)
    }
}

/// ワールドマップ（面選択・#798）。到達済みの面だけ選べ、選んで遊んでも記録が巻き戻らない。
@Suite("チャリンコおじさん: ワールドマップ（面選択）")
@MainActor
struct RunnerStageSelectTests {

    /// 使い捨ての `PlayLog`（`UserDefaults.standard` を汚さない）。
    private func makePlayLog(_ suite: String) -> PlayLog {
        let name = "asobiba.runner.tests.playlog.select.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return PlayLog(defaults: defaults)
    }

    @Test("1 面は最初から到達済み。クリアすると次の面が到達済みになる")
    func clearingUnlocksNextStage() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("select-unlock"))
        #expect(model.reachedStage == 1)
        #expect(model.isStageReached(1))
        #expect(!model.isStageReached(2))
        #expect(!model.isStageReached(0))
        #expect(!model.isStageReached(RunnerRules.stageCount + 1))

        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(model.reachedStage == 2, "クリアした面の次が選べるようになる")
        #expect(model.isStageReached(2))
        #expect(!model.isStageReached(3))
        // ミスしても到達点は動かない。
        model.advanceToNextStage()
        failCurrentStage(model)
        #expect(model.reachedStage == 2)
    }

    @Test("未到達の面は選べず、到達済みの面はその頭から始まる")
    func onlyReachedStagesCanBeSelected() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("select-guard"))
        autoPlayCurrentStage(model)                      // 1 面クリア → 2 面まで到達
        let generation = model.runGeneration

        #expect(!model.newGame(startingAtStage: 3), "未到達の面は拒む")
        #expect(model.phase == .cleared, "拒んだときは何も起きない")
        #expect(model.runGeneration == generation)
        #expect(!model.newGame(startingAtStage: 0))

        #expect(model.newGame(startingAtStage: 2))
        #expect(model.stageNumber == 2)
        #expect(model.mode == .stages)
        #expect(model.phase == .ready)
        #expect(model.field.distance == 0, "選んだ面の頭から")
        #expect(model.field.stage.number == 2)
        #expect(model.runGeneration == generation + 1)
        #expect(model.reachedStage == 2)

        // エンドレスから戻るときもステージ制に焼き直る。
        model.newEndlessGame(seed: 1)
        #expect(model.mode == .endless)
        #expect(model.newGame(startingAtStage: 1))
        #expect(model.mode == .stages)
        #expect(model.stageNumber == 1)
    }

    /// 受け入れ条件「面を選んでクリアしても `stageNumber` の記録が巻き戻らない」。
    /// 到達ステージ・ローカルの自己ベスト（`PlayLog`）・Game Center へ送る値・中断データの
    /// 4 つを見る。順位表は最大値が残る（送る値そのものは選んだ面の番号でよい）。
    @Test("面を選んでクリアしても到達ステージと自己ベストが巻き戻らない")
    func replayingLowerStageDoesNotRollBackRecords() {
        let store = MemorySnapshotStore()
        let log = makePlayLog("rollback")
        let spy = SpyGameCenterService()
        let model = RunnerModel(
            services: makeServices(store: store, log: log, gameCenter: spy),
            startingAt: 1, preference: makePreference("select-rollback")
        )
        // 1〜3 面を順にクリア → 4 面まで到達。
        for expected in 1...3 {
            autoPlayCurrentStage(model)
            #expect(model.phase == .cleared, "\(expected) 面")
            if expected < 3 { model.advanceToNextStage() }
        }
        #expect(model.reachedStage == 4)
        #expect(log.record(gameID: RunnerModel.gameID)?.bestPoints == 3)
        #expect(log.summaryLine(gameID: RunnerModel.gameID) == "1-4 まで到達", "ハブの 1 行は到達した面（#931）")

        // 1 面を選んでクリア。
        #expect(model.newGame(startingAtStage: 1))
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(model.stageNumber == 1)

        #expect(model.reachedStage == 4, "到達点は巻き戻らない")
        #expect(model.isStageReached(4))
        #expect(log.record(gameID: RunnerModel.gameID)?.bestPoints == 3, "自己ベスト（到達ステージ数）は最大値のまま")
        #expect(log.summaryLine(gameID: RunnerModel.gameID) == "1-4 まで到達")
        #expect(!model.didReachNewStage, "到達済みの面のクリアに印は付かない")
        // Game Center へは毎回クリアした面の番号を送る（順位表側で最大値が残る）。
        #expect(spy.scores.map(\.value) == [1, 2, 3, 1])

        // 中断データにも到達点が残り、開き直しても 4 面まで選べる。
        let saved = store.load(RunnerSnapshot.self, for: RunnerModel.gameID)
        #expect(saved?.reachedStage == 4)
        #expect(saved?.stage == 2, "再開位置はいま遊んでいる面の次")
        let reopened = RunnerModel(services: makeServices(store: store),
                                   preference: makePreference("select-rollback-b"))
        #expect(reopened.stageNumber == 2)
        #expect(reopened.reachedStage == 4)
        #expect(reopened.isStageReached(4))
        #expect(!reopened.isStageReached(5))
    }

    @Test("到達点の無い旧い中断データは再開面を到達点として読む")
    func legacySnapshotFallsBackToResumeStage() {
        let store = MemorySnapshotStore()
        store.inject(Data(#"{"stage":5,"bestSeconds":[10,11,12,13]}"#.utf8), for: "runner")
        let model = RunnerModel(services: makeServices(store: store),
                                preference: makePreference("select-legacy"))
        #expect(model.stageNumber == 5)
        #expect(model.reachedStage == 5)
        #expect(model.isStageReached(5))
        #expect(!model.isStageReached(6))

        // 到達点が再開面より前・上限超えの壊れた値は丸める。
        #expect(RunnerSnapshot(stage: 5, bestSeconds: [], reachedStage: 2).validated()?.reachedStage == 5)
        #expect(RunnerSnapshot(stage: 5, bestSeconds: [], reachedStage: 99).validated()?.reachedStage == RunnerRules.stageCount)
        #expect(RunnerSnapshot(stage: 5, bestSeconds: [], reachedStage: 9).validated()?.reachedStage == 9)
    }

    /// #1009 の受け入れ条件 F: **v1.1.5 で全 18 面をクリアした人は、30 面の版で 19 面を選べる**。
    /// v1.1.5 の中断データの到達点は最終面の 18 で頭打ちなので、到達点だけでは足した面が開かない。
    /// 記録（本編の `bestPoints` = クリアした面の番号）を根拠に次の面まで開ける。
    @Test("v1.1.5 で 18 面をクリアしていた人は、中断データが 18 のままでも 19 面を選べる")
    func clearedLastStageOfOlderVersionUnlocksTheNextStage() {
        let store = MemorySnapshotStore()
        store.inject(Data(#"{"stage":18,"bestSeconds":[],"reachedStage":18}"#.utf8), for: "runner")
        let log = makePlayLog("cleared-18")
        log.recordResult(gameID: RunnerModel.gameID, outcome: .win, score: GameScore(metric: .points, points: 18))
        let model = RunnerModel(services: makeServices(store: store, log: log),
                                preference: makePreference("select-cleared-18"))
        #expect(model.stageNumber == 18, "再開する面は中断データのまま")
        #expect(model.reachedStage == 19)
        #expect(model.isStageReached(19))
        #expect(!model.isStageReached(20))

        // 開けた到達点はその場で保存し直す（次に開いたときは中断データだけで 19 まで選べる）。
        let saved = store.load(RunnerSnapshot.self, for: "runner")
        #expect(saved?.reachedStage == 19)

        // 対照: 18 面に着いただけでクリアしていない人（記録は 17 面まで）は 19 面を選べない。
        let reachedOnly = MemorySnapshotStore()
        reachedOnly.inject(Data(#"{"stage":18,"bestSeconds":[],"reachedStage":18}"#.utf8), for: "runner")
        let log17 = makePlayLog("cleared-17")
        log17.recordResult(gameID: RunnerModel.gameID, outcome: .win, score: GameScore(metric: .points, points: 17))
        let notYet = RunnerModel(services: makeServices(store: reachedOnly, log: log17),
                                 preference: makePreference("select-cleared-17"))
        #expect(notYet.reachedStage == 18)
        #expect(!notYet.isStageReached(19))
    }

    /// 同じく F: **v1.1.4 の「全 15 面クリア」**（到達点の鍵が無く、ステージごとのタイムを持つ旧形式）も
    /// 記録から次の面を開ける。エンドレスの記録（区分 `endless`）は面の番号ではないので根拠にしない。
    @Test("v1.1.4 で全 15 面をクリアしていた人は 16 面を選べ、エンドレスの記録では開かない")
    func clearedAllStagesOfV114UnlocksStageSixteen() {
        let store = MemorySnapshotStore()
        let times = Array(repeating: 20, count: 15).map(String.init).joined(separator: ",")
        store.inject(Data(#"{"stage":15,"bestSeconds":[\#(times)]}"#.utf8), for: "runner")
        let log = makePlayLog("cleared-15")
        log.recordResult(gameID: RunnerModel.gameID, outcome: .win, score: GameScore(metric: .points, points: 15))
        let model = RunnerModel(services: makeServices(store: store, log: log),
                                preference: makePreference("select-cleared-15"))
        #expect(model.stageNumber == 15)
        #expect(model.reachedStage == 16)
        #expect(model.isStageReached(16))

        let endlessOnly = makePlayLog("endless-only")
        endlessOnly.recordResult(
            gameID: RunnerModel.gameID, outcome: .loss,
            score: GameScore(metric: .points, points: 5000, variant: RunnerMode.endless.recordVariant)
        )
        let fresh = RunnerModel(services: makeServices(log: endlessOnly), preference: makePreference("select-endless-only"))
        #expect(fresh.reachedStage == 1, "エンドレスの走行距離で面は開かない")

        // 記録の値から見た到達点の境界（無い・壊れた値は 1 面、最終面を超えない）。
        #expect(RunnerModel.reachedStage(afterClearing: nil) == 1)
        #expect(RunnerModel.reachedStage(afterClearing: 0) == 1)
        #expect(RunnerModel.reachedStage(afterClearing: -3) == 1)
        #expect(RunnerModel.reachedStage(afterClearing: 18) == 19)
        #expect(RunnerModel.reachedStage(afterClearing: RunnerRules.stageCount) == RunnerRules.stageCount)
        #expect(RunnerModel.reachedStage(afterClearing: 999) == RunnerRules.stageCount)
        #expect(RunnerModel.reachedStage(afterClearing: Int.max) == RunnerRules.stageCount, "溢れて落ちない")
    }

    @Test("最終面をクリアしても到達点は最終面のまま（その次にはならない）")
    func reachedStageIsCappedAtLastStage() {
        let model = RunnerModel(startingAt: RunnerRules.stageCount, preference: makePreference("select-cap"))
        autoPlayCurrentStage(model)
        #expect(model.phase == .allCleared)
        #expect(model.reachedStage == RunnerRules.stageCount)
        #expect(!model.isStageReached(RunnerRules.stageCount + 1))
    }
}

/// 開始シート（#1027）を `onAppear` で自動で出すかどうかの判定（#1063）。
///
/// 局面（`.ready`）だけを見る作りだと、QA・撮影用の起動（`-simulateRunner`）で作った画にも
/// シートが被る——`showcase` のように `.ready` のまま止まるシナリオがあるうえ、判定が
/// 起動引数の適用より前に走っていた。引数を見る純関数に切り出してここで固定する。
@Suite("チャリンコおじさん: 開始シートの自動表示（#1063）")
@MainActor
struct RunnerStartSheetGateTests {

    private func shouldPresent(_ arguments: [String], phase: RunnerPhase = .ready) -> Bool {
        RunnerView.shouldPresentStartSheet(
            arguments: arguments, phase: phase, canChooseMode: true,
            showsTutorial: false, showStartSheet: false
        )
    }

    @Test("ハブから開いた直後（走り出す前）は出す")
    func presentsWhenOpenedFromHub() {
        #expect(shouldPresent(["app"]))
    }

    @Test("QA・撮影用の起動（-simulateRunner）では出さない")
    func hiddenForDebugScenarios() {
        // ASO 撮影（`Scripts/capture-aso-screenshots.sh` の `05-runner`）と QA の見比べ。
        #expect(!shouldPresent(["app", "-simulateRunner", "bird:5"]))
        // `.ready` のまま止まるシナリオも被らない（局面だけでは判別できない）。
        #expect(!shouldPresent(["app", "-simulateRunner", "showcase"]))
        // 開始シートそのものを撮る `-showRunnerStartSheet` だけが開く（経路は `openStartSheet`）。
        #expect(!shouldPresent(["app", "-simulateRunner", "running", "-showRunnerStartSheet"]))
    }

    @Test("撮影モード（-screenshotMode）では出さない")
    func hiddenInScreenshotMode() {
        #expect(!shouldPresent(["app", "-screenshotMode"]))
    }

    @Test("走り出したあと・チェックポイント再開の直後・ガイドやシートを出している間は出さない")
    func hiddenWhileBusy() {
        for phase: RunnerPhase in [.running, .paused, .falling, .failed, .cleared, .allCleared] {
            #expect(!shouldPresent(["app"], phase: phase))
        }
        #expect(!RunnerView.shouldPresentStartSheet(
            arguments: ["app"], phase: .ready, canChooseMode: false,
            showsTutorial: false, showStartSheet: false
        ), "広告で得た再開を誤って手放させない")
        #expect(!RunnerView.shouldPresentStartSheet(
            arguments: ["app"], phase: .ready, canChooseMode: true,
            showsTutorial: true, showStartSheet: false
        ), "初回の操作ガイドの上に重ねない")
        #expect(!RunnerView.shouldPresentStartSheet(
            arguments: ["app"], phase: .ready, canChooseMode: true,
            showsTutorial: false, showStartSheet: true
        ), "すでに出ている")
    }
}

/// スタート画面（#931）。走り出す前のカードのボタン（次の面・エンドレス・つづきから）の遷移。
@Suite("チャリンコおじさん: スタート画面（#931）")
@MainActor
struct RunnerStartScreenTests {

    @Test("モードや面を選べるのは走り出す前で、コースの頭にいるときだけ")
    func availabilityIsPureFunctionOfPhase() {
        #expect(RunnerModel.canChooseMode(phase: .ready, passedCheckpoint: false))
        #expect(!RunnerModel.canChooseMode(phase: .ready, passedCheckpoint: true), "チェックポイント再開の直後は「つづきから」だけ")
        for phase: RunnerPhase in [.running, .paused, .falling, .failed, .cleared, .allCleared] {
            #expect(!RunnerModel.canChooseMode(phase: phase, passedCheckpoint: false), "\(phase)")
        }
    }

    @Test("主ボタンは作ってあるコースをそのまま走り出す")
    func mainButtonRunsCurrentCourse() {
        let model = RunnerModel(startingAt: 3, preference: makePreference("start-main"))
        #expect(model.canChooseMode)
        let generation = model.runGeneration
        #expect(model.start(.stages))
        #expect(model.phase == .running, "ボタン 1 タップで走り出す")
        #expect(model.mode == .stages)
        #expect(model.stageNumber == 3)
        #expect(model.runGeneration == generation, "同じモードならコースを作り直さない")

        // ボタンからの開始は押下を持ち込まない——直後のタップで普通に跳べる。
        model.press()
        #expect(!model.field.isGrounded, "走り出した直後のタップは踏み切りになる")
        model.release()
    }

    @Test("エンドレスのボタンはタップ 1 回で新しいコースを走り出す")
    func endlessButtonStartsNewCourse() {
        let model = RunnerModel(startingAt: 3, preference: makePreference("start-endless"))
        let generation = model.runGeneration
        #expect(model.start(.endless))
        #expect(model.mode == .endless)
        #expect(model.phase == .running)
        #expect(model.endlessSeed != nil)
        #expect(model.runGeneration == generation + 1)
        #expect(model.stageNumber == 3, "ステージ制のつづきは保持する")

        // ミス→「もう一度」で作った新しいコースは、エンドレスのボタンで二重に作り直さない。
        failCurrentStage(model)
        #expect(model.phase == .failed)
        model.retryStage()
        #expect(model.phase == .ready)
        let seed = model.endlessSeed
        let retried = model.runGeneration
        #expect(model.start(.endless))
        #expect(model.phase == .running)
        #expect(model.endlessSeed == seed)
        #expect(model.runGeneration == retried)
    }

    @Test("エンドレスから主ボタンで戻ると 1 面や到達点ではなく「つづき」の面から走り出す")
    func mainButtonFromEndlessResumesContinuationStage() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("start-back"))
        // 1〜2 面をクリアして 3 面へ、さらに 1 面を選び直して「つづき = 2 面・到達点 = 3 面」にする。
        for _ in 1...2 {
            autoPlayCurrentStage(model)
            #expect(model.phase == .cleared)
            model.advanceToNextStage()
        }
        #expect(model.stageNumber == 3)
        #expect(model.newGame(startingAtStage: 2))
        #expect(model.reachedStage == 3)

        model.newEndlessGame(seed: 1)
        let generation = model.runGeneration
        #expect(model.start(.stages))
        #expect(model.mode == .stages)
        #expect(model.phase == .running)
        #expect(model.stageNumber == 2, "つづきの面（到達点の 3 面でも 1 面でもない）")
        #expect(model.field.stage.number == 2)
        #expect(model.reachedStage == 3, "到達点は動かない")
        #expect(model.runGeneration == generation + 1)
    }

    @Test("走行中・一時停止中・ミス・クリアでは無視する")
    func ignoredWhileNotReady() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("start-ignore"))
        model.press(); model.release()
        #expect(model.phase == .running)
        #expect(!model.canChooseMode)
        let generation = model.runGeneration
        #expect(!model.start(.endless))
        #expect(!model.start(.stages))
        #expect(model.mode == .stages)
        #expect(model.runGeneration == generation)

        model.pause()
        #expect(!model.start(.endless))
        #expect(model.phase == .paused)
        model.resume()

        failCurrentStage(model)
        #expect(model.phase == .failed)
        #expect(!model.start(.endless))
        #expect(model.mode == .stages)

        model.retryStage()
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(!model.start(.endless))
        #expect(model.mode == .stages)
        #expect(model.phase == .cleared)
    }

    @Test("チェックポイント再開の直後はモードを変えられないが、「つづきから」は走り出せる")
    func onlyContinueRightAfterCheckpointResume() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("start-checkpoint"))
        failCurrentStage(model, stopAfterCheckpoint: true)
        #expect(model.phase == .failed)
        #expect(model.canResumeFromCheckpoint)
        #expect(model.resumeFromCheckpoint(forRun: model.runGeneration))
        #expect(model.phase == .ready)
        #expect(!model.canChooseMode, "広告で得た途中からの再開を誤タップで捨てさせない")
        #expect(!model.start(.endless))
        #expect(model.mode == .stages)
        #expect(model.phase == .ready)

        let generation = model.runGeneration
        #expect(model.start(.stages))
        #expect(model.phase == .running)
        #expect(model.field.passedCheckpoint, "途中からの再開のまま走り出す")
        #expect(model.field.distance == model.stage.checkpoint)
        #expect(model.runGeneration == generation)
    }
}

/// 面をまたぐ導線はスタート画面（`.ready`）を挟まない（#941・会長指示 2026-09-15）。
/// スタート画面が出るのはハブから入った直後・「はじめから」・マップで面を選んだとき・
/// チェックポイント再開だけ。
@Suite("チャリンコおじさん: 面をまたぐときはスタート画面を挟まない（#941）")
@MainActor
struct RunnerStageFlowTests {

    /// 送信されたイベントをそのまま溜めるスパイ（`EndlessCourseTests` と同じ形）。
    @MainActor
    private final class SpyAnalyticsService: AnalyticsService {
        private(set) var events: [AnalyticsEvent] = []
        func log(_ event: AnalyticsEvent) { events.append(event) }
    }

    @Test("「次の面へ」「もう一度」「このステージをもう一度」の直後は走行中で、直後のタップは踏み切り")
    func stageTransitionsRunImmediately() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("flow-run"))

        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        model.advanceToNextStage()
        #expect(model.phase == .running)
        #expect(model.stageNumber == 2)
        #expect(model.field.distance == 0, "面の頭から")
        #expect(!model.canChooseMode, "走行中なのでスタート画面の部品は出ない")
        // ボタンからの開始は押下を持ち込まない——直後のタップで普通に跳べる。
        model.press()
        #expect(!model.field.isGrounded, "走り出した直後のタップは踏み切りになる")
        model.release()

        failCurrentStage(model)
        #expect(model.phase == .failed)
        model.retryStage()
        #expect(model.phase == .running)
        #expect(model.stageNumber == 2, "ミスの「もう一度」は同じ面")
        #expect(model.field.distance == 0)

        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        model.replayCurrentStage()
        #expect(model.phase == .running)
        #expect(model.stageNumber == 2)
        #expect(model.field.distance == 0)
    }

    @Test("全ステージクリアからの「このステージをもう一度」もその場で走り出す")
    func replayAfterAllClearedRunsImmediately() {
        let model = RunnerModel(startingAt: RunnerRules.stageCount, preference: makePreference("flow-all"))
        autoPlayCurrentStage(model)
        #expect(model.phase == .allCleared)
        model.replayCurrentStage()
        #expect(model.phase == .running)
        #expect(model.stageNumber == RunnerRules.stageCount)
    }

    @Test("ハブから入った直後・はじめから・マップで選んだ面・チェックポイント再開はスタート画面のまま")
    func startScreenStaysForEntryPoints() {
        let store = MemorySnapshotStore()
        let fresh = RunnerModel(services: makeServices(store: store), startingAt: 1,
                                preference: makePreference("flow-entry"))
        #expect(fresh.phase == .ready, "ハブから入った直後")
        #expect(fresh.canChooseMode)

        autoPlayCurrentStage(fresh)
        fresh.advanceToNextStage()
        #expect(fresh.phase == .running)
        let restored = RunnerModel(services: makeServices(store: store), preference: makePreference("flow-restore"))
        #expect(restored.stageNumber == 2)
        #expect(restored.phase == .ready, "中断からの復元もスタート画面")

        #expect(fresh.newGame(startingAtStage: 1))
        #expect(fresh.phase == .ready, "マップで面を選んだとき")
        #expect(fresh.canChooseMode)

        fresh.press(); fresh.release()
        #expect(fresh.phase == .running)
        fresh.newGame()
        #expect(fresh.phase == .ready, "「はじめから」")

        failCurrentStage(fresh, stopAfterCheckpoint: true)
        #expect(fresh.resumeFromCheckpoint(forRun: fresh.runGeneration))
        #expect(fresh.phase == .ready, "広告からの再開は「つづきから」を押してもらう")
        #expect(!fresh.canChooseMode)
    }

    @Test("エンドレスの「もう一度」は対象外で、これまでどおりスタート画面に戻る")
    func endlessRetryKeepsStartScreen() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("flow-endless"))
        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        #expect(model.phase == .failed)
        model.retryStage()
        #expect(model.phase == .ready)
        #expect(model.canChooseMode)
    }

    /// 受け入れ条件「1 ステージ = 1 プレイの `game_start` の回数は変えない」。走り出しを
    /// `gameDidRestart` の**後**に置いてあるので、次の面を途中で捨てれば `game_end`（quit）が
    /// 出る（逆順だと「1 手指した」印が前のプレイに付き、離脱が記録されなくなる）。
    @Test("解析: 次の面へ進むたびに game_start が 1 回、途中で捨てれば game_end(quit) が出る")
    func analyticsCountsOnePlayPerStage() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: [RunnerModel.gameID], now: { Date(timeIntervalSince1970: 0) }
        )
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        let model = RunnerModel(services: services, startingAt: 1, preference: makePreference("flow-analytics"))

        func starts() -> [String] {
            spy.events.compactMap { event -> String? in
                if case let .gameStart(_, level, _) = event { return level?.parameterValue ?? "-" } else { return nil }
            }
        }
        func ends() -> [AnalyticsResult] {
            spy.events.compactMap { event -> AnalyticsResult? in
                if case let .gameEnd(_, result, _, _, _) = event { return result } else { return nil }
            }
        }

        #expect(starts() == ["stage-1"], "ハブから入った直後の 1 回")
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(ends().count == 1, "クリアで 1 回")

        model.advanceToNextStage()
        #expect(model.phase == .running)
        #expect(starts() == ["stage-1", "stage-2"], "次の面で 1 回だけ増える")
        #expect(ends().count == 1, "走り出しただけでは game_end は出ない")

        // ミス→「もう一度」は同じプレイの続き（増えない）。
        failCurrentStage(model)
        model.retryStage()
        #expect(model.phase == .running)
        #expect(starts() == ["stage-1", "stage-2"])
        #expect(ends().count == 1)

        // 走行中に「はじめから」で捨てると、2 面のプレイが途中離脱として閉じる。
        model.newGame()
        #expect(starts() == ["stage-1", "stage-2", "stage-1"])
        #expect(ends().count == 2)
        #expect(ends().last == .quit, "走り出した面を捨てたので途中離脱")
    }
}

/// 1 回の走行に `game_start` 1 本・`game_end` 1 本（#1064）。
///
/// PR #1028 以降、初回起動（中断データ無し）は「画面を開いた `init` で 1 本 → 開始シートの
/// 『スタート』（`newGame`）で 2 本目」になっていた。逆に 2 回目以降はシートを閉じて
/// コースをタップしても `init` も `newGame` も通らず 0 本だった。数えるのは**面を選んで
/// 始めたとき**（`newGame*` / `advanceToNextStage`）と**走り出したとき**（`beginRun`・冪等）だけ。
@Suite("チャリンコおじさん: 1 走行 = game_start 1 本（#1064）")
@MainActor
struct RunnerPlayCountTests {

    @MainActor
    private final class SpyAnalyticsService: AnalyticsService {
        private(set) var events: [AnalyticsEvent] = []
        func log(_ event: AnalyticsEvent) { events.append(event) }
    }

    private func makeAnalytics(_ spy: SpyAnalyticsService) -> GameServices {
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: [RunnerModel.gameID], now: { Date(timeIntervalSince1970: 0) }
        )
        return GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
    }

    private func starts(_ spy: SpyAnalyticsService) -> [String] {
        spy.events.compactMap { event -> String? in
            if case let .gameStart(_, level, _) = event { return level?.parameterValue ?? "-" } else { return nil }
        }
    }

    private func ends(_ spy: SpyAnalyticsService) -> [AnalyticsResult] {
        spy.events.compactMap { event -> AnalyticsResult? in
            if case let .gameEnd(_, result, _, _, _) = event { return result } else { return nil }
        }
    }

    @Test("中断データ無し: 開いて「スタート」で 1 面を走ると game_start 1 本・game_end 1 本")
    func freshStartSendsOneStart() {
        let spy = SpyAnalyticsService()
        // 本番の入口（ハブから開く）。中断データが無いので 1 面のスタート画面に着く。
        let model = RunnerModel(services: makeAnalytics(spy), preference: makePreference("count-fresh"))
        #expect(starts(spy).isEmpty, "画面を開いただけでは数えない（まだモードも面も選んでいない）")

        // 開始シートの「スタート」（ステージ制・1 面）。
        #expect(model.newGame(startingAtStage: 1))
        #expect(starts(spy) == ["stage-1"])

        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(starts(spy) == ["stage-1"], "走り出しでは増えない（`gameDidStart` は冪等）")
        #expect(ends(spy).count == 1)
    }

    @Test("中断データ有り: 開始シートを閉じてコースをタップした走行も game_start 1 本・game_end 1 本")
    func tapToStartSendsOneStart() {
        let store = MemorySnapshotStore()
        // 2 面まで進んで閉じたあと（中断データ = 走る面と到達点の控え）。解析は付けずに作る。
        _ = RunnerModel(services: makeServices(store: store), startingAt: 2, preference: makePreference("count-seed"))

        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: spy, allowedGameIDs: [RunnerModel.gameID], now: { Date(timeIntervalSince1970: 0) }
        )
        let services = GameServices(snapshots: store, ads: NoopAdService(), analytics: analytics)
        let model = RunnerModel(services: services, preference: makePreference("count-resume"))
        #expect(model.stageNumber == 2, "中断データから 2 面に戻る")
        #expect(starts(spy).isEmpty, "復元しただけでは数えない")

        // シートをキャンセルしてコースをタップした（`press`）＝走り出し。
        model.press()
        model.release()
        #expect(model.phase == .running)
        #expect(starts(spy) == ["stage-2"], "走り出しで 1 本")

        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(starts(spy) == ["stage-2"])
        #expect(ends(spy).count == 1)
    }
}

/// ハブの記録行（#931）。Core の表記（`RecordFormat.runnerStageLine`）は世界の割り方を写して
/// いるので、`RunnerWorld` とずれていないことをここで突き合わせる（Core からは参照できない）。
@Suite("チャリンコおじさん: ハブの記録行（到達した面）")
struct RunnerHubLineTests {

    @Test("クリアした面の次を「世界-面 まで到達」で言い、最終面のクリアは全面クリア")
    func hubLineMatchesWorldCodes() {
        for cleared in 1..<RunnerRules.stageCount {
            #expect(
                RecordFormat.runnerStageLine(clearedStage: cleared)
                    == "\(RunnerWorld.code(forStage: cleared + 1)) まで到達",
                "\(cleared) 面クリア"
            )
        }
        #expect(RecordFormat.runnerStageLine(clearedStage: RunnerRules.stageCount) == "全 \(RunnerRules.stageCount) 面クリア")
        #expect(RecordFormat.runnerStageLine(clearedStage: 1) == "1-2 まで到達")
        #expect(RecordFormat.runnerStageLine(clearedStage: 6) == "2-1 まで到達")

        let record = PlayRecord.applying(
            outcome: .win, score: GameScore(metric: .points, points: 8), to: nil
        ).record
        #expect(RecordFormat.hubLine([record], gameID: RunnerModel.gameID) == "2-3 まで到達")
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

    @Test("ペダルの乗りを読む")
    func speed() {
        #expect(RunnerAccessibility.speedLabel(ratio: 0) == "スピード 0パーセント")
        #expect(RunnerAccessibility.speedLabel(ratio: 1) == "スピード 100パーセント")
        // 10 刻みに丸める。範囲外は端に寄せる。
        #expect(RunnerAccessibility.speedLabel(ratio: 0.53) == "スピード 50パーセント")
        #expect(RunnerAccessibility.speedLabel(ratio: 1.5) == "スピード 100パーセント")
        #expect(RunnerAccessibility.speedLabel(ratio: -1) == "スピード 0パーセント")
    }

    @Test("無敵の残り時間は秒を切り上げて読む")
    func invincible() {
        #expect(RunnerAccessibility.invincibleLabel(remaining: 3.0) == "無敵 あと3秒")
        #expect(RunnerAccessibility.invincibleLabel(remaining: 2.2) == "無敵 あと3秒")
        #expect(RunnerAccessibility.invincibleLabel(remaining: 0.3) == "無敵 あと1秒", "残りわずかを 0 秒と読まない")
        #expect(RunnerAccessibility.invincibleLabel(remaining: -1) == "無敵 あと0秒")
    }

    @Test("エンドレスの走行距離と自己ベストを読む")
    func distance() {
        #expect(RunnerAccessibility.distanceLabel(1234) == "走行距離 1234メートル")
        #expect(RunnerAccessibility.bestDistanceLabel(nil) == "自己ベストはまだありません")
        #expect(RunnerAccessibility.bestDistanceLabel(500) == "自己ベスト 500メートル")
        #expect(RunnerAccessibility.endlessResultLabel(phase: .failed, distance: 800) == "800メートルでミスしました")
        #expect(RunnerAccessibility.endlessResultLabel(phase: .ready, distance: 0) == "エンドレス。タップでスタート")
    }

    @Test("面の見出しは「世界-面」の番号だけで、スタート画面のボタンはそれに添える（#931 #946）")
    func startScreen() {
        #expect(RunnerAccessibility.stageHeadline(number: 2) == "1-2")
        #expect(RunnerAccessibility.stageHeadline(number: 9) == "2-3")
        #expect(RunnerAccessibility.stageHeadline(number: 18) == "3-6")
        #expect(RunnerAccessibility.stageHeadline(number: 19) == "4-1")
        #expect(RunnerAccessibility.stageHeadline(number: 30) == "5-6")
        #expect(RunnerAccessibility.stageHeadline(number: 0) == "ステージ 0", "どの世界にも収まらない番号は「ステージ N」")
        #expect(RunnerAccessibility.stageHeadline(number: 31) == "ステージ 31")
        #expect(RunnerAccessibility.startStageLabel(number: 2) == "1-2 から走る")
        #expect(RunnerAccessibility.startEndlessLabel(bestDistance: 1234) == "エンドレス、自己ベスト 1,234 メートル")
        #expect(RunnerAccessibility.startEndlessLabel(bestDistance: nil) == "エンドレス、まだ記録なし")
    }

    @Test("状態ごとの結果を読む")
    func result() {
        #expect(RunnerAccessibility.resultLabel(phase: .falling, stageNumber: 2) == "ステージ 2 でミスしました")
        #expect(RunnerAccessibility.resultLabel(phase: .failed, stageNumber: 2) == "ステージ 2 でミスしました")
        #expect(RunnerAccessibility.resultLabel(phase: .cleared, stageNumber: 2) == "ステージ 2 クリア")
        #expect(RunnerAccessibility.resultLabel(phase: .allCleared, stageNumber: 15) == "全ステージクリア")
    }
}
