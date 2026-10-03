import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGomoku

/// 一手も打っていない盤は「続きから」に出さない（#1572）。
@Suite("五目並べの「続きから」判定（#1572）")
@MainActor
struct GomokuResumableSnapshotTests {
    @Test("新規対局の直後は続きではなく、一手打つと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = GomokuModule()
        let model = GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame()
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tap(row: 7, col: 7)
        #expect(module.hasResumableSnapshot(in: store), "一手打った盤（対照）")
    }

    @Test("手順を持たない旧形式は盤上の石で判定する")
    func legacySnapshotWithoutHistory() throws {
        let store = MemorySnapshotStore()
        var cells = [Int?](repeating: nil, count: gomokuBoardSize * gomokuBoardSize)
        func snapshot(_ cells: [Int?]) -> GomokuSnapshot {
            GomokuSnapshot(
                cells: cells, currentStone: GomokuStone.black.rawValue, humanSide: GomokuStone.black.rawValue,
                aiLevel: 1, startedAt: Date(), moveHistory: nil, undoUsed: nil, resigned: nil, winner: nil,
                forbiddenMoves: nil, hintsUsed: nil)
        }
        try store.save(snapshot(cells), for: "gomoku")
        #expect(!GomokuModule().hasResumableSnapshot(in: store))
        cells[0] = GomokuStone.black.rawValue
        try store.save(snapshot(cells), for: "gomoku")
        #expect(GomokuModule().hasResumableSnapshot(in: store))
    }
}
