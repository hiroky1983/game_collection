import Testing
import CoreEngine
@testable import GameMancala

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("マンカラ: 英語の文言")
struct MancalaLocalizationTests {

    @Test("表示名・用語・状況の文に英語の訳がある")
    func englishTerms() {
        #expect(GameMancala.tr("マンカラ", language: .english) == "Mancala")
        #expect(GameMancala.tr("あなたのストア", language: .english) == "Your store")
        #expect(GameMancala.tr("あなたの穴 %lld", 3, language: .english) == "Your pit 3")
        #expect(GameMancala.tr("向かいの %lld 個を取った！", 6, language: .english) == "You captured 6 seeds!")
        #expect(GameMancala.tr("あなた %1$lld – CPU %2$lld", 30, 18, language: .english) == "You 30 – CPU 18")
    }
}
