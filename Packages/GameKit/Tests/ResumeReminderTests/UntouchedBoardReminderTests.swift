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

/// ゲーム画面を出したままバックグラウンドへ入る中断（#1951）。ハブへ戻る `gameDidLeave` を通らない経路。
@Suite("バックグラウンドへ入ったときの通知予約（#1951）")
@MainActor
struct BackgroundReminderTests {
    private func makeServices(
        _ store: MemorySnapshotStore, spy: SpyReminderScheduler, resolver: Bool = true
    ) -> GameServices {
        let registry = GameRegistry([Game2048Module()])
        let reminders = ResumeReminderService(
            scheduler: spy, isEnabled: { true }, isSuppressed: false, reminderTitle: { _ in "2048" }
        )
        let isResumable: ((String, SnapshotStore) -> Bool)? = resolver
            ? { gameID, snapshots in registry.hasResumableSnapshot(gameID: gameID, in: snapshots) }
            : nil
        return GameServices(snapshots: store, ads: NoopAdService(), reminders: reminders, isResumable: isResumable)
    }

    @Test("手つかずの盤では予約せず、動かしてからバックグラウンドへ入れば予約し、前面に戻ると取り消す")
    func schedulesAfterProgressAndCancelsOnForeground() async throws {
        let store = MemorySnapshotStore()
        let spy = SpyReminderScheduler()
        let services = makeServices(store, spy: spy)
        let model = Game2048Model(services: services)

        services.gameDidEnterBackground(gameID: "2048")
        await services.reminders?.pendingWork?.value
        #expect(spy.reminders.isEmpty, "開いただけ（手つかず）")

        let direction = try #require(Direction.allCases.first { Game2048Logic.slide(model.board, $0).moved })
        model.move(direction)
        services.gameDidEnterBackground(gameID: "2048")
        await services.reminders?.pendingWork?.value
        #expect(spy.reminders["2048"] != nil, "動かした盤は予約する")

        services.gameDidReturnToForeground(gameID: "2048")
        #expect(spy.reminders["2048"] == nil, "前面に戻ったら取り消す")
    }

    @Test("離脱計測と画面の世代には触らない（1 プレイの数え方を変えない）")
    func doesNotTouchAnalyticsOrGeneration() async throws {
        let store = MemorySnapshotStore()
        let spy = SpyReminderScheduler()
        let services = makeServices(store, spy: spy, resolver: false)
        _ = Game2048Model(services: services)
        let generation = services.screenGeneration.current

        services.gameDidEnterBackground(gameID: "2048")
        await services.reminders?.pendingWork?.value
        services.gameDidReturnToForeground(gameID: "2048")

        #expect(services.screenGeneration.current == generation)
    }
}
