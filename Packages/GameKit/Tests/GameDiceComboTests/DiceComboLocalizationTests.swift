import Testing
import Core
@testable import GameDiceCombo

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("サイコロ役づくり: 英語の文言")
struct DiceComboLocalizationTests {

    @Test("表示名・役の名前・読み上げに英語の訳がある")
    func englishTerms() {
        #expect(GameDiceCombo.tr("サイコロ役づくり", language: .english) == "Dice Combos")
        #expect(GameDiceCombo.tr("フルハウス", language: .english) == "Full House")
        #expect(GameDiceCombo.tr("Bストレート", language: .english) == "Big Straight")
        #expect(GameDiceCombo.tr("%lldの目の合計", 3, language: .english) == "Sum of all 3's")
        #expect(GameDiceCombo.tr("サイコロを振る、残り%lld回", 1, language: .english) == "Roll dice, 1 roll left")
        #expect(GameDiceCombo.tr("サイコロを振る、残り%lld回", 2, language: .english) == "Roll dice, 2 rolls left")
        #expect(GameDiceCombo.tr("サイコロ%1$lld、%2$lld", 1, 4, language: .english) == "Die 1, 4")
    }
}
