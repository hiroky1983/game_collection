import Core
import Foundation
import Testing
@testable import GameRunner
import CoreTestSupport

/// 効果音 4 音（#703: 跳ぶ・取る・やられる・クリア）。
///
/// このゲームは音の発火点を持たず、触覚の呼び出しに App 層の効果音が相乗りする
/// （`RunnerFeedbackCue` の doc）。だから確かめるのは「できごと → 触覚」の対応表と、
/// その触覚が `SoundEffect` のどの音になるか、そして `RunnerModel` が実際にその触覚を
/// `services.feedback` へ渡すこと。

@MainActor
private func makeModel(_ feedback: FeedbackService, stage: Int, suite: String) -> RunnerModel {
    RunnerModel(
        services: GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: feedback
        ),
        startingAt: stage,
        preference: makePreference(suite)
    )
}

@Suite("チャリンコおじさん: 手応えと効果音")
@MainActor
struct RunnerFeedbackCueTests {

    @Test("できごとごとの手応えと、相乗りする効果音の対応")
    func cueTable() {
        #expect(RunnerFeedbackCue.cue(for: .collectedSpeedItem, lastLandingWasJust: false) == .impact(.light))
        // たこ焼き（#797）も「取る」の音に相乗り（4 音の表を増やさない）。
        #expect(RunnerFeedbackCue.cue(for: .collectedInvincibleItem, lastLandingWasJust: false) == .impact(.light))
        #expect(RunnerFeedbackCue.cue(for: .fell, lastLandingWasJust: false) == .notice(.error))
        #expect(RunnerFeedbackCue.cue(for: .crashed, lastLandingWasJust: false) == .notice(.error))
        #expect(RunnerFeedbackCue.cue(for: .reachedGoal, lastLandingWasJust: false) == .notice(.success))
        #expect(RunnerFeedbackCue.cue(for: .passedCheckpoint, lastLandingWasJust: false) == .notice(.success))
        // イノシシの予告「ドドド」（#801）は硬い手応えで、決着（notice）ではない。
        #expect(RunnerFeedbackCue.cue(for: .boarCharging, lastLandingWasJust: false) == .impact(.rigid))
        // 着地はジャスト着地（#673）だけ一段強い。
        #expect(RunnerFeedbackCue.cue(for: .landed, lastLandingWasJust: false) == .impact(.light))
        #expect(RunnerFeedbackCue.cue(for: .landed, lastLandingWasJust: true) == .impact(.medium))

        // 4 音（取る → light・やられる → error・クリア → success）。跳ぶ音は `press()` 側で light。
        #expect(RunnerFeedbackCue.cue(for: .collectedSpeedItem, lastLandingWasJust: false).soundEffect == .light)
        #expect(RunnerFeedbackCue.cue(for: .fell, lastLandingWasJust: false).soundEffect == .error)
        #expect(RunnerFeedbackCue.cue(for: .crashed, lastLandingWasJust: false).soundEffect == .error)
        #expect(RunnerFeedbackCue.cue(for: .reachedGoal, lastLandingWasJust: false).soundEffect == .success)
        #expect(SoundEffect(FeedbackImpact.light) == .light, "跳ぶ音")
    }

    @Test("跳ぶ音は踏み切りが成立したときだけ。二段目は鳴り、三度目と押しっぱなしでは鳴らない")
    func jumpSoundOnlyWhenJumpSucceeds() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy, stage: 1, suite: "cue-jump")
        model.press(); model.release()   // スタート（rigid）。跳ぶ音ではない。
        spy.reset()

        model.press()                    // 一段目
        #expect(spy.impacts == [.light])
        model.press()                    // 押しっぱなし: 何も起きない
        #expect(spy.impacts == [.light])
        model.release()
        model.press()                    // 二段目
        #expect(spy.impacts == [.light, .light])
        model.release()
        model.press()                    // 三度目は `RunnerRules.maxJumps` 超えで不成立
        #expect(spy.impacts == [.light, .light], "跳べていないのに音だけ鳴らさない")
        model.release()
    }

    @Test("穴に落ちる／岩にぶつかると error が 1 回だけ鳴る")
    func missPlaysErrorOnce() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy, stage: 1, suite: "cue-miss")
        failCurrentStage(model)
        #expect(model.phase == .failed)
        #expect(spy.notices.filter { $0 == .error }.count == 1)
        #expect(spy.notices.last == .error)
    }

    @Test("ゴールに着くと success が鳴る（チェックポイント通過の success とは別に 1 回）")
    func goalPlaysSuccess() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy, stage: 1, suite: "cue-goal")
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(spy.notices == [.success, .success], "チェックポイント通過 + ゴール")
        #expect(!spy.notices.contains(.error))
    }

    @Test("スピードアップアイテムを取ると light が鳴る")
    func pickupPlaysLight() {
        // 5 面が最初にアイテムを置いている面（`RunnerStage.patterns` の `s`）。
        let spy = SpyFeedbackService()
        let model = makeModel(spy, stage: 5, suite: "cue-pickup")
        #expect(!model.stage.pickups.isEmpty)
        model.press(); model.release()
        var frames = 0
        var lightsBefore = 0
        while model.field.collectedPickupIndices.isEmpty, model.phase.isRunning, frames < 60 * 60 {
            frames += 1
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            // 跳ぶ音（`press()`）を数えたあと、`tick` の中で起きたぶんだけを見る。
            lightsBefore = spy.impacts.filter { $0 == .light }.count
            model.tick(dt: 1.0 / 60)
        }
        #expect(!model.field.collectedPickupIndices.isEmpty, "自動操縦でアイテムを取れる")
        // 取った瞬間の `tick` で light が増えている（同じ tick に着地が重なることはあり得るが、
        // 取ったぶんの 1 回は必ず入る）。
        #expect(spy.impacts.filter { $0 == .light }.count > lightsBefore)
    }
}
