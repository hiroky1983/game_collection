import Testing
import Core
@testable import GameBlackjack

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("ブラックジャック: はじめての遊び方")
struct BlackjackOnboardingTests {
    private func card(_ rank: Int) -> BlackjackCard { BlackjackCard(id: rank, suit: .spades, rank: rank) }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(BlackjackOnboarding.guide.isWellFormed)
        #expect(BlackjackOnboarding.guide.gameID == "blackjack")
    }

    @Test("点数: A は 1 か 11・J Q K は 10・数字はそのまま。21 を超えるときだけ A を 1 にする")
    func cardValues() {
        #expect(handValue([card(1), card(13)]) == 21)
        #expect(handValue([card(11), card(12)]) == 20)
        #expect(handValue([card(2), card(9)]) == 11)
        #expect(handValue([card(13), card(7), card(6)]) == 23)
        // 図: 10 + 6 + A は A を 1 にして 17。
        #expect(handValue([card(10), card(6), card(1)]) == 17)
    }

    @Test("ヒットの図の例: 8 + 6 = 14、5 を引いて 19")
    func hitFigureNumbers() {
        #expect(handValue([card(8), card(6)]) == 14)
        #expect(handValue([card(8), card(6), card(5)]) == 19)
    }

    @Test("勝ち点: 勝ち 1 点・最初の 2 枚の 21 は 2 点・引き分けと負けとバストは 0 点。勝負は 10 回")
    func points() {
        #expect(blackjackPoints(for: .win) == 1)
        #expect(blackjackPoints(for: .playerBlackjack) == 2)
        #expect(blackjackPoints(for: .push) == 0)
        #expect(blackjackPoints(for: .lose) == 0)
        #expect(blackjackPoints(for: .bust) == 0)
        #expect(BlackjackModel.roundsPerMatch == 10)
        #expect(blackjackSettlement(player: [card(9), card(8)], dealer: [card(10), card(6), card(1)]) == .push)
        #expect(blackjackSettlement(player: [card(1), card(13)], dealer: [card(10), card(7)]) == .playerBlackjack)
    }

    @Test("文言の数字（勝負の回数・ディーラーの止まる合計）が実装の値から作られる")
    func numbersComeFromRules() {
        let lines = BlackjackOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("\(BlackjackModel.roundsPerMatch) 回勝負して、勝ち点の合計で競います。"))
        #expect(lines.contains("合計が 17 未満の間は引き、17 以上で止まります。"))
        #expect(BlackjackOnboarding.dealerStandsAt == 17)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let formatted = [
            "%lld 回勝負して、勝ち点の合計で競います。",
            "合計が %1$lld 未満の間は引き、%1$lld 以上で止まります。",
        ]
        let filled = [
            tr("%lld 回勝負して、勝ち点の合計で競います。", BlackjackModel.roundsPerMatch),
            tr("合計が %1$lld 未満の間は引き、%1$lld 以上で止まります。", BlackjackOnboarding.dealerStandsAt),
        ]
        for key in formatted {
            #expect(tr.hasTranslation(key, language: .english), "「\(key)」に英語の訳が無い")
        }
        for text in BlackjackOnboarding.guide.texts where !filled.contains(text) {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
