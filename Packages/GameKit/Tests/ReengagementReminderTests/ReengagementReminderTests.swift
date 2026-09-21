import Foundation
import Testing
import Core

// MARK: - テスト用の部品

/// 予約先のスパイ。実装（`UserNotificationReengagementScheduler`）と同じく、対象は常に高々1件。
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

    func scheduledGameID() async -> String? {
        scheduled.keys.first
    }

    func schedule(gameID: String, fireDates: [Date], title: String, body: String) async {
        scheduled[gameID] = fireDates
        contents[gameID] = (title, body)
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

private let titles = ["shogi": "将棋", "2048": "2048", "sudoku": "ナンプレ", "go": "囲碁"]

@MainActor
private func makeService(
    _ spy: SpyScheduler,
    _ env: Environment,
    suppressed: Bool = false
) -> ReengagementReminderService {
    ReengagementReminderService(
        scheduler: spy,
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

    @Test("対象が無ければ何も予約せず、前回の対象があれば取り消す")
    func cancelsWhenNoCandidate() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(20))
        let service = makeService(spy, env)
        let idle = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]
        service.applicationDidEnterBackground(games: idle, availableIDs: ["shogi"])
        await service.pendingWork?.value
        #expect(spy.scheduled["shogi"] != nil)

        // 次の背景遷移までに遊んで対象で無くなった。
        let none = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: env.now)]
        service.applicationDidEnterBackground(games: none, availableIDs: ["shogi"])
        await service.pendingWork?.value
        #expect(spy.scheduled.isEmpty)
        #expect(spy.cancelledGameIDs == ["shogi"])
    }

    @Test("対象が別のゲームに変わったら、古い対象を取り消して置き換える")
    func replacesWhenTargetChanges() async {
        let spy = SpyScheduler()
        let env = Environment(now: date(20))
        let service = makeService(spy, env)
        let first = [ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8))]
        service.applicationDidEnterBackground(games: first, availableIDs: ["shogi"])
        await service.pendingWork?.value
        #expect(spy.scheduled.keys.contains("shogi"))

        let second = [
            ReengagementCandidateInput(gameID: "shogi", plays: 10, lastPlayedAt: date(1, 8)),
            ReengagementCandidateInput(gameID: "2048", plays: 999, lastPlayedAt: date(1, 8)),
        ]
        service.applicationDidEnterBackground(games: second, availableIDs: ["shogi", "2048"])
        await service.pendingWork?.value

        #expect(spy.cancelledGameIDs == ["shogi"])
        #expect(spy.scheduled.keys.contains("2048"))
        #expect(!spy.scheduled.keys.contains("shogi"))
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
