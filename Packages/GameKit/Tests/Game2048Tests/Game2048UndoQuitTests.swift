import Testing
import Core
import CoreTestSupport
@testable import Game2048

/// 「戻す」で初期盤まで戻したら、離脱の印も戻す（#3414）。
@Suite("2048 戻すと離脱の印（#3414）")
@MainActor
struct Game2048UndoQuitTests {
    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["2048"]),
            isResumable: { _, snapshots in Game2048Module().hasResumableSnapshot(in: snapshots) }
        )
    }

    @Test("1 手動かして初期盤まで戻したら、離れても離脱に数えない")
    func undoToStartIsNotQuit() {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        services.gameDidStart(gameID: "2048")
        let model = Game2048Model(services: services, board: [
            [2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
        ])
        model.move(.left)
        #expect(model.hasProgressToLose, "前提: 1 手で進行ができた")
        #expect(model.undo())
        #expect(!model.hasProgressToLose, "前提: 初期盤に戻った")
        services.gameDidLeave(gameID: "2048")
        #expect(spy.quits.isEmpty, "手つかずの盤は離脱に数えない")
    }

    @Test("2 手動かして 1 回だけ戻したら、離れると離脱に数える（対照）")
    func undoMidwayStaysQuit() {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        services.gameDidStart(gameID: "2048")
        let model = Game2048Model(services: services, board: [
            [2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 2],
        ])
        model.move(.left)
        model.move(.up)
        #expect(model.history.count == 2)
        #expect(model.undo())
        #expect(model.hasProgressToLose, "前提: まだ進行が残っている")
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "2048", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["2048"])
    }
}
