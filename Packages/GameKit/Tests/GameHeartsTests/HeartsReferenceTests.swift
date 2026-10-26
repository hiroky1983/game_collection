import Testing
@testable import GameHearts

/// 早見表（#2788）の中身が、判定に使っている値と一致すること。
@Suite("ハーツ: 早見表")
struct HeartsReferenceTests {
    @Test("強さの順は A → 2 で、隣り合う札は実際の判定でも上の札が勝つ")
    func strengthOrderMatchesTrickWinner() {
        let order = HeartsReference.strengthOrder
        #expect(order == Array((2...14).reversed()))
        for (strong, weak) in zip(order, order.dropFirst()) {
            // 先に弱い札が出て、あとから強い札が出た巡は、強い札を出した席（1）が取る。
            let trick = [HeartsPlay(player: 0, card: HeartsCard(.diamond, weak)),
                         HeartsPlay(player: 1, card: HeartsCard(.diamond, strong))]
            #expect(HeartsRules.trickWinner(trick) == 1, "\(strong) は \(weak) に勝つはず")
            let reversed = [HeartsPlay(player: 0, card: HeartsCard(.diamond, strong)),
                            HeartsPlay(player: 1, card: HeartsCard(.diamond, weak))]
            #expect(HeartsRules.trickWinner(reversed) == 0)
        }
    }

    @Test("別のマークは A でも勝てない")
    func offSuitNeverWins() {
        let trick = [HeartsPlay(player: 0, card: HeartsCard(.diamond, 2)),
                     HeartsPlay(player: 1, card: HeartsCard(.spade, 14))]
        #expect(HeartsRules.trickWinner(trick) == 0)
    }

    @Test("点の一覧はカードの点そのもので、山札全体で 1 手の合計点になる")
    func pointEntriesMatchCardPoints() {
        let entries = HeartsReference.pointEntries
        #expect(entries.map(\.points) == [1, 13, 0])
        for entry in entries {
            #expect(HeartsCard(entry.suit, entry.rank).points == entry.points)
        }
        #expect(HeartsRules.points(HeartsCard.makeDeck()) == HeartsRules.pointsPerHand)
        #expect(HeartsRules.pointsPerHand == 13 + 13)
    }

    @Test("数字の表記")
    func rankLabels() {
        #expect(HeartsReference.strengthOrder.map(HeartsReference.rankLabel)
                == ["A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3", "2"])
    }
}
