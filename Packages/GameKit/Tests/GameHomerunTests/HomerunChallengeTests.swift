import Testing
import Foundation
@testable import GameHomerun

@Suite("柵越えおじさんの 1 挑戦・台帳・蓄積")
struct HomerunChallengeTests {

    private let perfect = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY)

    private func finished(_ swing: HomerunSwing?) -> HomerunChallenge {
        var c = HomerunChallenge()
        while !c.isFinished { c.swing(swing) }
        return c
    }

    // MARK: 挑戦

    @Test("1 挑戦は 10 球で終わり、終わったあとは何も起きない")
    func tenPitches() {
        var c = HomerunChallenge()
        #expect(HomerunChallenge.pitchCount == 10)
        #expect(c.pitches.count == 10)
        for i in 0..<10 {
            #expect(c.currentPitch == c.pitches[i])
            let ball = c.swing(perfect)
            #expect(ball != nil)
        }
        #expect(c.isFinished)
        #expect(c.currentPitch == nil)
        let extra = c.swing(perfect)
        #expect(extra == nil)
        #expect(c.results.count == 10)
    }

    @Test("配球は固定で、ゾーンは 0〜8 の範囲")
    func fixedSequence() {
        #expect(HomerunPitch.standardSequence == HomerunPitch.standardSequence)
        #expect(HomerunPitch.standardSequence.allSatisfy { (0..<9).contains($0.zone) })
    }

    @Test("集計: 全球ジャスト = 柵越え 10 本・合計 1350m。見逃しは空振り 10")
    func totals() {
        let all = finished(perfect)
        #expect(all.homerCount == 10)
        #expect(abs(all.totalDistance - 1350) < 1e-9)
        let none = finished(nil)
        #expect(none.missCount == 10)
        #expect(none.totalDistance == 0)
        #expect(none.homerCount == 0)
    }

    // MARK: 日次台帳

    @Test("台帳: 無料 3・広告 +1 を 5 本・アンケート +1 で最大 9")
    func ledgerAllowance() {
        var l = HomerunLedger(dayKey: 20260926)
        #expect(l.remaining == 3)
        for _ in 0..<5 { let ok = l.grantAd(); #expect(ok) }
        let sixth = l.grantAd()
        #expect(!sixth)
        let survey = l.grantSurvey()
        let surveyAgain = l.grantSurvey()
        #expect(survey && !surveyAgain)
        #expect(l.remaining == 9)
        for _ in 0..<9 { let ok = l.consume(); #expect(ok) }
        let tenth = l.consume()
        #expect(!tenth)
        #expect(l.remaining == 0)
        #expect(!l.canStart)
    }

    @Test("台帳: 回数が無ければ消費しない・減算は consume（打席に立った時点）だけ")
    func ledgerConsumeOnlyOnStart() {
        var l = HomerunLedger(dayKey: 1)
        l.consume(); l.consume(); l.consume()
        #expect(l.used == 3)
        let fourth = l.consume()
        #expect(!fourth)
        #expect(l.used == 3)
    }

    @Test("台帳: 日付が進むと補充され、戻しても・同じ日でも増えない")
    func ledgerRoll() {
        var l = HomerunLedger(dayKey: 20260926)
        l.consume(); l.consume(); l.consume()
        l.grantAd()
        l.roll(to: 20260926)
        #expect(l.remaining == 1)  // 同じ日は何もしない
        l.roll(to: 20260925)
        #expect(l.dayKey == 20260926)  // 時計を戻しても無料分は増えない
        #expect(l.remaining == 1)
        l.roll(to: 20260927)
        #expect(l.dayKey == 20260927)
        #expect(l.remaining == 3)
        #expect(l.adsWatched == 0 && !l.surveyDone)
    }

    @Test("台帳: 日付キーは 0:00 で切り替わる（タイムゾーンは Calendar で決まる）")
    func dayKeyAtMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let before = cal.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 23, minute: 59, second: 59))!
        let after = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 0, minute: 0, second: 0))!
        #expect(HomerunLedger.dayKey(for: before, calendar: cal) == 20260926)
        #expect(HomerunLedger.dayKey(for: after, calendar: cal) == 20260927)
    }

    @Test("台帳: 保存して読み戻せる。記録の消去用のキーとは別")
    func ledgerPersistence() throws {
        let suite = "homerun-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var l = HomerunLedger(dayKey: 5)
        l.consume(); l.grantAd()
        HomerunStorage.saveLedger(l, defaults)
        #expect(HomerunStorage.loadLedger(defaults) == l)
        #expect(HomerunStorage.recordsKey != HomerunStorage.ledgerKey)
    }

    // MARK: 蓄積

    @Test("蓄積: 挑戦の要約が積み上がる")
    func recordsSummary() {
        var r = HomerunRecords()
        r.record(finished(perfect))
        #expect(r.challenges == 1 && r.pitches == 10 && r.homers == 10)
        #expect(r.totalDistanceTenths == 13500)
        #expect(r.bestTotalTenths == 13500)
        #expect(r.longestTenths == 1350)
        r.record(finished(nil))
        #expect(r.challenges == 2 && r.misses == 10)
        #expect(r.bestTotalTenths == 13500)  // 悪い挑戦では下がらない
        #expect(r.totalDistanceTenths == 13500)
    }

    @Test("蓄積: 集計は 5 方向 × 8 距離帯の 40 セルで、当たった球だけ数える")
    func recordsHeatmap() {
        #expect(HomerunRecords().heatmap.count == 40)
        var r = HomerunRecords()
        r.record(finished(perfect))
        // 135m は最後の帯（135〜）・センター
        #expect(r.heatmap[HomerunRecords.heatmapIndex(direction: 0, distance: 135)] == 10)
        #expect(r.heatmap.reduce(0, +) == 10)
        r.record(finished(nil))
        #expect(r.heatmap.reduce(0, +) == 10)  // 空振りは数えない
        #expect(HomerunRecords.distanceBand(59.9) == 0)
        #expect(HomerunRecords.distanceBand(60) == 1)
        #expect(HomerunRecords.distanceBand(121.9) == 5)
        #expect(HomerunRecords.distanceBand(122) == 6)
        #expect(HomerunRecords.distanceBand(135) == 7)
        #expect(HomerunRecords.distanceBand(300) == 7)
    }

    @Test("蓄積: 直近は 20 挑戦だけで、21 挑戦目で最古が消える")
    func recentRingBuffer() {
        var r = HomerunRecords()
        for i in 0..<25 {
            var c = HomerunChallenge()
            // 挑戦ごとに 1 球目だけ距離が違う（識別用）: 帯の中心から縦にずらして芯を落とす
            c.swing(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY + Double(i) * 0.4))
            while !c.isFinished { c.swing(nil) }
            r.record(c)
        }
        #expect(HomerunRecords.recentLimit == 20)
        #expect(r.recent.count == 20)
        #expect(r.challenges == 25)  // 通算は減らない
        // 残っているのは 6〜25 挑戦目（0 始まりで i = 5...24）
        let first = HomerunShot(HomerunJudge.judge(
            HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY + 5 * 0.4)))
        #expect(r.recent.first?.first == first)
    }

    @Test("蓄積: 保存量は数 KB 未満（上限まで貯めて実測）・読み戻せる・不正な種別は捨てる")
    func recordsSizeAndRoundTrip() throws {
        var r = HomerunRecords()
        for _ in 0..<50 { r.record(finished(perfect)) }
        let data = try JSONEncoder().encode(r)
        #expect(data.count < 4096, "\(data.count) bytes")
        #expect(try JSONDecoder().decode(HomerunRecords.self, from: data) == r)
        let bad = Data("[0,0,9]".utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HomerunShot.self, from: bad) }
    }

    @Test("蓄積: 受け口（schemaVersion・将来の空配列）を最初から持つ")
    func futureHooks() {
        let r = HomerunRecords()
        #expect(r.schemaVersion == 1)
        #expect(r.unlockedStadiums.isEmpty && r.unlockedBats.isEmpty && r.titles.isEmpty)
    }

    @Test("蓄積: 保存と読み込み・壊れたデータは初期値に戻る")
    func recordsPersistence() throws {
        let suite = "homerun-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var r = HomerunRecords()
        r.record(finished(perfect))
        HomerunStorage.saveRecords(r, defaults)
        #expect(HomerunStorage.loadRecords(defaults) == r)
        defaults.set(Data("garbage".utf8), forKey: HomerunStorage.recordsKey)
        #expect(HomerunStorage.loadRecords(defaults) == HomerunRecords())
    }
}
