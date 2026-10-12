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
        try skipResult(model)
    }

    /// 結果を閉じて次へ（最後の球なら終了）。
    private func skipResult(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.resultUntil))
        // 最後の球なら、結果の演出（`.finale`）も閉じて結果画面へ。
        if model.phase == .finale { model.advance(now: try #require(model.finaleUntil)) }
    }

    // MARK: 広告を見てプレイ（#1694）

    /// 無料の回数を使い切り、結果画面まで進める。
    private func useUpFree(_ model: HomerunModel, at now: Date = HomerunConnectionTests.t0) throws {
        for _ in 0..<HomerunLedger.freePerDay {
            #expect(model.start(now: now))
            model.atBatDidAppear(now: now)
            try skip(model)
        }
        #expect(model.phase == .finished)
        #expect(!model.ledger.canStart)
    }

    @Test("使い切ったあと広告を見終えると、その場で打席に入る。回数は増えない・増えたように見えない")
    func adStartsChallengeImmediately() throws {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        try useUpFree(model)
        let before = model.ledger
        #expect(model.ledger.canPlayWithAd)
        #expect(model.startWithAd(forDay: model.dayKey(at: Self.t0), now: Self.t0))
        #expect(model.phase == .pitching, "確認を挟まずに打席へ")
        #expect(model.startedWithAd)
        #expect(model.ledger.allowance == before.allowance, "回数（分母）は増えない")
        #expect(model.ledger.remaining == 0, "残りも 0 のまま")
        #expect(model.ledger.used == before.used, "回数から引かない（広告の 1 本で遊ぶ）")
        #expect(model.ledger.adPlays == 1, "台帳の上で広告での挑戦と分かる")
        #expect(HomerunStorage.loadLedger(defaults).adPlays == 1, "保存される")
    }

    @Test("広告でのプレイは 1 日 adLimitPerDay 本まで")
    func adPlaysUpToLimit() throws {
        let model = makeModel()
        try useUpFree(model)
        let day = model.dayKey(at: Self.t0)
        let limit = try #require(HomerunLedger.adLimitPerDay, "上限は 5 本（会長決裁 2026-10-04）")
        #expect(limit == 5)
        for i in 1...limit {
            #expect(model.startWithAd(forDay: day, now: Self.t0), "\(i) 本目は遊べる")
            model.atBatDidAppear(now: Self.t0)
            try skip(model)
        }
        #expect(!model.ledger.canWatchAd)
        #expect(!model.ledger.canPlayWithAd)
        #expect(!model.startWithAd(forDay: day, now: Self.t0), "上限を超えたら始めない")
        #expect(model.phase == .finished)
        #expect(model.ledger.adPlays == limit)
    }

    @Test("回数が残っているうちは広告では始めない（先に回数を使う）")
    func adPlayRequiresExhausted() {
        let model = makeModel()
        #expect(!model.ledger.canPlayWithAd)
        #expect(!model.startWithAd(forDay: model.dayKey(at: Self.t0), now: Self.t0))
        #expect(model.phase == .idle)
        #expect(model.ledger.adPlays == 0)
    }

    @Test("打席中は広告で始めない（打席前・結果だけ）")
    func adPlayOnlyFromIdleOrFinished() throws {
        let model = makeModel()
        try useUpFree(model)
        #expect(model.startWithAd(forDay: model.dayKey(at: Self.t0), now: Self.t0))
        #expect(model.phase == .pitching)
        #expect(!model.startWithAd(forDay: model.dayKey(at: Self.t0), now: Self.t0))
        #expect(model.ledger.adPlays == 1)
    }

    @Test("ふつうに打席に立った挑戦は広告での挑戦にならない")
    func normalStartIsNotAdPlay() throws {
        let model = makeModel()
        #expect(model.start(now: Self.t0))
        #expect(!model.startedWithAd)
        #expect(model.ledger.adPlays == 0)
    }

    @Test("広告を見ているあいだに 0:00 をまたいだら、前の日の広告では始めない")
    func adAcrossMidnightIsRejected() throws {
        let model = makeModel()
        try useUpFree(model)
        let dayBefore = model.dayKey(at: Self.t0)
        let nextDay = Self.t0.addingTimeInterval(24 * 3600)
        #expect(!model.startWithAd(forDay: dayBefore, now: nextDay))
        #expect(model.phase == .finished)
        #expect(model.ledger.adPlays == 0)
        #expect(model.ledger.remaining == HomerunLedger.freePerDay, "新しい日は無料分に戻っている")
    }

    @Test("画面を開いたまま 0:00 を過ぎ、その日の鍵を控えて見た広告: 新しい日は無料分があるので広告では始めない")
    func adAfterMidnightWithStaleLedgerUsesFreeFirst() throws {
        let model = makeModel()
        try useUpFree(model)
        let nextDay = Self.t0.addingTimeInterval(24 * 3600)
        let key = model.dayKey(at: nextDay)
        #expect(key != model.ledger.dayKey)
        #expect(!model.startWithAd(forDay: key, now: nextDay))
        #expect(model.ledger.canStart)
    }

    // MARK: 解析・記録

    @Test("広告を見てプレイした打席の credit は ad（game_start と game_end の両方・#1685 × #1694）")
    func adPlayCarriesAdCredit() throws {
        let spy = SpyAnalyticsService()
        let model = makeModel(services: makeServices(spy: spy))
        try useUpFree(model)
        #expect(model.startWithAd(forDay: model.dayKey(at: Self.t0), now: Self.t0))
        model.atBatDidAppear(now: Self.t0)
        try skip(model)
        #expect(spy.startCredits.last == .ad)
        #expect(spy.endCredits.last == .ad)
    }

    @Test("消費した枠（credit）は 無料 → ご褒美 → 広告 の固定順で、game_start と game_end の両方に載る（#1685）")
    func creditFollowsFixedOrder() throws {
        let spy = SpyAnalyticsService()
        let defaults = makeDefaults()
        let day = HomerunLedger.dayKey(for: Self.t0, calendar: Self.calendar)
        // 無料 3 + ご褒美 2（月 1 回）+ 広告 1。もらった順（広告が先）に関わらず固定順で使う。
        var ledger = HomerunLedger(dayKey: day, legacyAdGrants: 1, bonus: 2)
        HomerunStorage.saveLedger(ledger, defaults)
        let model = makeModel(services: makeServices(spy: spy), defaults: defaults)
        for _ in 0..<6 {
            model.start(now: Self.t0)
            model.atBatDidAppear(now: Self.t0)
            try skip(model)
        }
        let expected: [AnalyticsCredit?] = [.free, .free, .free, .bonus, .bonus, .ad]
        #expect(spy.startCredits == expected)
        #expect(spy.endCredits == expected, "終わりは開始と同じ枠で突き合わせられる")
        #expect(!model.start(now: Self.t0), "7 回目は回数が無い")
        #expect(spy.starts.count == 6, "回数が無くて立てなかった打席は数えない")
        ledger.roll(to: day)
    }

    // 鍵（`debugUnlimitedKey`）は `HomerunModel+Debug.swift` の #if DEBUG の中だけの宣言なので、
    // 参照するこのテストも同じく #if DEBUG で囲む（出荷ビルドのテストが壊れないように・#1705）。
    #if DEBUG
    @Test("DEBUG の回数無制限では credit を載せない（#1685）")
    func unlimitedDoesNotSendCredit() throws {
        let spy = SpyAnalyticsService()
        let defaults = makeDefaults()
        defaults.set(true, forKey: HomerunModel.debugUnlimitedKey)
        let model = makeModel(services: makeServices(spy: spy), defaults: defaults)
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try skip(model)
        #expect(spy.startCredits == [nil])
        #expect(spy.endCredits == [nil])
    }
    #endif

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
        // 1 球目: 真ん中でボールの 4pt 下（フライの芯の基準点）・ジャスト = 中堅 180 m の柵越え（最高の当たり）。
        let arrive = try #require(model.arrival)
        model.press(at: CGPoint(x: 150, y: 600))
        let ball = model.ballPoint
        model.drag(to: CGPoint(x: 150 + ball.x, y: 600 + ball.y + 4))
        model.release(at: CGPoint(x: 150 + ball.x, y: 600 + ball.y + 4), now: arrive)
        try skipResult(model)
        #expect(model.phase == .finished)
        #expect(spy.outcomes == [.win])
        #expect(try #require(log.record(gameID: HomerunModel.gameID)).bestPoints == 180)
    }

    // MARK: 消去

    @Test("蓄積・実績は「プレイ記録を消去」の対象、日次台帳は対象外（補充の穴を塞ぐ）")
    func clearScope() {
        #expect(PlayLog.allKeys.contains(HomerunStorage.recordsKey))
        #expect(PlayLog.allKeys.contains(HomerunStorage.achievementsKey))
        #expect(!PlayLog.allKeys.contains(HomerunStorage.ledgerKey))
        #expect(PlayLog.homerunKeys == [HomerunStorage.recordsKey, HomerunStorage.achievementsKey])
    }
}
