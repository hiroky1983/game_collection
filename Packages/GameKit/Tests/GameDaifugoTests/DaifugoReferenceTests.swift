import Testing
@testable import GameDaifugo

/// 早見表（#2788）の中身が、判定に使っている値と一致すること。
@Suite("大富豪: 早見表")
struct DaifugoReferenceTests {
    private func card(_ rank: Int) -> DaifugoCard {
        DaifugoCard(id: rank, suit: rank == DaifugoRules.jokerRank ? nil : .spades, rank: rank)
    }

    @Test("ふだんの強さは 3 → K → A → 2 → ジョーカー")
    func normalOrder() {
        let labels = DaifugoReference.strengthOrder(isRevolution: false).map(DaifugoReference.rankLabel)
        #expect(labels == ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2", "JK"])
    }

    @Test("革命中は 3 が最強・2 が最弱に逆転し、ジョーカーだけ最強のまま")
    func revolutionOrder() {
        let labels = DaifugoReference.strengthOrder(isRevolution: true).map(DaifugoReference.rankLabel)
        #expect(labels == ["2", "A", "K", "Q", "J", "10", "9", "8", "7", "6", "5", "4", "3", "JK"])
    }

    @Test("表の並びのとおり、隣り合う札は実際の出せる・出せないの判定でも上の札だけが勝つ")
    func orderMatchesIsValidPlay() {
        for isRevolution in [false, true] {
            let order = DaifugoReference.strengthOrder(isRevolution: isRevolution)
            for (weak, strong) in zip(order, order.dropFirst()) {
                #expect(DaifugoRules.isValidPlay([card(strong)], field: [card(weak)], isRevolution: isRevolution))
                #expect(!DaifugoRules.isValidPlay([card(weak)], field: [card(strong)], isRevolution: isRevolution))
            }
        }
    }

    @Test("革命の枚数・8切り・反則上がりの表の文言は、判定の値（4 枚・8・2/8/ジョーカー）に対応する")
    func specialRuleValues() {
        #expect(DaifugoRules.revolutionCount == 4)
        let four = (0..<4).map { DaifugoCard(id: $0, suit: DaifugoSuit.allCases[$0], rank: 5) }
        #expect(DaifugoRules.triggersRevolution(four))
        #expect(!DaifugoRules.triggersRevolution(Array(four.prefix(3))))
        #expect(DaifugoRules.clearsField([card(8)]))
        #expect(DaifugoRules.isFoulFinish([card(2)]))
        #expect(DaifugoRules.isFoulFinish([card(8)]))
        #expect(DaifugoRules.isFoulFinish([card(DaifugoRules.jokerRank)]))
        #expect(!DaifugoRules.isFoulFinish([card(9)]))
    }

    @Test("しばりの段は、しばりを選んだ局にだけ出る")
    func bindSectionFollowsRuleSet() {
        #expect(!DaifugoReference.showsBind(.standard))
        #expect(DaifugoReference.showsBind(DaifugoRuleSet(isBindEnabled: true)))
    }
}
