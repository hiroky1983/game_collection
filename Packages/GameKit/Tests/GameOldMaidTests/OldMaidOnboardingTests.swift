import Testing
import Core
import CoreEngine
@testable import GameOldMaid

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("ババ抜き: はじめての遊び方")
struct OldMaidOnboardingTests {
    private func card(_ suit: OldMaidSuit, _ rank: Int) -> OldMaidCard {
        OldMaidCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
    }

    private func game(seed: UInt64) -> OldMaidGame {
        var generator = SplitMix64(seed: seed)
        var deck = OldMaidCard.makeDeck()
        deck.shuffle(using: &generator)
        return OldMaidGame(deck: deck, firstPlayer: Int(seed % 4), aiLevel: 1, tellSeed: seed)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(OldMaidOnboarding.guide.isWellFormed)
        #expect(OldMaidOnboarding.guide.gameID == OldMaidModel.gameID)
    }

    @Test("配られた手札から、同じ数字の 2 枚を捨てる。ジョーカーはペアにならない")
    func pairsAreDiscarded() {
        let hand = [card(.spades, 5), card(.diamonds, 9), card(.hearts, 5), OldMaidCard.joker]
        let result = OldMaidGame.removingPairs(from: hand)
        let pairIsFives = result.pairs.first?.allSatisfy { $0.rank == 5 } ?? false
        let jokerKept = result.kept.contains(OldMaidCard.joker)
        #expect(result.pairs.count == 1 && pairIsFives)
        #expect(jokerKept && result.kept.count == 2)
        for seed in UInt64(1)...30 {
            let g = game(seed: seed)
            let noPairs = g.hands.allSatisfy { hand in
                let ranks = hand.filter { !$0.isJoker }.map(\.rank)
                return Set(ranks).count == ranks.count
            }
            #expect(noPairs)
        }
    }

    @Test("自分の番では次の CPU の伏せ札を 1 枚引く。引いたジョーカーは手札の右端に入る")
    func drawAndJokerGoesRight() {
        var checked = false
        for seed in UInt64(1)...200 where !checked {
            var g = game(seed: seed)
            guard g.currentPlayer == OldMaidGame.humanIndex, let target = g.currentTarget,
                  g.hands[target].contains(where: \.isJoker) else { continue }
            #expect(target == g.nextActive(after: OldMaidGame.humanIndex))
            let drawn = g.draw(cardID: OldMaidCard.jokerID)
            #expect(drawn)
            let lastIsJoker = g.hands[OldMaidGame.humanIndex].last?.isJoker == true
            #expect(lastIsJoker)
            #expect(g.humanJokerWatched, "右端に入ったジョーカーは CPU に見られている")
            checked = true
        }
        #expect(checked)
    }

    @Test("手札がなくなった人から抜け、最後にジョーカーを持って残った人が負け")
    func loserHoldsJoker() {
        var g = game(seed: 7)
        var generator = SplitMix64(seed: 7)
        var steps = 0
        while !g.isOver, steps < 2_000 {
            if g.currentPlayer == OldMaidGame.humanIndex {
                let id = g.hands[g.currentTarget!].randomElement(using: &generator)!.id
                _ = g.draw(cardID: id)
            } else {
                _ = g.performCPUTurn(using: &generator)
            }
            steps += 1
        }
        #expect(g.isOver)
        let loser = g.loser ?? -1
        #expect(g.hands.indices.contains(loser))
        let holdsJoker = g.hands[max(loser, 0)].contains(where: \.isJoker)
        #expect(holdsJoker)
        #expect(g.activePlayers.count == 1)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in OldMaidOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
