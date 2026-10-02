import Testing
@testable import Core

/// 共通のクリアカード（#1755）の読み上げ文。
@Suite("GameClearCard")
struct GameClearCardTests {
    @Test("読み上げは見出しの「！」を落とし、記録の行を句点でつなぐ")
    func accessibilityLabel() {
        let label = GameClearCard.accessibilityLabel(title: "クリア！", details: ["38手 / タイム 05:12"])
        #expect(label == "クリア。38手 / タイム 05:12")
    }

    @Test("記録の行が無ければ見出しだけ読む")
    func accessibilityLabelWithoutDetails() {
        #expect(GameClearCard.accessibilityLabel(title: "全部取り切った！", details: []) == "全部取り切った")
    }
}
