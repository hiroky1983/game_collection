import Testing
import Foundation
@testable import Core

/// 計時ラベルの読み上げ（#3043）。表示の「0:12」「003」ではなく経過秒から読みを組み立てる。
@Suite("計時ラベルの読み上げ")
struct GameClockLabelSpokenTests {

    @Test("1分未満は秒だけ、1分以上は分と秒で読む")
    func spokenLabel() {
        #expect(GameClockLabel.spokenLabel(elapsedSeconds: 3) == "経過3秒")
        #expect(GameClockLabel.spokenLabel(elapsedSeconds: 75) == "経過1分15秒")
        #expect(GameClockLabel.spokenLabel(elapsedSeconds: 0) == "経過0秒")
    }

    @Test("負の値は 0 秒に丸める")
    func negativeClamped() {
        #expect(GameClockLabel.spokenLabel(elapsedSeconds: -5) == "経過0秒")
    }
}
