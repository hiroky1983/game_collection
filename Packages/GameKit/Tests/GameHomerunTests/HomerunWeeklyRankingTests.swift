import Testing
import Foundation
import Core
import CoreTestSupport
import HomerunCore
@testable import GameHomerun
import GameKitTestSupport

/// 週間ランキング（#1792）: 送る値・入れ替えアニメの計画・文言・送信と読み込みの進行。
@Suite("柵越えおじさんの週間ランキング")
@MainActor
struct HomerunWeeklyRankingTests {
    private static let moon = GameCenterLeaderboard.homerunWeeklyMoonMeters
    private let justHomer = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 8)

    // MARK: 送る値

    @Test("月まで飛んだ打球は 384,400 km（m で 384,400,000）として数え、ふつうの球は切り捨てた m")
    func scoreCountsMoonAsFullDistance() {
        var plain = HomerunChallenge()
        let ball = plain.swing(justHomer)
        #expect(HomerunWeekly.score(for: plain) == Int(ball?.distance ?? -1))

        var moons = HomerunChallenge(forcesMoon: true)
        moons.swing(justHomer)
        #expect(HomerunWeekly.score(for: moons) == Self.moon)
        moons.swing(justHomer)
        #expect(moons.isMoonBroken)
        #expect(HomerunWeekly.score(for: moons) == Self.moon * 2)
        // 常設の記録は従来どおり 180 m で数える。
        #expect(moons.totalDistance < 1000)
    }

    @Test("送る値の上限は月 2 回 + 180 m × 8 球 = 768,801,440 m")
    func maxScore() {
        #expect(GameCenterLeaderboard.homerunWeeklyMaxMeters == 768_801_440)
    }

    // MARK: 入れ替えアニメの計画

    private func row(_ id: String, _ score: Int, rank: Int, me: Bool = false) -> GameCenterBoardRow {
        GameCenterBoardRow(id: id, name: id, score: score, rank: rank, isMe: me)
    }

    private func board(_ rows: [GameCenterBoardRow], myRank: Int?, myScore: Int?) -> GameCenterBoard {
        GameCenterBoard(rows: rows, myRank: myRank, myScore: myScore, participants: rows.count, start: nil, end: nil, lastWeekRank: nil)
    }

    private var after: GameCenterBoard {
        board([row("a", 1462, rank: 1), row("b", 1398, rank: 2), row("c", 1244, rank: 3),
               row("me", 1206, rank: 4, me: true), row("d", 1168, rank: 5), row("e", 1120, rank: 6),
               row("f", 1002, rank: 7)], myRank: 4, myScore: 1206)
    }

    @Test("記録が伸びて順位が上がるとき、自分は前の記録の位置から始まり目的の位置へ上がる")
    func motionMovesMeUp() throws {
        let before = board([], myRank: 7, myScore: 980)
        let motion = try #require(HomerunRankingPlan.motion(before: before, after: after))
        #expect(motion.entries.map(\.id) == ["a", "b", "c", "d", "e", "f", "me"])
        #expect(motion.entries.last?.meters == 980)
        #expect(motion.from == 6)
        #expect(motion.to == 3)
        #expect(motion.newMeters == 1206)
    }

    @Test("今週はじめての記録は最下位から数え上げる")
    func motionForFirstRecord() throws {
        let motion = try #require(HomerunRankingPlan.motion(before: board([], myRank: nil, myScore: nil), after: after))
        #expect(motion.entries.last?.isMe == true)
        #expect(motion.entries.last?.meters == 0)
        #expect(motion.from == 6)
        #expect(motion.to == 3)
    }

    @Test("順位が変わらなくても記録が伸びたら数え上げだけ流す（from == to）。目的の位置は Game Center の順位に従う")
    func motionCountUpOnly() throws {
        let motion = try #require(HomerunRankingPlan.motion(before: board([], myRank: 4, myScore: 1200), after: after))
        #expect(motion.from == 3 && motion.to == 3)
        #expect(motion.entries.map(\.id) == ["a", "b", "c", "me", "d", "e", "f"])
        // 同点で Game Center が自分を後ろに並べたときも、位置は Game Center の並び（rows）のとおり。
        let tied = board([row("a", 1462, rank: 1), row("t", 1206, rank: 2), row("me", 1206, rank: 3, me: true)], myRank: 3, myScore: 1206)
        #expect(HomerunRankingPlan.motion(before: board([], myRank: nil, myScore: nil), after: tied)?.to == 2)
    }

    @Test("記録が伸びない・送る前を読めない・上位の外のときはアニメ無し")
    func motionAbsent() {
        #expect(HomerunRankingPlan.motion(before: board([], myRank: 4, myScore: 1206), after: after) == nil)
        #expect(HomerunRankingPlan.motion(before: nil, after: after) == nil)
        let outside = board([row("a", 5000, rank: 1)], myRank: 40, myScore: 100)
        #expect(HomerunRankingPlan.motion(before: board([], myRank: nil, myScore: nil), after: outside) == nil)
    }

    @Test("上位の外の自分は一覧の末尾に自分の順位で足す")
    func entriesAppendsMeOutsideTop() {
        let outside = board([row("a", 5000, rank: 1)], myRank: 40, myScore: 100)
        let entries = HomerunRankingPlan.entries(of: outside)
        #expect(entries.count == 2)
        #expect(entries.last?.isMe == true)
        #expect(entries.last?.rank == 40)
    }

    // MARK: 文言

    @Test("距離は 100 万 m 未満は m、以上は km（切り捨て・桁区切り）")
    func distanceText() {
        #expect(HomerunRankingText.distance(1_206) == "1,206 m")
        #expect(HomerunRankingText.distance(999_999) == "999,999 m")
        #expect(HomerunRankingText.distance(384_401_440) == "384,401 km")
    }

    @Test("月の補足は 0 回なし・1 回「月まで飛んだ」・2 回「月を割った」")
    func moonNote() {
        func note(_ m: Int) -> String? { HomerunRankingText.moonNote(HomerunRankEntry(id: "x", name: "x", meters: m, rank: 1, isMe: false)) }
        #expect(note(1_000) == nil)
        #expect(note(Self.moon + 1_440) == "月まで飛んだ")
        #expect(note(Self.moon * 2) == "月を割った")
    }

    @Test("あとの距離は上の人を 1 m 上回る値")
    func gapText() {
        #expect(HomerunRankingText.gap(aboveMeters: 1_244, myMeters: 1_206, aboveRank: 3) == "あと 39 m で 3位")
    }

    @Test("週の範囲は始まりと終わりの前日・残り日数")
    func weekRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
        #expect(HomerunRankingText.weekRange(start: start, end: end, now: now, calendar: calendar) == "10/5（月） 〜 10/11（日）　あと 3 日")
        let last = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
        #expect(HomerunRankingText.weekRange(start: start, end: end, now: last, calendar: calendar)?.hasSuffix("今日まで") == true)
        #expect(HomerunRankingText.weekRange(start: nil, end: end, now: now, calendar: calendar) == nil)
    }

    // MARK: 送信と読み込みの進行

    @MainActor
    private final class SpyService: GameCenterService {
        var submitted: [GameCenterScore] = []
        var boards: [GameCenterBoard?] = []
        var loads = 0
        func submit(_ score: GameCenterScore) {}
        func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
        func submitAndWait(_ score: GameCenterScore) async -> Bool { submitted.append(score); return true }
        func loadBoard(leaderboardID: String, topCount: Int, includesLastWeek: Bool) async -> GameCenterBoard? {
            defer { loads += 1 }
            return loads < boards.count ? boards[loads] : nil
        }
    }

    private func makeModel(_ spy: SpyService, signedIn: Bool = true, leaderboardID: String? = "weekly.test") -> HomerunModel {
        let suite = "asobiba.homerun.weekly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: SpyFeedbackService(),
            gameCenter: GameCenterReporter(service: spy, allowedGameIDs: [HomerunModel.gameID], isAvailable: { signedIn })
        )
        return HomerunModel(services: services, defaults: defaults, weeklyLeaderboardID: leaderboardID)
    }

    private var finished: HomerunChallenge {
        var c = HomerunChallenge(forcesMoon: true)
        c.swing(justHomer)
        return c
    }

    @Test("送る前の順位表 → 送信 → 送った後の順位表の順に読み、ready になる")
    func readyFlow() async throws {
        let spy = SpyService()
        spy.boards = [board([], myRank: 7, myScore: 980), after]
        let model = makeModel(spy)
        model.beginWeekly(for: finished)
        #expect(model.weekly == .loading)
        await model.weeklyTask?.value
        #expect(spy.submitted == [GameCenterScore(leaderboardID: "weekly.test", value: Self.moon)])
        guard case .ready(let before, let after) = model.weekly else { Issue.record("ready ではない: \(model.weekly)"); return }
        #expect(before?.myScore == 980)
        #expect(after.myRank == 4)
        #expect(model.weekly.showsAfterFinale)
    }

    @Test("順位表を読めなければ failed（それでも結果ページの前にページは挟む）")
    func failedFlow() async {
        let spy = SpyService()
        let model = makeModel(spy)
        model.beginWeekly(for: finished)
        await model.weeklyTask?.value
        #expect(model.weekly == .failed)
        #expect(model.weekly.showsAfterFinale)
    }

    @Test("未サインインは signedOut（何も送らず挟まない）、送り先が未作成なら off")
    func offAndSignedOut() {
        let spy = SpyService()
        let signedOut = makeModel(spy, signedIn: false)
        signedOut.beginWeekly(for: finished)
        #expect(signedOut.weekly == .signedOut)
        #expect(!signedOut.weekly.showsAfterFinale)
        let off = makeModel(spy, leaderboardID: nil)
        off.beginWeekly(for: finished)
        #expect(off.weekly == .off)
        #expect(spy.submitted.isEmpty && spy.loads == 0)
    }

    @Test("出荷時点では送り先が未作成で、ランキングは出ない")
    func shippedDefaultIsOff() {
        #expect(GameCenterLeaderboard.homerunWeekly == nil)
    }
}
