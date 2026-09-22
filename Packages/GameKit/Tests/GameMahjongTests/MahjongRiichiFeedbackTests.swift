import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong
import CoreTestSupport

/// 立直の合図（#714）。
///
/// 人間の立直成立は「成功」、CPU の立直は相手が脅威を作った合図で意味が逆になる。
/// 同じ `notify(.success)` を鳴らすと音と振動では区別できないため、出し分けをここで固定する。

/// 5s / 8s 待ちの聴牌。東（1z）を切れば聴牌のまま立直できる。
@MainActor
private func tenpaiHand() -> MahjongHand { MahjongNotation.hand("234m567m22p345p67s") }

/// 聴牌から遠く、東を切られてもロン・ポンできない手。
@MainActor
private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

/// `riichiPlayer` だけが聴牌して東をツモっている局面。
@MainActor
private func makeModel(_ spy: SpyFeedbackService, riichiPlayer: Int) -> MahjongModel {
    let model = MahjongModel(
        services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy),
        cpuDelay: .zero,
        seed: 2026
    )
    model.startGame()
    var hands = Array(repeating: junkHand(), count: MahjongModel.playerCount)
    hands[riichiPlayer] = tenpaiHand()
    model.configureForTesting(
        hands: hands,
        wall: MahjongNotation.tiles("111122223333m"),
        currentPlayer: riichiPlayer,
        dealer: riichiPlayer,
        drawnTile: MahjongNotation.tile("1z")
    )
    spy.reset()
    return model
}

@Suite("立直の合図")
@MainActor
struct MahjongRiichiFeedbackTests {

    @Test("CPU の立直では「成功」を鳴らさず、硬い触覚を 1 回だけ鳴らす")
    func cpuRiichiDoesNotSoundSuccess() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy, riichiPlayer: 1)

        model.stepCPUForTesting()

        #expect(model.riichi[1], "前提: CPU が立直している")
        #expect(!spy.notices.contains(.success), "自分が和了ったときと同じ合図になる")
        #expect(spy.impacts.filter { $0 == .rigid }.count == 1, "相手の立直にも合図は要る")
    }

    @Test("人間の立直成立では従来どおり「成功」を 1 回鳴らす")
    func humanRiichiSoundsSuccess() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy, riichiPlayer: MahjongModel.humanIndex)

        model.declareRiichi()
        model.discard(MahjongNotation.tile("1z"))

        #expect(model.riichi[MahjongModel.humanIndex], "前提: 立直が成立している")
        #expect(spy.notices == [.success])
        #expect(spy.impacts == [.rigid, .light], "宣言の硬い触覚と打牌の軽い触覚は変えない")
    }

    @Test("立直の宣言を取り消すと軽い触覚を 1 回鳴らす")
    func cancelRiichiDeclarationSoundsOnce() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy, riichiPlayer: MahjongModel.humanIndex)
        model.declareRiichi()
        spy.reset()

        model.cancelRiichiDeclaration()

        #expect(!model.isDeclaringRiichi)
        #expect(spy.impacts == [.light])
        #expect(spy.notices.isEmpty)
    }

    @Test("宣言していないときの取り消しは何も鳴らさない")
    func cancelWithoutDeclarationIsSilent() {
        let spy = SpyFeedbackService()
        let model = makeModel(spy, riichiPlayer: MahjongModel.humanIndex)

        model.cancelRiichiDeclaration()

        #expect(spy.impacts.isEmpty)
        #expect(spy.notices.isEmpty)
    }
}
