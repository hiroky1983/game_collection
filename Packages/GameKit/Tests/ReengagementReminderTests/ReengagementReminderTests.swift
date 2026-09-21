import Foundation
import Testing
import Core

// MARK: - テスト用の部品

/// 予約先のスパイ。実装（`UserNotificationReengagementScheduler`）と同じく、ゲームごとに予約を持つ。
@MainActor
private final class SpyScheduler: ReengagementReminderScheduler {
    var status: ReminderAuthorization
    /// 明示的な許可を求めたあとの状態。
    var statusAfterRequest: ReminderAuthorization
    private(set) var explicitRequests = 0
    private(set) var scheduled: [String: [Date]] = [:]
    private(set) var contents: [String: (title: String, body: String)] = [:]
    private(set) var cancelledGameIDs: [String] = []
    private(set) var cancelAllCount = 0

    /// true のあいだ `authorization()` がそこで止まる（問い合わせ中の競合を作るため）。
    var holdsAuthorization = false
    private var held: [CheckedContinuation<Void, Never>] = []
    var heldCount: Int { held.count }

    init(status: ReminderAuthorization = .authorized, statusAfterRequest: ReminderAuthorization = .authorized) {
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
        return status
    }

    func requestExplicitAuthorization() async -> ReminderAuthorization {
        explicitRequests += 1
        status = statusAfterRequest
        return status
    }

    func schedule(gameID: String, fireDates: [Date], title: String, body: String) async {
        if fireDates.isEmpty {
            scheduled[gameID] = nil
            contents[gameID] = nil
        } else {
            scheduled[gameID] = fireDates
            contents[gameID] = (title, body)
        }
    }

    func cancel(gameID: String) {
        cancelledGameIDs.append(gameID)
        scheduled[gameID] = nil
        contents[gameID] = nil
    }

    func cancelAll() {
        cancelAllCount += 1
        scheduled.removeAll()
        contents.removeAll()
    }
}

/// 設定と時計。サービスの closure から読むため参照型にする。
@MainActor
private final class Environment {
    var enabled = true
    var hidden: Set<String> = []
    var now: Date
    init(now: Date) { self.now = now }
}

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

/// `days` 日後の暦日で、送信時刻（19時）に設定した日時。月をまたぐ計算はこちらを使う。
private func offsetDate(_ days: Int, from base: Date, hour: Int = ReengagementReminderPolicy.deliveryHour) -> Date {
    let day = tokyo.date(byAdding: .day, value: days, to: base)!
    return tokyo.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
}

private let titles = ["shogi": "将棋", "2048": "2048", "sudoku": "ナンプレ", "go": "囲碁"]

/// テストごとに独立した `UserDefaults` の入れ物（プロセス内の他テストと状態を共有しないため）。
private func freshStore() -> ReengagementReminderStore {
    ReengagementReminderStore(defaults: UserDefaults(suiteName: "ReengagementReminderTests.\(UUID().uuidString)")!)
}

@MainActor
private func makeService(
    _ spy: SpyScheduler,
    _ env: Environment,
    store: ReengagementReminderStore = freshStore(),
    suppressed: Bool = false
) -> ReengagementReminderService {
    ReengagementReminderService(
        scheduler: spy,
        store: store,
        isEnabled: { env.enabled },
        isSuppressed: suppressed,
        reminderTitle: { env.hidden.contains($0) ? nil : titles[$0] },
        now: { env.now },
        calendar: tokyo
    )
}

private let day: TimeInterval = 24 * 60 * 60

// MARK: - 判定の規則

@Suite("再エンゲージメント通知の規則（#1193）")
struct ReengagementReminderPolicyTests {
    @Test("7日以上遊んでいない中で最もプレイ回数が多いゲームを選ぶ")
    func picksMostPlayedIdleGame() {
        let now = date(20)
        let games = [
            ReengagementCandidateInput(gameID: "shogi", plays: 50, lastPlayedAt: now.addingTimeInterval(-10 * day)),
            ReengagementCandidateInput(gameID: "2048", plays: 80, lastPlayedAt: now.addingTimeInterval(-8 * day)),
            ReengagementCandidateInput(gameID: "sudoku", plays: 100, lastPlayedAt: now.addingTimeInterval(-2 * day)),
        ]
        // sudoku は直近2日で対象外。残る shogi(50) / 2048(80) のうち最多は2048。
        #expect(ReengagementReminderPolicy.candidate(games: games, availableIDs: ["shogi", "2048", "sudoku"], now: now) == "2048")
    }

