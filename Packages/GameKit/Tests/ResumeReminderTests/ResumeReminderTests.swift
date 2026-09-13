import Foundation
import Testing
import Core
import Game2048
import GameChess
import GameRunner
import GameShogi

// MARK: - テスト用の部品

/// 予約先のスパイ。`UNUserNotificationCenter` と同じく、同じゲームの予約は置き換わる。
@MainActor
private final class SpyScheduler: ResumeReminderScheduler {
    var status: ReminderAuthorization
    /// `.provisional` を求めたあとの状態。
    var statusAfterRequest: ReminderAuthorization
    private(set) var provisionalRequests = 0
    private(set) var reminders: [String: ResumeReminder] = [:]
    private(set) var contents: [String: (title: String, body: String)] = [:]
    private(set) var cancelled: [String] = []
    private(set) var cancelAllCount = 0

    /// true のあいだ `authorization()` がそこで止まる（問い合わせ中の競合を作るため）。
    var holdsAuthorization = false
    /// true なら問い合わせ・予約のたびに 1 回ほかのタスクへ譲る。本物の通知センターは応答を待つ間に
    /// 他の処理が割り込めるが、譲らないスパイだと処理が混ざらず、直列化を外しても緑のまま素通りする。
    var yieldsOnEveryCall = false
    private var held: [CheckedContinuation<Void, Never>] = []
    var heldCount: Int { held.count }

    init(status: ReminderAuthorization = .provisional, statusAfterRequest: ReminderAuthorization = .provisional) {
        self.status = status
        self.statusAfterRequest = statusAfterRequest
    }

    func releaseAuthorization() {
        holdsAuthorization = false
        let waiting = held
        held.removeAll()
        waiting.forEach { $0.resume() }
    }

    func authorization() async -> ReminderAuthorization {
        if holdsAuthorization {
            await withCheckedContinuation { held.append($0) }
        }
        if yieldsOnEveryCall { await Task.yield() }
        return status
    }

    func requestProvisionalAuthorization() async -> ReminderAuthorization {
        provisionalRequests += 1
        status = statusAfterRequest
        return status
    }

    func pendingReminders() async -> [ResumeReminder] {
        let snapshot = Array(reminders.values)
        if yieldsOnEveryCall { await Task.yield() }
        return snapshot
    }

    /// true のあいだ `schedule` が予約を書き込む前に止まる（追加の完了待ちの間の競合を作るため）。
    /// 止まっている間の取り消しは、まだ入っていない予約には効かない（本物の通知センターで
    /// 取り消しが追加より先に処理された場合と同じ）。
    var holdsSchedule = false
    private var heldSchedules: [CheckedContinuation<Void, Never>] = []
    var heldScheduleCount: Int { heldSchedules.count }

    func releaseSchedule() {
        holdsSchedule = false
        let waiting = heldSchedules
        heldSchedules.removeAll()
        waiting.forEach { $0.resume() }
    }

    func schedule(_ reminder: ResumeReminder, title: String, body: String) async {
        if holdsSchedule {
            await withCheckedContinuation { heldSchedules.append($0) }
        }
        if yieldsOnEveryCall { await Task.yield() }
        reminders[reminder.gameID] = reminder
        contents[reminder.gameID] = (title, body)
    }

    func cancel(gameIDs: [String]) {
        cancelled += gameIDs
        gameIDs.forEach { reminders[$0] = nil }
    }

    func cancelAll() {
        cancelAllCount += 1
        reminders.removeAll()
    }
}

/// 設定と時計。サービスの closure から読むため参照型にする。
@MainActor
private final class Environment {
    var enabled = true
    var now: Date
    init(now: Date) { self.now = now }
}

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private let titles = ["shogi": "将棋", "2048": "2048", "sudoku": "ナンプレ", "go": "囲碁", "chess": "チェス"]

@MainActor
private func makeService(
    _ spy: SpyScheduler,
    _ env: Environment,
    suppressed: Bool = false
) -> ResumeReminderService {
    ResumeReminderService(
        scheduler: spy,
        isEnabled: { env.enabled },
        isSuppressed: suppressed,
        reminderTitle: { titles[$0] },
        now: { env.now },
        calendar: tokyo
    )
}

