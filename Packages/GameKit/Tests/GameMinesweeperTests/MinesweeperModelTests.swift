import Testing
import Foundation
@testable import GameMinesweeper

// MARK: - 計時の停止（#375: タイマー Task がモデルごとリークする）

@Suite("マインスイーパー 計時の停止")
@MainActor
struct MinesweeperTimerLifecycleTests {

    @Test("画面を離れると計時が止まり、戻ると再開する（#375）")
    func pauseAndResumeTimer() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)   // 最初のタップで地雷が配置され計時が始まる
        #expect(model.isTimerRunning)

        model.pauseTimer()
        #expect(!model.isTimerRunning, "onDisappear で計時 Task を手放す（モデルが解放できるようになる）")

        model.resumeTimerIfNeeded()
        #expect(model.isTimerRunning, "画面に戻れば計時は再開する")
    }

    @Test("まだ始めていない盤では再開しない")
    func doesNotResumeBeforeFirstTap() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        model.pauseTimer()
        model.resumeTimerIfNeeded()
        #expect(!model.isTimerRunning)
    }
}
