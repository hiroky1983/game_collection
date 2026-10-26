import Core
import Foundation
import Testing
@testable import GameRunner
import CoreTestSupport
import GameRunnerTestSupport

/// 図で見る「はじめての遊び方」（#2826）の文言が、モードごとに実装のルールのとおりになっていること。
@MainActor
@Suite("チャリンコおじさん: はじめての遊び方")
struct RunnerOnboardingTests {
    /// 障害の無い一本道。
    private func flatStage() -> RunnerStage {
        RunnerStage(number: 1, pattern: String(repeating: "-", count: 20), speed: 40)
    }

    /// 踏み切ってから `releaseAfter` 秒で離したときの頂点の高さ。
    private func apex(releaseAfter seconds: Double) -> Double {
        var field = RunnerField(stage: flatStage())
        field.jump()
        var released = false
        var top: Double = 0
        var elapsed: Double = 0
        let step = 1.0 / 2400
        while !field.isGrounded, elapsed < 3 {
            if !released, elapsed >= seconds {
                field.endHold()
                released = true
            }
            _ = field.step(dt: step)
            elapsed += step
            top = max(top, field.altitude)
        }
        return top
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている。モードで変わるのは目的と最後のカードだけ")
    func wellFormed() {
        for mode in RunnerMode.allCases {
            let guide = RunnerOnboarding.guide(mode: mode)
            #expect(guide.isWellFormed, "\(mode)")
            #expect(guide.gameID == RunnerModel.gameID)
            #expect(guide.gameID == RunnerModule().id)
        }
        let stages = RunnerOnboarding.guide(mode: .stages).pages
        let endless = RunnerOnboarding.guide(mode: .endless).pages
        #expect(stages.count == endless.count)
        #expect(stages.first?.lines != endless.first?.lines)
        #expect(stages.last?.lines != endless.last?.lines)
        #expect(stages.dropFirst().dropLast().map(\.lines) == endless.dropFirst().dropLast().map(\.lines))
        #expect(stages.last?.lines.contains { $0.contains("チェックポイント") } == true)
        #expect(endless.last?.lines.contains { $0.contains("チェックポイント") } == false, "エンドレスに広告での再開は無い")
    }

    @Test("走り出す: 走る前にタップすると走り出し、あとは押さなくても右へ進む")
    func tapToStart() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("onboarding-start"))
        #expect(model.phase == .ready)
        model.press()
        model.release()
        #expect(model.phase == .running)
        let before = model.distance
        for _ in 0..<30 { model.tick(dt: 1.0 / 60) }
        #expect(model.distance > before)
    }

    @Test("ジャンプ: 長く押すほど高く跳べる")
    func holdLongerJumpsHigher() {
        let tap = apex(releaseAfter: 0)
        let long = apex(releaseAfter: 0.3)
        #expect(tap < long)
        #expect(abs(long - RunnerRules.jumpApex) < 0.3)
    }

    @Test("二段ジャンプ: 空中でもう一度だけ踏み切れる。ペダルは地面でしか漕げない")
    func doubleJumpAndPedal() {
        #expect(RunnerRules.maxJumps == 2)
        var field = RunnerField(stage: flatStage())
        let first = field.jump()
        _ = field.step(dt: 1.0 / 60)
        let second = field.jump()
        _ = field.step(dt: 1.0 / 60)
        let third = field.jump()
        #expect(first && second && !third)

        var pedal = RunnerField(stage: flatStage())
        for _ in 0..<600 { _ = pedal.step(dt: 1.0 / 60) }
        let grounded = pedal.pedalBoost
        #expect(grounded > 1, "接地して漕ぐと速くなる")
        pedal.jump()
        pedal.endHold()
        _ = pedal.step(dt: 1.0 / 60)
        #expect(pedal.currentSpeed == pedal.stage.speed, "空中では漕げず基準の速さ")
        while !pedal.isGrounded { _ = pedal.step(dt: 1.0 / 240) }
        #expect(pedal.pedalBoost < grounded, "跳んでいたぶん乗りが落ちる")
    }

    @Test("ステージ制: ミスしても頭からやり直せ、チェックポイントより先のミスだけ広告で再開できる")
    func stageMissAndCheckpoint() {
        let early = RunnerModel(startingAt: 1, preference: makePreference("onboarding-miss"))
        failCurrentStage(early)
        #expect(early.phase == .failed)
        #expect(!early.canResumeFromCheckpoint)
        early.retryStage()
        #expect(early.phase == .running)
        #expect(early.stageNumber == 1)
        #expect(early.distance == 0, "ステージの頭から")

        let late = RunnerModel(startingAt: 1, preference: makePreference("onboarding-checkpoint"))
        failCurrentStage(late, stopAfterCheckpoint: true)
        #expect(late.phase == .failed)
        #expect(late.canResumeFromCheckpoint)

        let cleared = RunnerModel(startingAt: 1, preference: makePreference("onboarding-goal"))
        autoPlayCurrentStage(cleared)
        #expect(cleared.phase == .cleared, "ゴールでステージクリア")
    }

    @Test("エンドレス: ミスでおしまい・走った距離が記録。途中で閉じた走行は記録に残らない")
    func endlessRecord() {
        let log = PlayLog(defaults: {
            let name = "asobiba.runner.onboarding.tests.endless"
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            return defaults
        }())
        let store = MemorySnapshotStore()
        let model = RunnerModel(services: makeServices(store: store, log: log), startingAt: 1,
                                preference: makePreference("onboarding-endless"))
        model.newEndlessGame(seed: 1)
        let saveCount = store.saveCount
        model.press()
        model.release()
        for _ in 0..<30 { model.tick(dt: 1.0 / 60) }
        #expect(model.phase == .running && model.distance > 0)
        // 走っているあいだは何も保存しない（記録はミスした時点で初めて付く）ので、ここで閉じて開き直すと
        // エンドレスの走行は戻らず、記録も付いていない。
        #expect(store.saveCount == saveCount, "エンドレスの走行は中断データに書かない")
        #expect(log.record(gameID: RunnerModel.gameID, variant: RunnerMode.endless.recordVariant) == nil)
        let reopened = RunnerModel(services: makeServices(store: store, log: log),
                                   preference: makePreference("onboarding-endless-reopen"))
        #expect(reopened.mode == .stages, "エンドレスは復元しない")
        #expect(reopened.distance == 0)

        model.newEndlessGame(seed: 1)
        failCurrentStage(model)
        #expect(model.isRunOver, "ミスで 1 回が終わる")
        #expect(!model.canResumeFromCheckpoint)
        #expect(log.record(gameID: RunnerModel.gameID, variant: RunnerMode.endless.recordVariant)?.bestPoints
                == model.distanceMeters, "走った距離が記録")
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let figureTexts = ["ゴールでステージクリア", "走った距離が記録", "自動で右へ進む", "ちょんと押す", "長く押す",
                           "空中でもう一度タップ", "穴に落ちたらミス", "穴に落ちたらおしまい"]
        for mode in RunnerMode.allCases {
            for text in RunnerOnboarding.guide(mode: mode).texts + figureTexts {
                #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
            }
        }
    }
}
