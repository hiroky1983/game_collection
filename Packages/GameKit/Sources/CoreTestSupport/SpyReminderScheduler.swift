import Core

/// お知らせの予約先のスパイ（#1215）。
///
/// 「予約が入ったか」だけを見る最小限の実装。許諾の状態や競合まで見たいテストは
/// `ResumeReminderTests` の `SpyScheduler` を使う。BJ・ポーカーのテストに逐語コピーされていたのを寄せた。
@MainActor
public final class SpyReminderScheduler: ResumeReminderScheduler {
    public private(set) var reminders: [String: ResumeReminder] = [:]

    public init() {}

    public func authorization() async -> ReminderAuthorization { .authorized }
    public func requestExplicitAuthorization() async -> ReminderAuthorization { .authorized }
    public func pendingReminders() async -> [ResumeReminder] { Array(reminders.values) }
    public func schedule(_ reminder: ResumeReminder, title: String, body: String) async {
        reminders[reminder.gameID] = reminder
    }
    public func cancel(gameIDs: [String]) { gameIDs.forEach { reminders[$0] = nil } }
    public func cancelAll() { reminders.removeAll() }
}

/// アプリを起動し直した状態（決着済みの印を覚えていない新しいサービス）を作る。
///
/// `reminderTitle` は予約の見出しを返すゲームだけ non-nil を返す（そのゲームの予約だけが入る）。
@MainActor
public func makeRelaunchedServices(
    store: MemorySnapshotStore,
    ads: any AdService,
    reminderTitle: @escaping @Sendable (String) -> String?
) -> (GameServices, ResumeReminderService, SpyReminderScheduler) {
    let spy = SpyReminderScheduler()
    let reminders = ResumeReminderService(
        scheduler: spy,
        isEnabled: { true },
        isSuppressed: false,
        reminderTitle: reminderTitle
    )
    let services = GameServices(snapshots: store, ads: ads, reminders: reminders)
    return (services, reminders, spy)
}
