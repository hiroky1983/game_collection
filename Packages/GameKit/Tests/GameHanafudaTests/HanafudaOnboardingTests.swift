import Testing
import Core
@testable import GameHanafuda

/// 図で見る「はじめての遊び方」（#2827）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("花札: はじめての遊び方")
struct HanafudaOnboardingTests {
    private let options = HanafudaOptions()

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(HanafudaOnboarding.guide.isWellFormed)
        #expect(HanafudaOnboarding.guide.gameID == HanafudaModel.gameID)
    }

    @Test("図に並べた役の札は、本当にその役になり、文数が表示と一致する")
    func yakuFigureMatchesScoring() {
        for sample in HanafudaOnboarding.sampleYaku {
            let cards = sample.cardIDs.map(HanafudaCard.init(id:))
            let hits = HanafudaScoring.yaku(for: cards, options: options)
            #expect(hits.map(\.yaku) == [sample.yaku], "\(sample.yaku): 札の並びが役の成立条件と合わない")
            #expect(hits.first?.points == sample.yaku.basePoints)
        }
    }

    @Test("図に並べた札の種類が、札の表のとおり")
    func kindsFigureMatchesCards() {
        for sample in HanafudaOnboarding.sampleKinds {
            #expect(HanafudaCard(id: sample.cardID).kind == sample.kind)
        }
        #expect(Set(HanafudaOnboarding.sampleKinds.map(\.kind)) == Set(HanafudaKind.allCases))
    }

    @Test("文言の数字（48 枚・7 文で 2 倍・こいこい返しで 2 倍）が実装の値と同じ")
    func textsMatchRules() {
        let all = HanafudaOnboarding.guide.pages.flatMap(\.lines).joined(separator: "\n")
        #expect(HanafudaCard.deckSize == 48)
        #expect(all.contains("全部で 48 枚"))
        #expect(HanafudaScoring.sevenMonThreshold == 7)
        #expect(all.contains("\(HanafudaScoring.sevenMonThreshold) 文以上"))
        // 7 文以上は 2 倍・相手がこいこいを宣言したあとにあがると 2 倍（重なると 4 倍）。
        #expect(HanafudaScoring.finalScore(base: 7, opponentDeclaredKoiKoi: false) == 14)
        #expect(HanafudaScoring.finalScore(base: 5, opponentDeclaredKoiKoi: true) == 10)
        #expect(HanafudaScoring.finalScore(base: 5, opponentDeclaredKoiKoi: false) == 5)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in HanafudaOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
