import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameGomoku

/// 手順（`moveHistory`）を持たない旧形式の中断データを再開して保存し直しても、復元前の石が消えない（#2200）。
@MainActor
@Suite("五目並べ 旧形式の中断データの再保存（#2200）")
struct GomokuLegacyResaveTests {
    private let legacyStones: [(Int, Int, GomokuStone)] = [
        (7, 7, .black), (7, 8, .white), (8, 7, .black), (8, 8, .white),
    ]

    private func legacySnapshot() -> GomokuSnapshot {
        var board = GomokuBoard()
        for (row, col, stone) in legacyStones { board[row, col] = stone }
        return GomokuSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: GomokuStone.black.rawValue,
            humanSide: GomokuStone.black.rawValue,
            aiLevel: 1,
            startedAt: Date(),
            moveHistory: nil,
            undoUsed: nil,
            resigned: nil,
            winner: nil,
            forbiddenMoves: nil,
            hintsUsed: nil
        )
    }

    private func makeModel(_ store: MemorySnapshotStore) -> GomokuModel {
        GomokuModel(services: GameServices(snapshots: store, ads: NoopAdService()))
    }

    /// 離れた空き交点に人間が 1 手打ち、CPU の応手まで進める。
    private func playExchange(_ model: GomokuModel) async throws {
        let before = model.moveCount
        model.tap(row: 0, col: 0)
        await model.performAIMoveIfNeeded()
        try #require(model.moveCount == before + 2, "前提: 人間の手と CPU の応手が打てている")
    }

    private func expectLegacyStones(_ model: GomokuModel, _ context: Comment) {
        for (row, col, stone) in legacyStones {
            #expect(model.board[row, col] == stone, context)
        }
    }

    @Test("旧形式を復元して 1 往復打ち、再度復元しても復元前の石が残る")
    func legacyStonesSurviveResave() async throws {
        let store = MemorySnapshotStore()
        try store.save(legacySnapshot(), for: "gomoku")

        let first = makeModel(store)
        expectLegacyStones(first, "前提: 復元直後は全部見える")
        try await playExchange(first)

        let second = makeModel(store)
        expectLegacyStones(second, "再保存後の復元で復元前の石が消えている")
        #expect(second.moveCount == 6)
        #expect(second.board[0, 0] == .black)
    }

    @Test("旧形式を復元して 1 往復打って待ったしても、復元前の石は盤に残る")
    func legacyStonesSurviveUndo() async throws {
        let store = MemorySnapshotStore()
        try store.save(legacySnapshot(), for: "gomoku")

        let model = makeModel(store)
        try await playExchange(model)
        try #require(model.canUndo)
        model.undoLastExchange()

        expectLegacyStones(model, "待ったで復元前の石が消えている")
        #expect(model.board[0, 0] == nil)
        #expect(model.moveCount == 4)
        #expect(!model.canUndo, "戻せるのは復元後の手だけ")

        // 待った後の保存を復元しても同じ。
        let again = makeModel(store)
        expectLegacyStones(again, "待った後の保存を復元すると復元前の石が消えている")
        #expect(again.moveCount == 4)
    }

    @Test("再保存後に復元した局でも、待ったで戻るのは復元後の手だけ")
    func undoAfterReloadKeepsLegacyStones() async throws {
        let store = MemorySnapshotStore()
        try store.save(legacySnapshot(), for: "gomoku")
        try await playExchange(makeModel(store))

        let reloaded = makeModel(store)
        try #require(reloaded.canUndo)
        reloaded.undoLastExchange()
        expectLegacyStones(reloaded, "再復元後の待ったで復元前の石が消えている")
        #expect(reloaded.board[0, 0] == nil)
        #expect(!reloaded.canUndo)
    }
}
