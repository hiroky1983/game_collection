import Testing
@testable import Core
@testable import GameConcentration

/// 英語の表示（多言語⑥ #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("神経衰弱: 英語の文言")
struct ConcentrationLocalizationTests {

    @Test("題名・盤面サイズ・札の読み上げに英語の訳がある")
    func englishTerms() {
        #expect(GameConcentration.tr("神経衰弱", language: .english) == "Memory Match")
        #expect(GameConcentration.tr("8ペア", language: .english) == "8 Pairs")
        #expect(GameConcentration.tr("ヒント（残り%lld回）", 2, language: .english) == "Hint (2 left)")
        #expect(GameConcentration.tr("%@（獲得済み）", "Apple", language: .english) == "Apple (taken)")
        // 不一致は枠の色だけだったので読み上げにも出す（#2322）。
        #expect(GameConcentration.tr("%@（一致しませんでした）", "Apple", language: .english) == "Apple (no match)")
    }

    /// 絵柄の名前（`ObjectCardKind.displayName`）は Core の表で引く。しりとりの読みとは別物なので英語にしてよい。
    @Test("絵柄の名前は Core の表に英語の訳がある")
    func figureNames() {
        #expect(Core.tr("りんご", language: .english) == "Apple")
        #expect(Core.tr("クマ", language: .english) == "Bear")
        #expect(Core.tr("すいとう", language: .english) == "Water bottle")
        // 日本語では従来の読み上げ文のまま。
        #expect(ObjectCardKind.apple.displayName == "りんご")
    }
}
