import Testing
import Core
@testable import GameMinesweeper

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("マインスイーパー: 英語の文言")
struct MinesweeperLocalizationTests {

    @Test("題名・難易度・読み上げに英語の訳がある")
    func englishTerms() {
        #expect(GameMinesweeper.tr("マインスイーパー", language: .english) == "Minesweeper")
        #expect(GameMinesweeper.tr("上級", language: .english) == "Expert")
        #expect(GameMinesweeper.tr("周囲の地雷%lld", 1, language: .english) == "1 mine nearby")
        #expect(GameMinesweeper.tr("周囲の地雷%lld", 3, language: .english) == "3 mines nearby")
        #expect(GameMinesweeper.tr("%1$lld×%2$lld  %3$lld地雷", 9, 9, 10, language: .english) == "9x9  10 mines")
    }

    /// 記録の区分名は保存されるので、表示が英語でも日本語のまま（表示の英語化は #2168）。
    @Test("記録の区分名は日本語のまま")
    func recordLabelsStayJapanese() {
        #expect(MinesweeperDifficulty.allCases.map(\.recordLabel) == ["初級", "中級", "上級"])
    }
}
