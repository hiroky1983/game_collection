import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GamePoker

/// 自分が替えた札の位置（#2704）。「もう 1 回交換するか勝負するか」の場面と決着後に、引いた札へ枠を付けるために Model が持つ。
@Suite("ポーカー: 自分が替えた札")
@MainActor
struct PokerPlayerExchangeTests {

    private func exchangeModel(store: MemorySnapshotStore = MemorySnapshotStore()) -> PokerModel {
        makePokerModel(
            pokerSnapshot(phase: .exchange, player: PokerHands.highCard, cpu: PokerHands.fullHouse),
            store: store)
    }

    @Test("交換した札の位置を覚える")
    func remembersExchangedPositions() {
        let model = exchangeModel()
        let hand = model.playerHand
        model.toggleCardSelection(hand[1])
        model.toggleCardSelection(hand[3])
        model.confirmExchange()
        #expect(model.playerExchangedIndices == [1, 3])
        #expect(model.playerHand[0] == hand[0] && model.playerHand[2] == hand[2], "残した札はそのまま")
    }

    @Test("交換しなければ印は付かない")
    func noExchangeHasNoMarks() {
        let model = exchangeModel()
        model.confirmExchange()
        #expect(model.playerExchangedIndices.isEmpty)
    }

    @Test("もう 1 回交換したときは両方の回の分が残る")
    func extraExchangeAccumulates() async {
        let model = exchangeModel()
        model.toggleCardSelection(model.playerHand[0])
        model.confirmExchange()
        #expect(model.phase == .drawn)
        _ = await model.extraExchangeAfterAd()
        #expect(model.phase == .exchange)
        model.toggleCardSelection(model.playerHand[4])
        model.confirmExchange()
        #expect(model.playerExchangedIndices == [0, 4])
    }

    @Test("決着の後も、中断→再開しても位置が残る")
    func survivesShowdownAndResume() {
        let store = MemorySnapshotStore()
        let model = exchangeModel(store: store)
        model.toggleCardSelection(model.playerHand[2])
        model.confirmExchange()
        let resumed = makePokerModel(store.load(PokerSnapshot.self, for: "poker")!, store: store)
        #expect(resumed.phase == .drawn)
        #expect(resumed.playerExchangedIndices == [2])
        resumed.showdown()
        #expect(resumed.playerExchangedIndices == [2])
    }

    @Test("この項目を足す前の中断データは読めて、印は付かない")
    func legacySnapshotHasNoMarks() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.fullHouse))
        #expect(model.phase == .drawn)
        #expect(model.playerExchangedIndices.isEmpty)
    }

    @Test("次の回を配ると印は消える")
    func nextRoundClearsMarks() {
        let model = exchangeModel()
        model.toggleCardSelection(model.playerHand[0])
        model.confirmExchange()
        model.showdown()
        model.nextRound()
        #expect(model.playerExchangedIndices.isEmpty)
    }

    @Test("読み上げは、選べない場面では引いた札に「引いた札」を添える")
    func spokenLabel() {
        let card = pc(1, 7, .hearts)
        let name = card.figure.spokenLabel
        #expect(PokerAccessibility.handCardLabel(card: card, isSelected: false, phase: .drawn, wasExchanged: true) == "\(name)、引いた札")
        #expect(PokerAccessibility.handCardLabel(card: card, isSelected: false, phase: .result, wasExchanged: false) == name)
        #expect(PokerAccessibility.handCardLabel(card: card, isSelected: true, phase: .exchange, wasExchanged: true) == "\(name)、捨てる札に選択中")
    }
}
