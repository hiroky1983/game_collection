import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
import GameKitTestSupport
@testable import GameSudoku

/// ヒントの使用が計測に伝わる結線（#2323）。`applyHint` が `gameDidProgress` / `gameDidUseHint` を呼ぶ。
@MainActor
@Suite("数独 ヒントの解析（#2323）")
struct SudokuHintAnalyticsTests {

    private func makeModel() -> (SudokuModel, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["sudoku"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        return (SudokuModel(services: services, seed: 2026), spy)
    }

    private func endParameters(_ spy: SpyAnalyticsService) -> [[String: AnalyticsValue]] {
        spy.events.compactMap { if case .gameEnd = $0 { return $0.parameters } else { return nil } }
    }

    @Test("ヒントだけ使って新規ゲームにすると、quit の game_end が出て hints_used が載る")
    func hintOnlyThenNewGameEmitsQuit() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        let target = try #require((0..<81).first { model.canHint(at: $0) })
        #expect(model.applyHint(at: target))

        await model.newGame(difficulty: .easy)

        let ends = endParameters(spy)
        #expect(ends.count == 1)
        #expect(ends.first?["result"] == .string("quit"))
        #expect(ends.first?["hints_used"] == .int(1))
    }

    @Test("ヒントを 2 回使って盤を完成させると、game_end の hints_used が 2 になる")
    func clearCarriesHintsUsed() async throws {
        let (model, spy) = makeModel()
        await model.newGame(difficulty: .easy)
        let empties = (0..<81).filter { !model.given[$0] }
        try #require(empties.count >= 2)
        // 残り 2 マスを残して正解を直接入れ、最後の 2 マスはヒントで埋める。
        for i in empties.dropLast(2) { model.select(index: i); model.enter(digit: model.solution[i]) }
        for i in empties.suffix(2) { #expect(model.applyHint(at: i)) }

        #expect(model.state == .cleared)
        let ends = endParameters(spy)
        #expect(ends.count == 1)
        #expect(ends.first?["hints_used"] == .int(2))
    }
}
