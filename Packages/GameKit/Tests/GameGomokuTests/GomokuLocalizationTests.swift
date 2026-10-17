import Testing
import CoreEngine
@testable import GameGomoku

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("五目並べ: 英語の文言")
struct GomokuLocalizationTests {

    @Test("表示名・禁じ手・読み上げに英語の訳がある")
    func englishTerms() {
        #expect(GameGomoku.tr("五目並べ", language: .english) == "Gomoku")
        #expect(GameGomoku.tr("三三", language: .english) == "Double three")
        #expect(GameGomoku.tr("%@は打てません（禁じ手）", "Overline", language: .english)
                == "Overline isn't allowed (forbidden move)")
        #expect(GameGomoku.tr("%1$lld行%2$lld列", 8, 3, language: .english) == "Row 8, column 3")
    }
}
