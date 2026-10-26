import Testing
import Core
@testable import GameShiritori

/// 英語の表示（多言語⑥ #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
/// しりとりの読み（かな）はゲームの中身なので、英語の文の中でも日本語のまま埋め込む。
@Suite("カードしりとり: 英語の文言")
struct ShiritoriLocalizationTests {

    @Test("画面の文言に英語の訳があり、かなは日本語のまま埋め込まれる")
    func englishTerms() {
        #expect(GameShiritori.tr("カードしりとり", language: .english) == "Card Shiritori")
        #expect(GameShiritori.tr("「%@」からはじまる札を取ろう", "ご", language: .english) == "Pick a card that starts with “ご”")
        #expect(GameShiritori.tr("CPUが「%@」で終わった！勝ち！", ShiritoriPresentation.nKana, language: .english)
                == "The CPU ended on “ん”! You win!")
        #expect(GameShiritori.tr("のこり%lld秒", 1, language: .english) == "1 second left")
        #expect(GameShiritori.tr("のこり%lld秒", 30, language: .english) == "30 seconds left")
    }

    @Test("記録に保存する区分名と札の読みは表示言語によらず日本語のまま")
    func gameContentStaysJapanese() {
        #expect(ShiritoriMode.endless.scoreVariant(quota: .normal)?.label == "とことん")
        #expect(ShiritoriCard.deck.first?.primaryReading == "りんご")
    }

    @Test("ノルマの記録は難易度で分かれ、「ふつう」だけ従来の保存先（区分なし）のまま（#2608）")
    func quotaRecordVariantsSplitByDifficulty() {
        #expect(ShiritoriMode.quota.scoreVariant(quota: .normal) == nil)
        #expect(ShiritoriMode.quota.scoreVariant(quota: .easy)?.key == "quota-easy")
        #expect(ShiritoriMode.quota.scoreVariant(quota: .easy)?.label == "かんたん")
        #expect(ShiritoriMode.quota.scoreVariant(quota: .hard)?.key == "quota-hard")
        #expect(ShiritoriMode.quota.scoreVariant(quota: .hard)?.label == "むずかしい")
        #expect(ShiritoriMode.endless.scoreVariant(quota: .hard)?.key == "endless")
        #expect(RecordVariantLabels.label(recordKey: "shiritori#quota-hard", language: .english) == "Hard")
    }
}
