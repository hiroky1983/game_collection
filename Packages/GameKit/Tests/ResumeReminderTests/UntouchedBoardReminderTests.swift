import Testing
import Core
import Game2048
import GameRunner
import CoreTestSupport

/// 手つかずの盤で戻っても「続きから」の通知を予約しない（#1847）。ハブと同じ判定（モジュールの
/// `hasResumableSnapshot`）を通知予約と離脱計測にも使う。
@Suite("手つかずの盤の通知予約（#1847）")
@MainActor
struct UntouchedBoardReminderTests {
    private func makeServices(_ store: MemorySnapshotStore, spy: SpyReminderScheduler, resolver: Bool) -> GameServices {
        let registry = GameRegistry([Game2048Module()])
        let reminders = ResumeReminderService(
            scheduler: spy, isEnabled: { true }, isSuppressed: false, reminderTitle: { _ in "2048" }
        )
        let isResumable: ((String, SnapshotStore) -> Bool)? = resolver
            ? { gameID, snapshots in registry.hasResumableSnapshot(gameID: gameID, in: snapshots) }
            : nil
        return GameServices(snapshots: store, ads: NoopAdService(), reminders: reminders, isResumable: isResumable)
    }

    @Test("2048 を開いてすぐ戻っても予約せず、動かして戻れば予約する")
    func untouchedBoardSchedulesNothing() async throws {
        let store = MemorySnapshotStore()
        let spy = SpyReminderScheduler()
        let services = makeServices(store, spy: spy, resolver: true)

        let model = Game2048Model(services: services)
        services.gameDidLeave(gameID: "2048")
        await services.reminders?.pendingWork?.value
        #expect(spy.reminders.isEmpty, "開いただけ")

        let direction = try #require(Direction.allCases.first { Game2048Logic.slide(model.board, $0).moved })
        model.move(direction)
        services.gameDidLeave(gameID: "2048")
        await services.reminders?.pendingWork?.value
        #expect(spy.reminders["2048"] != nil, "動かした盤（対照）")
    }

    @Test("判定を差し込まない場合は従来どおり中断データの有無で予約する（対照）")
    func withoutResolverFallsBackToExistence() async {
        let store = MemorySnapshotStore()
        let spy = SpyReminderScheduler()
        let services = makeServices(store, spy: spy, resolver: false)

        _ = Game2048Model(services: services)
        services.gameDidLeave(gameID: "2048")
        await services.reminders?.pendingWork?.value
        #expect(spy.reminders["2048"] != nil)
    }
}
