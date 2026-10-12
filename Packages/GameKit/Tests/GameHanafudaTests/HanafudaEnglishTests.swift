import Core
import Foundation
import Testing
@testable import GameHanafuda

/// 花札の英語表示（#2166）。`AppLanguageStore.shared` は書き換えず、`language: .english` を明示して引く。
@Suite("花札: 英語の文言（#2166）")
struct HanafudaEnglishTests {

    @Test("役名はローマ字＋英語の説明（会長決定）")
    func yakuNamesAreRomajiWithGloss() {
        #expect(GameHanafuda.tr("猪鹿蝶", language: .english) == "Inoshikachou (Boar, Deer & Butterfly)")
        #expect(GameHanafuda.tr("五光", language: .english) == "Gokou (Five Brights)")
        #expect(GameHanafuda.tr("雨四光", language: .english) == "Ame-Shikou (Rainy Four Brights)")
        #expect(GameHanafuda.tr("花見酒", language: .english) == "Hanami-zake (Cherry Viewing Sake)")
        #expect(GameHanafuda.tr("カス", language: .english) == "Kasu (Plains)")
    }

    @Test("札名・ゲーム名・こいこいの宣言")
    func cardsAndCalls() {
        #expect(GameHanafuda.tr("松に鶴", language: .english) == "Crane and Sun (Pine)")
        #expect(GameHanafuda.tr("柳に小野道風", language: .english) == "Rain Man (Willow)")
        #expect(GameHanafuda.tr("花札こいこい", language: .english) == "Hanafuda Koi-Koi")
        #expect(GameHanafuda.tr("こいこい", language: .english) == "Koi-Koi")
        #expect(GameHanafuda.tr("あがり", language: .english) == "Stop")
    }

    @Test("枚数・文数の複数形と語順")
    func pluralsAndOrder() {
        #expect(GameHanafuda.tr("光%lld枚", 1, language: .english) == "1 Bright")
        #expect(GameHanafuda.tr("カス%lld枚", 3, language: .english) == "3 Plains")
        #expect(GameHanafuda.tr("あなたが%1$@で%2$lld枚取った", "Moon (Pampas)", 2, language: .english)
                == "You captured 2 cards with Moon (Pampas)")
        #expect(GameHanafuda.tr("%lld局", 1, language: .english) == "1 round")
    }

    @Test("ハブの表示名・説明は英語でも権利チェックの結論に沿う")
    func moduleSurfacesAvoidTrademarks() {
        let title = GameHanafuda.tr("花札こいこい", language: .english)
        let description = GameHanafuda.tr("CPUと役を競う。こいこいで倍を狙おう", language: .english)
        for surface in [title, description] {
            #expect(!surface.lowercased().contains("online"))
            #expect(!surface.lowercased().contains("tsukimi"))
        }
    }

    @Test("日本語では表示用の札名が原文の札名と一致する（48枚）")
    func displayNamesMatchJapaneseNames() {
        for card in HanafudaCard.fullDeck {
            #expect(card.displayName == card.name, "\(card.id)")
        }
    }

    @Test("英語では帯の種別表記が2文字の略号になる")
    func englishBadges() {
        // 帯は `badgeLabel` の規則をそのまま英語の表に当てた結果を確かめる。
        let bright = GameHanafuda.tr("光", language: .english)
        let animal = GameHanafuda.tr("タネ", language: .english)
        #expect(bright.hasPrefix("Br"))
        #expect(animal.contains("(Animals)"))
        #expect(GameHanafuda.tr("短", language: .english) == "Rb")
    }

    @Test("中断データに残る倍率の内訳は日本語の原文のまま、画面は表示言語")
    func multiplierReasonsStayCanonical() {
        let reasons = HanafudaScoring.multiplierReasons(base: 8, opponentDeclaredKoiKoi: true)
        #expect(reasons == ["7文以上で2倍", "こいこい返しで2倍"])
        #expect(reasons.map(HanafudaScoring.reasonLabel) == reasons, "日本語では原文のまま")
    }
}
