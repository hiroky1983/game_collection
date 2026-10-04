import Testing
import Foundation
import HomerunCore
@testable import GameHomerun

/// 1 テスト 1 つの UserDefaults（台帳・蓄積の保存先）。
@MainActor
private final class Fixture {
    let defaults: UserDefaults
    private let name: String
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    /// 2027-01-15 12:00 JST。
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        name = "asobiba.homerun.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
    }

    deinit { UserDefaults().removePersistentDomain(forName: name) }

    /// 照準の吸い寄せは既定で切る（入力どおりの照準で判定を確かめる）。吸い寄せのテストだけ `.standard` を渡す。
    func model(pitches: [HomerunPitch] = HomerunPitch.standardSequence, aimAssist: HomerunAimAssist = .off,
               now: Date = Fixture.t0) -> HomerunModel {
        let model = HomerunModel(defaults: defaults, calendar: Self.calendar, pitches: pitches, aimAssist: aimAssist, now: now)
        // 空振りの演出（#1681）の「3 回に 1 回」は引かない（2 回目の空振りは必ず出るので、空振りを重ねるテストは `resultEnd` で閉じる）。
        model.whiffGagRoll = { 1 }
        return model
    }

    static var todayKey: Int { HomerunLedger.dayKey(for: t0, calendar: calendar) }
}

