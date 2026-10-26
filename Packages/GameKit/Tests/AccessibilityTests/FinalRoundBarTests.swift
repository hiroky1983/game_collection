import Testing
@testable import Core

/// 最後の回の帯（#2592）。見た目はシミュレータで確かめ、読み上げ文だけここで固定する。
@Suite("最後の勝負の帯")
struct FinalRoundBarTests {
    @Test("最後の回だけ読み上げの頭に「最後の勝負」が付く")
    func announcesOnlyOnFinalRound() {
        #expect(FinalRoundBar.accessibilityLabel("10回目 / 10", isFinal: true) == "最後の勝負、10回目 / 10")
        #expect(FinalRoundBar.accessibilityLabel("9回目 / 10", isFinal: false) == "9回目 / 10")
    }
}
