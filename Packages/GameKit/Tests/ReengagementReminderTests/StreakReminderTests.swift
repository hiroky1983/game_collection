import Foundation
import Testing
@testable import CoreEngine
import Core
import CoreTestSupport
import GameKitTestSupport

@MainActor
private final class SpyStreakScheduler: StreakReminderScheduler {
    var status: ReminderAuthorization = .authorized
    var scheduled: [(fireDate: Date, title: String, body: String)] = []
    var cancelled = 0
    var duringAuthorization: (() -> Void)?
    func authorization() async -> ReminderAuthorization {
        duringAuthorization?()
        return status
    }
    func schedule(fireDate: Date, title: String, body: String) async -> Bool {
        scheduled = [(fireDate, title, body)]
        return true
    }
    func cancel() { cancelled += 1; scheduled = [] }
}

@Suite("連続日数の夕方の通知（#3417）")
struct StreakReminderTests {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }
    private static func date(_ d: Int, hour: Int, month: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: d, hour: hour))!
    }
    private static func day(_ d: Int, month: Int = 11) -> Int {
        PlayDayStreak.dayNumber(for: date(d, hour: 12, month: month), calendar: calendar)
    }

    @Test("連続 2 日・今日未プレイ・20 時前 → 今日の 20:00")
    func todayEvening() {
        let plan = StreakReminderPolicy.plan(days: [Self.day(7), Self.day(8)], now: Self.date(9, hour: 10), calendar: Self.calendar)
        #expect(plan == .init(fireDate: Self.date(9, hour: 20), streak: 2))
    }

    @Test("連続 1 日だけなら予約しない")
    func singleDayNoReminder() {
        #expect(StreakReminderPolicy.plan(days: [Self.day(8)], now: Self.date(9, hour: 10), calendar: Self.calendar) == nil)
        #expect(StreakReminderPolicy.plan(days: [], now: Self.date(9, hour: 10), calendar: Self.calendar) == nil)
    }

    @Test("今日の 20:00 を過ぎていて未プレイなら予約しない（翌日は連続が切れている）")
    func afterDeliveryHourUnplayed() {
        #expect(StreakReminderPolicy.plan(days: [Self.day(7), Self.day(8)], now: Self.date(9, hour: 21), calendar: Self.calendar) == nil)
    }

    @Test("昨日も遊んでいなければ連続が切れているので予約しない")
    func brokenStreak() {
        #expect(StreakReminderPolicy.plan(days: [Self.day(5), Self.day(6)], now: Self.date(9, hour: 10), calendar: Self.calendar) == nil)
    }

    @Test("今日遊んだ後 → 今日分は無く、翌日の 20:00 に連続日数（今日を含む）で予約")
    func playedTodaySchedulesTomorrow() {
        let plan = StreakReminderPolicy.plan(days: [Self.day(8), Self.day(9)], now: Self.date(9, hour: 21), calendar: Self.calendar)
        #expect(plan == .init(fireDate: Self.date(10, hour: 20), streak: 2))
    }

    @Test("今日遊んだが連続は 1 日だけなら予約しない")
    func playedTodayShortStreak() {
        #expect(StreakReminderPolicy.plan(days: [Self.day(9)], now: Self.date(9, hour: 10), calendar: Self.calendar) == nil)
    }

    @Test("月をまたいでも翌日 20:00（11/30 に遊んだら 12/1）")
    func crossesMonth() {
        let plan = StreakReminderPolicy.plan(days: [Self.day(29), Self.day(30)], now: Self.date(30, hour: 22), calendar: Self.calendar)
        #expect(plan?.fireDate == Self.date(1, hour: 20, month: 12))
    }

    @MainActor
    @Test("タップ先: 最終プレイが最も新しいゲームを選ぶ（#3534）")
    func landingPicksNewest() {
        let dates = ["a": Self.date(5, hour: 9), "b": Self.date(8, hour: 9), "c": Self.date(6, hour: 9)]
        #expect(StreakReminderPolicy.landingGameID(visibleGameIDs: ["a", "b", "c"], lastPlayedAt: dates) == "b")
    }

    @Test("タップ先: 記録が無ければ nil（ハブのまま）")
    func landingNilWithoutRecords() {
        #expect(StreakReminderPolicy.landingGameID(visibleGameIDs: ["a", "b"], lastPlayedAt: [:]) == nil)
        #expect(StreakReminderPolicy.landingGameID(visibleGameIDs: [], lastPlayedAt: ["a": Self.date(5, hour: 9)]) == nil)
    }

    @Test("タップ先: 最新が非表示なら、見えるゲームの中で最新を選ぶ。見えるものに記録が無ければ nil")
    func landingSkipsHidden() {
        let dates = ["hidden": Self.date(9, hour: 9), "a": Self.date(5, hour: 9), "b": Self.date(7, hour: 9)]
        #expect(StreakReminderPolicy.landingGameID(visibleGameIDs: ["a", "b"], lastPlayedAt: dates) == "b")
        #expect(StreakReminderPolicy.landingGameID(visibleGameIDs: ["x"], lastPlayedAt: dates) == nil)
    }

    @Test("タップ先: 同時刻はハブの並びで先のゲーム")
    func landingTieUsesHubOrder() {
        let t = Self.date(8, hour: 9)
        #expect(StreakReminderPolicy.landingGameID(visibleGameIDs: ["b", "a"], lastPlayedAt: ["a": t, "b": t]) == "b")
        #expect(StreakReminderPolicy.landingGameID(visibleGameIDs: ["a", "b"], lastPlayedAt: ["a": t, "b": t]) == "a")
    }

    @MainActor
    @Test("タップは保留として残り、ハブが受け取ると下りる")
    func tapPendingUntilConsumed() {
        let service = make(SpyStreakScheduler())
        #expect(!service.hasPendingTap)
        service.notificationTapped()
        #expect(service.hasPendingTap && service.tapCount == 1)
        service.consumeTap()
        #expect(!service.hasPendingTap)
    }

    @Test("ハブは連続日数の通知のタップで、最後に遊んだゲームを streak_reminder の導線で開く（結線）")
    func tapIsWiredToHub() throws {
        let source = try SourceScan.appSources()
        guard let handler = source.range(of: ".onChange(of: services.streakReminder?.hasPendingTap, initial: true)") else {
            Issue.record("ハブが連続日数の通知のタップを受け取っていない")
            return
        }
        let body = String(source[handler.upperBound...].prefix(900))
        #expect(body.contains("StreakReminderPolicy.landingGameID("))
        #expect(body.contains("showSettings = false") && body.contains("showRecords = false"), "シートを閉じていない")
        #expect(body.range(of: #"visibleModules\(from: registry\)"#, options: .regularExpression) != nil, "非表示を除いていない")
        #expect(body.range(of: #"openFromOutside\(HubRoute\(\s*gameID: id, source: \.streakReminder,"#, options: .regularExpression) != nil)
    }

    @MainActor private func make(_ spy: SpyStreakScheduler, enabled: Bool = true, suppressed: Bool = false, hour: Int = 10) -> StreakReminderService {
        StreakReminderService(
            scheduler: spy, isEnabled: { enabled }, isSuppressed: suppressed,
            now: { Self.date(9, hour: hour) }, calendar: Self.calendar
        )
    }

    @MainActor
    @Test("許可済み・条件を満たせば 1 件予約し、繰り返しても 1 件のまま")
    func schedulesOnce() async {
        let spy = SpyStreakScheduler()
        let service = make(spy)
        let days = [Self.day(7), Self.day(8)]
        await service.refresh(playDays: days)
        await service.refresh(playDays: days)
        #expect(spy.scheduled.count == 1)
        #expect(spy.scheduled.first?.fireDate == Self.date(9, hour: 20))
    }

    @MainActor
    @Test("通知設定オフ・抑止中・未許諾・拒否では予約しない")
    func noScheduleWhenOffOrUnauthorized() async {
        let days = [Self.day(7), Self.day(8)]
        let off = SpyStreakScheduler()
        await make(off, enabled: false).refresh(playDays: days)
        #expect(off.scheduled.isEmpty)
        let suppressed = SpyStreakScheduler()
        await make(suppressed, suppressed: true).refresh(playDays: days)
        #expect(suppressed.scheduled.isEmpty)
        for status in [ReminderAuthorization.notDetermined, .denied] {
            let spy = SpyStreakScheduler()
            spy.status = status
            await make(spy).refresh(playDays: days)
            #expect(spy.scheduled.isEmpty)
        }
    }

    @MainActor
    @Test("遊んだら（cancel）予約が消え、条件を外れた refresh でも消える")
    func cancelAfterPlay() async {
        let spy = SpyStreakScheduler()
        let service = make(spy)
        await service.refresh(playDays: [Self.day(7), Self.day(8)])
        #expect(spy.scheduled.count == 1)
        service.cancel()
        #expect(spy.scheduled.isEmpty)
        await service.refresh(playDays: [Self.day(7), Self.day(8)])
        await service.refresh(playDays: [Self.day(9)])   // 今日だけ遊んだ → 連続 1
        #expect(spy.scheduled.isEmpty)
    }

    @MainActor
    @Test("許可の確認を待つ間に取り消されたら予約しない")
    func supersededWhileAwaitingAuthorization() async {
        let spy = SpyStreakScheduler()
        let service = make(spy)
        spy.duringAuthorization = { service.cancel() }
        await service.refresh(playDays: [Self.day(7), Self.day(8)])
        #expect(spy.scheduled.isEmpty)
    }

    @Test("タップは識別子で振り分ける")
    func tapTarget() {
        #expect(NotificationTapTarget.resolve(identifier: NotificationTapTarget.streakReminderIdentifier, gameID: nil) == .streakReminder)
    }

    @MainActor
    @Test("決着を記録したら（gameDidFinish）その日の予約を取り消す")
    func cancelsWhenGameFinishes() async {
        let spy = SpyStreakScheduler()
        let service = make(spy)
        await service.refresh(playDays: [Self.day(7), Self.day(8)])
        #expect(spy.scheduled.count == 1)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), streakReminder: service)
        services.gameDidFinish(gameID: "shogi", outcome: .win)
        #expect(spy.scheduled.isEmpty)
    }

    @MainActor
    @Test("判定が追い越されても、新しい判定の予約は消さない")
    func overtakenRefreshKeepsNewerSchedule() async {
        let spy = SpyStreakScheduler()
        let service = make(spy)
        let days = [Self.day(7), Self.day(8)]
        async let first: Void = service.refresh(playDays: days)
        async let second: Void = service.refresh(playDays: days)
        _ = await (first, second)
        #expect(spy.scheduled.count == 1)
    }
}