    @Test("同率はハブの並び順（availableIDs の先頭）で決める")
    func tieBreaksByHubOrder() {
        let now = date(20)
        let games = [
            ReengagementCandidateInput(gameID: "shogi", plays: 50, lastPlayedAt: now.addingTimeInterval(-10 * day)),
            ReengagementCandidateInput(gameID: "go", plays: 50, lastPlayedAt: now.addingTimeInterval(-10 * day)),
        ]
        #expect(ReengagementReminderPolicy.candidate(games: games, availableIDs: ["go", "shogi"], now: now) == "go")
        #expect(ReengagementReminderPolicy.candidate(games: games, availableIDs: ["shogi", "go"], now: now) == "shogi")
    }

    @Test("プレイ回数0・最終プレイ日時なし・ハブに無い・7日未満はいずれも対象外")
    func excludesIneligibleGames() {
        let now = date(20)
        let games = [
            ReengagementCandidateInput(gameID: "unplayed", plays: 0, lastPlayedAt: nil),
            ReengagementCandidateInput(gameID: "noDate", plays: 999, lastPlayedAt: nil),
            ReengagementCandidateInput(gameID: "hiddenFromHub", plays: 999, lastPlayedAt: now.addingTimeInterval(-30 * day)),
            ReengagementCandidateInput(gameID: "recentlyPlayed", plays: 999, lastPlayedAt: now.addingTimeInterval(-1 * day)),
        ]
        let availableIDs = ["unplayed", "noDate", "recentlyPlayed"] // hiddenFromHub をハブから除く
        #expect(ReengagementReminderPolicy.candidate(games: games, availableIDs: availableIDs, now: now) == nil)
    }

    @Test("ちょうど7日は対象、6日は対象外")
    func minimumIdleDaysIsInclusive() {
        let now = date(20)
        let sevenDaysAgo = [ReengagementCandidateInput(gameID: "shogi", plays: 1, lastPlayedAt: now.addingTimeInterval(-7 * day))]
        #expect(ReengagementReminderPolicy.candidate(games: sevenDaysAgo, availableIDs: ["shogi"], now: now) == "shogi")

        let sixDaysAgo = [ReengagementCandidateInput(gameID: "shogi", plays: 1, lastPlayedAt: now.addingTimeInterval(-6 * day))]
        #expect(ReengagementReminderPolicy.candidate(games: sixDaysAgo, availableIDs: ["shogi"], now: now) == nil)
    }

    @Test("発火時刻は最終プレイの7日後・30日後・60日後の19時")
    func fireDatesAreSevenThirtySixtyDaysAt19() {
        let lastPlayedAt = date(1, 8)
        let dates = ReengagementReminderPolicy.fireDates(lastPlayedAt: lastPlayedAt, now: date(1, 8), calendar: tokyo)
        #expect(dates == [date(8, 19), date(31, 19), tokyo.date(byAdding: .day, value: 60, to: date(1, 19))!])
    }

    @Test("既に過去に落ちる発火時刻は含めない")
    func pastFireDatesAreExcluded() {
        let lastPlayedAt = date(1, 8)
        // 40日後に評価した場合、7日後・30日後は既に過去。
        let now = lastPlayedAt.addingTimeInterval(40 * day)
        let dates = ReengagementReminderPolicy.fireDates(lastPlayedAt: lastPlayedAt, now: now, calendar: tokyo)
        #expect(dates.count == 1)
        #expect(dates.first == tokyo.date(byAdding: .day, value: 60, to: date(1, 19))!)
    }

