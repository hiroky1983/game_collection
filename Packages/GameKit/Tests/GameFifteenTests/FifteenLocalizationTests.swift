import Testing
import Core
@testable import GameFifteen

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("15パズル: 英語の文言")
struct FifteenLocalizationTests {

    @Test("題名・読み上げ・クリア表示に英語の訳がある")
    func englishTerms() {
        #expect(GameFifteen.tr("15パズル", language: .english) == "15 Puzzle")
        #expect(GameFifteen.tr("%1$lld行%2$lld列、%3$lld", 2, 3, 7, language: .english) == "Row 2, column 3, 7")
        #expect(GameFifteen.tr("%lld手で揃えました", 1, language: .english) == "Solved in 1 move")
        #expect(GameFifteen.tr("%lld手で揃えました", 42, language: .english) == "Solved in 42 moves")
        // 日本語では従来の読み上げ文のまま。
        #expect(FifteenAccessibility.cellLabel(index: 6, value: 7) == "2行3列、7")
        #expect(FifteenAccessibility.cellLabel(index: 15, value: 0) == "4行4列、空き")
        // 正位置は色だけでなく読み上げにも出す（#2322）。空きマスには付けない。
        #expect(GameFifteen.tr("、正しい位置", language: .english) == ", in the right place")
        #expect(FifteenAccessibility.cellLabel(index: 6, value: 7, isHome: true) == "2行3列、7、正しい位置")
        #expect(FifteenAccessibility.cellLabel(index: 6, value: 7, isHint: true, isHome: true).hasPrefix("2行3列、7、正しい位置、ヒント"))
        #expect(FifteenAccessibility.cellLabel(index: 15, value: 0, isHome: true) == "4行4列、空き")
    }
}
