import Testing
import Core
@testable import Game2048

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("2048: 英語の文言")
struct Game2048LocalizationTests {

    @Test("説明・マスの読み上げ・「戻す」の補充に英語の訳がある")
    func englishTerms() {
        #expect(Game2048.tr("タイルを合体させて2048を目指そう", language: .english) == "Merge tiles and reach 2048")
        #expect(Game2048.tr("%1$lld行%2$lld列、%3$@", 2, 3, "128", language: .english) == "Row 2, column 3, 128")
        #expect(Game2048.tr("広告を見て%lld回補充する", 1, language: .english) == "Watch an ad for 1 more undo")
        #expect(Game2048.tr("広告を見て%lld回補充する", 3, language: .english) == "Watch an ad for 3 more undos")
    }

    @Test("日本語では原文のまま")
    func japaneseUnchanged() {
        #expect(Game2048Accessibility.tileLabel(row: 1, col: 2, value: 0) == "2行3列、空き")
    }
}