    @Test("新規スレッドの追加は直近の追加からちょうど3日で解禁、2日は不可")
    func newThreadCooldown() {
        let lastAdded = date(1, 8)
        #expect(!ReengagementReminderPolicy.canAddNewThread(lastThreadAddedAt: lastAdded, now: date(3, 8), calendar: tokyo))
        #expect(ReengagementReminderPolicy.canAddNewThread(lastThreadAddedAt: lastAdded, now: date(4, 8), calendar: tokyo))
        #expect(ReengagementReminderPolicy.canAddNewThread(lastThreadAddedAt: nil, now: date(1, 8), calendar: tokyo),
                "一度も追加していなければ常に追加できる")
    }

    @Test("60日後通知は発火予定時刻+24時間経つまでは未反応と判定しない")
    func unresponsiveRequires24HoursAfterSixtyDayFire() {
        let lastPlayedAt = date(1, 8)
        let fireDate = ReengagementReminderPolicy.sixtyDayFireDate(lastPlayedAt: lastPlayedAt, calendar: tokyo)!
        #expect(fireDate == tokyo.date(byAdding: .day, value: 60, to: date(1, 19))!)
        #expect(!ReengagementReminderPolicy.isUnresponsiveAfterSixtyDays(fireDate: fireDate, now: fireDate.addingTimeInterval(23 * 60 * 60)))
        #expect(ReengagementReminderPolicy.isUnresponsiveAfterSixtyDays(fireDate: fireDate, now: fireDate.addingTimeInterval(24 * 60 * 60)))
    }

    @Test("同じ暦日に重なったら日数の大きい方だけ残る")
    func resolvingCollisionsKeepsLargerOffset() {
        let sameDay = date(10, 19)
        let otherDay = date(20, 19)
        let threads: [String: [(days: Int, date: Date)]] = [
            "shogi": [(30, sameDay), (60, otherDay)],
            "go": [(7, sameDay)],
        ]
        let resolved = ReengagementReminderPolicy.resolvingCollisions(threads: threads, calendar: tokyo)
        #expect(resolved["shogi"] == [sameDay, otherDay], "衝突しなかった shogi の 60 日後はそのまま残る")
        #expect(resolved["go"] == nil, "go の 7 日後は shogi の 30 日後に負けてスキップされる")
    }
}

// MARK: - サービスの挙動

