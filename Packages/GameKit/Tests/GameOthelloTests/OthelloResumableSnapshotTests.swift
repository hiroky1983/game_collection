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
}
