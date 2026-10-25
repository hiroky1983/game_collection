import Testing
import SwiftUI
import Core
@testable import GameHearts

/// 図で見る「はじめての遊び方」（#2827）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("ハーツ: はじめての遊び方")
struct HeartsOnboardingTests {
    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(HeartsOnboarding.guide.isWellFormed)
        #expect(HeartsOnboarding.guide.gameID == HeartsModel.gameID)
    }

    @Test("文言の数字（渡す枚数・終わりの点）が実装の値から作られる")
    func numbersComeFromRules() {
        let lines = HeartsOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("13 枚が配られたら、まず \(HeartsRules.passCount) 枚を選んで左どなりへ渡します。"))
        #expect(lines.contains("だれかが \(HeartsRules.targetScore) 点に届いたら、そこで終わりです。"))
        #expect(HeartsRules.handSize == 13)
    }

    @Test("点数: ハートは 1 点・スペードの Q は 13 点・ほかは 0 点")
    func pointsMatchCards() {
        #expect(HeartsCard(.heart, 5).points == 1)
        #expect(HeartsCard.queenOfSpades.points == 13)
        #expect(HeartsCard(.club, 13).points == 0)
        let lines = HeartsOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("ハートは 1 枚 1 点、スペードの Q は 13 点です。"))
    }

    @Test("強さ: A が最強で 2 が最弱。強い札を出した人が取り、別のマークは A でも勝てない")
    func strengthAndTrick() {
        #expect(HeartsReference.strengthOrder.first == 14)
        #expect(HeartsReference.strengthOrder.last == 2)
        let trick = [
            HeartsPlay(player: 0, card: HeartsCard(.diamond, 7)),
            HeartsPlay(player: 1, card: HeartsCard(.diamond, 12)),
            HeartsPlay(player: 2, card: HeartsCard(.spade, 14)),
            HeartsPlay(player: 3, card: HeartsCard(.diamond, 3)),
        ]
        #expect(HeartsRules.trickWinner(trick) == 1)
    }

    @Test("ハート: 割れるまで先頭に出せない・手札がハートだけなら出せる・1 巡目は点の札を出せない")
    func heartsRules() {
        let hand = [HeartsCard(.heart, 9), HeartsCard(.club, 4)]
        let unbroken = HeartsRules.legalPlays(hand: hand, trick: [], heartsBroken: false, isFirstTrick: false)
        #expect(unbroken == [HeartsCard(.club, 4)])
        let broken = HeartsRules.legalPlays(hand: hand, trick: [], heartsBroken: true, isFirstTrick: false)
        #expect(broken.contains(HeartsCard(.heart, 9)))
        let onlyHearts = HeartsRules.legalPlays(hand: [HeartsCard(.heart, 9)], trick: [], heartsBroken: false, isFirstTrick: false)
        #expect(onlyHearts == [HeartsCard(.heart, 9)])
        // 1 巡目: 同じマークが無くても、ハートとスペードの Q は出せない（ほかに札があるとき）。
        let lead = [HeartsPlay(player: 3, card: HeartsCard.twoOfClubs)]
        let first = HeartsRules.legalPlays(
            hand: [HeartsCard(.heart, 9), HeartsCard.queenOfSpades, HeartsCard(.diamond, 5)],
            trick: lead, heartsBroken: false, isFirstTrick: true)
        #expect(first == [HeartsCard(.diamond, 5)])
    }

    /// 花札こいこいのページ送りで画面が固まってクラッシュした不具合（#2905）の再発防止。
    /// 同じ共通部品（`OnboardingGuideView`）を使うハーツでも、全ページの図が描けることを確かめる。
    @Test("全ページの図が描ける")
    func allPagesRender() throws {
        for (index, page) in HeartsOnboarding.guide.pages.enumerated() {
            let renderer = ImageRenderer(content: page.figure().fixedSize())
            renderer.scale = 1
            _ = try #require(renderer.cgImage, "\(index + 1) 枚目（\(page.heading)）の図が描けない")
        }
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        // 数を埋め込む 2 行は、表のキー（書式）の形で確かめる。
        let formatted = [
            "13 枚が配られたら、まず %lld 枚を選んで左どなりへ渡します。",
            "だれかが %lld 点に届いたら、そこで終わりです。",
        ]
        let filled = [
            tr("13 枚が配られたら、まず %lld 枚を選んで左どなりへ渡します。", HeartsRules.passCount),
            tr("だれかが %lld 点に届いたら、そこで終わりです。", HeartsRules.targetScore),
        ]
        for key in formatted {
            #expect(tr.hasTranslation(key, language: .english), "「\(key)」に英語の訳が無い")
        }
        for text in HeartsOnboarding.guide.texts where !filled.contains(text) {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