@Suite("再エンゲージメント通知サービス（#1193）")
@MainActor
struct ReengagementReminderServiceTests {
    @Test("対象があれば7・30・60日後を予約する")
    func schedulesForCandidate() async {
        let spy = SpyScheduler()
        // ちょうど7日ぶり（対象になる下限）で判定すると、7・30・60日後がすべて未来に残る。
        let env = Environment(now: date(8, 8))
        let service = makeService(spy, env)
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]

        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        #expect(spy.scheduled["shogi"]?.count == 3)
        #expect(spy.contents["shogi"]?.title == "「将棋」、久しぶりに遊んでみませんか？")
    }

    @Test("複数ゲームのスレッドが同時にアクティブになれ、新しい対象が選ばれても既存スレッドはキャンセルされない")
    func multipleThreadsCanBeActiveSimultaneously() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(8, 8))
        let service = makeService(spy, env)

        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))],
            availableIDs: ["shogi"]
        )
        await service.pendingWork?.value
        #expect(spy.scheduled["shogi"] != nil)

        // クールダウン（3日）が明けた4日後、別のゲームが新しい対象として選ばれる。
        env.now = date(12, 8)
        service.applicationDidEnterBackground(
            games: [
                ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8)),
                ReengagementCandidateInput(gameID: "go", plays: 999, lastPlayedAt: date(4, 8)),
            ],
            availableIDs: ["shogi", "go"]
        )
        await service.pendingWork?.value

        #expect(spy.cancelledGameIDs.isEmpty, "既存のアクティブなスレッド（shogi）がキャンセルされている")
        #expect(spy.scheduled["shogi"] != nil, "既存スレッドの予約が消えている")
        #expect(spy.scheduled["go"] != nil, "新しい対象が予約されていない")
    }

    @Test("既にアクティブなスレッドと同じゲームが再度選ばれても、二重登録しない")
    func reselectingActiveThreadIsNoop() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(8, 8))
        let service = makeService(spy, env)
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]

        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value
        let firstDates = spy.scheduled["shogi"]

        env.now = date(12, 8)
        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        #expect(spy.explicitRequests == 0, "既にアクティブなスレッドの再選定で許諾を求め直している")
        #expect(spy.scheduled["shogi"] == firstDates, "同じスレッドが組み直されて発火予定が変わっている")
    }

    @Test("直近のスレッド追加から3日以内は、新規対象が生まれても新しいスレッドを追加しない")
    func newThreadCooldownBlocksAddition() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(8, 8))
        let service = makeService(spy, env)

        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))],
            availableIDs: ["shogi"]
        )
        await service.pendingWork?.value
        #expect(spy.scheduled["shogi"] != nil)

        // クールダウン中（2日後）に新しい対象が現れても見送る。
        env.now = date(10, 8)
        service.applicationDidEnterBackground(
            games: [
                ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8)),
                ReengagementCandidateInput(gameID: "go", plays: 999, lastPlayedAt: date(1, 8)),
            ],
            availableIDs: ["shogi", "go"]
        )
        await service.pendingWork?.value
        #expect(spy.scheduled["go"] == nil, "クールダウン中に新しいスレッドが追加されている")

        // クールダウンが明けた（4日後）ら追加できる。
        env.now = date(12, 8)
        service.applicationDidEnterBackground(
            games: [
                ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8)),
                ReengagementCandidateInput(gameID: "go", plays: 999, lastPlayedAt: date(1, 8)),
            ],
            availableIDs: ["shogi", "go"]
        )
        await service.pendingWork?.value
        #expect(spy.scheduled["go"] != nil, "クールダウン明けに新しいスレッドが追加されていない")
    }

    @Test("同日に複数のスレッドの発火日が重なったら、日数が大きい方だけ送られ小さい方はその回だけスキップされる")
    func collisionsOnSameDaySkipSmallerOffset() async {
        let spy = SpyScheduler()
        let aBaseline = date(1, 8)
        let env = Environment(now: date(8, 8))
        let service = makeService(spy, env)

        // shogi: 9/1 起点。30日後は shogi の 30 日後（10/1 19時）。
        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: aBaseline)],
            availableIDs: ["shogi"]
        )
        await service.pendingWork?.value
        let shogiThirtyDay = offsetDate(30, from: aBaseline)

        // go: 「go の7日後」が「shogi の30日後」と同じ暦日になるよう起点を選ぶ（衝突を作る）。
        let bBaseline = tokyo.date(byAdding: .day, value: -7, to: tokyo.startOfDay(for: shogiThirtyDay))!
        let bBaselineAtMorning = tokyo.date(bySettingHour: 8, minute: 0, second: 0, of: bBaseline)!
        env.now = tokyo.date(byAdding: .day, value: 7, to: bBaselineAtMorning)! // go がちょうど7日idleになる瞬間

        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "go", plays: 999, lastPlayedAt: bBaselineAtMorning)],
            availableIDs: ["go"]
        )
        await service.pendingWork?.value

        let goSevenDay = offsetDate(7, from: bBaselineAtMorning)
        #expect(tokyo.isDate(goSevenDay, inSameDayAs: shogiThirtyDay), "テストの前提（同じ暦日に重なる）が崩れている")

        #expect(spy.scheduled["shogi"]?.contains(shogiThirtyDay) == true, "衝突に勝った shogi の30日後が消えている")
        #expect(spy.scheduled["go"]?.contains(goSevenDay) != true, "衝突に負けた go の7日後がスキップされていない")
    }

    @Test("60日後通知が発火して24時間経っても未反応なら、ユーザー全体でこの機能を永続停止する")
    func permanentlyStopsAfterSixtyDaySilence() async {
        let spy = SpyScheduler()
        let baseline = date(1, 8)
        let env = Environment(now: date(8, 8))
        let store = freshStore()
        let service = makeService(spy, env, store: store)

        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: baseline)],
            availableIDs: ["shogi"]
        )
        await service.pendingWork?.value
        #expect(spy.scheduled["shogi"] != nil)

        // 60日後の発火予定時刻から24時間経ったが、lastPlayedAt は変わっていない（未反応）。
        let sixtyDayFire = ReengagementReminderPolicy.sixtyDayFireDate(lastPlayedAt: baseline, calendar: tokyo)!
        env.now = sixtyDayFire.addingTimeInterval(24 * 60 * 60)
        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: baseline)],
            availableIDs: ["shogi"]
        )
        await service.pendingWork?.value

        #expect(store.isPermanentlyStopped)
        #expect(spy.cancelAllCount == 1)
        #expect(store.activeThreads.isEmpty)

        // 永続停止後は、別のゲームが対象になっても一切判定しない。
        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "go", plays: 999, lastPlayedAt: date(1, 8))],
            availableIDs: ["go"]
        )
        await service.pendingWork?.value
        #expect(spy.scheduled.isEmpty, "永続停止後に新しいスレッドが追加されている")
    }

    @Test("60日後通知の発火予定時刻から24時間経つ前は、未反応と判定せず永続停止しない")
    func doesNotStopBeforeTwentyFourHoursPassed() async {
        let spy = SpyScheduler()
        let baseline = date(1, 8)
        let env = Environment(now: date(8, 8))
        let store = freshStore()
        let service = makeService(spy, env, store: store)

        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: baseline)],
            availableIDs: ["shogi"]
        )
        await service.pendingWork?.value

        let sixtyDayFire = ReengagementReminderPolicy.sixtyDayFireDate(lastPlayedAt: baseline, calendar: tokyo)!
        env.now = sixtyDayFire.addingTimeInterval(23 * 60 * 60)
        service.applicationDidEnterBackground(
            games: [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: baseline)],
            availableIDs: ["shogi"]
        )
        await service.pendingWork?.value

        #expect(!store.isPermanentlyStopped)
        #expect(spy.cancelAllCount == 0)
    }

    @Test("そのゲームを開くと取り消す")
    func openingCancels() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(20))
        let service = makeService(spy, env)
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]
        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        service.gameDidOpen(gameID: "shogi")
        #expect(spy.cancelledGameIDs == ["shogi"])
    }

    @Test("予約の無いゲームを開いても何も起きない")
    func openingUnscheduledGameIsNoop() {
        let spy = SpyScheduler()
        let service = makeService(spy, Environment(now: date(20)))
        service.gameDidOpen(gameID: "shogi")
        #expect(spy.cancelledGameIDs == ["shogi"], "識別子はゲーム単位で決まるので取り消し自体は呼ばれる")
        #expect(spy.scheduled.isEmpty)
    }

    @Test("許諾が未決定なら、標準の許可ダイアログ（明示的な許可）を求めてから予約する")
    func requestsExplicitAuthorizationWhenNotDetermined() async {
        let spy = SpyScheduler(status: .notDetermined, statusAfterRequest: .authorized)
        let service = makeService(spy, Environment(now: date(20)))
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]

        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        #expect(spy.explicitRequests == 1)
        #expect(spy.scheduled["shogi"] != nil)
    }

    @Test("許可が得られない・拒否されているなら予約しない")
    func doesNotScheduleWithoutPermission() async {
        let denied = SpyScheduler(status: .denied)
        let service = makeService(denied, Environment(now: date(20)))
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]

        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        #expect(denied.scheduled.isEmpty)
        #expect(denied.explicitRequests == 0, "拒否した人に許可を求め直している")
    }

    @Test("設定がオフなら判定せず、オフにしたら予約済みもすべて取り消す")
    func settingTurnsRemindersOff() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(20))
        let service = makeService(spy, env)
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]
        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value
        #expect(spy.scheduled["shogi"] != nil)

        env.enabled = false
        service.cancelAll()
        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        #expect(spy.cancelAllCount == 1)
        #expect(spy.scheduled.isEmpty)
    }

    @Test("撮影モード・DEBUG ビルドでは判定も許諾の要求もしない")
    func suppressedBuildsDoNothing() async {
        let spy = SpyScheduler(status: .notDetermined)
        let service = makeService(spy, Environment(now: date(20)), suppressed: true)
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]

        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        #expect(spy.scheduled.isEmpty)
        #expect(spy.explicitRequests == 0)
    }

    @Test("設定で非表示にしたゲームは対象にならない")
    func hiddenGamesAreIneligible() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(20))
        env.hidden = ["shogi"]
        let service = makeService(spy, env)
        let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]

        service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
        await service.pendingWork?.value

        #expect(spy.scheduled.isEmpty)
    }

    @Test("許諾の問い合わせを待つ間に対象が無くなった・設定を切られたなら予約しない")
    func stateChangesDuringQueryWin() async throws {
        for change in ["retarget", "disable"] {
            let spy = SpyScheduler()
            let env = Environment(now: date(20))
            let service = makeService(spy, env)
            spy.holdsAuthorization = true
            let games = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]

            service.applicationDidEnterBackground(games: games, availableIDs: ["shogi"])
            var spins = 0
            while spy.heldCount == 0 {
                await Task.yield()
                spins += 1
                try #require(spins < 10_000, "予約の処理が問い合わせに到達しない")
            }

            switch change {
            case "retarget":
                let none = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: env.now)]
                service.applicationDidEnterBackground(games: none, availableIDs: ["shogi"])
            default:
                env.enabled = false
                service.cancelAll()
            }
            spy.releaseAuthorization()
            await service.pendingWork?.value

            #expect(spy.scheduled.isEmpty, "\(change) の後に古い予約が入った")
        }
    }

    @Test("通知のタップは対象外のゲームを無視する")
    func tapIgnoresIneligibleGames() {
        let env = Environment(now: date(20))
        env.hidden = ["2048"]
        let service = makeService(SpyScheduler(), env)

        service.notificationTapped(gameID: "2048")
        #expect(service.requestedGameID == nil, "非表示にしたゲームを通知から開いた")

        service.notificationTapped(gameID: "shogi")
        #expect(service.requestedGameID == "shogi")
    }
}

