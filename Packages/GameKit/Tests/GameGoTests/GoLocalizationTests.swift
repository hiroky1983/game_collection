import Testing
import CoreEngine
@testable import GameGo

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("囲碁: 英語の文言")
struct GoLocalizationTests {

    @Test("表示名・用語・結果の文に英語の訳がある")
    func englishTerms() {
        #expect(GameGo.tr("囲碁", language: .english) == "Go")
        #expect(GameGo.tr("コウ", language: .english) == "Ko")
        #expect(GameGo.tr("パス", language: .english) == "Pass")
        #expect(GameGo.tr("%1$@ %2$@目勝ち", "White", "3.5", language: .english) == "White wins by 3.5")
        #expect(GameGo.tr("黒 %1$lld 目 / 白 %2$lld 目 + コミ %3$@", 40, 41, "6.5", language: .english)
                == "Black 40 / White 41 + komi 6.5")
        #expect(GameGo.tr("%lld子", 1, language: .english) == "1 stone")
        #expect(GameGo.tr("%lld子", 3, language: .english) == "3 stones")
    }
}
