import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameOthello

/// 中断から再開しても、直前の着手位置の印が残る（#1575）。
@Suite("オセロの着手位置の復元（#1575）")
@MainActor
struct OthelloLastMoveRestoreTests {
    private func services(_ store: MemorySnapshotStore) -> GameServices {
        GameServices(snapshots: store, ads: NoopAdService())
    }

    @Test("保存して開き直すと lastMove が一致する")
    func lastMoveSurvivesRestore() async throws {
        let store = MemorySnapshotStore()
        let model = OthelloModel(services: services(store), flipSettleDelay: .zero)
        model.newGame()
        model.tap(row: 2, col: 3)
        await model.performAIMoveIfNeeded()
        let last = try #require(model.lastMove, "前提: CPU が打った後は印がある")

        let restored = OthelloModel(services: services(store), flipSettleDelay: .zero)
        let restoredLast = try #require(restored.lastMove)
        #expect(restoredLast.row == last.row && restoredLast.col == last.col)
    }

    @Test("旧形式（lastRow/lastCol 無し）のデータは印なしで開く")
    func legacySnapshotHasNoMark() throws {
        let store = MemorySnapshotStore()
        let model = OthelloModel(services: services(store), flipSettleDelay: .zero)
        model.newGame()
        model.tap(row: 2, col: 3)
        var snap = try #require(store.load(OthelloSnapshot.self, for: "othello"))
        snap.lastRow = nil
        snap.lastCol = nil
        try store.save(snap, for: "othello")

        let restored = OthelloModel(services: services(store), flipSettleDelay: .zero)
        #expect(restored.lastMove == nil)
    }

    @Test("盤の範囲外の座標は捨てる")
    func outOfRangeIsDropped() throws {
        let store = MemorySnapshotStore()
        let model = OthelloModel(services: services(store), flipSettleDelay: .zero)
        model.newGame()
        model.tap(row: 2, col: 3)
        var snap = try #require(store.load(OthelloSnapshot.self, for: "othello"))
        snap.lastRow = 99
        snap.lastCol = -1
        try store.save(snap, for: "othello")

        let restored = OthelloModel(services: services(store), flipSettleDelay: .zero)
        #expect(restored.lastMove == nil)
    }
}
