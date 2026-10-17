import Testing
import Core
@testable import GameFruits

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("おじさんの盆栽: 英語の文言")
struct FruitsLocalizationTests {

    @Test("表示名・盆栽の名前・読み上げに英語の訳がある（英語名はローマ字）")
    func englishTerms() {
        #expect(GameFruits.tr("おじさんの盆栽", language: .english) == "Ojisan no Bonsai")
        #expect(GameFruits.tr("金の松", language: .english) == "Golden Pine")
        #expect(GameFruits.tr("盆栽 %lld 鉢", 1, language: .english) == "1 bonsai")
        #expect(GameFruits.tr("盆栽 %lld 鉢", 4, language: .english) == "4 bonsai")
        for kind in FruitKind.allCases {
            #expect(GameFruits.tr.hasTranslation(kind.name, language: .english), "\(kind.name) に英語の訳が無い")
        }
    }

    @Test("英語の文言に他社の商標名を含めない")
    func noTrademarkInEnglish() {
        for key in ["おじさんの盆栽", "同じ盆栽をくっつけて、立派に育てよう"] {
            #expect(!GameFruits.tr(key, language: .english).contains("Suika"))
        }
    }
}
