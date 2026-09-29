import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong
import CoreTestSupport

/// 対局中の操作行（立直・カン・ツモ）は、出来るときだけ出す（会長 QA 指摘）。
@Suite("対局中の操作ボタンの出し分け")
@MainActor
struct MahjongTurnActionsTests {

    private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

    private func model(
        hand: String, drawn: String?, currentPlayer: Int = MahjongModel.humanIndex
    ) -> MahjongModel {
        let model = MahjongModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
            cpuDelay: .zero,
            seed: 2026
        )
        model.startGame()
        model.configureForTesting(
            hands: [MahjongNotation.hand(hand), junkHand(), junkHand(), junkHand()],
            wall: MahjongNotation.tiles("111122223333m"),
            currentPlayer: currentPlayer,
            dealer: 1,
            drawnTile: drawn.map(MahjongNotation.tile)
        )
        return model
    }

    @Test("聴牌から遠い手では何も出さない")
    func nothingWhenNoActionAvailable() {
        let actions = MahjongTurnActions(model: model(hand: "147m258p369s1234z", drawn: "5z"))
        #expect(actions.isEmpty)
    }

    @Test("他家の手番では何も出さない")
    func nothingOnCPUTurn() {
        let actions = MahjongTurnActions(
            model: model(hand: "234m567m22p345p67s", drawn: nil, currentPlayer: 1)
        )
        #expect(actions.isEmpty)
    }

    @Test("聴牌していれば立直だけ出し、ツモは出さない")
    func riichiOnlyWhenTenpai() {
        let actions = MahjongTurnActions(model: model(hand: "234m567m22p345p67s", drawn: "1z"))
        #expect(actions.showsRiichi)
        #expect(actions.showsTsumo == false)
        #expect(actions.showsCancelRiichi == false)
    }

    @Test("和了牌を引いたらツモを出す")
    func tsumoWhenWinning() {
        let actions = MahjongTurnActions(model: model(hand: "234m567m22p345p67s", drawn: "8s"))
        #expect(actions.showsTsumo)
    }

    @Test("立直の宣言牌を選んでいる間は立直の代わりに「やめる」を出す")
    func cancelWhileDeclaringRiichi() {
        let m = model(hand: "234m567m22p345p67s", drawn: "1z")
        m.declareRiichi()
        let actions = MahjongTurnActions(model: m)
        #expect(actions.showsCancelRiichi)
        #expect(actions.showsRiichi == false)
    }

    @Test("カンは出来るときだけ出す")
    func kanOnlyWhenAvailable() {
        let m = model(hand: "1111m567m22p345p6s", drawn: "7z")
        #expect(MahjongTurnActions(model: m).showsKan == m.canDeclareKan)
        #expect(m.canDeclareKan)
    }
}
