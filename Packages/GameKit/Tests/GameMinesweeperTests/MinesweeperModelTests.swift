import Testing
import Foundation
import Core
@testable import GameMinesweeper

/// テスト専用の中断データ置き場（`MinesweeperMarkTests` と同じ手口。ファイルに書かない）。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func save<T: Codable>(_ value: T, for key: String) throws {
        storage[key] = try JSONEncoder().encode(value)
    }

    func load<T: Codable>(_ type: T.Type, for key: String) -> T? {
        guard let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear(for key: String) { storage[key] = nil }
    func exists(for key: String) -> Bool { storage[key] != nil }
}

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

// MARK: - 計時の保存（#513: 経過秒が操作時にしか保存されず自己ベストが洗われる。#240 の横展開）

@Suite("マインスイーパー 計時の保存（#513）")
@MainActor
struct MinesweeperTimerPersistenceTests {

    private func makeModel(store: MemorySnapshotStore) -> MinesweeperModel {
        MinesweeperModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            rows: 9, cols: 9, mines: 10
        )
    }

    /// 保存済みの経過秒。まだ何も保存されていなければ nil。
    private func savedElapsed(_ store: MemorySnapshotStore) -> Int? {
        store.load(MinesweeperSnapshot.self, for: "minesweeper")?.elapsedSeconds
    }

    @Test("計時だけが進んでも一定間隔で経過秒が保存される")
    func elapsedSecondsArePersistedWhileOnlyTimeAdvances() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.tap(row: 0, col: 0)   // 最初のタップで地雷が配置され、計時と保存が始まる
        #expect(savedElapsed(store) == 0, "前提: タップ時点の経過秒が入っている")

        // 保存の間隔に満たない間は、操作が無い限り古い経過秒のまま。
        for _ in 0..<(MinesweeperModel.persistInterval - 1) { model.tick() }
        #expect(model.elapsedSeconds == MinesweeperModel.persistInterval - 1)
        #expect(savedElapsed(store) == 0)

        model.tick()

        #expect(model.elapsedSeconds == MinesweeperModel.persistInterval)
        #expect(
            savedElapsed(store) == MinesweeperModel.persistInterval,
            "操作が無くても \(MinesweeperModel.persistInterval) 秒ごとに経過秒が保存される"
        )
    }

    @Test("強制終了して開き直しても、経過秒は直近の保存間隔ぶんまでしか失われない")
    func resumeKeepsTheElapsedSecondsSavedByTheTimer() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.tap(row: 0, col: 0)
        // 保存の間隔ちょうど + 数秒。最後の保存以降のぶんだけが失われる。
        for _ in 0..<(MinesweeperModel.persistInterval + 5) { model.tick() }

        // アプリを強制終了して開き直した状態（復元は init で行われる）。
        let resumed = MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService()))

        #expect(resumed.gameState == .playing, "前提: 中断データから復元できている")
        #expect(
            resumed.elapsedSeconds == MinesweeperModel.persistInterval,
            "失われるのは直近の保存以降だけ（\(MinesweeperModel.persistInterval) 秒以内）"
        )
        #expect(
            model.elapsedSeconds - resumed.elapsedSeconds < MinesweeperModel.persistInterval,
            "受け入れ条件: 経過秒が直近 \(MinesweeperModel.persistInterval) 秒以内まで復元される"
        )
    }

    @Test("画面を離れるときに経過秒が保存される")
    func pauseTimerPersistsElapsedSeconds() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.tap(row: 0, col: 0)
        for _ in 0..<5 { model.tick() }
        #expect(savedElapsed(store) == 0, "前提: 保存の間隔に乗っていないので、まだ古い経過秒のまま")

        model.pauseTimer()

        #expect(savedElapsed(store) == 5, "止める直前の経過秒が残る")
    }

    @Test("まだ始めていない盤で画面を離れても「続きから」は生えない")
    func pauseTimerDoesNotSaveAnUntouchedBoard() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)

        model.pauseTimer()

        #expect(model.gameState == .idle, "前提: 1 マスも開いていない")
        #expect(!store.exists(for: "minesweeper"))
    }
}
