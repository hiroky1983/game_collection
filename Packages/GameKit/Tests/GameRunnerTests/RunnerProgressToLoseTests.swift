import Foundation
import Testing
@testable import GameRunner

/// 「はじめから」で捨てる走りがあるか（#3148）。共通の確認を出す境目。
@Suite("チャリンコおじさん: 捨てる進行")
@MainActor
struct RunnerProgressToLoseTests {
    @Test("走り出す前は捨てる進行が無く、走って距離が出たら有り、止めても残り、止めた後も有る")
    func progressFollowsTheRun() {
        let model = RunnerModel(startingAt: 1, preference: makePreference("progress-to-lose"))
        #expect(!model.hasProgressToLose)
        model.press()
        model.release()
        for _ in 0..<240 {
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
        }
        #expect(model.phase == .running, "自動操縦で 4 秒走り続けられるはず")
        #expect(model.hasProgressToLose)
        model.pause()
        #expect(model.hasProgressToLose, "一時停止中も走りは残っている")
        model.resume()
        #expect(model.hasProgressToLose)
    }
}
