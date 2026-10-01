import Testing
import Foundation
import Core
import CoreTestSupport
import HomerunCore
@testable import GameHomerun

/// 段 4 の接続: 広告での回数 +1・解析（`game_start` / `game_end`）・記録・消去の対象（#1348）。
@Suite("柵越えおじさんの接続（広告・解析・記録）")
@MainActor
struct HomerunConnectionTests {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    /// 2027-01-15 12:00 JST。
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeDefaults() -> UserDefaults {
        let suite = "asobiba.homerun.connection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeServices(spy: SpyAnalyticsService, log: PlayLog? = nil) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: SpyFeedbackService(), playLog: log,
            analytics: GameAnalytics(service: spy, allowedGameIDs: [HomerunModel.gameID])
        )
    }

    private func makeModel(services: GameServices? = nil, defaults: UserDefaults? = nil,
                           pitches: [HomerunPitch] = [HomerunPitch(zone: 4)],
                           now: Date = HomerunConnectionTests.t0) -> HomerunModel {
        // 照準の吸い寄せは切る（入力どおりの照準で柵越えを打つ）。
        HomerunModel(services: services, defaults: defaults ?? makeDefaults(), calendar: Self.calendar,
                     pitches: pitches, aimAssist: .off, now: now)
    }

    /// 見送りで 1 球進めて結果を閉じる。
    private func skip(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.nextWake))
        model.advance(now: try #require(model.resultUntil))
    }

    /// 結果を閉じて次へ（最後の球なら終了）。
    private func skipResult(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.resultUntil))
    }

    // MARK: 広告で +1

    @Test("広告を見ると今日の回数が 1 増え、保存される。1 日 5 本まで")
    func adGrantsUpToLimit() {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        let day = model.dayKey(at: Self.t0)
        for i in 1...HomerunLedger.adLimitPerDay {
            #expect(model.grantAdChallenge(forDay: day, now: Self.t0), "\(i) 本目は増える")
        }
        #expect(model.ledger.allowance == HomerunLedger.freePerDay + HomerunLedger.adLimitPerDay)
        #expect(!model.grantAdChallenge(forDay: day, now: Self.t0), "6 本目は増えない")
        #expect(model.ledger.allowance == HomerunLedger.freePerDay + HomerunLedger.adLimitPerDay)
        #expect(HomerunStorage.loadLedger(defaults).adsWatched == HomerunLedger.adLimitPerDay)
    }

    @Test("広告を見ているあいだに 0:00 をまたいだら、前の日の広告では増やさない")
    func adAcrossMidnightIsRejected() {
        let model = makeModel()
        let dayBefore = model.dayKey(at: Self.t0)
        let nextDay = Self.t0.addingTimeInterval(24 * 3600)
        #expect(!model.grantAdChallenge(forDay: dayBefore, now: nextDay))
        #expect(model.ledger.adsWatched == 0)
        #expect(model.ledger.remaining == HomerunLedger.freePerDay, "新しい日は無料分に戻っている")
    }

    @Test("画面を開いたまま 0:00 を過ぎても、その日の鍵を控えて見た広告は増やす（台帳の日付が古いだけで弾かない）")
    func adAfterMidnightWithStaleLedgerIsGranted() {
        let model = makeModel()
        let nextDay = Self.t0.addingTimeInterval(24 * 3600)
        // 台帳はまだ前の日のまま（refreshDay が走っていない）。ボタンを押した時点の時計から鍵を作る。
        let key = model.dayKey(at: nextDay)
        #expect(key != model.ledger.dayKey)
        #expect(model.grantAdChallenge(forDay: key, now: nextDay))
        #expect(model.ledger.adsWatched == 1)
    }

    @Test("使い切ったあと広告で 1 回増え、打席に立てる")
    func adRestoresChallenge() throws {
        let model = makeModel()
        for _ in 0..<HomerunLedger.freePerDay {
            #expect(model.start(now: Self.t0))
            model.atBatDidAppear(now: Self.t0)
            try skip(model)
        }
        #expect(!model.ledger.canStart)
        #expect(model.grantAdChallenge(forDay: model.dayKey(at: Self.t0), now: Self.t0))
        #expect(model.ledger.remaining == 1)
        #expect(model.start(now: Self.t0))
    }

    // MARK: アンケートで +1

    @Test("アンケートに答えると今日の回数が 1 増え、保存される。1 日 1 回")
    func surveyGrantsOncePerDay() {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        let day = model.dayKey(at: Self.t0)
        #expect(model.submitSurvey([1, 2, 3], forDay: day, now: Self.t0))
        #expect(model.ledger.allowance == HomerunLedger.freePerDay + HomerunLedger.surveyBonus)
        #expect(!model.submitSurvey([1, 2, 3], forDay: day, now: Self.t0), "2 回目は増えない")
        #expect(model.ledger.allowance == HomerunLedger.freePerDay + HomerunLedger.surveyBonus)
        #expect(HomerunStorage.loadLedger(defaults).surveyDone)
    }

    @Test("未回答・範囲外の回答では増えず、回答も送られない")
    func incompleteSurveyIsRejected() {
        let spy = SpyAnalyticsService()
        let model = makeModel(services: makeServices(spy: spy))
        let day = model.dayKey(at: Self.t0)
        #expect(!model.submitSurvey([1, 2], forDay: day, now: Self.t0), "2 問しか答えていない")
        #expect(!model.submitSurvey([1, 2, 9], forDay: day, now: Self.t0), "選択肢の範囲外")
        #expect(!model.submitSurvey([0, 1, 1], forDay: day, now: Self.t0), "番号は 1 始まり")
        #expect(!model.ledger.surveyDone)
        #expect(spy.events.isEmpty)
    }

    @Test("回答中に 0:00 をまたいだら、前の日の回答では増やさず送りもしない")
    func surveyAcrossMidnightIsRejected() {
        let spy = SpyAnalyticsService()
        let model = makeModel(services: makeServices(spy: spy))
        let dayBefore = model.dayKey(at: Self.t0)
        let nextDay = Self.t0.addingTimeInterval(24 * 3600)
        #expect(!model.submitSurvey([1, 1, 1], forDay: dayBefore, now: nextDay))
        #expect(!model.ledger.surveyDone)
        #expect(spy.events.isEmpty)
    }

    @Test("回答は survey_answer として選択肢の番号だけが 1 回送られ、端末には台帳の済みフラグしか残らない")
    func surveySendsAnswersOnlyOnce() {
        let spy = SpyAnalyticsService()
        let defaults = makeDefaults()
        let model = makeModel(services: makeServices(spy: spy), defaults: defaults)
        let day = model.dayKey(at: Self.t0)
        model.submitSurvey([2, 4, 1], forDay: day, now: Self.t0)
        model.submitSurvey([1, 1, 1], forDay: day, now: Self.t0)
        #expect(spy.events == [.surveyAnswer(gameID: HomerunModel.gameID, answers: [2, 4, 1])])
    }

    @Test("設問は 3 問で、番号の範囲が選択肢の数と一致する")
    func surveyValidation() {
        #expect(HomerunSurvey.questions.count == 3)
        #expect(HomerunSurvey.isValid([1, 1, 1]))
        let maxes = HomerunSurvey.questions.map(\.choices.count)
        #expect(HomerunSurvey.isValid(maxes))
        #expect(!HomerunSurvey.isValid(maxes.map { $0 + 1 }))
    }

    // MARK: 解析・記録

    @Test("打席に立つと game_start、10 球目で game_end が 1 回ずつ。柵越えが無ければ loss")
    func analyticsStartAndEnd() throws {
        let spy = SpyAnalyticsService()
        let model = makeModel(services: makeServices(spy: spy))
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        #expect(spy.starts == [HomerunModel.gameID])
        #expect(spy.ends.isEmpty)
        try skip(model)
        #expect(model.phase == .finished)
        #expect(spy.ends.count == 1)
        #expect(spy.outcomes == [.loss])
    }

    @Test("2 回目以降の打席は game_start をもう 1 回数える（始め直し）")
    func secondChallengeCountsAnotherStart() throws {
        let spy = SpyAnalyticsService()
        let model = makeModel(services: makeServices(spy: spy))
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try skip(model)
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        #expect(spy.starts.count == 2)
        #expect(spy.ends.count == 1, "1 本目は決着済みなので quit は出ない")
    }

    @Test("10 球の結果は PlayLog の自己ベスト（points）に載る")
    func recordsScore() throws {
        let suite = "asobiba.homerun.connection.log.\(UUID().uuidString)"
        let log = PlayLog(defaults: UserDefaults(suiteName: suite)!)
        let spy = SpyAnalyticsService()
        let model = makeModel(services: makeServices(spy: spy, log: log))
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try skip(model)
        let record = try #require(log.record(gameID: HomerunModel.gameID))
        #expect(record.plays == 1)
        #expect(record.bestPoints == 0, "見送りだけの挑戦は 0 m")
        #expect(spy.outcomes == [.loss])
    }

    @Test("柵越えが 1 本あれば win で、合計飛距離（m・切り捨て）が points に載る")
    func homerRecordsPointsAndWin() throws {
        let suite = "asobiba.homerun.connection.log2.\(UUID().uuidString)"
        let log = PlayLog(defaults: UserDefaults(suiteName: suite)!)
        let spy = SpyAnalyticsService()
        let model = makeModel(services: makeServices(spy: spy, log: log))
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        // 1 球目: 真ん中でボールの 9pt 下・ジャスト = 中堅 161 m の柵越え。
        let arrive = try #require(model.arrival)
        model.press(at: CGPoint(x: 150, y: 600))
        let ball = model.ballPoint
        model.drag(to: CGPoint(x: 150 + ball.x, y: 600 + ball.y + 9))
        model.release(at: CGPoint(x: 150 + ball.x, y: 600 + ball.y + 9), now: arrive)
        try skipResult(model)
        #expect(model.phase == .finished)
        #expect(spy.outcomes == [.win])
        #expect(try #require(log.record(gameID: HomerunModel.gameID)).bestPoints == 161)
    }

    // MARK: 消去

    @Test("蓄積は「プレイ記録を消去」の対象、日次台帳は対象外（補充の穴を塞ぐ）")
    func clearScope() {
        #expect(PlayLog.allKeys.contains(HomerunStorage.recordsKey))
        #expect(!PlayLog.allKeys.contains(HomerunStorage.ledgerKey))
        #expect(PlayLog.homerunKeys == [HomerunStorage.recordsKey])
    }
}
