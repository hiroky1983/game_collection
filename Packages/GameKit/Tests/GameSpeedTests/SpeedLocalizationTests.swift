import Testing
import Core
@testable import GameSpeed

/// 英語の表示（多言語⑥ #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("スピード: 英語の文言")
struct SpeedLocalizationTests {

    @Test("札・山札の読み上げと速さに英語の訳がある")
    func englishTerms() {
        #expect(GameSpeed.tr("あなたの山札", language: .english) == "Your stock")
        #expect(GameSpeed.tr("%1$@、残り%2$lld枚", "Your stock", 1, language: .english) == "Your stock, 1 card left")
        #expect(GameSpeed.tr("%1$@、残り%2$lld枚", "Your stock", 12, language: .english) == "Your stock, 12 cards left")
        #expect(GameSpeed.tr("はやい", language: .english) == "Fast")
    }

    @Test("記録に保存する区分名は表示言語によらず日本語のまま")
    func recordLabelStaysJapanese() {
        #expect(SpeedSettings(level: .slow).variantLabel == "ゆっくり")
        #expect(SpeedSettings(level: .normal).variantLabel == "ふつう")
        #expect(SpeedSettings(level: .fast).variantLabel == "はやい")
    }
}
