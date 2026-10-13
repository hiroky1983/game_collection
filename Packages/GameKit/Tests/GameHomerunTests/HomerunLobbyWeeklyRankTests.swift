import Testing
import Foundation
import Core
import CoreTestSupport
import HomerunCore
@testable import GameHomerun
import GameKitTestSupport

/// 打席前の今週の順位（#2216）: 状態ごとの文言（日本語・英語）・週の切り替わり・読み込みの進行。
@Suite("柵越えおじさんの打席前の今週の順位")
@MainActor
struct HomerunLobbyWeeklyRankTests {
    private typealias State = HomerunModel.WeeklyState

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private static func date(_ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    /// 10/5（月）0:00 〜 10/12（月）0:00 の回。
    private static let weekStart = date(5)
    private static let weekEnd = date(12)

    private func board(myRank: Int?, participants: Int, start: Date? = weekStart, end: Date? = weekEnd) -> GameCenterBoard {
        let rows = myRank.map { [GameCenterBoardRow(id: "me", name: "me", score: 1200, rank: $0, isMe: true)] } ?? []
        return GameCenterBoard(rows: rows, myRank: myRank, myScore: myRank.map { _ in 1200 }, participants: participants,
                               start: start, end: end, lastWeekRank: nil)
    }

    // MARK: 文言

    @Test("各状態の文言（日本語）。表記は結果画面・ランキングページの既存の文言に合わせる")
    func japaneseDetail() {
        func detail(_ state: State) -> String? { HomerunLobbyRankText.detail(for: state, language: .japanese) }
        #expect(detail(.off) == nil)
        #expect(detail(.signedOut) == "Game Center に登録すると見られます")
        #expect(detail(.loading) == "今週の順位を読み込んでいます")
        #expect(detail(.failed) == "ランキングを取得できませんでした")
        #expect(detail(.ready(before: nil, after: board(myRank: nil, participants: 120))) == "今週はまだ記録がありません")
        #expect(detail(.ready(before: nil, after: board(myRank: 12, participants: 340))) == "12位 / 340人")
        // 人数が取れない（0・順位より少ない）ときは順位だけ。
        #expect(detail(.ready(before: nil, after: board(myRank: 12, participants: 0))) == "12位")
        #expect(detail(.ready(before: nil, after: board(myRank: 12, participants: 5))) == "12位")
        #expect(detail(.ready(before: nil, after: board(myRank: 1, participants: 1))) == "1位 / 1人")
    }

    @Test("各状態の文言（英語）")
    func englishDetail() {
        func detail(_ state: State) -> String? { HomerunLobbyRankText.detail(for: state, language: .english) }
        #expect(detail(.off) == nil)
        #expect(detail(.signedOut) == "Sign in to see where you rank")
        #expect(detail(.loading) == "Loading this week's rankings")
        #expect(detail(.failed) == "Couldn't load the rankings")
        #expect(detail(.ready(before: nil, after: board(myRank: nil, participants: 120))) == "No score yet this week")
        #expect(detail(.ready(before: nil, after: board(myRank: 12, participants: 340))) == "#12 of 340")
        #expect(detail(.ready(before: nil, after: board(myRank: 12, participants: 0))) == "#12")
    }

    // MARK: 週の切り替わり

    @Test("今週の表はそのまま。終わりが取れない表も今週のものとして扱う")
    func currentWeekKeepsThisWeek() {
        let b = board(myRank: 3, participants: 10)
        #expect(HomerunWeekly.currentWeek(b, now: Self.date(11, hour: 23, minute: 59)) == b)
        #expect(!HomerunWeekly.isPastWeek(b, now: Self.date(11, hour: 23, minute: 59)))
        let noEnd = board(myRank: 3, participants: 10, start: nil, end: nil)
        #expect(HomerunWeekly.currentWeek(noEnd, now: Self.date(20)) == noEnd)
    }

    @Test("切り替わった直後（月曜 0:00 ちょうど）に前週の表が残っていたら、前週の順位は出さず次の回の空の表にする")
    func currentWeekDropsLastWeek() {
        let last = board(myRank: 3, participants: 10)
        let now = Self.date(12)
        #expect(HomerunWeekly.isPastWeek(last, now: now))
        let current = HomerunWeekly.currentWeek(last, now: now)
        #expect(current.myRank == nil)
        #expect(current.myScore == nil)
        #expect(current.rows.isEmpty)
        #expect(current.participants == 0)
        #expect(current.start == Self.date(12))
        #expect(current.end == Self.date(19))
        #expect(current.lastWeekRank == nil)
        #expect(HomerunLobbyRankText.detail(for: .ready(before: nil, after: current), language: .japanese) == "今週はまだ記録がありません")
    }

    @Test("何週ぶんも空いていたら、いまを含む回まで進め、先週の順位は出さない")
    func currentWeekSkipsSeveralWeeks() {
        let current = HomerunWeekly.currentWeek(board(myRank: 3, participants: 10), now: Self.date(20, hour: 9))
        #expect(current.start == Self.date(19))
        #expect(current.end == Self.date(26))
        #expect(current.lastWeekRank == nil)
    }

    // MARK: 読み込みの進行（Game Center は差し替え）

    @MainActor
    private final class StubService: GameCenterService {
        var boards: [GameCenterBoard?] = []
        var loads = 0
        var lastIncludesLastWeek: Bool?
        func submit(_ score: GameCenterScore) {}
        func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
        func loadBoard(leaderboardID: String, topCount: Int, includesLastWeek: Bool) async -> GameCenterBoard? {
            defer { loads += 1 }
            lastIncludesLastWeek = includesLastWeek
            return loads < boards.count ? boards[loads] : nil
        }
    }

    private func makeModel(_ stub: StubService, signedIn: Bool = true, leaderboardID: String? = "weekly.test") -> HomerunModel {
        let suite = "asobiba.homerun.lobbyweekly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: SpyFeedbackService(),
            gameCenter: GameCenterReporter(service: stub, allowedGameIDs: [HomerunModel.gameID], isAvailable: { signedIn })
        )
        return HomerunModel(services: services, defaults: defaults, weeklyLeaderboardID: leaderboardID)
    }

