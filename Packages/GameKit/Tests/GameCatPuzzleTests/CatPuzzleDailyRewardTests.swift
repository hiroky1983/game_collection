import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// 前日のデイリーランキング 1〜3 位に渡す特典（#3256）。
@Suite("おじさんちのねこさがしのランキング特典（#3256）")
@MainActor
struct CatPuzzleDailyRewardTests {

    private func jst(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "asobiba.catpuzzle.dailyreward.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func make(_ name: String, now: Date, defaults: UserDefaults? = nil)
        -> (model: CatPuzzleModel, spy: SpyAnalyticsService, defaults: UserDefaults) {
        let defaults = defaults ?? makeDefaults(name)
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: [CatPuzzleModel.gameID]))
        let model = CatPuzzleModel(services: services, puzzle: CatPuzzleStage(1).makePuzzle(), size: .easy, stage: 1,
                                   stageDefaults: defaults)
        model.eventNow = { now }
        return (model, spy, defaults)
    }

    @Test("順位ごとに足す数: 1 位=ヒント+猫を教える・2 位=猫を教える・3 位=ヒント・4 位以下と順位なしは無し")
    func grantPerRank() {
        #expect(CatPuzzleDailyReward.grant(forRank: 1) == .init(rank: 1, hints: 1, teaches: 1))
        #expect(CatPuzzleDailyReward.grant(forRank: 2) == .init(rank: 2, hints: 0, teaches: 1))
        #expect(CatPuzzleDailyReward.grant(forRank: 3) == .init(rank: 3, hints: 1, teaches: 0))
        #expect(CatPuzzleDailyReward.grant(forRank: 4) == nil)
        #expect(CatPuzzleDailyReward.grant(forRank: nil) == nil)
    }

    @Test("残りは上限の 5 を超えて足され、保存される。カードの中身と reward_grant も出る")
    func addsBeyondFive() async {
        let (model, spy, defaults) = make("beyond", now: jst(2026, 11, 20))
        await model.claimDailyReward { .rank(1) }
        #expect(model.hintsRemaining == 6 && model.teachRemaining == 6)
        #expect(defaults.integer(forKey: CatPuzzleModel.stageHintsLeftKey) == 6)
        #expect(model.dailyRewardCard?.rank == 1)
        #expect(spy.grants.count == 1 && spy.grants.first?.rank == 1 && spy.grants.first?.items == .hintTeach)
        let reopened = CatPuzzleModel(services: nil, puzzle: CatPuzzleStage(1).makePuzzle(), size: .easy, stage: 1,
                                      stageDefaults: defaults)
        #expect(reopened.hintsRemaining == 6 && reopened.teachRemaining == 6, "再起動しても足したぶんは残る")
    }

    @Test("2 位は猫を教えるだけ・3 位はヒントだけ")
    func partialItems() async {
        let (second, spy2, _) = make("second", now: jst(2026, 11, 20))
        await second.claimDailyReward { .rank(2) }
        #expect(second.hintsRemaining == 5 && second.teachRemaining == 6 && spy2.grants.first?.items == .teach)
        let (third, spy3, _) = make("third", now: jst(2026, 11, 20))
        await third.claimDailyReward { .rank(3) }
        #expect(third.hintsRemaining == 6 && third.teachRemaining == 5 && spy3.grants.first?.items == .hint)
    }

    @Test("同じ日に 2 回渡さない（モデルを作り直しても）。翌日はまた受け取れる")
    func oncePerDay() async {
        let (model, spy, defaults) = make("once", now: jst(2026, 11, 20))
        await model.claimDailyReward { .rank(1) }
        await model.claimDailyReward { .rank(1) }
        let (again, _, _) = make("once", now: jst(2026, 11, 20, 23), defaults: defaults)
        await again.claimDailyReward { .rank(1) }
        #expect(again.hintsRemaining == 6 && spy.grants.count == 1)
        let (nextDay, _, _) = make("once", now: jst(2026, 11, 21, 1), defaults: defaults)
        await nextDay.claimDailyReward { .rank(2) }
        #expect(nextDay.teachRemaining == 7)
    }

    @Test("開催期間の前日・後日は渡さない。最終日 12/9 の分は 12/10 に受け取れ、12/11 は不可")
    func period() async {
        for (name, now, expected) in [("before", jst(2026, 11, 9), false), ("first", jst(2026, 11, 10), true),
                                      ("last", jst(2026, 12, 10), true), ("after", jst(2026, 12, 11), false)] {
            let (model, _, _) = make(name, now: now)
            var asked = false
            await model.claimDailyReward { asked = true; return .rank(1) }
            #expect((model.hintsRemaining == 6) == expected, "\(name)")
            #expect(asked == expected, "期間外は Game Center に問い合わせない: \(name)")
        }
    }

    @Test("読めなかったとき（未サインイン・通信なし）は保存せず、次に開いたときに再試行する")
    func retryWhenUnavailable() async {
        let (model, _, defaults) = make("retry", now: jst(2026, 11, 20))
        await model.claimDailyReward { .unavailable }
        #expect(model.hintsRemaining == 5 && model.dailyRewardCard == nil)
        #expect(!CatPuzzleDailyReward.isClaimed(defaults, now: jst(2026, 11, 20)))
        await model.claimDailyReward { .rank(3) }
        #expect(model.hintsRemaining == 6, "次に開いたときに読めれば渡す")
    }

    @Test("4 位以下と分かった日は読み直さない。順位なし（nil）は読み損ねかもしれないので次回も読む")
    func outsideTopStopsRetry() async {
        let (model, _, defaults) = make("outside", now: jst(2026, 11, 20))
        await model.claimDailyReward { .rank(nil) }
        #expect(!CatPuzzleDailyReward.isClaimed(defaults, now: jst(2026, 11, 20)))
        await model.claimDailyReward { .rank(8) }
        #expect(CatPuzzleDailyReward.isClaimed(defaults, now: jst(2026, 11, 20)))
        var asked = false
        await model.claimDailyReward { asked = true; return .rank(1) }
        #expect(!asked && model.hintsRemaining == 5)
    }

    @Test("読んでいる間に日付が変わったら、その順位は捨てる")
    func dayChangeDuringLookup() async {
        let (model, _, defaults) = make("daychange", now: jst(2026, 11, 20, 23))
        await model.claimDailyReward {
            model.eventNow = { self.jst(2026, 11, 21, 0) }
            return .rank(1)
        }
        #expect(model.hintsRemaining == 5 && model.dailyRewardCard == nil)
        #expect(!CatPuzzleDailyReward.isClaimed(defaults, now: jst(2026, 11, 21, 1)))
    }

    @Test("ランキング画面の読み取り: 日付が変わった直後に前の回が返ったときは、その回の順位を前日として使う")
    func lookupUsesPreviousOccurrence() {
        let now = jst(2026, 11, 20)
        let fresh = GameCenterBoard(rows: [], myRank: 9, myScore: 1, participants: 10, start: nil,
                                    end: now.addingTimeInterval(3600), lastWeekRank: 2)
        let stale = GameCenterBoard(rows: [], myRank: 3, myScore: 1, participants: 10, start: nil,
                                    end: now.addingTimeInterval(-60), lastWeekRank: 7)
        #expect(CatPuzzleRankingModel.today(fresh, now: now).lastWeekRank == 2)
        #expect(CatPuzzleRankingModel.today(stale, now: now).lastWeekRank == 3)
    }

    @Test("前回の回が前日の回のときだけ順位を使う。2 日前の回・始まり不明は前日と認めない")
    func yesterdaysOccurrenceOnly() {
        let now = jst(2026, 11, 20, 9)
        #expect(CatPuzzleDailyReward.isYesterdaysOccurrence(start: jst(2026, 11, 19, 0), now: now))
        #expect(!CatPuzzleDailyReward.isYesterdaysOccurrence(start: jst(2026, 11, 18, 0), now: now), "2 日前の回")
        #expect(!CatPuzzleDailyReward.isYesterdaysOccurrence(start: jst(2026, 11, 20, 0), now: now), "今日の回")
        #expect(!CatPuzzleDailyReward.isYesterdaysOccurrence(start: nil, now: now))
    }

    @Test("前日に遊んでいないと分かった日は何も足さず、その日は読み直さない")
    func notYesterdayStopsRetry() async {
        let (model, spy, defaults) = make("notyesterday", now: jst(2026, 11, 20))
        await model.claimDailyReward { .notYesterday }
        #expect(model.hintsRemaining == 5 && model.teachRemaining == 5 && spy.grants.isEmpty)
        #expect(CatPuzzleDailyReward.isClaimed(defaults, now: jst(2026, 11, 20)))
    }

    @Test("日付が変わった直後に前の回が返ったとき、その回の始まりも前日の確認に使える")
    func staleBoardKeepsStart() {
        let now = jst(2026, 11, 20, 0).addingTimeInterval(60)
        let stale = GameCenterBoard(rows: [], myRank: 3, myScore: 1, participants: 10, start: jst(2026, 11, 19, 0),
                                    end: jst(2026, 11, 20, 0), lastWeekRank: 7, lastWeekStart: jst(2026, 11, 18, 0))
        let day = CatPuzzleRankingModel.today(stale, now: now)
        #expect(day.lastWeekRank == 3 && CatPuzzleDailyReward.isYesterdaysOccurrence(start: day.lastWeekStart, now: now))
    }
}