private func approx(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

@MainActor
private func arrival(_ model: HomerunModel) throws -> Date {
    try #require(model.arrival)
}

/// 押す → カーソルを**ボールの中心から** (dx, dy) の位置へずらす → `arrival + offset` 秒で離す。
@MainActor
@discardableResult
private func swing(_ model: HomerunModel, dx: Double, dy: Double, offset: TimeInterval) throws -> HomerunBattedBall? {
    let hit = try arrival(model).addingTimeInterval(offset)
    let start = CGPoint(x: 150, y: 600)
    model.press(at: start)
    let ball = model.ballPoint
    let end = CGPoint(x: start.x + ball.x + dx - model.cursor.x, y: start.y + ball.y + dy - model.cursor.y)
    return model.release(at: end, now: hit)
}

/// 見送りで 1 球進め、結果を閉じて次へ進める（最後の球なら終了）。戻り値は次の時刻。
@MainActor
@discardableResult
private func skipPitch(_ model: HomerunModel) throws -> Date {
    let deadline = try #require(model.nextWake)
    model.advance(now: deadline)
    let close = try #require(model.resultUntil)
    model.advance(now: close)
    return close
}

@Suite("柵越えおじさんの進行")
@MainActor
struct HomerunModelTests {

    @Test("打席に立った時点で挑戦回数を 1 減らして保存し、1.2 秒のマシンの込める動き（#1612）の後に 1.2 秒で輪が的に重なる")
    func startConsumesLedger() throws {
        let f = Fixture()
        let model = f.model()
        #expect(model.phase == .idle)
        #expect(model.ledger.remaining == 3)
        #expect(model.start(now: Fixture.t0))
        #expect(model.phase == .pitching)
        #expect(model.ledger.remaining == 2)
        #expect(model.ledger.dayKey == Fixture.todayKey)
        // 途中で画面を閉じても戻らない（開始時に保存済み）。
        #expect(HomerunStorage.loadLedger(f.defaults).used == 1)
        #expect(model.pitchStart == Fixture.t0.addingTimeInterval(1.2))
        #expect(model.arrival == Fixture.t0.addingTimeInterval(1.2).addingTimeInterval(1.2))
        #expect(model.pitchNumber == 1)
        #expect(model.challenge?.results.isEmpty == true)
    }

    @Test("打席の 3D を作り終えたら 1 球目のモーションを数え直す（作る間の停止でモーションが見えないまま的が出ない）。押した後・2 球目以降は数え直さない")
    func atBatDidAppearRestartsFirstPitch() throws {
        let fixture = Fixture()
        let model = fixture.model()
        let t0 = Fixture.t0
        model.start(now: t0)
        #expect(model.awaitsAtBat)
        // 画面が描き始めるまでは締め切りを待たせない（作る間に 1 球目が見送りで確定しない）。
        #expect(model.nextWake == nil)
        let ready = t0.addingTimeInterval(0.6)
        model.atBatDidAppear(now: ready)
        #expect(!model.awaitsAtBat)
        #expect(model.nextWake != nil)
        #expect(model.pitchStart == ready.addingTimeInterval(HomerunModel.windup))
        #expect(model.ballClock?.pitchStart == model.pitchStart)
        // 押した後は数え直さない。
        model.press(at: CGPoint(x: 150, y: 600), now: ready.addingTimeInterval(0.1))
        model.atBatDidAppear(now: ready.addingTimeInterval(0.2))
        #expect(model.pitchStart == ready.addingTimeInterval(HomerunModel.windup))
        // 2 球目以降も数え直さない。
        model.release(at: CGPoint(x: 150, y: 600), now: try arrival(model))
        model.advance(now: try #require(model.resultUntil))
        let second = model.pitchStart
        model.atBatDidAppear(now: ready.addingTimeInterval(10))
        #expect(model.pitchStart == second)
    }

    @Test("ホールド → ずらす → 離す: ボールの少し下でジャストなら中堅へ 180 m の柵越え（最高の当たり・#1647）")
    func justFlyToCenterIsHomer() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        // 1 球目は真ん中（zone 4）。ボールの 4pt 下 = フライの芯の基準点（#1647）。
        let ball = try #require(try swing(model, dx: 0, dy: 4, offset: 0))
        #expect(ball.kind == .homer)
        #expect(ball.timing == .just)
        #expect(ball.launch == .fly)
        #expect(approx(ball.distance, HomerunJudge.bestDistance))
        #expect(approx(ball.direction, 0))
        #expect(model.phase == .ballResult)
        #expect(model.lastBall == ball)
        #expect(model.challenge?.results == [ball])
    }

    @Test("タイミングは「離した時刻 − 輪が的に重なる時刻」（負が早い・引っ張り）")
    func timingOffsetIsReleaseMinusArrival() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        // -55ms（月まで飛ぶ ±50ms・#1680 の外のナイス）。
        let ball = try #require(try swing(model, dx: 0, dy: 4, offset: -0.055))
        let expected = HomerunJudge.judge(HomerunSwing(timingOffset: -55, cursorDX: 0, cursorDY: 4))
        #expect(ball.timing == .nice)
        #expect(approx(ball.direction, expected.direction, 1e-3))
        #expect(ball.direction < 0, "早いと引っ張り（左）")
        #expect(approx(ball.distance, 125 * 1.15, 1e-6))

        // 遅いと流し（右）。
        let close = try #require(model.resultUntil)
        model.advance(now: close)
        let late = try #require(try swing(model, dx: 0, dy: 4, offset: 0.08))
        #expect(late.timing == .hit)
        #expect(late.direction > 0, "2 球目は左上（zone 0）でも、ボールから測るので同じ結果の形になる")
    }

    @Test("カーソルは指の移動量だけ動く（トラックパッド式）。押した位置そのものには飛ばない")
    func cursorFollowsFingerDelta() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        model.press(at: CGPoint(x: 200, y: 700))
        #expect(model.cursor == .zero, "押しただけでは動かない")
        model.drag(to: CGPoint(x: 190, y: 730))
        #expect(model.cursor == CGPoint(x: -10, y: 30))
        // 指を離しても（モーション中は素振りで判定しない）カーソルは残り、次に押した位置から相対に動く。
        #expect(model.release(at: CGPoint(x: 190, y: 730), now: Fixture.t0.addingTimeInterval(0.3)) == nil)
        #expect(model.phase == .pitching, "モーション中に離しても判定しない")
        model.press(at: CGPoint(x: 50, y: 650))
        model.drag(to: CGPoint(x: 55, y: 640))
        #expect(model.cursor == CGPoint(x: -5, y: 20))
    }

    @Test("カーソルはゾーンの外 1 帯ぶんで止まる")
    func cursorIsClamped() {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        model.press(at: CGPoint(x: 0, y: 0))
        model.drag(to: CGPoint(x: 999, y: -999))
        #expect(model.cursor == CGPoint(x: HomerunZoneGeometry.cursorLimit, y: -HomerunZoneGeometry.cursorLimit))
        #expect(approx(HomerunZoneGeometry.cursorLimit, 77))
    }

    @Test("スイングのカーソル座標はボール（的）の中心から測る")
    func swingIsMeasuredFromBall() throws {
        let f = Fixture()
        // 左上（zone 0）のボール。
        let model = f.model(pitches: [HomerunPitch(zone: 0)])
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let cell = HomerunZoneGeometry.cellSize
        #expect(model.ballPoint == CGPoint(x: -cell, y: -cell))
        // カーソルをボールの 4pt 下（ゾーン中心からは (-cell, -cell + 4)）に置く。
        let ball = try #require(try swing(model, dx: 0, dy: 4, offset: 0))
        #expect(approx(Double(model.cursor.x), -cell, 1e-9) && approx(Double(model.cursor.y), -cell + 4, 1e-9))
        #expect(ball.kind == .homer)
        #expect(approx(ball.direction, 0, 1e-9))
        // ゾーン中心のまま振ると、ボールから (cell, cell) ずれて芯を外す（空振り）。
        let f2 = Fixture()
        let model2 = f2.model(pitches: [HomerunPitch(zone: 0)])
        model2.start(now: Fixture.t0)
        model2.atBatDidAppear(now: Fixture.t0)
        let whiff = try #require(try swing(model2, dx: cell, dy: cell, offset: 0))
        #expect(model2.cursor == .zero)
        #expect(whiff.kind == .miss)
    }

    @Test("押さずに見送りの締め切り（輪の 0.3 秒後）を過ぎたら見送り = 空振りと同じ扱い")
    func noSwingIsMiss() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let arrive = try arrival(model)
        #expect(HomerunModel.lateLimit == 0.3)
        #expect(model.nextWake == arrive.addingTimeInterval(0.3))
        model.advance(now: arrive.addingTimeInterval(0.299))
        #expect(model.phase == .pitching, "締め切りの前はまだ振れる（当たり窓の外なら遅い空振り）")
        model.advance(now: arrive.addingTimeInterval(0.3))
        #expect(model.phase == .ballResult)
        #expect(model.lastBall == HomerunJudge.judge(nil))
        #expect(model.lastBall?.kind == .miss)
        #expect(model.lastBall?.launch == nil)
    }

    @Test("振った球だけ swingCount が進み didSwingLastBall が立つ（3D の打者のスイングの合図）。見送りでは進まない")
    func swingCountOnlyCountsSwings() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        #expect(model.swingCount == 0 && !model.didSwingLastBall)
        try swing(model, dx: 0, dy: 10, offset: 0)
        #expect(model.phase == .ballResult)
        #expect(model.swingCount == 1 && model.didSwingLastBall)
        let close = try #require(model.resultUntil)
        model.advance(now: close)
        #expect(model.phase == .pitching)
        try skipPitch(model)
        #expect(model.swingCount == 1, "見送りで数が進んだ")
        #expect(!model.didSwingLastBall)
    }

    @Test("モーション中（的が出る前）に離すと素振り: 打者はその場で振るが、判定・球数・台帳・記録は変わらず、その球はそのまま来る")
    func releaseDuringWindupIsPracticeSwing() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let ledger = model.ledger
        let records = model.records
        let step = model.step
        let practice = Fixture.t0.addingTimeInterval(0.3)
        model.press(at: CGPoint(x: 150, y: 600), now: Fixture.t0.addingTimeInterval(0.1))
        #expect(model.release(at: CGPoint(x: 150, y: 600), now: practice) == nil)
        #expect(model.phase == .pitching && model.pitchNumber == 1)
        #expect(model.challenge?.results.isEmpty == true)
        #expect(model.swingCount == 0 && model.lastBall == nil)
        #expect(model.ledger == ledger && model.records == records && model.step == step)
        #expect(HomerunStorage.loadLedger(f.defaults) == ledger)
        #expect(model.pitchStart == Fixture.t0.addingTimeInterval(HomerunModel.windup), "その球はそのまま投げられてくる")
        #expect(model.ballClock?.practiceSwingAt == practice && model.ballClock?.pressedAt == nil)
        // 3D の打者: 離した瞬間から頭（20 コマ目）で振り抜き、振り終わったら構えへ戻る。
        let plan = HomerunSwingPlan(model: model)
        #expect(plan.batterMotion(at: practice) == .swing(start: practice))
        #expect(plan.batterMotion(at: practice.addingTimeInterval(0.5)) == .swing(start: practice))
        #expect(plan.batterMotion(at: practice.addingTimeInterval(HomerunBatterMotion.swingDuration)) == .stance)
        // もう一度押して、的が出た後に離せば通常の判定（当たり窓・結果は素振りの有無で変わらない）。
        let ball = try #require(try swing(model, dx: 0, dy: 4, offset: 0))
        #expect(ball.kind == .homer && ball.timing == .just)
        #expect(model.phase == .ballResult && model.swingCount == 1)
        #expect(model.challenge?.results == [ball])
    }

    @Test("素振りの振り抜き中に押し直して的が出てから離すと通常の判定。素振りは次の球へ持ち越さない")
    func pressAgainDuringPracticeSwing() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let pitchStart = try #require(model.pitchStart)
        let practice = pitchStart.addingTimeInterval(-0.1)
        model.press(at: CGPoint(x: 150, y: 600), now: practice.addingTimeInterval(-0.1))
        model.release(at: CGPoint(x: 150, y: 600), now: practice)
        model.press(at: CGPoint(x: 150, y: 600), now: practice.addingTimeInterval(0.05))
        let release = pitchStart.addingTimeInterval(0.2)   // 素振りの振り抜きの途中・的は出ている
        #expect(release < practice.addingTimeInterval(HomerunBatterMotion.swingDuration))
        let ball = try #require(model.release(at: CGPoint(x: 150, y: 600), now: release))
        #expect(ball.kind == .miss, "早すぎる空振り")
        #expect(model.phase == .ballResult && model.swingCount == 1 && model.challenge?.results.count == 1)
        #expect(model.ballClock?.releasedAt == release && model.ballClock?.practiceSwingAt == practice)
        let offset = try #require(model.ballClock?.timingOffset)
        #expect(HomerunSwingPlan(model: model).batterMotion(at: release)
                == .swing(start: HomerunSwingContact.swingStart(release: release, offsetMilliseconds: offset, column: 0),
                          catchUpFrom: release))
        let close = try #require(model.resultUntil)
        model.advance(now: close)
        #expect(model.phase == .pitching && model.ballClock?.practiceSwingAt == nil)
    }

    @Test("押したまま締め切りを過ぎても見送り。結果の間に離しても判定も素振りもしない（会長 QA 2026-09-30）")
    func holdingPastDeadlineIsMiss() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        model.press(at: CGPoint(x: 10, y: 10))
        model.drag(to: CGPoint(x: 10, y: 32))
        let arrive = try arrival(model)
        model.advance(now: arrive.addingTimeInterval(HomerunModel.lateLimit))
        #expect(model.lastBall?.kind == .miss)
        #expect(model.challenge?.results.count == 1)
        #expect(!model.didSwingLastBall && model.lastMissReason == nil, "見送り（理由は出さない）")
        // 結果を見せているあいだに離しても判定しない。見送りのカードの裏で打者が振らないよう素振りにもしない。
        #expect(model.release(at: CGPoint(x: 10, y: 32), now: arrive.addingTimeInterval(0.8)) == nil)
        #expect(model.challenge?.results.count == 1)
        #expect(model.ballClock?.practiceSwingAt == nil)
        // その後に押し直して離せば、結果の間の素振りは今までどおり。
        model.press(at: CGPoint(x: 10, y: 32))
        #expect(model.release(at: CGPoint(x: 10, y: 32), now: arrive.addingTimeInterval(0.9)) == nil)
        #expect(model.ballClock?.practiceSwingAt == arrive.addingTimeInterval(0.9))
    }

    @Test("結果の間に押して離すと素振り（判定なし）。振っている最中の素振りは受け付けず、振り終わっていない素振りは次の球へ持ち越す")
    func practiceSwingDuringResult() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let arrive = try arrival(model)
        let ball = try #require(try swing(model, dx: 40, dy: 0, offset: 0))
        #expect(ball.kind == .miss)
        let step = model.step
        // 本番の振り（離した瞬間から 0.8 秒）の途中: 受け付けない。
        model.press(at: CGPoint(x: 100, y: 600))
        #expect(model.release(at: CGPoint(x: 100, y: 600), now: arrive.addingTimeInterval(0.5)) == nil)
        #expect(model.ballClock?.practiceSwingAt == nil)
        #expect(model.isSwinging(at: arrive.addingTimeInterval(0.5)))
        // 振り終わった後: 素振り。判定・球数・進行は変わらない。
        model.press(at: CGPoint(x: 100, y: 600))
        let practice = arrive.addingTimeInterval(HomerunBatterMotion.swingDuration + 0.1)
        #expect(model.release(at: CGPoint(x: 100, y: 600), now: practice) == nil)
        #expect(model.ballClock?.practiceSwingAt == practice)
        #expect(model.challenge?.results.count == 1 && model.swingCount == 1 && model.step == step && model.phase == .ballResult)
        #expect(HomerunSwingPlan(model: model).batterMotion(at: practice) == .swing(start: practice))
        // 結果が閉じても振り終わっていなければ、次の球のモーション中も最後まで振る。
        let close = try #require(model.resultUntil)
        #expect(close < practice.addingTimeInterval(HomerunBatterMotion.swingDuration))
        model.advance(now: close)
        #expect(model.phase == .pitching && model.ballClock?.practiceSwingAt == practice)
        #expect(HomerunSwingPlan(model: model).batterMotion(at: close) == .swing(start: practice))
    }

    @Test("空振りの理由: 早い / 遅い / 照準のずれ。当たり・見送りは理由なし")
    func missReasons() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        try swing(model, dx: 0, dy: 4, offset: -0.2)
        #expect(model.lastBall?.kind == .miss && model.lastMissReason == .early)
        model.advance(now: try #require(model.resultEnd))
        try swing(model, dx: 0, dy: 4, offset: 0.2)
        #expect(model.lastBall?.kind == .miss && model.lastMissReason == .late)
        model.advance(now: try #require(model.resultEnd))
        try swing(model, dx: 40, dy: 0, offset: 0)
        #expect(model.lastBall?.kind == .miss && model.lastMissReason == .aim)
        model.advance(now: try #require(model.resultEnd))
        try swing(model, dx: 0, dy: 4, offset: 0)
        #expect(model.lastBall?.kind != .miss && model.lastMissReason == nil)
        model.advance(now: try #require(model.resultUntil))
        try skipPitch(model)
        #expect(model.lastMissReason == nil)
        #expect(HomerunAtBatView.missNote(didSwing: false, reason: nil) == nil, "見送りは理由を付けず見出しを「見送り」にする")
        #expect(HomerunAtBatView.missNote(didSwing: true, reason: .early) == "振るのが早い")
        #expect(HomerunAtBatView.missNote(didSwing: true, reason: .late) == "振るのが遅い")
        #expect(HomerunAtBatView.missNote(didSwing: true, reason: .aim) == "照準がずれた")
        #expect(HomerunAtBatView.missNote(didSwing: true, reason: nil) == nil)
    }

    @Test("結果のカード: 見送りは見出し「見送り」で理由なし、振って外したら見出し「空振り」＋理由（会長 QA 2026-09-30）")
    func resultCardHeadline() {
        let miss = HomerunJudge.judge(nil)
        #expect(HomerunBallResultCard.headline(miss, tookPitch: true) == "見送り")
        #expect(HomerunBallResultCard.reasonLine(miss, tookPitch: true,
                                                 missNote: HomerunAtBatView.missNote(didSwing: false, reason: nil)) == nil)
        let whiff = HomerunJudge.judge(HomerunSwing(timingOffset: 300, cursorDX: 0, cursorDY: 0))
        #expect(whiff.kind == .miss)
        #expect(HomerunBallResultCard.headline(whiff, tookPitch: false) == "空振り")
        #expect(HomerunBallResultCard.reasonLine(whiff, tookPitch: false,
                                                 missNote: HomerunAtBatView.missNote(didSwing: true, reason: .late)) == "振るのが遅い")
        let homer = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 4))
        // 最高の当たり（中堅 180m）はスタンドの最後列の後端（約 148m）を越えるので「場外！」（#1654）。
        #expect(homer.isOutOfPark)
        #expect(HomerunBallResultCard.headline(homer, tookPitch: false) == "場外！")
        #expect(HomerunBallResultCard.reasonLine(homer, tookPitch: false, missNote: nil) == nil)
    }

    @Test("照準の吸い寄せ: 投球中に押している間だけ、押し始め（的が出る前からなら的が出た瞬間）からの時間でボールへ寄り、離した位置で判定する")
    func aimAssistPullsTowardBall() throws {
        let f = Fixture()
        let assist = HomerunAimAssist.standard
        #expect(assist.pull(heldFor: 0) == 0)
        #expect(abs(assist.pull(heldFor: assist.rampSeconds / 2) - assist.maxPull / 2) < 1e-9)
        #expect(assist.pull(heldFor: assist.rampSeconds * 3) == assist.maxPull)
        #expect(HomerunAimAssist.off.pull(heldFor: 10) == 0)
        // 右上（zone 2）のボール。カーソルは中央のまま。
        let model = f.model(pitches: [HomerunPitch(zone: 2)], aimAssist: assist)
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let pitchStart = try #require(model.pitchStart)
        let ballPoint = model.ballPoint
        #expect(model.aimCursor(at: pitchStart.addingTimeInterval(0.5)) == .zero, "押していなければ寄らない")
        model.press(at: CGPoint(x: 150, y: 600), now: Fixture.t0.addingTimeInterval(0.1))   // モーション中から押している
        #expect(model.aimCursor(at: pitchStart.addingTimeInterval(-0.1)) == .zero, "的が出る前は寄らない")
        let half = model.aimCursor(at: pitchStart.addingTimeInterval(assist.rampSeconds / 2))
        #expect(abs(Double(half.x) - Double(ballPoint.x) * assist.maxPull / 2) < 1e-9)
        #expect(abs(Double(half.y) - Double(ballPoint.y) * assist.maxPull / 2) < 1e-9)
        #expect(model.cursor == .zero, "指で動かしたカーソルそのものは変わらない")
        // 輪が重なった瞬間に離す: 寄せた位置で判定する（中央のままでも、1 マス離れたボールに当たる）。
        let arrive = try arrival(model)
        let aimed = model.aimCursor(at: arrive)
        let ball = try #require(model.release(at: CGPoint(x: 150, y: 600), now: arrive))
        #expect(model.cursor == aimed, "離した瞬間の照準が結果の間も残る")
        let expected = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: Double(aimed.x - ballPoint.x), cursorDY: Double(aimed.y - ballPoint.y)))
        #expect(ball == expected)
        #expect(ball.kind != .miss, "吸い寄せで当たる")
        // 吸い寄せを切ると、中央のままでは 1 マス離れた右上のボールには当たらない。
        let f2 = Fixture()
        let plain = f2.model(pitches: [HomerunPitch(zone: 2)])
        plain.start(now: Fixture.t0)
        plain.atBatDidAppear(now: Fixture.t0)
        plain.press(at: CGPoint(x: 150, y: 600), now: Fixture.t0.addingTimeInterval(0.1))
        let whiff = try #require(plain.release(at: CGPoint(x: 150, y: 600), now: try arrival(plain)))
        #expect(whiff.kind == .miss && plain.lastMissReason == .aim)
    }

    @Test("1 球の結果は種別ごとの時間だけ見せ、次の球ではカーソルが中央へ戻る。押したままなら今の指が新しい基準")
    func resultThenNextPitch() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let hitAt = try arrival(model)
        // 芯の基準点から 2pt 下（月まで飛ぶ 0.5pt・#1680 の外の柵越え）。
        let ball = try #require(try swing(model, dx: 0, dy: 6, offset: 0))
        #expect(ball.kind == .homer && !ball.isMoon)
        #expect(model.resultUntil == hitAt.addingTimeInterval(HomerunModel.resultDuration(for: ball)))
        #expect(HomerunModel.resultDuration(for: .miss) < HomerunModel.resultDuration(for: .homer))
        let close = try #require(model.resultUntil)
        // 結果を見せているあいだに押してずらしておく。
        model.press(at: CGPoint(x: 100, y: 100))
        model.drag(to: CGPoint(x: 120, y: 100))
        #expect(model.cursor == CGPoint(x: 20, y: 6))
        model.advance(now: close.addingTimeInterval(-0.01))
        #expect(model.phase == .ballResult)
        model.advance(now: close)
        #expect(model.phase == .pitching)
        #expect(model.pitchNumber == 2)
        #expect(model.cursor == .zero, "投球ごとにゾーンの中央へ戻る")
        #expect(model.pitchStart == close.addingTimeInterval(1.2))
        // 基準は投球が替わった時点の指の位置（120, 100）。
        model.drag(to: CGPoint(x: 125, y: 110))
        #expect(model.cursor == CGPoint(x: 5, y: 10))
    }

    @Test("10 球で終わり、蓄積に取り込んで保存する。自己ベストの更新も判定する")
    func tenPitchesFinishAndRecord() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        for i in 0..<HomerunChallenge.pitchCount {
            #expect(model.phase == .pitching)
            #expect(model.pitchNumber == i + 1)
            if i == 0 {
                try swing(model, dx: 0, dy: 4, offset: 0)   // 180 m の柵越え
                model.advance(now: try #require(model.resultUntil))
            } else {
                try skipPitch(model)
            }
        }
        #expect(model.phase == .finished)
        #expect(model.challenge?.results.count == 10)
        #expect(model.nextWake == nil)
        #expect(model.isNewBest)
        #expect(model.records.challenges == 1)
        #expect(model.records.pitches == 10)
        #expect(model.records.homers == 1)
        #expect(model.records.misses == 9)
        #expect(model.records.bestTotalTenths == 1800)
        #expect(HomerunStorage.loadRecords(f.defaults) == model.records, "終了時に保存する")

        // 2 回目: 全部見送り → ベスト更新ではない。
        #expect(model.start(now: Fixture.t0.addingTimeInterval(60)))
        model.atBatDidAppear(now: Fixture.t0.addingTimeInterval(60))
        #expect(model.challenge?.results.isEmpty == true, "新しい挑戦は空から")
        for _ in 0..<HomerunChallenge.pitchCount { try skipPitch(model) }
        #expect(model.phase == .finished)
        #expect(!model.isNewBest)
        #expect(HomerunStorage.loadRecords(f.defaults).challenges == 2)
        #expect(HomerunStorage.loadLedger(f.defaults).used == 2)
    }

    @Test("9 球目までは蓄積に書かず、10 球目を打った時点（結果を見せる前）に書く")
    func recordsWhenTenthPitchResolves() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        for _ in 0..<9 { try skipPitch(model) }
        #expect(model.phase == .pitching)
        #expect(HomerunStorage.loadRecords(f.defaults).challenges == 0)
        #expect(model.records.challenges == 0)
        // 10 球目の結果を見せているあいだに画面を閉じても、打ち終えた挑戦は残る。
        model.advance(now: try #require(model.nextWake))
        #expect(model.phase == .ballResult)
        #expect(HomerunStorage.loadRecords(f.defaults).challenges == 1)
        #expect(HomerunStorage.loadRecords(f.defaults).pitches == 10)
        model.advance(now: try #require(model.resultUntil))
        #expect(model.phase == .finished)
        #expect(HomerunStorage.loadRecords(f.defaults).challenges == 1, "終了で二重に取り込まない")
    }

    @Test("止まっているあいだは押せず、止める・戻すたびに step が 1 ずつ進み、戻ったらカーソルは中央")
    func holdBlocksPressAndAdvancesStep() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        model.press(at: .zero)
        model.drag(to: CGPoint(x: 30, y: 30))
        let s0 = model.step
        model.hold(.sheet, true, now: Fixture.t0)
        #expect(model.step == s0 + 1)
        model.press(at: CGPoint(x: 5, y: 5))
        #expect(!model.isHolding, "止まっているあいだは押せない")
        model.hold(.sheet, true, now: Fixture.t0)
        #expect(model.step == s0 + 1, "同じ理由を重ねても進まない")
        model.hold(.sheet, false, now: Fixture.t0.addingTimeInterval(1))
        #expect(model.step > s0 + 1)
        #expect(model.cursor == .zero, "投げ直しの球ではカーソルが中央へ戻る")
        #expect(!model.isHolding)
    }

    @Test("一時停止（#1550）: 止めているあいだは進まず押せない。再開でその球を投げ直す。打席前・結果では効かない")
    func pauseStopsThePitchAndResumeRepitches() throws {
        let f = Fixture()
        let model = f.model()
        model.pause(now: Fixture.t0)
        #expect(!model.isPaused, "打席前では止めない")
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let number = model.pitchNumber
        let used = model.ledger.remaining
        model.pause(now: Fixture.t0.addingTimeInterval(0.5))
        #expect(model.isPaused && model.isHeld)
        #expect(model.nextWake == nil, "止めているあいだは時計が進まない")
        #expect(model.pitchStart == nil)
        model.press(at: CGPoint(x: 5, y: 5))
        #expect(!model.isHolding, "止めているあいだは押せない")
        model.resume(now: Fixture.t0.addingTimeInterval(10))
        #expect(!model.isPaused && !model.isHeld)
        #expect(model.phase == .pitching && model.pitchNumber == number, "同じ球を投げ直す")
        #expect(model.pitchStart != nil && model.nextWake != nil)
        #expect(model.ledger.remaining == used, "台帳は動かない")
    }

    @Test("一時停止とバックグラウンドは別の理由: 前面に戻っても一時停止は解けない")
    func pauseSurvivesInactive() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        model.pause(now: Fixture.t0)
        model.hold(.inactive, true, now: Fixture.t0)
        model.hold(.inactive, false, now: Fixture.t0.addingTimeInterval(1))
        #expect(model.isPaused && model.nextWake == nil)
    }

    @Test("途中でやめる（#1550）: 一時停止中だけ効き、打席前へ戻る。回数は戻らず、記録は付かない")
    func quitChallengeFromPause() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let remaining = model.ledger.remaining
        let records = model.records
        model.quitChallenge()
        #expect(model.phase == .pitching, "止めていなければやめられない")
        model.pause(now: Fixture.t0)
        let s0 = model.step
        model.quitChallenge()
        #expect(model.phase == .idle)
        #expect(model.challenge == nil && model.lastBall == nil && model.ballClock == nil)
        #expect(!model.isPaused && !model.isHeld && !model.isHolding)
        #expect(model.step == s0 + 1)
        #expect(model.ledger.remaining == remaining, "使った回数は戻らない")
        #expect(model.records == records, "途中でやめた挑戦は記録に付けない")
        #expect(model.nextWake == nil)
        #expect(model.start(now: Fixture.t0.addingTimeInterval(5)), "続けて次の挑戦に立てる（回数が残っていれば）")
    }

    // 鍵（`debugUnlimitedKey`）は `HomerunModel+Debug.swift` の #if DEBUG の中だけの宣言なので、
    // 参照するこのテストも同じく #if DEBUG で囲む（出荷ビルドのテストが壊れないように・#1705）。
    #if DEBUG
    @Test("動作確認用の回数無制限: 立っても回数が減らず、使い切りでも立てる。既定はオフ")
    func debugUnlimitedChallenges() throws {
        let f = Fixture()
        HomerunStorage.saveLedger(HomerunLedger(dayKey: Fixture.todayKey, used: 3), f.defaults)
        let model = f.model()
        #expect(!model.start(now: Fixture.t0), "既定（鍵なし）は出荷の挙動")
        f.defaults.set(true, forKey: HomerunModel.debugUnlimitedKey)
        #expect(model.start(now: Fixture.t0))
        #expect(model.ledger.remaining == 0)
    }
    #endif

    @Test("回数が無ければ打席に立てない。日付が進めば 0:00 で補充")
    func exhaustedThenNextDay() throws {
        let f = Fixture()
        HomerunStorage.saveLedger(HomerunLedger(dayKey: Fixture.todayKey, used: 3), f.defaults)
        let model = f.model()
        #expect(model.ledger.remaining == 0)
        #expect(!model.start(now: Fixture.t0))
        #expect(model.phase == .idle)
        #expect(model.ledger.used == 3, "失敗した開始で消費しない")
        #expect(model.challenge == nil)

        let tomorrow = Fixture.t0.addingTimeInterval(24 * 3600)
        #expect(model.start(now: tomorrow))
        #expect(model.ledger.used == 1)
        #expect(model.ledger.dayKey == HomerunLedger.dayKey(for: tomorrow, calendar: Fixture.calendar))
    }

    @Test("時計を戻しても補充されない")
    func clockBackDoesNotRefill() {
        let f = Fixture()
        let tomorrowKey = HomerunLedger.dayKey(for: Fixture.t0.addingTimeInterval(24 * 3600), calendar: Fixture.calendar)
        HomerunStorage.saveLedger(HomerunLedger(dayKey: tomorrowKey, used: 3), f.defaults)
        let model = f.model()
        #expect(!model.start(now: Fixture.t0))
        #expect(model.ledger.dayKey == tomorrowKey)
    }

    @Test("画面を開いたまま日付が変わったら refreshDay で補充して保存する")
    func refreshDayRollsAndSaves() {
        let f = Fixture()
        HomerunStorage.saveLedger(HomerunLedger(dayKey: Fixture.todayKey, used: 3), f.defaults)
        let model = f.model()
        model.refreshDay(now: Fixture.t0.addingTimeInterval(24 * 3600))
        #expect(model.ledger.remaining == 3)
        #expect(HomerunStorage.loadLedger(f.defaults).used == 0)
    }

    @Test("止めると投球が止まり、戻ったらその球を投げ直す（台帳は戻さない）")
    func pauseRestartsPitch() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        try skipPitch(model)
        #expect(model.pitchNumber == 2)
        model.press(at: .zero)
        let paused = Fixture.t0.addingTimeInterval(10)
        model.hold(.inactive, true, now: paused)
        #expect(model.isHeld)
        #expect(!model.isHolding, "押していた指は外す")
        #expect(model.nextWake == nil)
        #expect(model.timingOffset(at: paused) == nil)
        model.advance(now: paused.addingTimeInterval(3600))
        #expect(model.phase == .pitching, "止まっているあいだは見送りにならない")
        #expect(model.challenge?.results.count == 1)
        // 理由が 2 つ重なったら、両方外すまで止まったまま。
        model.hold(.sheet, true, now: paused)
        model.hold(.inactive, false, now: paused.addingTimeInterval(5))
        #expect(model.isHeld)
        let resumed = paused.addingTimeInterval(20)
        model.hold(.sheet, false, now: resumed)
        #expect(!model.isHeld)
        #expect(model.pitchNumber == 2, "同じ球をやり直す")
        #expect(model.pitchStart == resumed.addingTimeInterval(1.2))
        #expect(model.ledger.used == 1)
        #expect(HomerunStorage.loadLedger(f.defaults).used == 1)
    }

    @Test("結果を見せているあいだに止めたら、戻ってから見せ直す")
    func pauseDuringResult() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        let deadline = try #require(model.nextWake)
        model.advance(now: deadline)
        #expect(model.phase == .ballResult)
        model.hold(.inactive, true, now: deadline)
        model.advance(now: deadline.addingTimeInterval(60))
        #expect(model.phase == .ballResult)
        let back = deadline.addingTimeInterval(100)
        model.hold(.inactive, false, now: back)
        #expect(model.resultUntil == back.addingTimeInterval(HomerunModel.resultDuration(for: .miss)))
    }

    @Test("打球を追っている間に止めたら、戻ったときは止めた所から追い直す（#1613）")
    func pauseDuringChaseResumesTheFlight() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        _ = try arrival(model)
        let ball = try #require(try swing(model, dx: 0, dy: 4, offset: 0))
        #expect(ball.kind != .miss)
        let contact = try #require(HomerunSwingPlan(model: model).contactAt)
        let paused = contact.addingTimeInterval(0.5)
        let before = try #require(HomerunSwingPlan(model: model).chaseFrame(at: paused))
        model.pause(now: paused)
        let back = paused.addingTimeInterval(30)
        model.resume(now: back)
        let plan = HomerunSwingPlan(model: model)
        #expect(plan.chaseFrame(at: back) == before, "止めた所から続かない")
        let card = try #require(plan.chaseCardAt)
        #expect(card > back, "戻った直後にカードが出てしまう")
        #expect(try #require(model.resultUntil).timeIntervalSince(card) >= HomerunBallChase.cardHold - 1e-6)
    }

    @Test("step は進行が変わるたびに進む（View の待ちの鍵）")
    func stepAdvances() throws {
        let f = Fixture()
        let model = f.model()
        let s0 = model.step
        model.start(now: Fixture.t0)
        let s1 = model.step
        #expect(s1 == s0 + 1)
        try swing(model, dx: 0, dy: 4, offset: 0)
        #expect(model.step == s1 + 1)
        model.advance(now: try #require(model.resultUntil))
        #expect(model.step == s1 + 2)
        // 締め切り前の advance では進まない（View の待ちを組み直さない）。
        model.advance(now: Fixture.t0)
        #expect(model.step == s1 + 2)
    }

    @Test("方向メーターの先読みはタイミングを当たり窓の端に丸める")
    func previewSwing() throws {
        let f = Fixture()
        let model = f.model()
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        model.press(at: .zero)
        model.drag(to: CGPoint(x: -11, y: 22))
        // モーション中（的が出る前）は窓の早い端。
        let early = model.previewSwing(at: Fixture.t0)
        #expect(early.timingOffset == -HomerunTiming.hitWindow)
        #expect(early.cursorDX == -11 && early.cursorDY == 22)
        #expect(approx(HomerunJudge.direction(early), -50))
        let arrive = try arrival(model)
        #expect(approx(model.previewSwing(at: arrive).timingOffset, 0, 1e-3))
        #expect(model.previewSwing(at: arrive.addingTimeInterval(0.5)).timingOffset == HomerunTiming.hitWindow)
    }

    @Test("10 球の結果から打席前へ戻れる。途中では戻らない")
    func backToLobby() throws {
        let f = Fixture()
        let model = f.model(pitches: [HomerunPitch(zone: 4)])
        model.start(now: Fixture.t0)
        model.atBatDidAppear(now: Fixture.t0)
        model.backToLobby()
        #expect(model.phase == .pitching)
        try skipPitch(model)
        #expect(model.phase == .finished)
        model.backToLobby()
        #expect(model.phase == .idle)
        #expect(model.challenge == nil)
    }
}
