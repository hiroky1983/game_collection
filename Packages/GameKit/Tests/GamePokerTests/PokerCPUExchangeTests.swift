import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GamePoker

/// CPU が替えた札の位置（#2594）。決着で表になったとき、引いた札に枠を付けるために Model が持つ。
@Suite("ポーカー: CPU が替えた札")
@MainActor
struct PokerCPUExchangeTests {

    /// スリーカードが 1〜3 番目。残りの 0・4 番目が替わる（役の判定は `cpuKeepIndices` が決める）。
    private let tripsInTheMiddle = [
        pc(30, 3, .clubs), pc(31, 9, .spades), pc(32, 9, .hearts), pc(33, 9, .diamonds), pc(34, 12, .clubs),
    ]

    @Test("替えた札の位置は、バッジの枚数と一致する")
    func exchangedIndicesMatchBadge() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: tripsInTheMiddle))
        model.showdown()
        #expect(model.cpuAction == "2枚交換")
        #expect(model.cpuExchangedIndices == [0, 4])
        #expect(model.cpuHand[1] == tripsInTheMiddle[1], "残した札はそのまま")
        #expect(model.cpuHand[0] != tripsInTheMiddle[0] && model.cpuHand[4] != tripsInTheMiddle[4])
    }

    @Test("交換なしのときは何も付かない")
    func noExchangeHasNoMarks() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.fullHouse))
        model.showdown()
        #expect(model.cpuAction == "カード交換なし")
        #expect(model.cpuExchangedIndices.isEmpty)
    }

    @Test("中断→再開後の決着でも位置が残る")
    func survivesResume() {
        let store = MemorySnapshotStore()
        let first = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: tripsInTheMiddle), store: store)
        first.showdown()
        #expect(first.phase == .result)
        let resumed = makePokerModel(store.load(PokerSnapshot.self, for: "poker")!, store: store)
        #expect(resumed.phase == .result)
        #expect(resumed.cpuExchangedIndices == [0, 4])
    }

    @Test("この項目を足す前の中断データは読めて、印は付かない")
    func legacySnapshotHasNoMarks() {
        let model = makePokerModel(pokerSnapshot(phase: .result, player: PokerHands.highCard, cpu: tripsInTheMiddle))
        #expect(model.phase == .result)
        #expect(model.cpuExchangedIndices.isEmpty)
    }

    @Test("次の回を配ると印は消える")
    func nextRoundClearsMarks() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: tripsInTheMiddle))
        model.showdown()
        model.nextRound()
        #expect(model.cpuExchangedIndices.isEmpty)
    }

    @Test("読み上げは引いた札にだけ「引いた札」を添える（日英）")
    func spokenLabel() {
        let card = pc(1, 7, .hearts)
        let plain = PokerAccessibility.cpuCardLabel(card: card, wasExchanged: false)
        let drawn = PokerAccessibility.cpuCardLabel(card: card, wasExchanged: true)
        #expect(plain == card.figure.spokenLabel)
        #expect(drawn == "\(plain)、引いた札")
        #expect(GamePoker.tr("%@、引いた札", "Seven of Hearts", language: .english) == "Seven of Hearts, drawn card")
    }
}
