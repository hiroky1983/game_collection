import Testing
import Foundation
@testable import HomerunCore

/// 月まで飛ぶ隠し演出（#1680・会長決裁 2026-10-01）の判定・1 挑戦・台帳・蓄積。
@Suite("柵越えおじさんの月まで飛ぶ隠し演出")
struct HomerunMoonTests {
    private let flyCenter = HomerunLaunch.fly.centerDY
    private let normal = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY + 3)

    private func swing(_ ms: Double, dx: Double = 0, dy: Double? = nil) -> HomerunSwing {
        HomerunSwing(timingOffset: ms, cursorDX: dx, cursorDY: dy ?? flyCenter)
    }

    // MARK: 発生条件

    @Test("発生条件: タイミング ±50ms 以内 かつ フライの芯の基準点から 1pt 以内（境界は含む）")
    func conditionBoundaries() {
        #expect(HomerunJudge.moonTimingWindow == 50)
        #expect(HomerunJudge.moonCursorRadius == 1)
        // タイミングの境界。
        #expect(HomerunJudge.isMoonShot(swing(0)))
        #expect(HomerunJudge.isMoonShot(swing(50)))
        #expect(HomerunJudge.isMoonShot(swing(-50)))
        #expect(!HomerunJudge.isMoonShot(swing(50.1)))
        #expect(!HomerunJudge.isMoonShot(swing(-50.1)))
        // カーソルの境界（縦・横・斜め）。
        #expect(HomerunJudge.isMoonShot(swing(0, dy: flyCenter + 1)))
        #expect(HomerunJudge.isMoonShot(swing(0, dy: flyCenter - 1)))
        #expect(HomerunJudge.isMoonShot(swing(0, dx: 1)))
        #expect(!HomerunJudge.isMoonShot(swing(0, dy: flyCenter + 1.01)))
        #expect(!HomerunJudge.isMoonShot(swing(0, dx: -1.01)))
        #expect(HomerunJudge.isMoonShot(swing(0, dx: 0.7, dy: flyCenter + 0.7)))
        #expect(!HomerunJudge.isMoonShot(swing(0, dx: 0.75, dy: flyCenter + 0.75)))
        // 何もずらさずボールの中心を打った（照準の吸い寄せの寄せる先）は月にならない。
        #expect(!HomerunJudge.isMoonShot(swing(0, dy: 0)))
        // 両方そろって初めて月。
        #expect(!HomerunJudge.isMoonShot(swing(60, dx: 0)))
    }

    @Test("1 挑戦の判定: 条件の中は柵越え・180m・月（.hit）。外・見送りはふだんの判定（月にならない）。飛距離の式（judge）は月を持たない")
    func judgeMoonBall() {
        for s in [swing(0), swing(-50, dx: 1), swing(50, dy: flyCenter - 1)] {
            var c = HomerunChallenge()
            let ball = c.swing(s)!
            #expect(HomerunJudge.judge(s).moon == nil)
            #expect(ball.moon == .hit)
            #expect(ball.isMoon)
            #expect(ball.kind == .homer)
            #expect(ball.distance == HomerunJudge.moonCountedDistance)
            #expect(ball.distance == 180)
            #expect(ball.launch == .fly)
            #expect(abs(ball.direction) <= HomerunJudge.foulLimit)
        }
        var c = HomerunChallenge()
        let near = c.swing(swing(51))
        #expect(near?.moon == nil && near?.kind == .homer)
        #expect(c.swing(normal)?.moon == nil)
        #expect(c.swing(nil)?.moon == nil)
        #expect(HomerunMoon.displayKilometers == 384_400)
    }

    @Test("確認用の強制（-homerunForceMoon）: 振れば窓の外でも月・見送りは月にならない・方向はフェアに丸める")
    func forcedMoon() {
        var c = HomerunChallenge(forcesMoon: true)
        let late = c.swing(HomerunSwing(timingOffset: 200, cursorDX: 30, cursorDY: 30))
        #expect(late?.moon == .hit)
        #expect(late?.kind == .homer)
        #expect(abs(late?.direction ?? 99) <= 20)
        let took = c.swing(nil)
        #expect(took?.moon == nil && took?.kind == .miss)
        let second = c.swing(HomerunSwing(timingOffset: -300, cursorDX: -30, cursorDY: -30))
        #expect(second?.moon == .broken)
        #expect(c.isFinished)
    }

    // MARK: 1 挑戦

    @Test("1 挑戦: 1 回目はヒビ（.hit）で続く・2 回目で割れ（.broken）、その場で挑戦が終わり残りの球は没収")
    func firstAndSecondMoon() {
        var c = HomerunChallenge()
        c.swing(normal)
        let first = c.swing(swing(0))
        #expect(first?.moon == .hit)
        #expect(c.moonCount == 1 && !c.isMoonBroken && !c.isFinished)
        c.swing(normal)
        c.swing(nil)
        let second = c.swing(swing(20, dx: 0.4))
        #expect(second?.moon == .broken)
        #expect(c.moonCount == 2 && c.isMoonBroken)
        #expect(c.isFinished)
        #expect(c.currentPitch == nil)
        #expect(c.results.count == 5)
        // 終わった後は振っても何も起きない（残りの球は没収）。
        #expect(c.swing(normal) == nil)
        #expect(c.results.count == 5)
        // それまでの記録は残る: 合計は月を 180m として数える。
        let normalDistance = HomerunJudge.judge(normal).distance
        #expect(abs(c.totalDistance - (2 * normalDistance + 360)) < 1e-9)
        #expect(c.homerCount == 4)
    }

    // MARK: 台帳

    @Test("台帳: 月が割れたら当日分として +2（上限なし・何回でも）・0:00 で消える")
    func ledgerMoonBonus() {
        var l = HomerunLedger(dayKey: 20261001, legacyAdGrants: 5)  // 以前の版で貯めた広告分
        l.grantSurvey()
        #expect(l.allowance == 9)
        l.grantMoonBonus()
        #expect(l.bonus == 2)
        #expect(l.allowance == 11)
        #expect(l.remaining == 11)
        l.grantMoonBonus()
        #expect(l.allowance == 13)
        for _ in 0..<13 { l.consume() }
        #expect(!l.canStart)
        l.roll(to: 20261002)
        #expect(l.bonus == 0)
        #expect(l.allowance == HomerunLedger.freePerDay)
    }

    @Test("台帳の保存の互換: 以前の保存（ボーナスのキー無し）が読める・ボーナス 0 はキーを書かない・+2 は読み戻せる")
    func ledgerCompatibility() throws {
        let old = Data(#"{"dayKey":20261001,"used":2,"adsWatched":1,"surveyDone":true}"#.utf8)
        let decoded = try JSONDecoder().decode(HomerunLedger.self, from: old)
        #expect(decoded == HomerunLedger(dayKey: 20261001, used: 2, legacyAdGrants: 1, surveyDone: true))
        #expect(decoded.bonus == 0)
        #expect(decoded.remaining == 3)

        let plain = try JSONEncoder().encode(HomerunLedger(dayKey: 20261001, used: 1))
        let plainKeys = try #require(try JSONSerialization.jsonObject(with: plain) as? [String: Any]).keys
        #expect(Set(plainKeys) == ["dayKey", "used", "adsWatched", "surveyDone"])

        var granted = HomerunLedger(dayKey: 20261001, used: 3)
        granted.grantMoonBonus()
        let data = try JSONEncoder().encode(granted)
        let back = try JSONDecoder().decode(HomerunLedger.self, from: data)
        #expect(back == granted)
        #expect(back.remaining == 2)

        let suite = "homerun-moon-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(old, forKey: HomerunStorage.ledgerKey)
        #expect(HomerunStorage.loadLedger(defaults) == decoded)
    }

    // MARK: 蓄積

    @Test("蓄積: 月は 180m として自己ベスト・合計・最長に数え、実績（月まで飛ばした・割れた）を別に数える")
    func recordsCountMoonAs180() {
        var r = HomerunRecords()
        var c = HomerunChallenge()
        c.swing(swing(0))
        c.swing(swing(0))
        #expect(c.isFinished)
        r.record(c)
        #expect(r.longestTenths == 1800)
        #expect(r.bestTotalTenths == 3600)
        #expect(r.totalDistanceTenths == 3600)
        #expect(r.homers == 2)
        #expect(r.pitches == 2)
        #expect(r.moonShots == 2)
        #expect(r.moonBreaks == 1)
        #expect(r.recent.last?.map(\.distance) == [180, 180])

        var once = HomerunChallenge()
        once.swing(swing(0))
        while !once.isFinished { once.swing(nil) }
        r.record(once)
        #expect(r.moonShots == 3)
        #expect(r.moonBreaks == 1)
    }

    @Test("蓄積の保存の互換: 以前の保存（実績のキー無し）が読める・実績 0 はキーを書かない・実績は読み戻せる")
    func recordsCompatibility() throws {
        var r = HomerunRecords()
        var c = HomerunChallenge()
        while !c.isFinished { c.swing(normal) }
        r.record(c)
        let data = try JSONEncoder().encode(r)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("moon"))
        // 以前の版が書いた形（実績のキー無し）を読める。
        let back = try JSONDecoder().decode(HomerunRecords.self, from: data)
        #expect(back == r)
        #expect(back.moonShots == 0 && back.moonBreaks == 0)

        var m = HomerunChallenge()
        m.swing(swing(0))
        m.swing(swing(0))
        r.record(m)
        let withMoon = try JSONDecoder().decode(HomerunRecords.self, from: try JSONEncoder().encode(r))
        #expect(withMoon.moonShots == 2 && withMoon.moonBreaks == 1)
        #expect(withMoon == r)
    }
}
