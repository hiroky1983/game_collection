import Testing
import Foundation
import Core
@testable import GameGomoku
import CoreTestSupport

/// 盤の寸法・着手の座標が範囲外の中断データは消して新規開始に倒す（#1384）。
@Suite("五目並べの壊れた中断データ")
@MainActor
struct GomokuBrokenSnapshotTests {
    private func snapshot(cellCount: Int, history: [GomokuMoveRecord]?) -> GomokuSnapshot {
        GomokuSnapshot(
            cells: Array(repeating: nil, count: cellCount), currentStone: GomokuStone.black.rawValue,
            humanSide: GomokuStone.black.rawValue, aiLevel: 1, startedAt: Date(), moveHistory: history,
            undoUsed: nil, resigned: nil, winner: nil, forbiddenMoves: nil, hintsUsed: nil)
    }

    private func load(_ snap: GomokuSnapshot) throws -> (GomokuModel, MemorySnapshotStore) {
        let store = MemorySnapshotStore()
        try store.save(snap, for: "gomoku")
        return (GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService())), store)
    }

    @Test("着手の座標が盤の外なら落ちず、新規開始に倒す")
    func outOfRangeMoveIsDiscarded() throws {
        let bad = GomokuMoveRecord(row: 99, col: 0, stone: GomokuStone.black.rawValue)
        let (model, store) = try load(snapshot(cellCount: 0, history: [bad]))
        #expect(model.moveCount == 0)
        #expect(store.load(GomokuSnapshot.self, for: "gomoku") == nil)
    }

    @Test("旧形式で升数が合わない盤は捨てる")
    func wrongCellCountIsDiscarded() throws {
        let (model, store) = try load(snapshot(cellCount: 7, history: nil))
        #expect(model.moveCount == 0)
        #expect(store.load(GomokuSnapshot.self, for: "gomoku") == nil)
    }

    @Test("盤の内側の手順は復元する（対照）")
    func validHistoryIsKept() throws {
        let ok = GomokuMoveRecord(row: 7, col: 7, stone: GomokuStone.black.rawValue)
        let (model, _) = try load(snapshot(cellCount: 0, history: [ok]))
        #expect(model.moveCount == 1)
    }
}
