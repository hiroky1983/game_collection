import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ねこさがしのランキングイベント（#3204）。#3221 で 1 か月通しの合計から日本時間の 1 日ごとのデイリーに変えた。
@Suite("おじさんちのねこさがしのランキングイベント")
@MainActor
struct CatPuzzleEventTests {

    private func jst(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "asobiba.catpuzzle.event.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    private final class SpyGameCenter: GameCenterService {
        var submitted: [GameCenterScore] = []
        var succeeds = true
        func submit(_ score: GameCenterScore) {}
        func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
        func submitAndWait(_ score: GameCenterScore) async -> Bool { submitted.append(score); return succeeds }
    }

    private func makeModel(defaults: UserDefaults, now: Date, center: SpyGameCenter? = nil, signedIn: Bool = true,
                           analytics: SpyAnalyticsService? = nil) -> CatPuzzleModel {
        let reporter = center.map { GameCenterReporter(service: $0, allowedGameIDs: [CatPuzzleModel.gameID], isAvailable: { signedIn }) }
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [CatPuzzleModel.gameID]) },
            gameCenter: reporter
        )
        let model = CatPuzzleModel(services: services, stageDefaults: defaults)
        model.eventNow = { now }
        model.refreshEventTotal()
        return model
    }

    private func start(_ model: CatPuzzleModel, _ number: Int = 1) async {
        model.startStage(number)
        await model.stagePreparation?.value
    }

    private func miss(_ model: CatPuzzleModel, times: Int) {
        let solution = Set(model.puzzle.solutionCells)
        for cell in (0..<model.puzzle.cellCount).filter({ !solution.contains($0) }).prefix(times) { model.findCat(cell: cell) }
    }

    private func solve(_ model: CatPuzzleModel) {
        for cell in model.puzzle.solutionCells where model.marks[cell] != .cat { model.findCat(cell: cell) }
    }

    @Test("ミスの数ごとのポイントは 0 回 3pt・1 回 2pt・2 回 1pt・3 回以上は 0pt")
    func pointsPerMistakes() {
        #expect([0, 1, 2, 3, 4].map(CatPuzzleEvent.points(mistakes:)) == [3, 2, 1, 0, 0])
    }

    @Test("期間は 2026-11-09 0:00 から 12-09 の終わりまで（JST）")
    func period() {
        #expect(!CatPuzzleEvent.isActive(now: jst(2026, 11, 8, 23, 59)))
        #expect(CatPuzzleEvent.isActive(now: jst(2026, 11, 9)))
        #expect(CatPuzzleEvent.isActive(now: jst(2026, 12, 9, 23, 59)))
        #expect(!CatPuzzleEvent.isActive(now: jst(2026, 12, 10)))
    }

    @Test("ステージのクリアでミスの数に応じたポイントが貯まり、合計は保存され、game_end に載る")
    func awardsAndPersists() async {
        let defaults = makeDefaults()
        let spy = SpyAnalyticsService()
        let model = makeModel(defaults: defaults, now: jst(2026, 11, 10), analytics: spy)
        await start(model, 1)
        miss(model, times: 1)
        solve(model)
        #expect(model.isSolved)
        #expect(model.lastEventPoints == 2)
        #expect(model.eventTotal == 2)
        #expect(spy.endEventPoints.last == .some(2))
        await start(model, 2)
        #expect(model.lastEventPoints == nil, "次の面では前のポイントを持ち越さない")
        solve(model)
        #expect(model.lastEventPoints == 3 && model.eventTotal == 5)
        let reopened = makeModel(defaults: defaults, now: jst(2026, 11, 10))
        #expect(reopened.eventTotal == 5, "再起動しても今日の合計は消えない")
    }

    @Test("ヒント・猫を教えるを使ってもポイントは減らない")
    func assistsDoNotReduce() async {
        let model = makeModel(defaults: makeDefaults(), now: jst(2026, 11, 10))
        await start(model, 1)
        model.useHint()
        model.teachCat()
        #expect(model.hintsUsed > 0)
        solve(model)
        #expect(model.isSolved)
        #expect(model.lastEventPoints == 3)
    }

    @Test("コンティニューで戻したあとは画面のミス数で数える（3 回ミス → 広告で続ける → クリアは 2 回扱いで 1pt）")
    func continueUsesDisplayedMistakes() async {
        let model = makeModel(defaults: makeDefaults(), now: jst(2026, 11, 10))
        await start(model, 1)
        miss(model, times: 3)
        #expect(model.continueAfterAd())
        solve(model)
        #expect(model.isSolved)
        #expect(model.mistakes == 2)
        #expect(model.lastEventPoints == 1)
        #expect(model.eventTotal == 1)
    }

    @Test("期間外のクリアは加算せず、game_end にも載せない。負けも 0")
    func outsidePeriodAddsNothing() async {
        let spy = SpyAnalyticsService()
        let defaults = makeDefaults()
        let before = makeModel(defaults: defaults, now: jst(2026, 11, 8), analytics: spy)
        await start(before, 1)
        solve(before)
        #expect(before.lastEventPoints == nil && before.eventTotal == 0)
        #expect(spy.endEventPoints.last == .some(nil))
        let after = makeModel(defaults: defaults, now: jst(2026, 12, 10))
        await start(after, 1)
        solve(after)
        #expect(after.eventTotal == 0)
        #expect(!after.isEventActive)
    }

    @Test("自由に遊ぶ盤のクリアはイベントの対象外")
    func freePlayIsExcluded() {
        let model = makeModel(defaults: makeDefaults(), now: jst(2026, 11, 10))
        solve(model)
        #expect(model.isSolved && model.lastEventPoints == nil && model.eventTotal == 0)
    }

    @Test("サインイン済みなら今日の合計を日ごとのリーダーボードへ送り、送り済みを控える")
    func submitsTotal() async {
        let center = SpyGameCenter()
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults, now: jst(2026, 11, 10), center: center)
        await start(model, 1)
        solve(model)
        await model.eventSubmitTask?.value
        #expect(center.submitted == [GameCenterScore(leaderboardID: "asobiba.catpuzzle.daily", value: 3)])
        #expect(CatPuzzleEvent.sent(defaults, now: jst(2026, 11, 10)) == 3)
    }

    @Test("未サインインでも pt は貯まり、サインイン後に画面を開くと送る。送れなかったときは控えを進めず次で送り直す")
    func signedOutThenSignedIn() async {
        let defaults = makeDefaults()
        let offline = makeModel(defaults: defaults, now: jst(2026, 11, 10), center: SpyGameCenter(), signedIn: false)
        await start(offline, 1)
        solve(offline)
        #expect(offline.eventTotal == 3 && CatPuzzleEvent.sent(defaults, now: jst(2026, 11, 10)) == 0)

        let center = SpyGameCenter()
        center.succeeds = false
        let failing = makeModel(defaults: defaults, now: jst(2026, 11, 10), center: center)
        failing.submitEventTotalIfNeeded()
        await failing.eventSubmitTask?.value
        #expect(center.submitted.count == 1 && CatPuzzleEvent.sent(defaults, now: jst(2026, 11, 10)) == 0, "失敗は送り済みにしない")

        center.succeeds = true
        let retry = makeModel(defaults: defaults, now: jst(2026, 11, 10, 23, 59), center: center)
        retry.submitEventTotalIfNeeded()
        await retry.eventSubmitTask?.value
        #expect(center.submitted.last?.value == 3 && CatPuzzleEvent.sent(defaults, now: jst(2026, 11, 10)) == 3)
        retry.submitEventTotalIfNeeded()
        #expect(retry.eventSubmitTask == nil, "送り済みなら何もしない")
    }

    @Test("日付（JST 0:00）が変わると今日の合計は 0 に戻り、新しい日は 0 から貯まる")
    func resetsAtJSTMidnight() async {
        let defaults = makeDefaults()
        let day1 = makeModel(defaults: defaults, now: jst(2026, 11, 10, 23, 59))
        await start(day1, 1)
        solve(day1)
        #expect(day1.eventTotal == 3)
        let day2 = makeModel(defaults: defaults, now: jst(2026, 11, 11))
        #expect(day2.eventTotal == 0, "0:00 を過ぎたら今日の合計は 0")
        await start(day2, 2)
        solve(day2)
        #expect(day2.eventTotal == 3 && day2.lastEventPoints == 3, "前日の 3pt は持ち越さない")
        #expect(CatPuzzleEvent.total(defaults, now: jst(2026, 11, 10)) == 0, "保存は今日の分だけ")
    }

    @Test("日付をまたいでアプリを開いたままでも、クリア時点の日付で数える")
    func countsByClearTimeDate() async {
        let defaults = makeDefaults()
        var clock = jst(2026, 11, 10, 23, 58)
        let model = makeModel(defaults: defaults, now: clock)
        model.eventNow = { clock }
        await start(model, 1)
        solve(model)
        #expect(model.eventTotal == 3)
        clock = jst(2026, 11, 11, 0, 1)
        await start(model, 2)
        #expect(model.eventTotal == 0, "次の面を始めた時点で今日の合計に読み直す")
        solve(model)
        #expect(model.eventTotal == 3)
        #expect(CatPuzzleEvent.day(of: clock) == "2026-11-11")
        clock = jst(2026, 11, 12)
        #expect(model.eventTotal == 3 && model.todayEventTotal == 0, "開いたまま日が変わっても、開始シートには前日の合計を出さない")
    }

    @Test("前日分は送らない。日付が変わったら今日の分だけを送る")
    func doesNotSendPreviousDay() async {
        let defaults = makeDefaults()
        let offline = makeModel(defaults: defaults, now: jst(2026, 11, 10), center: SpyGameCenter(), signedIn: false)
        await start(offline, 1)
        solve(offline)
        #expect(offline.eventTotal == 3)

        let center = SpyGameCenter()
        let nextDay = makeModel(defaults: defaults, now: jst(2026, 11, 11, 9), center: center)
        nextDay.submitEventTotalIfNeeded()
        #expect(nextDay.eventSubmitTask == nil && center.submitted.isEmpty, "前日の 3pt は送らない")
        await start(nextDay, 1)
        miss(nextDay, times: 1)
        solve(nextDay)
        await nextDay.eventSubmitTask?.value
        #expect(center.submitted == [GameCenterScore(leaderboardID: "asobiba.catpuzzle.daily", value: 2)])
    }

    @Test("期間外は日付が違っても加算しない（開始前・終了後）")
    func outsidePeriodByDay() async {
        let defaults = makeDefaults()
        for now in [jst(2026, 11, 8, 23, 59), jst(2026, 12, 10)] {
            let model = makeModel(defaults: defaults, now: now)
            await start(model, 1)
            solve(model)
            #expect(model.eventTotal == 0 && model.lastEventPoints == nil)
        }
    }

    @Test("リーダーボード ID と、ハブの印がねこさがしに付く")
    func ids() throws {
        #expect(GameCenterLeaderboard.catPuzzleEvent == "asobiba.catpuzzle.daily")
        #expect(CatPuzzleModel.gameID == "catpuzzle")
    }
}
