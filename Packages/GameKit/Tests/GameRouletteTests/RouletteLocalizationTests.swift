import Testing
import Core
@testable import GameRoulette

/// 英語の表示（多言語⑥ #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("ルーレット: 英語の文言")
struct RouletteLocalizationTests {

    @Test("賭けの区分と操作の文言に英語の訳がある")
    func englishTerms() {
        #expect(GameRoulette.tr("スピン", language: .english) == "Spin")
        #expect(GameRoulette.tr("奇数", language: .english) == "Odd")
        #expect(GameRoulette.tr("%1$lld〜%2$lld", 13, 24, language: .english) == "13-24")
        #expect(GameRoulette.tr("+%lld枚", 1, language: .english) == "+1 chip")
        #expect(GameRoulette.tr("+%lld枚", 350, language: .english) == "+350 chips")
    }

    @Test("日本語ではキーがそのまま出る（区分の名前は従来どおり）")
    func japaneseIsUnchanged() {
        #expect(GameRoulette.tr("%1$lld〜%2$lld", 13, 24, language: .japanese) == "13〜24")
    }
}
