import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GameCatPuzzle

/// ねこさがしの 1 か月ランキングイベント（#3204）。
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
        #expect(reopened.eventTotal == 5, "再起動しても合計は消えない")
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

    @Test("コンティニューで戻したミスも数える（3 回ミス → 広告で続ける → クリアは 0pt）")
    func continueCountsTheMistake() async {
        let model = makeModel(defaults: makeDefaults(), now: jst(2026, 11, 10))
        await start(model, 1)
        miss(model, times: 3)
        #expect(model.continueAfterAd())
        solve(model)
        #expect(model.isSolved)
        #expect(model.lastEventPoints == 0)
        #expect(model.eventTotal == 0)
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

    @Test("サインイン済みなら合計を新しいリーダーボードへ送り、送り済みを控える")
    func submitsTotal() async {
        let center = SpyGameCenter()
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults, now: jst(2026, 11, 10), center: center)
        await start(model, 1)
        solve(model)
        await model.eventSubmitTask?.value
        #expect(center.submitted == [GameCenterScore(leaderboardID: "asobiba.catpuzzle.event202611", value: 3)])
        #expect(CatPuzzleEvent.sent(defaults) == 3)
    }

    @Test("未サインインでも pt は貯まり、サインイン後に画面を開くと送る。送れなかったときは控えを進めず次で送り直す")
    func signedOutThenSignedIn() async {
        let defaults = makeDefaults()
        let offline = makeModel(defaults: defaults, now: jst(2026, 11, 10), center: SpyGameCenter(), signedIn: false)
        await start(offline, 1)
        solve(offline)
        #expect(offline.eventTotal == 3 && CatPuzzleEvent.sent(defaults) == 0)

        let center = SpyGameCenter()
        center.succeeds = false
        let failing = makeModel(defaults: defaults, now: jst(2026, 11, 10), center: center)
        failing.submitEventTotalIfNeeded()
        await failing.eventSubmitTask?.value
        #expect(center.submitted.count == 1 && CatPuzzleEvent.sent(defaults) == 0, "失敗は送り済みにしない")

        center.succeeds = true
        let retry = makeModel(defaults: defaults, now: jst(2026, 12, 20), center: center)
        retry.submitEventTotalIfNeeded()
        await retry.eventSubmitTask?.value
        #expect(center.submitted.last?.value == 3 && CatPuzzleEvent.sent(defaults) == 3, "期間が終わっても貯めたぶんは送れる")
        retry.submitEventTotalIfNeeded()
        #expect(retry.eventSubmitTask == nil, "送り済みなら何もしない")
    }

    @Test("リーダーボード ID と、ハブの印がねこさがしに付く")
    func ids() throws {
        #expect(GameCenterLeaderboard.catPuzzleEvent == "asobiba.catpuzzle.event202611")
        #expect(CatPuzzleModel.gameID == "catpuzzle")
    }
}
