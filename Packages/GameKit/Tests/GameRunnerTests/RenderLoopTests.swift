import Foundation
import Observation
import Testing
@testable import GameRunner

/// `withObservationTracking` の `onChange` は Sendable なので、通知の有無は箱に入れて受ける。
private final class NotifyFlag: @unchecked Sendable { var fired = false }

@Suite("チャリンコおじさん: 描画ループと観測（#1386）")
@MainActor
struct RunnerRenderLoopTests {

    @Test("描画ループが要るのはスタート前・走行中・演出中だけ")
    func needsAnimationFramesPerPhase() {
        let running: [RunnerPhase] = [.ready, .running, .falling, .chasing]
        let idle: [RunnerPhase] = [.paused, .failed, .story, .cleared, .allCleared]
        for phase in running { #expect(phase.needsAnimationFrames, "\(phase) は動く") }
        for phase in idle { #expect(!phase.needsAnimationFrames, "\(phase) は動かない") }
    }

    @Test("走行中に毎フレーム field が変わっても、観測している側には通知が飛ばない")
    func fieldIsNotObserved() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("observe-field"))
        model.press()
        model.release()
        let flag = NotifyFlag()
        withObservationTracking {
            _ = model.field
            _ = model.field.distance
        } onChange: {
            flag.fired = true
        }
        for _ in 0..<5 { model.tick(dt: 1.0 / 60) }
        #expect(model.field.distance > 0, "field は実際に進んでいる")
        #expect(!flag.fired)
    }

    @Test("距離・進捗は表示用ミラーが field に追随し、変わったときだけ通知する")
    func mirrorsFollowField() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("observe-mirror"))
        model.press()
        model.release()
        let flag = NotifyFlag()
        withObservationTracking {
            _ = model.distanceMeters
        } onChange: {
            flag.fired = true
        }
                for _ in 0..<600 { model.tick(dt: 1.0 / 60) }
        #expect(model.distanceMeters == Int(model.field.distance / RunnerRules.tileWidth))
        #expect(model.distanceMeters > 0)
        #expect(flag.fired, "1 m 進めば通知される")
        #expect(abs(model.displayProgress - model.field.progress) <= 0.005)
        #expect(abs(model.displayPedalBoost - model.field.pedalBoost) <= 0.01)
    }

    @Test("コースを組み直すとミラーも戻る")
    func mirrorsResetWithField() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("observe-reset"))
        model.press()
        model.release()
        for _ in 0..<300 { model.tick(dt: 1.0 / 60) }
        #expect(model.distanceMeters > 0)
        model.resetRun(RunnerField(stage: RunnerStage.all[0]))
        #expect(model.distanceMeters == 0)
        #expect(model.displayProgress == 0)
        #expect(!model.passedCheckpoint)
    }

    @Test("描画ループを止めていた穴（古いフレーム）は進めず、通常のフレームは進める")
    func staleFrameIsNotAdvanced() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("stale-frame"))
        let scene = RunnerScene(model: model)
        model.press()
        model.release()
        scene.update(100)   // 初回は時計を合わせるだけ
        scene.update(100 + 1.0 / 60)
        let advanced = model.field.distance
        #expect(advanced > 0, "通常のフレームは進む")
        scene.update(100 + 1.0 / 60 + 10)   // 10 秒止めていたあとの再開フレーム
        #expect(model.field.distance == advanced, "止めていた時間ぶんは進めない")
        scene.update(100 + 1.0 / 60 + 10 + 1.0 / 60)
        #expect(model.field.distance > advanced, "次のフレームからは進む")
    }
}
