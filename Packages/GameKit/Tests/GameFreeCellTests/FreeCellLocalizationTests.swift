import Testing
import CoreEngine
@testable import GameFreeCell

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("フリーセル: 英語の文言")
struct FreeCellLocalizationTests {

    @Test("表示名・札の用語・読み上げの文に英語の訳がある")
    func englishTerms() {
        #expect(GameFreeCell.tr("フリーセル", language: .english) == "FreeCell")
        #expect(GameFreeCell.tr("フリーセル%lld、空", 2, language: .english) == "Cell 2, empty")
        #expect(GameFreeCell.tr("ヒント、%1$@を%2$@の組札へ", "A of spades", "spades", language: .english)
                == "Hint: move A of spades to the spades foundation")
        #expect(GameFreeCell.tr("配札 #%@", "1234", language: .english) == "Deal #1234")
        #expect(GameFreeCell.tr("終了して新規ゲーム", language: .english) == "Quit & New Game")
    }
}
