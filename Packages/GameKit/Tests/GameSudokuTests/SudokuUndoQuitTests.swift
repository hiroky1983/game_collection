import Testing
import Core
import CoreTestSupport
@testable import GameSudoku

/// 「元に戻す」で手つかずの盤まで戻したら、離脱の印も戻す（#3414）。
@Suite("ナンプレ 元に戻すと離脱の印（#3414）")
@MainActor
struct SudokuUndoQuitTests {
    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["sudoku"]),
            isResumable: { _, snapshots in SudokuModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    @Test("1 マス入れて戻したら、離れても離脱に数えない")
    func undoToUntouchedIsNotQuit() async throws {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        services.gameDidStart(gameID: "sudoku")
        let model = SudokuModel(services: services, seed: 2026)
        await model.newGame(difficulty: .easy)
        let index = try #require(model.board.indices.first { model.board[$0] == 0 })
        model.select(index: index)
        model.enter(digit: model.solution[index])
        model.undo()
        #expect(model.board[index] == 0, "前提: 戻った")
        services.gameDidLeave(gameID: "sudoku")
        #expect(spy.quits.isEmpty, "手つかずの盤は離脱に数えない")
    }

    @Test("2 マス入れて 1 回戻しただけなら、離れると離脱に数える（対照）")
    func undoMidwayStaysQuit() async throws {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        services.gameDidStart(gameID: "sudoku")
        let model = SudokuModel(services: services, seed: 2026)
        await model.newGame(difficulty: .easy)
        let empties = model.board.indices.filter { model.board[$0] == 0 }
        let first = try #require(empties.first)
        let second = try #require(empties.dropFirst().first)
        for i in [first, second] {
            model.select(index: i)
            model.enter(digit: model.solution[i])
        }
        model.undo()
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "sudoku", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["sudoku"])
    }
}
