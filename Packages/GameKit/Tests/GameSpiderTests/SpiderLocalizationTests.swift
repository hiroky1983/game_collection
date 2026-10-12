import Testing
import CoreEngine
@testable import GameSpider

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("スパイダーソリティア: 英語の文言")
struct SpiderLocalizationTests {

    @Test("表示名・スート数・読み上げの文に英語の訳がある")
    func englishTerms() {
        #expect(GameSpider.tr("スパイダーソリティア", language: .english) == "Spider Solitaire")
        #expect(GameSpider.tr("%lldスート", 1, language: .english) == "1 Suit")
        #expect(GameSpider.tr("%lldスート", 4, language: .english) == "4 Suits")
        #expect(GameSpider.tr("スペード", language: .english) == "spades")
        #expect(GameSpider.tr("山札、残り%lld回", 5, language: .english) == "Stock, 5 deals left")
        #expect(GameSpider.tr("配る（残り%lld）", 2, language: .english) == "Deal (2 left)")
    }

    @Test("記録に保存する区分名は表示の言語によらず日本語のまま")
    func recordLabelStaysJapanese() {
        #expect(SpiderSuitCount.two.recordLabel == "2スート")
        #expect(SpiderSuitCount.two.label == "2スート")
    }
}
