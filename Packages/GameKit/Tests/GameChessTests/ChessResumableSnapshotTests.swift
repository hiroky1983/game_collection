import Testing
import Core
import CoreTestSupport
@testable import GameChess

/// 一手も指していない局は「続きから」に出さない（#1599。#1572 の取りこぼし）。
@Suite("チェスの「続きから」判定（#1599）")
@MainActor
struct ChessResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手指すと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = ChessModule()
        let model = ChessGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        let move = ChessMove.fromUCI("e2e4")!
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        #expect(module.hasResumableSnapshot(in: store), "一手指した局（対照）")
    }

    @Test("人間が黒のとき、CPU の初手だけでは続きではなく手つかず。自分が指すと続きになる（#2508）")
    func blackAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = ChessModule()
        let model = ChessGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .black)
        await model.performAIMoveIfNeeded()
        #expect(!model.moves.isEmpty, "CPU が初手を指した（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        let reply = model.legalMovesCache.first!
        model.tapSquare(reply.from)
        model.tapSquare(reply.to)
        #expect(module.hasResumableSnapshot(in: store), "自分が指した局（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }
}
