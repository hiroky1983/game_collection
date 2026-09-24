import Testing
@testable import GameSpeed

private func card(_ suit: SpeedSuit, _ rank: Int) -> SpeedCard {
    SpeedCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

@Suite("スピードのルール")
struct SpeedRulesTests {
    @Test("1 つ違いの数字だけがつながり、A と K もつながる")
    func adjacency() {
        #expect(SpeedRules.isAdjacent(6, 7))
        #expect(SpeedRules.isAdjacent(7, 6))
        #expect(SpeedRules.isAdjacent(1, 13), "A と K")
        #expect(SpeedRules.isAdjacent(13, 1))
        #expect(!SpeedRules.isAdjacent(7, 7), "同じ数字は重ねられない")
        #expect(!SpeedRules.isAdjacent(5, 7))
        #expect(!SpeedRules.isAdjacent(1, 12))
        // 1〜13 のどの数字も、つながる相手はちょうど 2 つ。
        for rank in 1...13 {
            let partners = (1...13).filter { SpeedRules.isAdjacent(rank, $0) }
            #expect(partners.count == 2, "\(rank) の相手が \(partners)")
        }
    }

    @Test("マークは関係なく、台札が空なら重ねられない")
    func canPlay() {
        #expect(SpeedRules.canPlay(card(.hearts, 6), onto: card(.spades, 7)))
        #expect(SpeedRules.canPlay(card(.hearts, 6), onto: card(.hearts, 5)))
        #expect(!SpeedRules.canPlay(card(.hearts, 6), onto: card(.hearts, 6)))
        #expect(!SpeedRules.canPlay(card(.hearts, 6), onto: nil))
    }

    @Test("出せる組は手札の順 → 台札の順で列挙される")
    func placements() {
        let hand = [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 8)]
        let tops: [SpeedCard?] = [card(.spades, 6), card(.clubs, 9)]
        let result = SpeedRules.placements(hand: hand, tops: tops)
        #expect(result == [
            SpeedPlacement(cardID: card(.hearts, 5).id, pile: 0),
            SpeedPlacement(cardID: card(.hearts, 8).id, pile: 1),
        ])
        #expect(SpeedRules.hasPlayable(hand: hand, tops: tops))
        #expect(!SpeedRules.hasPlayable(hand: [card(.hearts, 2)], tops: tops))
        #expect(!SpeedRules.hasPlayable(hand: hand, tops: [nil, nil]))
    }

    @Test("52 枚は赤 26 枚と黒 26 枚に分かれ、id が重ならない")
    func deck() {
        let deck = SpeedCard.makeDeck()
        #expect(deck.count == 52)
        #expect(Set(deck.map(\.id)).count == 52)
        #expect(SpeedCard.redHalf().count == 26)
        #expect(SpeedCard.blackHalf().count == 26)
        #expect(SpeedCard.redHalf().allSatisfy { $0.suit.isRed })
        #expect(SpeedCard.blackHalf().allSatisfy { !$0.suit.isRed })
        for suit in SpeedSuit.allCases {
            #expect(deck.filter { $0.suit == suit }.map(\.rank).sorted() == Array(1...13))
        }
    }

    @Test("CPU は出せる組が無ければ nil、あれば出したあとに自分が続けやすく相手が出しにくい組を選ぶ")
    func cpuChoice() {
        // 出せない。
        #expect(SpeedRules.cpuChoice(hand: [card(.spades, 2)], tops: [card(.hearts, 7), card(.hearts, 9)], opponentHand: []) == nil)

        // ♠6 は左（♥7）に、♠10 は右（♥9）に出せる。相手（♥8）は左にも右にも出せる。
        // ♠6 を左に置くと相手は右（9）にだけ出せ、自分は ♠5 が続く（+1）。
        // ♠10 を右に置くと相手は左（7）にだけ出せ、自分は続かない（0）。→ ♠6 を左。
        let hand = [card(.spades, 10), card(.spades, 6), card(.spades, 5), card(.clubs, 2)]
        let choice = SpeedRules.cpuChoice(
            hand: hand, tops: [card(.hearts, 7), card(.hearts, 9)], opponentHand: [card(.hearts, 8)]
        )
        #expect(choice == SpeedPlacement(cardID: card(.spades, 6).id, pile: 0))

        // 同点なら手札の順で先のもの（♠10 が先）。
        let tie = SpeedRules.cpuChoice(
            hand: [card(.spades, 10), card(.spades, 6)], tops: [card(.hearts, 7), card(.hearts, 9)], opponentHand: []
        )
        #expect(tie == SpeedPlacement(cardID: card(.spades, 10).id, pile: 1))
    }

    @Test("CPU は相手の出したい台札を塞ぐ組を高く見る")
    func cpuBlocks() {
        // ♠4 は左（♥3）にも右（♥5）にも出せる。相手は ♥6 を持ち、右（5）にだけ出せる。
        // 右に置けば相手は出せなくなる（−0）。左に置くと相手は右に出せる（−1）。→ 右。
        let choice = SpeedRules.cpuChoice(
            hand: [card(.spades, 4)], tops: [card(.hearts, 3), card(.hearts, 5)], opponentHand: [card(.hearts, 6)]
        )
        #expect(choice == SpeedPlacement(cardID: card(.spades, 4).id, pile: 1))
    }
}