private let hour: TimeInterval = 60 * 60

// MARK: - 予約と取り消し

@Suite("中断したゲームのお知らせ（#663）")
@MainActor
struct ResumeReminderServiceTests {
    @Test("中断データを持って戻ったときだけ予約する")
    func schedulesOnlyWithSnapshot() async {
        let spy = SpyScheduler()
        let service = makeService(spy, Environment(now: date(13, 12)))

        service.gameDidLeave(gameID: "shogi", hasSnapshot: false)
        await service.pendingWork?.value
        #expect(spy.reminders.isEmpty)

        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value
        #expect(spy.reminders["shogi"]?.fireDate == date(14, 12))
        #expect(spy.contents["shogi"]?.title == "「将棋」が途中のままです")
        #expect(spy.contents["shogi"]?.body == "続きから、そのまま遊べます。")
    }

    @Test("同じゲームは1件にまとまり、最後に戻った時刻で知らせる")
    func oneReminderPerGame() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(13, 12))
        let service = makeService(spy, env)

        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        env.now = date(13, 14)
        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value

        #expect(spy.reminders.count == 1)
        #expect(spy.reminders["shogi"]?.fireDate == date(14, 14))
        #expect(spy.cancelled.isEmpty, "同じゲームの予約は置き換えで、上限による取り消しに数えない")
    }

    @Test("全体で3件まで。あふれたら古い中断から外す（続けて戻っても上限を超えない）")
    func atMostThreeReminders() async {
        let spy = SpyScheduler()
        spy.yieldsOnEveryCall = true
        let env = Environment(now: date(13, 10))
        let service = makeService(spy, env)

        // 途中で待たずに4件続ける。予約が直列に流れていないと、4件とも空の一覧を見て全部予約してしまう。
        for (offset, gameID) in ["shogi", "2048", "sudoku", "go"].enumerated() {
            env.now = date(13, 10 + offset)
            service.gameDidLeave(gameID: gameID, hasSnapshot: true)
        }
        await service.pendingWork?.value
        // 直列でない実装だと最後の処理より先に終わらない処理が残りうるので、実時間ではなく譲る回数で待つ。
        for _ in 0..<100 { await Task.yield() }

        #expect(Set(spy.reminders.keys) == ["2048", "sudoku", "go"])
        #expect(spy.cancelled == ["shogi"])
    }

    @Test("そのゲームを開くと取り消す")
    func openingCancels() async {
        let spy = SpyScheduler()
        let service = makeService(spy, Environment(now: date(13, 12)))
        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        service.gameDidLeave(gameID: "2048", hasSnapshot: true)
        await service.pendingWork?.value

        service.gameDidOpen(gameID: "shogi")
        #expect(Set(spy.reminders.keys) == ["2048"])
    }

    @Test("中断データが消える（終局・やり直し）と取り消す")
    func clearingSnapshotCancels() async {
        let spy = SpyScheduler()
        let service = makeService(spy, Environment(now: date(13, 12)))
        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value

        service.snapshotDidClear(gameID: "shogi")
        #expect(spy.reminders.isEmpty)
    }

    @Test("許諾が未決定なら、ダイアログの出ない provisional を求めてから予約する")
    func requestsProvisionalWhenNotDetermined() async {
        let spy = SpyScheduler(status: .notDetermined, statusAfterRequest: .provisional)
        let service = makeService(spy, Environment(now: date(13, 12)))

        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value

        #expect(spy.provisionalRequests == 1)
        #expect(spy.reminders["shogi"] != nil)
    }

    @Test("許可が得られない・拒否されているなら予約しない")
    func doesNotScheduleWithoutPermission() async {
        let undetermined = SpyScheduler(status: .notDetermined, statusAfterRequest: .notDetermined)
        let first = makeService(undetermined, Environment(now: date(13, 12)))
        first.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await first.pendingWork?.value
        #expect(undetermined.reminders.isEmpty, "許諾が未決定のまま予約している")

        let denied = SpyScheduler(status: .denied)
        let second = makeService(denied, Environment(now: date(13, 12)))
        second.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await second.pendingWork?.value
        #expect(denied.reminders.isEmpty)
        #expect(denied.provisionalRequests == 0, "拒否した人に許可を求め直している")
    }

    @Test("設定がオフなら予約せず、オフにしたら予約済みもすべて取り消す")
    func settingTurnsRemindersOff() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(13, 12))
        let service = makeService(spy, env)
        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value

        env.enabled = false
        service.cancelAll()
        service.gameDidLeave(gameID: "2048", hasSnapshot: true)
        await service.pendingWork?.value

        #expect(spy.cancelAllCount == 1)
        #expect(spy.reminders.isEmpty)
    }

    @Test("撮影モード・DEBUG ビルドでは予約も許諾の要求もしない")
    func suppressedBuildsDoNothing() async {
        let spy = SpyScheduler(status: .notDetermined)
        let service = makeService(spy, Environment(now: date(13, 12)), suppressed: true)

        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value

        #expect(spy.reminders.isEmpty)
        #expect(spy.provisionalRequests == 0)
    }

    @Test("対象外のゲーム（中断データから局を復元しない等）は予約しない")
    func ineligibleGamesAreSkipped() async {
        let spy = SpyScheduler()
        let service = makeService(spy, Environment(now: date(13, 12)))

        service.gameDidLeave(gameID: "runner", hasSnapshot: true)
        await service.pendingWork?.value

        #expect(spy.reminders.isEmpty)
    }

    @Test("許諾の問い合わせを待つ間に開き直された・設定を切られたなら予約しない")
    func stateChangesDuringQueryWin() async throws {
        for change in ["open", "clear", "disable"] {
            let spy = SpyScheduler()
            let env = Environment(now: date(13, 12))
            let service = makeService(spy, env)
            spy.holdsAuthorization = true

            service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
            // 予約の処理が問い合わせで止まるところまで進める（実時間では待たない）。
            var spins = 0
            while spy.heldCount == 0 {
                await Task.yield()
                spins += 1
                try #require(spins < 10_000, "予約の処理が問い合わせに到達しない")
            }

            switch change {
            case "open":  service.gameDidOpen(gameID: "shogi")
            case "clear": service.snapshotDidClear(gameID: "shogi")
            default:
                env.enabled = false
                service.cancelAll()
            }
            spy.releaseAuthorization()
            await service.pendingWork?.value

            #expect(spy.reminders.isEmpty, "\(change) の後に古い予約が入った")
        }
    }

    @Test("予約の完了を待つ間に開き直された・中断が消えた・設定を切られたなら、入った予約を取り消す")
    func stateChangesDuringScheduleWin() async throws {
        for change in ["open", "clear", "disable"] {
            let spy = SpyScheduler()
            let env = Environment(now: date(13, 12))
            let service = makeService(spy, env)
            spy.holdsSchedule = true

            service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
            // 予約の処理が追加の完了待ちで止まるところまで進める（実時間では待たない）。
            var spins = 0
            while spy.heldScheduleCount == 0 {
                await Task.yield()
                spins += 1
                try #require(spins < 10_000, "予約の処理が追加に到達しない")
            }

            switch change {
            case "open":  service.gameDidOpen(gameID: "shogi")
            case "clear": service.snapshotDidClear(gameID: "shogi")
            default:
                env.enabled = false
                service.cancelAll()
            }
            spy.releaseSchedule()
            await service.pendingWork?.value

            #expect(spy.reminders.isEmpty, "\(change) の後に、取り消したはずの予約が残った")
        }
    }

    @Test("通知のタップは対象のゲームだけを開くよう求める")
    func tapRequestsOnlyEligibleGames() {
        let service = makeService(SpyScheduler(), Environment(now: date(13, 12)))

        service.notificationTapped(gameID: "runner")
        #expect(service.requestedGameID == nil)

        service.notificationTapped(gameID: "shogi")
        #expect(service.requestedGameID == "shogi")
    }
}

