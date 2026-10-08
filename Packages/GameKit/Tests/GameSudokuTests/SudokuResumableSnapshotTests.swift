import Testing
import Core
import CoreTestSupport
@testable import GameSudoku

/// 1 マスも入力していない盤は「続きから」に出さない（#1912）。
@Suite("ナンプレの「続きから」判定（#1912）")
@MainActor
struct SudokuResumableSnapshotTests {
    @Test("出題しただけでは続きではなく、1 マス入れると続きになる")
    func untouchedBoardIsNotResumable() async throws {
        let store = MemorySnapshotStore()
        let module = SudokuModule()
        let model = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()), seed: 2026)
        await model.newGame(difficulty: .easy)
        #expect(store.exists(for: module.id), "出題直後に保存はされる（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "出題しただけ")

        let index = try #require(model.board.indices.first { model.board[$0] == 0 })
        model.select(index: index)
        model.enter(digit: model.solution[index])
        #expect(module.hasResumableSnapshot(in: store), "入力した盤（対照）")
    }

    @Test("メモだけ書いた盤も続きになる")
    func notedBoardIsResumable() async throws {
        let store = MemorySnapshotStore()
        let module = SudokuModule()
        let model = SudokuModel(services: GameServices(snapshots: store, ads: NoopAdService()), seed: 2026)
        await model.newGame(difficulty: .easy)
        let index = try #require(model.board.indices.first { model.board[$0] == 0 })
        model.select(index: index)
        model.toggleNoteMode()
        model.enter(digit: 1)
        #expect(module.hasResumableSnapshot(in: store))
    }
}
