import Testing
import Core
import CoreTestSupport
@testable import GameOthello

/// 一手も打っていない盤は「続きから」に出さない（#1572）。
@Suite("オセロの「続きから」判定（#1572）")
@MainActor
struct OthelloResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手打つと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = OthelloModule()
        let model = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tap(row: 2, col: 3)
        #expect(module.hasResumableSnapshot(in: store), "一手打った盤（対照）")
    }

    @Test("人間が白のとき、CPU の初手だけでは続きではなく手つかず。自分が打つと続きになる（#2508）")
    func whiteAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let module = OthelloModule()
        let model = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        #expect(!model.isAITurn, "CPU が初手を打った（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store), "CPU の初手だけは手つかず")
        if let point = model.board.validMoves(for: .white).first { model.tap(row: point.0, col: point.1) }
        #expect(module.hasResumableSnapshot(in: store), "自分が打った盤（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }
}
