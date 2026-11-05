import Testing
import Foundation
import Core
import MahjongTiles
@testable import GameMahjong
import CoreTestSupport

/// 和了の可否・役に直結する状態（嶺上・一発・同巡フリテン）が中断を挟んでも保たれることを固定する（#1948）。

@MainActor
private func junkHand() -> MahjongHand { MahjongNotation.hand("147m258p369s1234z") }

@MainActor
private func makeModel(store: SnapshotStore) -> MahjongModel {
    MahjongModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 2026)
}

/// 保存済みの中断データから作り直す（アプリの終了→「続きから」）。
@MainActor
private func relaunch(_ store: SnapshotStore) -> MahjongModel {
    MahjongModel(services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero)
}

@Suite("麻雀: 和了状態の中断復元（#1948）")
@MainActor
struct MahjongWinStateSnapshotTests {

    @Test("立直の一巡後に中断して再開しても、自分の次のツモに一発が付く")
    func ippatsuSurvivesRelaunch() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startGame()
        model.configureForTesting(
            hands: [MahjongNotation.hand("234m567m22p345p67s"), junkHand(), junkHand(), junkHand()],
            wall: MahjongNotation.tiles("999m") + MahjongNotation.tiles("8s"),
            dealer: 0,
            drawnTile: MahjongNotation.tile("1z")
        )
        model.declareRiichi()
        model.discard(MahjongNotation.tile("1z"))
        for _ in 0..<3 { model.stepCPUForTesting() }
        try #require(model.drawnTile == MahjongNotation.tile("8s"))
        model.persist()

        let restored = relaunch(store)
        #expect(restored.riichiTurn == model.riichiTurn)
        restored.declareTsumo()
        #expect(
            restored.handResult?.yaku.contains { $0.hasPrefix("一発") } == true,
            "実際の役: \(restored.handResult?.yaku ?? [])"
        )
    }

    @Test("嶺上牌を引いた直後に中断して再開しても、ツモ和了に嶺上開花が付く")
    func rinshanSurvivesRelaunch() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startGame()
        model.configureForTesting(
            hands: [MahjongNotation.hand("234p567p234s678s5m"), junkHand(), junkHand(), junkHand()],
            wall: MahjongNotation.tiles("9999m"),
            currentPlayer: 0,
            drawnTile: MahjongNotation.tile("5m")
        )
        model.isRinshanDraw = true
        model.persist()

        let restored = relaunch(store)
        #expect(restored.isRinshanDraw)
        restored.declareTsumo()
        let yaku = try #require(restored.handResult?.yaku)
        #expect(yaku.contains { $0.hasPrefix("嶺上") }, "実際の役: \(yaku)")
    }

    @Test("ロンを見逃した直後に中断して再開しても、同巡内はフリテンのまま")
    func temporaryFuritenSurvivesRelaunch() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startGame()
        model.temporaryFuriten[MahjongModel.humanIndex] = true
        model.persist()

        let restored = relaunch(store)
        #expect(restored.temporaryFuriten[MahjongModel.humanIndex])
        #expect(restored.isFuriten(MahjongModel.humanIndex))
        #expect(!restored.temporaryFuriten[1])
    }

    @Test("ロンを見逃した直後にポン選択が出た状態で中断して再開しても、同巡内はフリテンのまま（#2298）")
    func temporaryFuritenSurvivesRelaunchDuringCallOffer() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startGame()
        // 双碰 5m・8s 待ち … ではなく、8s 待ちの聴牌に 8s のポン材（88s）を持たせて、ロンとポンが両方できる形にする。
        model.configureForTesting(
            hands: [MahjongNotation.hand("234m567m88s345p67s"), junkHand(), junkHand(), junkHand()],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("8s")
        )
        model.discardForTesting(MahjongNotation.tile("8s"), by: 1)
        try #require(model.phase == .ronOffer)
        model.declineRon()
        try #require(model.phase == .callOffer, "見逃した直後はポン選択")

        let restored = relaunch(store)
        #expect(restored.temporaryFuriten[MahjongModel.humanIndex])
        #expect(restored.isFuriten(MahjongModel.humanIndex))
    }

    @Test("ロン見逃し直後のポン選択で中断して再開すると、次家の自摸から局が続く（#3040）")
    func resumesAfterDeclinedRonDuringCallOffer() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startGame()
        model.configureForTesting(
            hands: [MahjongNotation.hand("234m567m88s345p67s"), junkHand(), junkHand(), junkHand()],
            wall: MahjongNotation.tiles("1111m"),
            currentPlayer: 1,
            dealer: 1,
            drawnTile: MahjongNotation.tile("8s")
        )
        model.discardForTesting(MahjongNotation.tile("8s"), by: 1)
        try #require(model.phase == .ronOffer)
        model.declineRon()
        try #require(model.phase == .callOffer)

        let restored = relaunch(store)
        #expect(restored.phase == .playing)
        // 切ったのは家 1 なので、次は家 2 の自摸。誰かが打牌待ちになっている。
        #expect(restored.currentPlayer == 2)
        #expect(restored.drawnTile != nil)
        #expect(restored.awaitsDiscard(restored.currentPlayer))
        // CPU が打牌して、自分の番か鳴きの提示（人間の選択待ち）まで局が進む。
        var steps = 0
        while restored.phase == .playing, !restored.isPlayerTurn, steps < 6 {
            restored.stepCPUForTesting()
            steps += 1
        }
        #expect(
            restored.isPlayerTurn || restored.phase != .playing,
            "CPU が打牌して人の選択まで進む（実際: 手番 \(restored.currentPlayer)・phase \(restored.phase)）"
        )
    }

    @Test("3 項目の鍵が無い旧形式の中断データは、従来どおり（立直中は宣言巡 0・他は false）に戻る")
    func legacySnapshotFallsBack() throws {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startGame()
        model.riichi[1] = true
        model.persist()
        // 新しい 3 つの鍵だけを落として旧形式を作る。
        let raw = try #require(store.rawData(for: "mahjong4"))
        var json = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        for key in ["temporaryFuriten", "riichiTurn", "isRinshanDraw"] { json.removeValue(forKey: key) }
        store.inject(try JSONSerialization.data(withJSONObject: json), for: "mahjong4")

        let restored = relaunch(store)
        #expect(restored.temporaryFuriten == [false, false, false, false])
        #expect(restored.riichiTurn == [nil, 0, nil, nil])
        #expect(!restored.isRinshanDraw)
    }
}