// MARK: - 時刻と件数の規則

@Suite("中断のお知らせの規則（#663）")
struct ResumeReminderPolicyTests {
    @Test("日中に戻ったらちょうど24時間後")
    func daytimeIsExactlyOneDay() {
        #expect(ResumeReminderPolicy.fireDate(leftAt: date(13, 12, 30), calendar: tokyo) == date(14, 12, 30))
    }

    @Test("24時間後が夜・早朝に当たるなら、次の朝9時まで後ろへずらす")
    func nightIsDeferredToMorning() {
        #expect(ResumeReminderPolicy.fireDate(leftAt: date(13, 22, 30), calendar: tokyo) == date(15, 9))
        #expect(ResumeReminderPolicy.fireDate(leftAt: date(13, 3), calendar: tokyo) == date(14, 9))
        #expect(ResumeReminderPolicy.fireDate(leftAt: date(13, 20, 59), calendar: tokyo) == date(14, 20, 59))
        #expect(ResumeReminderPolicy.fireDate(leftAt: date(13, 21), calendar: tokyo) == date(15, 9))
    }

    @Test("どの時刻に戻っても24〜48時間後で、21時〜9時には届かない")
    func everyMinuteOfTheDayStaysInRange() {
        for minute in stride(from: 0, to: 24 * 60, by: 5) {
            let leftAt = date(13, 0).addingTimeInterval(TimeInterval(minute * 60))
            let fire = ResumeReminderPolicy.fireDate(leftAt: leftAt, calendar: tokyo)
            let elapsed = fire.timeIntervalSince(leftAt)
            #expect(elapsed >= 24 * hour && elapsed <= 48 * hour, "\(leftAt) → \(fire)")
            #expect(ResumeReminderPolicy.deliveryHours.contains(tokyo.component(.hour, from: fire)), "\(leftAt) → \(fire)")
        }
    }