// MARK: - 永続状態

@Suite("再エンゲージメント通知の永続状態（#1229）")
struct ReengagementReminderStoreTests {
    @Test("アクティブなスレッド・最終追加日時・永続停止フラグを保存・復元できる")
    func persistsState() {
        let store = freshStore()
        #expect(store.activeThreads.isEmpty)
        #expect(store.lastThreadAddedAt == nil)
        #expect(!store.isPermanentlyStopped)

        let now = date(1, 8)
        store.activeThreads = ["shogi": now, "go": date(4, 8)]
        store.lastThreadAddedAt = now
        store.isPermanentlyStopped = true

        #expect(store.activeThreads == ["shogi": now, "go": date(4, 8)])
        #expect(store.lastThreadAddedAt == now)
        #expect(store.isPermanentlyStopped)
    }
}

// MARK: - PlayLog の集計

@Suite("再エンゲージメント通知向けの通算プレイ回数（#1193）")
@MainActor
struct PlayLogTotalPlaysTests {
    @Test("区分があるゲームは合算する")
    func sumsAcrossVariants() {
        let defaults = UserDefaults(suiteName: "ReengagementReminderTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description) }
        let log = PlayLog(defaults: defaults)

        log.recordResult(gameID: "minesweeper", outcome: .win, score: GameScore(variant: "easy"))
        log.recordResult(gameID: "minesweeper", outcome: .win, score: GameScore(variant: "easy"))
        log.recordResult(gameID: "minesweeper", outcome: .loss, score: GameScore(variant: "hard"))
        log.recordResult(gameID: "shogi", outcome: .win, score: GameScore())

        #expect(log.totalPlaysByGame["minesweeper"] == 3)
        #expect(log.totalPlaysByGame["shogi"] == 1)
        #expect(log.totalPlaysByGame["untouched"] == nil)
    }
}
