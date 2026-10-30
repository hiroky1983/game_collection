import Testing
import Core
@testable import GameSudoku

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("ナンプレ: 英語の文言")
struct SudokuLocalizationTests {

    @Test("題名・難易度・読み上げに英語の訳がある")
    func englishTerms() {
        #expect(GameSudoku.tr("ナンプレ", language: .english) == "Number Place")
        #expect(GameSudoku.tr("むずかしい", language: .english) == "Hard")
        #expect(GameSudoku.tr("ミス %1$lld/%2$lld", 1, 3, language: .english) == "Mistakes 1/3")
        #expect(GameSudoku.tr("残り%1$lldマス、経過%2$@", 1, "5 sec", language: .english) == "1 square left, 5 sec elapsed")
        #expect(GameSudoku.tr("残り%1$lldマス、経過%2$@", 12, "5 sec", language: .english) == "12 squares left, 5 sec elapsed")
    }

    /// 記録の区分名は保存されるので、表示が英語でも日本語のまま（表示の英語化は #2168）。
    @Test("記録の区分名は日本語のまま")
    func recordLabelsStayJapanese() {
        #expect(SudokuDifficulty.allCases.map(\.recordLabel) == ["かんたん", "ふつう", "むずかしい", "上級"])
    }
}