    @Test("上限の判定は同じゲームの予約を数えず、知らせる時刻が早いものから外す")
    func evictionOrder() {
        let pending = [
            ResumeReminder(gameID: "go", fireDate: date(14, 15)),
            ResumeReminder(gameID: "shogi", fireDate: date(14, 10)),
            ResumeReminder(gameID: "2048", fireDate: date(14, 12)),
        ]
        #expect(ResumeReminderPolicy.evictions(pending: pending, adding: "sudoku") == ["shogi"])
        #expect(ResumeReminderPolicy.evictions(pending: pending, adding: "go").isEmpty)
        #expect(ResumeReminderPolicy.evictions(pending: Array(pending.prefix(2)), adding: "sudoku").isEmpty)
    }
}

// MARK: - 周辺の結線

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var data: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws { data[gameID] = try JSONEncoder().encode(snapshot) }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        data[gameID].flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
    func clear(for gameID: String) { data[gameID] = nil }
    func exists(for gameID: String) -> Bool { data[gameID] != nil }
}

private final class ClearRecorder: @unchecked Sendable {
    var gameIDs: [String] = []
}

@Suite("中断のお知らせの周辺（#663）")
@MainActor
struct ResumeReminderIntegrationTests {
    @Test("チャリンコおじさんは対象外、2048 は既定のまま対象")
    func moduleDeclaresEligibility() {
        let modules: [GameModule] = [RunnerModule(), Game2048Module()]
        #expect(modules.map(\.resumesFromSnapshot) == [false, true])
    }

    @Test("中断データの消去を横から知らせ、読み書きはそのまま下へ渡す")
    func clearObservingStoreForwards() throws {
        let recorder = ClearRecorder()
        let base = MemorySnapshotStore()
        let store = ClearObservingSnapshotStore(base: base) { recorder.gameIDs.append($0) }

        try store.save([1, 2, 3], for: "shogi")
        #expect(base.exists(for: "shogi"))
        #expect(store.load([Int].self, for: "shogi") == [1, 2, 3])
        #expect(recorder.gameIDs.isEmpty)

        store.clear(for: "shogi")
        #expect(!base.exists(for: "shogi"))
        #expect(recorder.gameIDs == ["shogi"])
    }

