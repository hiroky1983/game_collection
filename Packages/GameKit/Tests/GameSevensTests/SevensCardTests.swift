import Testing
@testable import GameSevens

@Suite("七並べのカード")
struct SevensCardTests {

    @Test("山札はジョーカー無しの52枚で、ID・スート・ランクが重複しない")
    func deckHas52UniqueCards() {
        let deck = SevensCard.makeDeck()
        #expect(deck.count == 52)
        #expect(Set(deck.map(\.id)).count == 52)
        for suit in SevensSuit.allCases {
            let ranks = deck.filter { $0.suit == suit }.map(\.rank).sorted()
            #expect(ranks == Array(1...13), "\(suit) は 1〜13 がちょうど1枚ずつ")
        }
    }

    @Test("rankLabel は A・J・Q・K を文字で、それ以外は数字で返す")
    func rankLabelFormatsFaceCards() {
        #expect(SevensCard(id: 0, suit: .spades, rank: 1).rankLabel == "A")
        #expect(SevensCard(id: 0, suit: .spades, rank: 11).rankLabel == "J")
        #expect(SevensCard(id: 0, suit: .spades, rank: 12).rankLabel == "Q")
        #expect(SevensCard(id: 0, suit: .spades, rank: 13).rankLabel == "K")
        for rank in 2...10 {
            #expect(SevensCard(id: 0, suit: .spades, rank: rank).rankLabel == "\(rank)")
        }
    }
}
