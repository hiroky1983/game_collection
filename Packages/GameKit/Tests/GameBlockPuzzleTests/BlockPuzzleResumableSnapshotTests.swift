import Testing
import Core
import CoreTestSupport
@testable import GameBlockPuzzle

/// 一つも置いていない盤は「続きから」に出さない（#1912）。
@Suite("ブロックならべの「続きから」判定（#1912）")
@MainActor
struct BlockPuzzleResumableSnapshotTests {
    @Test("配っただけでは続きではなく、1 つ置くと続きになる")
    func untouchedBoardIsNotResumable() throws {
        let store = MemorySnapshotStore()
        let module = BlockPuzzleModule()
        let model = BlockPuzzleModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(store.exists(for: module.id), "配った直後に保存はされる（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")

        var placed = false
        search: for index in model.hand.indices where model.hand[index] != nil {
            for row in 0..<BlockPuzzleBoard.size {
                for col in 0..<BlockPuzzleBoard.size where model.place(pieceIndex: index, row: row, col: col) {
                    placed = true
                    break search
                }
            }
        }
        try #require(placed)
        #expect(module.hasResumableSnapshot(in: store), "置いた盤（対照）")
    }
}