    @Test("読み込み中 → 読めたら ready。決着のときと同じ読み込み（先週の順位つき）を使う")
    func readyFlow() async {
        let stub = StubService()
        let b = board(myRank: 12, participants: 340, start: Date().addingTimeInterval(-86_400), end: Date().addingTimeInterval(86_400))
        stub.boards = [b]
        let model = makeModel(stub)
        model.refreshLobbyWeekly()
        #expect(model.lobbyWeekly == .loading)
        await model.lobbyWeeklyTask?.value
        #expect(model.lobbyWeekly == .ready(before: nil, after: b))
        #expect(stub.lastIncludesLastWeek == true)
        #expect(HomerunLobbyRankText.detail(for: model.lobbyWeeklyState(now: Date()), language: .japanese) == "12位 / 340人")
        // 決着の読み込み（`weekly`）には触らない。
        #expect(model.weekly == .off)
    }

    @Test("読み直しのあいだも今週の順位は出し続ける（ちらつかない）")
    func keepsReadyWhileReloading() async {
        let stub = StubService()
        let b = board(myRank: 12, participants: 340, start: Date().addingTimeInterval(-86_400), end: Date().addingTimeInterval(86_400))
        stub.boards = [b, b]
        let model = makeModel(stub)
        model.refreshLobbyWeekly()
        await model.lobbyWeeklyTask?.value
        model.refreshLobbyWeekly()
        #expect(model.lobbyWeekly == .ready(before: nil, after: b))
        await model.lobbyWeeklyTask?.value
        #expect(stub.loads == 2)
    }

    @Test("今週の順位を出しているときに読み直しが失敗しても、出していた順位は消さない")
    func keepsReadyWhenReloadFails() async {
        let stub = StubService()
        let b = board(myRank: 12, participants: 340, start: Date().addingTimeInterval(-86_400), end: Date().addingTimeInterval(86_400))
        stub.boards = [b, nil]
        let model = makeModel(stub)
        model.refreshLobbyWeekly()
        await model.lobbyWeeklyTask?.value
        model.refreshLobbyWeekly()
        await model.lobbyWeeklyTask?.value
        #expect(stub.loads == 2)
        #expect(model.lobbyWeekly == .ready(before: nil, after: b))
    }

    @Test("前週の表が残っている状態で読み直すときは読み込み中に戻す。表示はその間も前週の順位を出さない")
    func staleReloadShowsLoading() async {
        let stub = StubService()
        let past = board(myRank: 3, participants: 10, start: Date().addingTimeInterval(-8 * 86_400), end: Date().addingTimeInterval(-86_400))
        stub.boards = [past]
        let model = makeModel(stub)
        model.refreshLobbyWeekly()
        await model.lobbyWeeklyTask?.value
        // Game Center が前の回を返しても、出すときは今週の空の表にする。
        #expect(HomerunLobbyRankText.detail(for: model.lobbyWeeklyState(now: Date()), language: .japanese) == "今週はまだ記録がありません")
        model.refreshLobbyWeekly()
        #expect(model.lobbyWeekly == .loading)
    }

    @Test("読めなければ failed、未サインインは signedOut、送り先が未作成なら off（どちらも読みに行かない）")
    func failedSignedOutOff() async {
        let stub = StubService()
        let model = makeModel(stub)
        model.refreshLobbyWeekly()
        await model.lobbyWeeklyTask?.value
        #expect(model.lobbyWeekly == .failed)

        let other = StubService()
        let signedOut = makeModel(other, signedIn: false)
        signedOut.refreshLobbyWeekly()
        #expect(signedOut.lobbyWeekly == .signedOut)
        let off = makeModel(other, leaderboardID: nil)
        off.refreshLobbyWeekly()
        #expect(off.lobbyWeekly == .off)
        #expect(other.loads == 0)
    }
}
