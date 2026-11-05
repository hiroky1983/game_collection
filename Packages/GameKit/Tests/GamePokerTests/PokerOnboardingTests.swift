import Testing
import Core
import CoreMiniCard
@testable import GamePoker

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("ポーカー: はじめての遊び方")
struct PokerOnboardingTests {
    private func hand(_ cards: [(String, RuleMiniCard.Suit)]) -> [PokerCard] {
        cards.enumerated().map { i, c in
            let rank: Int
            switch c.0 {
            case "K": rank = 13
            case "Q": rank = 12
            case "J": rank = 11
            case "A": rank = 14
            default: rank = Int(c.0) ?? 2
            }
            let suit: PokerSuit
            switch c.1 {
            case .spade: suit = .spades
            case .heart: suit = .hearts
            case .club: suit = .clubs
            default: suit = .diamonds
            }
            return PokerCard(id: i, suit: suit, rank: rank)
        }
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(PokerOnboarding.guide.isWellFormed)
        #expect(PokerOnboarding.guide.gameID == "poker")
    }

    @Test("目的の図: あなたのフルハウスが CPU のワンペアに勝つ")
    func versusExample() {
        let you = hand(PokerOnboarding.exampleYou)
        let cpu = hand(PokerOnboarding.exampleCPU)
        #expect(HandEvaluator.evaluate(you).rank == .fullHouse)
        #expect(HandEvaluator.evaluate(cpu).rank == .onePair)
        #expect(HandEvaluator.compare(you, cpu) > 0)
    }

    @Test("役は 10 種類で、強いほど点が大きい。引き分け・負けは点が入らない")
    func rankAndPoints() {
        #expect(PokerScoreTable.table.count == 10)
        let points = PokerScoreTable.table.map(\.points)
        #expect(points == points.sorted(by: >))
        #expect(PokerScoreTable.points(for: .highCard) == 1)
        #expect(PokerHandRank.onePair < .twoPair && PokerHandRank.twoPair < .threeOfAKind && PokerHandRank.threeOfAKind < .fullHouse)
    }

    @Test("選んだ札だけが入れ替わる。交換しないなら手札はそのまま")
    func selectedCardsAreReplaced() {
        let model = PokerModel()
        model.startGame()
        let before = model.playerHand
        let picked = Array(before.prefix(2))
        for card in picked { model.toggleCardSelection(card) }
        #expect(model.selectedForExchange == Set(picked.map(\.id)))
        model.confirmExchange()
        #expect(model.playerHand[2...] == before[2...])
        #expect(model.playerHand[0] != before[0] && model.playerHand[1] != before[1])
        #expect(model.playerExchangedIndices == [0, 1])

        let stay = PokerModel()
        stay.startGame()
        let hold = stay.playerHand
        stay.confirmExchange()
        #expect(stay.playerHand == hold)
    }

    @Test("勝負は 10 回。勝った回にだけ自分の役の点が入る")
    func sessionLengthAndPoints() {
        #expect(PokerModel.roundsPerSession == 10)
        let lines = PokerOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("\(PokerModel.roundsPerSession) 回勝負して、合計点の多いほうが勝ちです。"))
        #expect(lines.contains("役は全部で \(PokerScoreTable.table.count) 種類あります。"))
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let formatted = [
            "役は全部で %lld 種類あります。",
            "%lld 回勝負して、合計点の多いほうが勝ちです。",
        ]
        let filled = [
            tr("役は全部で %lld 種類あります。", PokerScoreTable.table.count),
            tr("%lld 回勝負して、合計点の多いほうが勝ちです。", PokerModel.roundsPerSession),
        ]
        for key in formatted {
            #expect(tr.hasTranslation(key, language: .english), "「\(key)」に英語の訳が無い")
        }
        for text in PokerOnboarding.guide.texts where !filled.contains(text) {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
