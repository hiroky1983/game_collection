import Testing
import Core
@testable import GameFruits

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("くっつきフルーツ: 英語の文言")
struct FruitsLocalizationTests {

    @Test("表示名・果物の名前・読み上げに英語の訳がある")
    func englishTerms() {
        #expect(GameFruits.tr("くっつきフルーツ", language: .english) == "Fruit Merge")
        #expect(GameFruits.tr("メロン", language: .english) == "Melon")
        #expect(GameFruits.tr("果物 %lld 個", 1, language: .english) == "1 fruit")
        #expect(GameFruits.tr("果物 %lld 個", 4, language: .english) == "4 fruits")
    }

    @Test("英語の文言に他社の商標名を含めない")
    func noTrademarkInEnglish() {
        for key in ["くっつきフルーツ", "同じくだものをくっつけて、大きく育てよう"] {
            #expect(!GameFruits.tr(key, language: .english).contains("Suika"))
        }
    }
}
