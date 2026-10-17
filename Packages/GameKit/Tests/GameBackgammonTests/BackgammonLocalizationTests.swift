import Testing
import CoreEngine
@testable import GameBackgammon

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("バックギャモン: 英語の文言")
struct BackgammonLocalizationTests {

    @Test("表示名・用語・状況の文に英語の訳がある")
    func englishTerms() {
        #expect(GameBackgammon.tr("バックギャモン", language: .english) == "Backgammon")
        #expect(GameBackgammon.tr("バー", language: .english) == "Bar")
        #expect(GameBackgammon.tr("ギャモン勝ち", language: .english) == "Gammon win")
        #expect(GameBackgammon.tr("%lldポイント", 6, language: .english) == "Point 6")
        #expect(GameBackgammon.tr("ピップカウント、あなた%1$lld、CPU%2$lld", 167, 150, language: .english)
                == "Pip count: you 167, CPU 150")
        #expect(GameBackgammon.tr("先手は CPU（オープニングロール CPU %1$lld – あなた %2$lld）", 5, 3,
                                  language: .english) == "CPU goes first (opening roll: CPU 5 – you 3)")
    }
}
