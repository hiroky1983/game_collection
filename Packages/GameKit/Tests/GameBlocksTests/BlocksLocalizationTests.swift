import Testing
import Core
@testable import GameBlocks

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("ブロック崩し: 英語の文言")
struct BlocksLocalizationTests {

    @Test("表示名・ステージ・残機に英語の訳がある")
    func englishTerms() {
        #expect(GameBlocks.tr("ブロック崩し", language: .english) == "Block Breaker")
        #expect(GameBlocks.tr("ステージ %1$lld / %2$lld", 2, 10, language: .english) == "Stage 2 / 10")
        #expect(GameBlocks.tr("残機 %lld", 1, language: .english) == "1 life left")
        #expect(GameBlocks.tr("残機 %lld", 3, language: .english) == "3 lives left")
    }
}
