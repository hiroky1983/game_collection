import Testing
import Core
@testable import GameAnzan

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("ぱっと暗算: 英語の文言")
struct AnzanLocalizationTests {

    @Test("表示名と難易度の 3 軸に英語の訳がある")
    func englishTerms() {
        #expect(GameAnzan.tr("ぱっと暗算", language: .english) == "Quick Mental Math")
        #expect(GameAnzan.tr("%lld桁", 1, language: .english) == "1 digit")
        #expect(GameAnzan.tr("%lld桁", 2, language: .english) == "2 digits")
        #expect(GameAnzan.tr("%lld個", 10, language: .english) == "10 numbers")
        #expect(GameAnzan.tr("%1$@・%2$@・%3$@", "2 digits", "10 numbers", "Normal", language: .english)
                == "2 digits · 10 numbers · Normal")
        #expect(AnzanDigits.two.label(language: .english) == "2 digits")
        #expect(AnzanSpeed.fast.label(language: .english) == "Fast")
    }

    @Test("記録に保存する区分名は表示言語によらず日本語のまま")
    func recordLabelStaysJapanese() {
        let settings = AnzanSettings(digits: .two, count: .ten, speed: .normal)
        #expect(settings.recordVariantLabel == "2桁・10個・ふつう")
        #expect(AnzanSettings.standard.recordVariantLabel == "1桁・5個・ゆっくり")
        // 日本語の表示名と記録の区分名は同じ文字列（既存の記録と食い違わない）。
        #expect(settings.variantLabel == settings.recordVariantLabel)
    }
}
