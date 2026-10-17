import Testing
import CoreEngine
@testable import GameSolitaire

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("ソリティア: 英語の文言")
struct SolitaireLocalizationTests {

    @Test("表示名・札の用語・読み上げの文に英語の訳がある")
    func englishTerms() {
        #expect(GameSolitaire.tr("ソリティア", language: .english) == "Solitaire")
        #expect(GameSolitaire.tr("3枚めくり", language: .english) == "Draw 3")
        #expect(GameSolitaire.tr("捨て札", language: .english) == "Waste")
        #expect(GameSolitaire.tr("%@の組札、空", "hearts", language: .english) == "Foundation for hearts, empty")
        #expect(GameSolitaire.tr("山札、残り%lld枚、タップでめくる", 1, language: .english) == "Stock, 1 card left, tap to draw")
        #expect(GameSolitaire.tr("ヒント、%1$lld列目の%2$@を組札へ", 3, "7 of hearts", language: .english)
                == "Hint: move 7 of hearts from Column 3 to a foundation")
        #expect(GameSolitaire.tr("%1$lld手 / タイム %2$@", 1, "00:42", language: .english) == "1 move / Time 00:42")
    }

    @Test("記録に保存する区分名は表示の言語によらず日本語のまま")
    func recordLabelStaysJapanese() {
        #expect(SolitaireDrawMode.three.recordLabel == "3枚めくり")
        #expect(SolitaireDrawMode.three.label == "3枚めくり")
    }
}
