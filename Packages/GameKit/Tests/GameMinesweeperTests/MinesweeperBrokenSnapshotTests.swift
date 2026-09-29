import Testing
import Foundation
import Core
@testable import GameMinesweeper
import CoreTestSupport

/// 寸法と cells が食い違う中断データは消して新規開始に倒す（#1384）。
@Suite("マインスイーパーの壊れた中断データ")
@MainActor
struct MinesweeperBrokenSnapshotTests {
    private func load(rows: Int, cols: Int, mines: Int, cellRows: Int, cellCols: Int)
        throws -> (MinesweeperModel, MemorySnapshotStore)
    {
        let cell = MinesweeperSnapshot.CellData(
            isRevealed: false, isFlagged: false, isMine: false, adjacentMines: 0, isContinuedMine: false)
        let store = MemorySnapshotStore()
        try store.save(
            MinesweeperSnapshot(
                rows: rows, cols: cols, totalMines: mines,
                cells: Array(repeating: Array(repeating: cell, count: cellCols), count: cellRows),
                flagCount: 0, revealedCount: 0, elapsedSeconds: 5),
            for: "minesweeper")
        return (MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService())), store)
    }

    @Test("行数と cells が食い違うなら新規開始に倒し、中断データを消す")
    func mismatchedRowsAreDiscarded() throws {
        let (m, store) = try load(rows: 9, cols: 9, mines: 10, cellRows: 2, cellCols: 9)
        #expect(m.cells.count == m.rows)
        #expect(m.elapsedSeconds == 0)
        #expect(store.load(MinesweeperSnapshot.self, for: "minesweeper") == nil)
    }

    @Test("寸法が 0 の盤・盤に収まらない地雷数も捨てる")
    func zeroSizeAndTooManyMines() throws {
        let (a, _) = try load(rows: 0, cols: 0, mines: 0, cellRows: 0, cellCols: 0)
        #expect(a.rows == 9)
        let (b, _) = try load(rows: 2, cols: 2, mines: 5, cellRows: 2, cellCols: 2)
        #expect(b.rows == 9)
    }

    @Test("寸法の合う中断データは復元する（対照）")
    func validSnapshotIsKept() throws {
        let (m, _) = try load(rows: 3, cols: 4, mines: 2, cellRows: 3, cellCols: 4)
        #expect(m.rows == 3 && m.cols == 4)
        #expect(m.elapsedSeconds == 5)
    }
}
