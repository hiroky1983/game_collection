import Testing
import CoreEngine
@testable import GameHearts

func c(_ suit: HeartsSuit, _ rank: Int) -> HeartsCard { HeartsCard(suit, rank) }
func p(_ player: Int, _ card: HeartsCard) -> HeartsPlay { HeartsPlay(player: player, card: card) }

@Suite("ハーツの札")
struct HeartsCardTests {
    @Test("52 枚・ID は 0〜51 で重複しない・点の合計は 26")
    func deck() {
        let deck = HeartsCard.makeDeck()
        #expect(deck.count == 52)
        #expect(Set(deck.map(\.id)) == Set(0..<52))
        #expect(HeartsRules.points(deck) == HeartsRules.pointsPerHand)
        #expect(c(.heart, 2).points == 1 && c(.heart, 14).points == 1)
        #expect(c(.spade, 12).points == 13)
        #expect(c(.spade, 13).points == 0 && c(.club, 12).points == 0 && c(.diamond, 12).points == 0)
    }

    @Test("描画の値は A が 1・ほかは数字のまま（トランプ共通基盤へ写す）")
    func figure() {
        #expect(c(.heart, 14).figure == .pip(suit: .heart, rank: 1))
        #expect(c(.spade, 12).figure == .pip(suit: .spade, rank: 12))
        #expect(c(.club, 2).figure == .pip(suit: .club, rank: 2))
        #expect(c(.diamond, 10).figure == .pip(suit: .diamond, rank: 10))
    }
}

@Suite("ハーツのルール")
struct HeartsRulesTests {
    @Test("1 巡目の先頭はクラブの 2 だけ")
    func firstLeadIsTwoOfClubs() {
        let hand = [c(.club, 2), c(.club, 9), c(.diamond, 5), c(.heart, 3)]
        #expect(HeartsRules.legalPlays(hand: hand, trick: [], heartsBroken: false, isFirstTrick: true) == [c(.club, 2)])
    }

    @Test("ハートが割れるまでハートを先頭に出せない（ハートしか無ければ出せる）")
    func heartsCannotBeLedUntilBroken() {
        let hand = [c(.club, 9), c(.spade, 12), c(.heart, 3), c(.heart, 10)]
        let closed = HeartsRules.legalPlays(hand: hand, trick: [], heartsBroken: false, isFirstTrick: false)
        #expect(closed == [c(.club, 9), c(.spade, 12)])
        let open = HeartsRules.legalPlays(hand: hand, trick: [], heartsBroken: true, isFirstTrick: false)
        #expect(open == hand)
        let onlyHearts = [c(.heart, 3), c(.heart, 10)]
        #expect(HeartsRules.legalPlays(hand: onlyHearts, trick: [], heartsBroken: false, isFirstTrick: false) == onlyHearts)
    }

    @Test("出だしのスートがあれば必ずそれを出す")
    func mustFollowSuit() {
        let hand = [c(.club, 9), c(.diamond, 4), c(.diamond, 13), c(.heart, 3)]
        let legal = HeartsRules.legalPlays(hand: hand, trick: [p(1, c(.diamond, 7))], heartsBroken: true, isFirstTrick: false)
        #expect(legal == [c(.diamond, 4), c(.diamond, 13)])
    }

    @Test("出だしのスートが無ければ何でも出せる。ただし 1 巡目は点の札を避ける（それしか無ければ出せる）")
    func voidRules() {
        let hand = [c(.diamond, 4), c(.spade, 12), c(.heart, 3)]
        let trick = [p(1, c(.club, 2))]
        #expect(HeartsRules.legalPlays(hand: hand, trick: trick, heartsBroken: false, isFirstTrick: false) == hand)
        #expect(HeartsRules.legalPlays(hand: hand, trick: trick, heartsBroken: false, isFirstTrick: true) == [c(.diamond, 4)])
        let onlyPoints = [c(.spade, 12), c(.heart, 3)]
        #expect(HeartsRules.legalPlays(hand: onlyPoints, trick: trick, heartsBroken: false, isFirstTrick: true) == onlyPoints)
    }

    @Test("出せる札は空でない（手札がある限り）")
    func neverEmpty() {
        var rng = SplitMix64(seed: 3)
        for _ in 0..<500 {
            let deck = HeartsCard.makeDeck().shuffled(using: &rng)
            let hand = Array(deck.prefix(Int.random(in: 1...13, using: &rng)))
            let trick = Bool.random(using: &rng) ? [] : [p(1, deck[20])]
            let legal = HeartsRules.legalPlays(hand: hand, trick: trick, heartsBroken: Bool.random(using: &rng),
                                               isFirstTrick: Bool.random(using: &rng))
            #expect(!legal.isEmpty)
            #expect(legal.allSatisfy(hand.contains))
        }
    }

    @Test("巡を取るのは出だしのスートで最大の札。ほかのスートの A は勝てない")
    func trickWinner() {
        let trick = [p(2, c(.diamond, 7)), p(3, c(.spade, 14)), p(0, c(.diamond, 12)), p(1, c(.diamond, 3))]
        #expect(HeartsRules.trickWinner(trick) == 0)
        #expect(HeartsRules.trickWinner([p(1, c(.heart, 2))]) == 1)
        #expect(HeartsRules.trickWinner([]) == nil)
    }

    @Test("渡す相手は左隣（次の番の人）・受け取るのは右隣から")
    func passDirection() {
        #expect((0..<4).map(HeartsRules.passTarget) == [1, 2, 3, 0])
        #expect((0..<4).map(HeartsRules.passSource) == [3, 0, 1, 2])
        for player in 0..<4 { #expect(HeartsRules.passSource(to: HeartsRules.passTarget(from: player)) == player) }
    }

    @Test("クラブの 2 を持つ人から始める")
    func startingPlayer() {
        let hands = [[c(.club, 3)], [c(.heart, 2)], [c(.club, 2)], [c(.spade, 2)]]
        #expect(HeartsRules.startingPlayer(hands: hands) == 2)
    }

    @Test("50 点に届いたら終わり・合計の少ない順・同点は同じ順位")
    func matchEnd() {
        #expect(!HeartsRules.isMatchOver(totals: [49, 0, 12, 30]))
        #expect(HeartsRules.isMatchOver(totals: [10, 50, 12, 30]))
        #expect(HeartsRules.ranking(totals: [21, 53, 26, 41]) == [0, 2, 3, 1])
        #expect(HeartsRules.ranking(totals: [30, 20, 20, 55]) == [1, 2, 0, 3])
        #expect(HeartsRules.place(of: 2, totals: [30, 20, 20, 55]) == 0)
        #expect(HeartsRules.place(of: 1, totals: [30, 20, 20, 55]) == 0)
        #expect(HeartsRules.place(of: 0, totals: [30, 20, 20, 55]) == 2)
        #expect(HeartsRules.place(of: 3, totals: [30, 20, 20, 55]) == 3)
    }
}