    @Test("GameServices は離れたときに中断の有無を渡し、開いたときに取り消す")
    func gameServicesForwardsLeaveAndOpen() async throws {
        let spy = SpyScheduler()
        let store = MemorySnapshotStore()
        let reminders = makeService(spy, Environment(now: date(13, 12)))
        let services = GameServices(snapshots: store, ads: NoopAdService(), reminders: reminders)

        services.gameDidLeave(gameID: "shogi")
        await reminders.pendingWork?.value
        #expect(spy.reminders.isEmpty, "中断データが無いのに予約した")

        try store.save("board", for: "shogi")
        services.gameDidLeave(gameID: "shogi")
        await reminders.pendingWork?.value
        #expect(spy.reminders["shogi"] != nil)

        services.gameDidOpen(gameID: "shogi", source: .notification, position: nil, resume: true)
        #expect(spy.reminders.isEmpty)
    }

    @Test("決着した局は、次のプレイを始めるか1手指すまで予約しない")
    func finishedGamesAreSkippedUntilNextPlay() async {
        let spy = SpyScheduler()
        let service = makeService(spy, Environment(now: date(13, 12)))

        service.gameDidFinish(gameID: "shogi")
        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value
        #expect(spy.reminders.isEmpty, "決着した局に「途中のままです」を予約した")

        service.gameDidBeginPlay(gameID: "shogi")
        service.gameDidLeave(gameID: "shogi", hasSnapshot: true)
        await service.pendingWork?.value
        #expect(spy.reminders["shogi"] != nil, "次のプレイを始めた局に予約していない")
    }

    @Test("GameServices の決着で印が付き、やり直し・1手指すで外れる")
    func gameServicesTracksFinishedState() async throws {
        let spy = SpyScheduler()
        let store = MemorySnapshotStore()
        let reminders = makeService(spy, Environment(now: date(13, 12)))
        let services = GameServices(snapshots: store, ads: NoopAdService(), reminders: reminders)
        try store.save("board", for: "2048")

        services.gameDidFinish(gameID: "2048", outcome: .loss)
        services.gameDidLeave(gameID: "2048")
        await reminders.pendingWork?.value
        #expect(spy.reminders.isEmpty, "決着したのに予約した")

        services.gameDidRestart(gameID: "2048")
        services.gameDidLeave(gameID: "2048")
        await reminders.pendingWork?.value
        #expect(spy.reminders["2048"] != nil, "やり直した局に予約していない")

        services.gameDidOpen(gameID: "2048", source: .hub, position: 1, resume: true)
        services.gameDidFinish(gameID: "2048", outcome: .loss)
        services.gameDidProgress(gameID: "2048")
        services.gameDidLeave(gameID: "2048")
        await reminders.pendingWork?.value
        #expect(spy.reminders["2048"] != nil, "決着後に1手指して続けた局に予約していない")
    }

    @Test("将棋・チェスは投了して戻っても、見返しを開き直して戻っても予約しない")
    func reviewSnapshotsAreNotReminded() async {
        for gameID in ["shogi", "chess"] {
            let spy = SpyScheduler()
            let store = MemorySnapshotStore()
            let reminders = makeService(spy, Environment(now: date(13, 12)))
            let services = GameServices(snapshots: store, ads: NoopAdService(), reminders: reminders)
            if gameID == "shogi" {
                ShogiGameModel(services: services).resign()
            } else {
                ChessGameModel(services: services).resign()
            }
            #expect(store.exists(for: gameID), "前提が崩れた: \(gameID) は終局後も見返しの中断データを残すはず")

            services.gameDidLeave(gameID: gameID)
            await reminders.pendingWork?.value
            #expect(spy.reminders.isEmpty, "\(gameID): 投了した局に予約した")

            // アプリを起動し直して見返しを開いた（決着済みの印を覚えていない新しいサービス）。
            let reopenedSpy = SpyScheduler()
            let reopenedReminders = makeService(reopenedSpy, Environment(now: date(13, 12)))
            let reopened = GameServices(snapshots: store, ads: NoopAdService(), reminders: reopenedReminders)
            if gameID == "shogi" {
                _ = ShogiGameModel(services: reopened)
            } else {
                _ = ChessGameModel(services: reopened)
            }
            reopened.gameDidLeave(gameID: gameID)
            await reopenedReminders.pendingWork?.value
            #expect(reopenedSpy.reminders.isEmpty, "\(gameID): 見返しを開き直して戻ったら予約した")
        }
    }
}
