import Testing
import Core
import CoreTestSupport
@testable import GameSudoku

/// 広告コンティニュー後の続きの局にも `game_end` が付く（#3446。2048 の #1953 と同じ取りこぼし）。
@Suite("ナンプレ コンティニュー後の game_end（#3446）")
@MainActor
struct SudokuContinueAnalyticsTests {
    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["sudoku"]),
            isResumable: { _, snapshots in SudokuModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    /// ミス上限まで誤答して負け、広告のコンティニューで続きに戻る。
    private func failAndContinue(_ model: SudokuModel) {
        for _ in 0..<SudokuModel.maxMistakes {
            guard let index = (0..<81).first(where: { !model.given[$0] && model.board[$0] == 0 }) else {
                Issue.record("空きマスが無い"); return
            }
            model.select(index: index)
            model.enter(digit: (1...9).first { $0 != model.solution[index] }!)
        }
        #expect(model.state == .failed, "前提: ミス上限に達している")
        #expect(model.continueAfterAd())
    }

    @Test("コンティニュー後にクリアすると game_end(win) が出て、game_start は 1 回増えるだけ")
    func winAfterContinueEmitsEnd() async {
        let spy = SpyAnalyticsService()
        let model = SudokuModel(services: makeServices(spy), seed: 2026)
        await model.newGame(difficulty: .easy)
        failAndContinue(model)
        #expect(spy.starts.count == 2, "新規 1 + コンティニュー 1")
        #expect(spy.outcomes == [.loss])
        for index in 0..<81 where model.board[index] != model.solution[index] {
            model.select(index: index)
            model.enter(digit: model.solution[index])
        }
        #expect(model.state == .cleared, "前提: クリアした")
        #expect(spy.outcomes == [.loss, .win])
    }

    @Test("コンティニュー後に新規ゲームで捨てると game_end(quit) が 1 回出る")
    func abandonAfterContinueEmitsQuit() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        let model = SudokuModel(services: services, seed: 2026)
        await model.newGame(difficulty: .easy)
        failAndContinue(model)
        services.analytics?.leaveGame(gameID: "sudoku", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["sudoku"])
    }
}
