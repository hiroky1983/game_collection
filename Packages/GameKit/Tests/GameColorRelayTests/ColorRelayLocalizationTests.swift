import Testing
import Core
@testable import GameColorRelay

/// 英語の表示（多言語⑥ #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("いろリレー: 英語の文言")
struct ColorRelayLocalizationTests {

    @Test("札の呼び名と操作の文言に英語の訳がある")
    func englishTerms() {
        #expect(GameColorRelay.tr("いろリレー", language: .english) == "Color Relay")
        #expect(GameColorRelay.tr("%1$@の%2$@", "Red", "Skip", language: .english) == "Red Skip")
        #expect(GameColorRelay.tr("残り%lld枚", 1, language: .english) == "1 card")
        #expect(GameColorRelay.tr("残り%lld枚", 7, language: .english) == "7 cards")
        #expect(GameColorRelay.tr("%@の番", "CPU2", language: .english) == "CPU2's turn")
    }

    @Test("英語の文言に他社の商標を含めない")
    func noTrademarkInEnglish() {
        for key in ["いろリレー", "色か数字をつないで手札を出し切ろう。CPU3人と対戦", "いろがえ", "いろがえ+4"] {
            let english = GameColorRelay.tr(key, language: .english)
            #expect(!english.uppercased().contains("UNO"), "「\(key)」の英語に商標が入っている")
        }
    }
}
