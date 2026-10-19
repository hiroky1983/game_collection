import Testing
import Core
import CoreTestSupport
@testable import GameShogi

/// 一手も指していない局は「続きから」に出さない（#1599。#1572 の取りこぼし）。
@Suite("将棋の「続きから」判定（#1599）")
@MainActor
struct ShogiResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手指すと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(module.hasResumableSnapshot(in: store), "一手指した局（対照）")
    }

    @Test("人間が後手のとき、CPU の初手だけでは続きではなく手つかず。自分が指すと続きになる（#2508）")
    func goteAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        #expect(!model.moves.isEmpty, "CPU が初手を指した（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        model.apply(model.legalMovesCache.first!)
        #expect(module.hasResumableSnapshot(in: store), "自分が指した局（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("駒落ちで CPU が上手（先に指す）のとき、CPU の初手だけでは続きではない（#2508）")
    func handicapCPUUpperOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = ShogiModule()
        let model = ShogiGameModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(handicap: .rook, dropper: .cpu)
        await model.performAIMoveIfNeeded()
        #expect(!model.moves.isEmpty, "CPU が初手を指した（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store))
    }
}
