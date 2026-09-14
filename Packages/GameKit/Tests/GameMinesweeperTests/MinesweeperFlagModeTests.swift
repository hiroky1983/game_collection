import Testing
import Foundation
import Core
@testable import GameMinesweeper

/// テスト専用の中断データ置き場（`MinesweeperModelTests` と同じ手口。ファイルに書かない）。
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

@MainActor
private final class SpyFeedback: FeedbackService {
    private(set) var impacts: [FeedbackImpact] = []
    private(set) var notices: [FeedbackNotice] = []

    func impact(_ style: FeedbackImpact) { impacts.append(style) }
    func notify(_ type: FeedbackNotice) { notices.append(type) }
}

/// 旗モードの切り替え（#761）。以前は View の `@State` で Model を通らず、手応えが鳴らなかった。
@Suite("マインスイーパー 旗モードの切り替え")
@MainActor
struct MinesweeperFlagModeTests {

    @Test("切り替えるたびに rigid が1回だけ鳴り、盤面には触れない")
    func toggleFiresRigidOnce() {
        let spy = SpyFeedback()
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: spy)
        let model = MinesweeperModel(services: services, rows: 9, cols: 9, mines: 10)
        #expect(!model.flagMode)

        model.toggleFlagMode()
        #expect(model.flagMode)
        #expect(spy.impacts == [.rigid])
        #expect(spy.notices.isEmpty)

        model.toggleFlagMode()
        #expect(!model.flagMode)
        #expect(spy.impacts == [.rigid, .rigid])
        #expect(model.gameState == .idle, "モードの切り替えだけで局は始まらない")
    }

    @Test("新規ゲームで旗モードはオフに戻る")
    func newGameResetsFlagMode() {
        let model = MinesweeperModel(rows: 9, cols: 9, mines: 10)
        model.toggleFlagMode()
        #expect(model.flagMode)

        model.newGame(rows: 16, cols: 16, mines: 40)
        #expect(!model.flagMode)
    }

    @Test("旗モードは中断データに書かず、再開時はオフ")
    func flagModeIsNotRestored() {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let model = MinesweeperModel(services: services, rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)          // 局を始めて中断データを作る
        model.toggleFlagMode()
        #expect(model.flagMode)
        #expect(model.gameState == .playing)
        #expect(store.exists(for: "minesweeper"))

        let restored = MinesweeperModel(services: services)
        #expect(restored.gameState == .playing, "中断データから復元できている（空振り防止）")
        #expect(!restored.flagMode)
    }
}
