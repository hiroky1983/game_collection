import Testing
import CoreEngine
@testable import GameOthello

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("オセロ: 英語の文言")
struct OthelloLocalizationTests {

    @Test("英語の表示名は商標を避けて Osero（ローマ字）")
    func englishTitleAvoidsTrademark() {
        #expect(GameOthello.tr("オセロ", language: .english) == "Osero")
        #expect(!GameOthello.tr("石を挟んでひっくり返せ！CPU に挑戦", language: .english).contains("Othello"))
    }

    @Test("結果の読み上げは語順を保ったまま英語になる")
    func resultLabel() {
        #expect(GameOthello.tr("%1$@ 黒 %2$lld 対 白 %3$lld", "You win", 40, 24, language: .english)
                == "You win. Black 40, white 24")
        #expect(GameOthello.tr("パス", language: .english) == "Pass")
    }
}
