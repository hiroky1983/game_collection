import Testing
import Foundation
import Core
@testable import GameSolitaire
import CoreTestSupport

/// 組札へ送れる札のダブルタップ（#2598）。
@MainActor
@Suite("Solitaire 組札へのダブルタップ（#2598）")
struct SolitaireDoubleTapTests {
    private func makeModel(seed: UInt64, _ manual: ManualClock) -> SolitaireModel {
        let model = SolitaireModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), seed: seed)
        model.clockNow = manual.now
        return model
    }

    /// 配った直後に、場札の一番上がそのまま組札へ送れる（エース）列を持つ局。
    private func sendableTableau(_ manual: ManualClock) throws -> (SolitaireModel, pile: Int) {
        for seed in UInt64(1)...300 {
            let model = makeModel(seed: seed, manual)
            if let pile = model.board.tableau.indices.first(where: { model.board.isLegal(.tableauToFoundation(pile: $0)) }) {
                return (model, pile)
            }
        }
        throw TestFailure("送れる場札のある配札が見つからない")
    }

    private struct TestFailure: Error { let message: String; init(_ m: String) { message = m } }

    @Test("場札の送れる札をダブルタップすると、選択なしで組札へ送られる")
    func doubleTapSendsTableauCard() throws {
        let manual = ManualClock()
        let (model, pile) = try sendableTableau(manual)
        let card = try #require(model.board.tableau[pile].faceUp.last)
        model.tapPile(pile, cardIndex: model.board.tableau[pile].faceUp.count - 1)
        #expect(model.selection != nil)
        manual.advance(by: .milliseconds(100))
        model.tapPile(pile, cardIndex: model.board.tableau[pile].faceUp.count - 1)
        #expect(model.selection == nil)
        #expect(model.board.foundations[card.suit?.rawValue ?? -1] == card.rank)
        #expect(model.moveCount == 1)
    }

    @Test("間隔が空いたら、2 回目は今までどおり選択解除")
    func slowSecondTapDeselects() throws {
        let manual = ManualClock()
        let (model, pile) = try sendableTableau(manual)
        model.tapPile(pile)
        manual.advance(by: SolitaireModel.doubleTapInterval + .milliseconds(50))
        model.tapPile(pile)
        #expect(model.selection == nil)
        #expect(model.moveCount == 0)
    }

    @Test("送れない札のダブルタップは何も起きない（拒否も数えない）")
    func doubleTapOnUnsendableDoesNothing() throws {
        let manual = ManualClock()
        let model = makeModel(seed: 1, manual)
        let pile = try #require(model.board.tableau.indices.first {
            !model.board.isLegal(.tableauToFoundation(pile: $0)) && !model.board.tableau[$0].faceUp.isEmpty
        })
        let rejected = model.rejectedTapCount
        model.tapPile(pile)
        manual.advance(by: .milliseconds(100))
        model.tapPile(pile)
        #expect(model.selection == nil)
        #expect(model.moveCount == 0)
        #expect(model.rejectedTapCount == rejected)
    }

    @Test("捨て札の送れる札をダブルタップすると組札へ送られる")
    func doubleTapSendsWasteCard() throws {
        let manual = ManualClock()
        for seed in UInt64(1)...300 {
            let model = makeModel(seed: seed, manual)
            var draws = 0
            while !model.board.isLegal(.wasteToFoundation), draws < 30, model.board.isLegal(.draw) {
                model.tapStock()
                draws += 1
            }
            guard model.board.isLegal(.wasteToFoundation) else { continue }
            let card = try #require(model.board.waste.last)
            let before = model.moveCount
            model.tapWaste()
            manual.advance(by: .milliseconds(100))
            model.tapWaste()
            #expect(model.selection == nil)
            #expect(model.board.foundations[card.suit?.rawValue ?? -1] == card.rank)
            #expect(model.moveCount == before + 1)
            return
        }
        Issue.record("送れる捨て札のある配札が見つからない")
    }

    @Test("deselect のあとの素早いタップはダブルタップにならない（ドラッグの落とし先の合成タップ）")
    func tapAfterDeselectIsNotDoubleTap() throws {
        let manual = ManualClock()
        let (model, pile) = try sendableTableau(manual)
        model.tapPile(pile)
        model.deselect()
        manual.advance(by: .milliseconds(50))
        model.tapPile(pile)
        #expect(model.selection != nil)
        #expect(model.moveCount == 0)
    }
}
