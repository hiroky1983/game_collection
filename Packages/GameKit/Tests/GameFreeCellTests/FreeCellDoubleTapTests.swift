import Testing
import Foundation
import Core
@testable import GameFreeCell
import CoreTestSupport

/// 組札へ送れる札のダブルタップ（#2598）。
@MainActor
@Suite("フリーセル 組札へのダブルタップ（#2598）")
struct FreeCellDoubleTapTests {
    private func makeModel(seed: UInt64, _ manual: ManualClock) -> FreeCellModel {
        let model = FreeCellModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), seed: seed)
        model.clockNow = manual.now
        return model
    }

    /// 配った直後に、場札の一番上がそのまま組札へ送れる（エース）列を持つ局。
    private func sendableModel(_ manual: ManualClock) -> (FreeCellModel, pile: Int)? {
        for seed in FreeCellDealer.verifiedSeeds {
            let model = makeModel(seed: seed, manual)
            if let pile = model.board.tableau.indices.first(where: { model.board.isLegal(.tableauToFoundation(pile: $0)) }) {
                return (model, pile)
            }
        }
        return nil
    }

    @Test("場札の送れる札をダブルタップすると、選択なしで組札へ送られる")
    func doubleTapSendsTableauCard() throws {
        let manual = ManualClock()
        let (model, pile) = try #require(sendableModel(manual))
        let card = try #require(model.board.tableau[pile].last)
        model.tapPile(pile, cardIndex: model.board.tableau[pile].count - 1)
        #expect(model.selection != nil)
        manual.advance(by: .milliseconds(100))
        model.tapPile(pile, cardIndex: model.board.tableau[pile].count - 1)
        #expect(model.selection == nil)
        #expect(model.board.foundations[card.suit.rawValue] == card.rank)
        #expect(model.moveCount == 1)
    }

    @Test("セルの送れる札をダブルタップすると組札へ送られる")
    func doubleTapSendsCellCard() throws {
        let manual = ManualClock()
        let (model, pile) = try #require(sendableModel(manual))
        let card = try #require(model.board.tableau[pile].last)
        // エースを空きセルへ退避してから、セルの札をダブルタップする。
        model.tapPile(pile)
        model.tapCell(0)
        #expect(model.board.cells[0] == card)
        manual.advance(by: .seconds(5))
        model.tapCell(0)
        manual.advance(by: .milliseconds(100))
        model.tapCell(0)
        #expect(model.selection == nil)
        #expect(model.board.cells[0] == nil)
        #expect(model.board.foundations[card.suit.rawValue] == card.rank)
        #expect(model.moveCount == 2)
    }

    @Test("間隔が空いたら、2 回目は今までどおり選択解除")
    func slowSecondTapDeselects() throws {
        let manual = ManualClock()
        let (model, pile) = try #require(sendableModel(manual))
        model.tapPile(pile)
        manual.advance(by: FreeCellModel.doubleTapInterval + .milliseconds(50))
        model.tapPile(pile)
        #expect(model.selection == nil)
        #expect(model.moveCount == 0)
    }

    @Test("送れない札のダブルタップは何も起きない（拒否も数えない）")
    func doubleTapOnUnsendableDoesNothing() throws {
        let manual = ManualClock()
        let model = makeModel(seed: FreeCellDealer.verifiedSeeds[0], manual)
        let pile = try #require(model.board.tableau.indices.first {
            !model.board.isLegal(.tableauToFoundation(pile: $0))
        })
        let rejected = model.rejectedTapCount
        model.tapPile(pile)
        manual.advance(by: .milliseconds(100))
        model.tapPile(pile)
        #expect(model.selection == nil)
        #expect(model.moveCount == 0)
        #expect(model.rejectedTapCount == rejected)
    }

    @Test("deselect のあとの素早いタップはダブルタップにならない（ドラッグの落とし先の合成タップ）")
    func tapAfterDeselectIsNotDoubleTap() throws {
        let manual = ManualClock()
        let (model, pile) = try #require(sendableModel(manual))
        model.tapPile(pile)
        model.deselect()
        manual.advance(by: .milliseconds(50))
        model.tapPile(pile)
        #expect(model.selection != nil)
        #expect(model.moveCount == 0)
    }
}
