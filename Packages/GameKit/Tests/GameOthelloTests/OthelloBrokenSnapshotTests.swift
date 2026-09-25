import Testing
import Foundation
import Core
import GameKitTestSupport
@testable import GameOthello
import CoreTestSupport

/// 盤の寸法が合わない中断データは消して新規開始に倒す（#1384）。
@Suite("オセロの壊れた中断データ")
@MainActor
struct OthelloBrokenSnapshotTests {
    private func snapshot(cellCount: Int) -> OthelloSnapshot {
        OthelloSnapshot(
            cells: Array(repeating: nil, count: cellCount), currentStone: OthelloStone.black.rawValue,
            humanSide: OthelloStone.black.rawValue, aiLevel: 1, startedAt: Date(), winner: nil,
            isDraw: false, mustPass: nil, turnID: nil, undoUsed: nil, undoCells: nil, undoCurrentStone: nil)
    }

    @Test("升数が足りない盤は初形で始め、中断データを消す")
    func shortBoardIsDiscarded() throws {
        let store = MemorySnapshotStore()
        try store.save(snapshot(cellCount: 3), for: "othello")
        let model = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.board == OthelloBoard())
        #expect(store.load(OthelloSnapshot.self, for: "othello") == nil)
    }

    @Test("正しい寸法の中断データは捨てない（対照）")
    func validBoardIsKept() throws {
        let store = MemorySnapshotStore()
        var cells = OthelloBoard().cells.map { $0?.rawValue }
        cells[0] = OthelloStone.black.rawValue
        var snap = snapshot(cellCount: 0)
        snap = OthelloSnapshot(
            cells: cells, currentStone: snap.currentStone, humanSide: snap.humanSide, aiLevel: 1,
            startedAt: Date(), winner: nil, isDraw: false, mustPass: nil, turnID: nil,
            undoUsed: nil, undoCells: nil, undoCurrentStone: nil)
        try store.save(snap, for: "othello")
        let model = OthelloModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.board.cells[0] == .black)
    }
}
