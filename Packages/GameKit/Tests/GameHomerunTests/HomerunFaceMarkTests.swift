import Testing
import Foundation
import simd
@testable import HomerunCore
@testable import GameHomerun

/// 結果に応じて頭に重ねる記号（キラキラ目・怒りマーク・#1760）: 発生条件はモデル側の純粋な値で固定する。
@Suite("柵越えおじさんの頭の記号")
@MainActor
struct HomerunFaceMarkTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func ball(_ kind: HomerunKind, _ timing: HomerunTiming) -> HomerunBattedBall {
        HomerunBattedBall(direction: 0, distance: 0, kind: kind, timing: timing, launch: kind == .miss ? nil : .fly, fence: 100)
    }

    private func decide(_ kind: HomerunKind, _ timing: HomerunTiming, swung: Bool = true,
                        best: Bool = false) -> HomerunFaceMark {
        .decide(ball: ball(kind, timing), swung: swung, isNewBest: best)
    }

    @Test("ジャストの当たり・柵越え・自己ベスト更新ではキラキラ目。ふつうの当たり・ファウル・見送りでは出ない")
    func sparkleRule() {
        #expect(decide(.inPlay, .just) == .sparkle)
        #expect(decide(.fenceHit, .just) == .sparkle)
        #expect(decide(.homer, .just) == .sparkle)
        #expect(decide(.homer, .hit) == .sparkle, "柵越えならジャストでなくても")
        #expect(decide(.inPlay, .nice, best: true) == .sparkle, "自己ベスト更新")
        #expect(decide(.inPlay, .nice) == .none)
        #expect(decide(.fenceHit, .hit) == .none)
        #expect(decide(.foul, .just) == .none, "ファウルはジャストでも出さない")
        #expect(decide(.foul, .nice, best: true) == .none)
        #expect(decide(.homer, .just, swung: false) == .none, "見送りは出さない")
        #expect(HomerunFaceMark.decide(ball: nil, swung: true, isNewBest: true) == .none)
    }

    @Test("空振りの球の結果中には記号を出さない（怒りマークは次の球の構え・#1769）")
    func noMarkOnWhiffResult() {
        #expect(decide(.miss, .miss) == .none)
        #expect(decide(.miss, .nice) == .none)
        #expect(decide(.miss, .miss, swung: false) == .none)
    }

    // MARK: モデル

    private func makeModel(roll: Double = 0.9) -> HomerunModel {
        let defaults = UserDefaults(suiteName: "HomerunFaceMarkTests.\(UUID())")!
        let model = HomerunModel(defaults: defaults, aimAssist: .off, now: Self.t0)
        model.whiffGagRoll = { roll }
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        return model
    }

    private func whiff(_ model: HomerunModel) throws {
        let release = try #require(model.arrival).addingTimeInterval(-0.3)
        model.press(at: CGPoint(x: 150, y: 600), now: release.addingTimeInterval(-0.2))
        #expect(model.release(at: CGPoint(x: 150, y: 600), now: release)?.kind == .miss)
    }

    private func hit(_ model: HomerunModel) throws {
        let release = try #require(model.arrival)
        model.press(at: CGPoint(x: 150, y: 600), now: release.addingTimeInterval(-0.5))
        let ball = model.ballPoint
        #expect(model.release(at: CGPoint(x: 150 + ball.x, y: 600 + ball.y + 4), now: release)?.kind != .miss)
    }

    private func take(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.nextWake))
    }

    private func next(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.nextWake))
        #expect(model.phase == .pitching)
    }

    @Test("判定は変えない: 記号の有無で飛距離・種別・結果の時間が変わらない")
    func judgementUnchanged() throws {
        let model = makeModel()
        try hit(model)
        let ball = try #require(model.lastBall)
        #expect(model.faceMark == .sparkle)
        #expect(ball.timing == .just)
        #expect(model.nextWake == model.resultUntil, "結果の時間は延ばさない")
    }

    // MARK: 見せる局面

    @Test("記号は結果の間だけ見せる")
    func shownOnlyDuringResult() {
        for phase in [HomerunModel.Phase.idle, .pitching, .finished] {
            #expect(HomerunSwingPlan(phase: phase, clock: nil, lastBall: nil, faceMark: .sparkle).faceMark == .none)
        }
        #expect(HomerunSwingPlan(phase: .ballResult, clock: nil, lastBall: nil, faceMark: .sparkle).faceMark == .sparkle)
    }

    @Test("記号の出始めはフォロースルーの頭（打点の後）、振り抜きの終わりより前")
    func appearTiming() {
        // どの列でも打点の窓が終わった後。
        let contact = (0..<3).map { HomerunSwingContact.contactWindow(column: $0).exit }.max() ?? 0
        let appear = (HomerunFaceMark.appearFrame - 1) / HomerunWhiffGag.frameRate
        #expect(appear > contact, "打点（\(contact) 秒）より後")
        #expect(appear < HomerunBatPath.duration, "振り終わりの前")
        #expect(HomerunFaceMark.appearGrow > 0 && HomerunFaceMark.pulse(since: 0, rate: 3, depth: 0.2) == 1)
    }

    // MARK: 次の球の構えのキラキラ目（#1762）

    /// ジャストで芯から 2pt 外した柵越え（芯そのものはジャストなら月まで飛ぶ・#1680）。
    static let homerDY = HomerunLaunch.fly.centerDY + 2

    /// 押す → ボールの中心から (0, dy) へずらす → 輪が重なる時刻 + `offset` 秒で離す。
    @discardableResult
    private func swing(_ model: HomerunModel, dy: Double, offset: TimeInterval = 0) throws -> HomerunBattedBall? {
        let hit = try #require(model.arrival).addingTimeInterval(offset)
        let start = CGPoint(x: 150, y: 600)
        model.press(at: start, now: hit.addingTimeInterval(-0.5))
        let ball = model.ballPoint
        return model.release(at: CGPoint(x: start.x + ball.x - model.cursor.x, y: start.y + ball.y + dy - model.cursor.y), now: hit)
    }

    @Test("構えの記号は柵越え（ポール直撃・月を含む）の次の球だけ。挑戦が終わる球の次は出さない")
    func waitingRule() {
        #expect(HomerunFaceMark.waiting(after: ball(.homer, .just), swung: true, challengeFinished: false) == .waitingSparkle)
        #expect(HomerunFaceMark.waiting(after: ball(.homer, .hit), swung: true, challengeFinished: false) == .waitingSparkle)
        var moon = ball(.homer, .just)
        moon.moon = .hit
        #expect(HomerunFaceMark.waiting(after: moon, swung: true, challengeFinished: false) == .waitingSparkle, "月まで飛んだ球の次も出す")
        moon.moon = .broken
        #expect(HomerunFaceMark.waiting(after: moon, swung: true, challengeFinished: true) == .none, "月が割れて終わるときは除く")
        #expect(HomerunFaceMark.waiting(after: ball(.homer, .just), swung: true, challengeFinished: true) == .none, "10 球目の次は無い")
        #expect(HomerunFaceMark.waiting(after: ball(.fenceHit, .just), swung: true, challengeFinished: false) == .none)
        #expect(HomerunFaceMark.waiting(after: ball(.inPlay, .just), swung: true, challengeFinished: false) == .none)
        #expect(HomerunFaceMark.waiting(after: ball(.foul, .just), swung: true, challengeFinished: false) == .none)
        #expect(HomerunFaceMark.waiting(after: ball(.homer, .just), swung: false, challengeFinished: false) == .waitingSparkle)
        #expect(HomerunFaceMark.waiting(after: nil, swung: true, challengeFinished: false) == .none)
    }

    @Test("振った空振りの次の球の構えで怒りマーク。見送り・当たり・挑戦が終わる球の次は出さない（#1769）")
    func angryWaitingRule() {
        #expect(HomerunFaceMark.waiting(after: ball(.miss, .miss), swung: true, challengeFinished: false) == .waitingAngry)
        #expect(HomerunFaceMark.waiting(after: ball(.miss, .nice), swung: true, challengeFinished: false) == .waitingAngry, "照準を外した空振りも空振り")
        #expect(HomerunFaceMark.waiting(after: ball(.miss, .miss), swung: false, challengeFinished: false) == .none, "見送りは数えない")
        #expect(HomerunFaceMark.waiting(after: ball(.miss, .miss), swung: true, challengeFinished: true) == .none, "最後の球の次は無い")
        #expect(HomerunFaceMark.waiting(after: ball(.foul, .just), swung: true, challengeFinished: false) == .none)
        #expect(HomerunFaceMark.waitingAngry.isWaiting && HomerunFaceMark.waitingSparkle.isWaiting && !HomerunFaceMark.sparkle.isWaiting)
    }

    @Test("1 回の空振りでも次の球で出て、見送ると消える。当たりでも消える。挑戦をやり直すと消える")
    func angryWaitingInModel() throws {
        let model = makeModel()
        try whiff(model)
        #expect(model.faceMark == .none, "空振りの結果中は出さない")
        #expect(model.waitingFaceMark == .waitingAngry)
        try next(model)
        #expect(model.waitingFaceMark == .waitingAngry, "次の球を待つ間")
        try take(model)
        #expect(model.waitingFaceMark == .none, "見送ると消える")
        try next(model)
        try hit(model)
        #expect(model.waitingFaceMark != .waitingAngry)
        try next(model)
        try whiff(model)
        #expect(model.waitingFaceMark == .waitingAngry)
        model.pause(now: Self.t0.addingTimeInterval(100))
        model.quitChallenge()
        model.start(now: Self.t0.addingTimeInterval(100))
        #expect(model.waitingFaceMark == .none)
    }

    @Test("柵越えの次の球の構えで出て、その球を見送ると消える。1 挑戦の最初の球・挑戦をまたいでは出さない")
    func waitingInModel() throws {
        let model = makeModel()
        #expect(model.waitingFaceMark == .none, "最初の球")
        let first = try swing(model, dy: Self.homerDY)
        #expect(first?.kind == .homer)
        #expect(model.waitingFaceMark == .waitingSparkle)
        try next(model)
        #expect(model.waitingFaceMark == .waitingSparkle, "次の球を待つ間")
        try take(model)
        #expect(model.waitingFaceMark == .none, "見送ると消える")
        try next(model)
        #expect(model.waitingFaceMark == .none)
    }

    @Test("柵越えをもう一度打てば次の球でも出る。ふつうの当たりで消える")
    func waitingRepeatsAndClears() throws {
        let model = makeModel()
        try swing(model, dy: Self.homerDY)
        try next(model)
        let second = try swing(model, dy: Self.homerDY)
        #expect(second?.kind == .homer)
        #expect(model.waitingFaceMark == .waitingSparkle, "また柵越えなら次の球でも")
        try next(model)
        try whiff(model)
        #expect(model.waitingFaceMark == .waitingAngry, "空振りで構えの記号は怒りマークに替わる")
    }

    @Test("挑戦をやり直すと構えの記号は消える")
    func waitingResetsOnNewChallenge() throws {
        let model = makeModel()
        try swing(model, dy: Self.homerDY)
        #expect(model.waitingFaceMark == .waitingSparkle)
        model.pause(now: Self.t0.addingTimeInterval(100))
        model.quitChallenge()
        model.start(now: Self.t0.addingTimeInterval(100))
        #expect(model.waitingFaceMark == .none)
    }

    @Test("構えの記号は球を待つ間（投球の局面）だけ見せる。結果の間は結果の記号")
    func waitingShownWhilePitching() {
        func plan(_ phase: HomerunModel.Phase) -> HomerunSwingPlan {
            HomerunSwingPlan(phase: phase, clock: nil, lastBall: nil, faceMark: .sparkle, waitingFaceMark: .waitingSparkle)
        }
        #expect(plan(.pitching).faceMark == .waitingSparkle)
        #expect(plan(.ballResult).faceMark == .sparkle)
        #expect(plan(.idle).faceMark == .none && plan(.finished).faceMark == .none)
    }

    @Test("構え・踏み込みの頭の表は 20 コマ目で振り抜きの表とつながる")
    func preSwingHeadJoinsSwingTable() {
        let a = HomerunWhiffGag.preSwingHead(atClipTime: HomerunBatterMotion.loadDuration)
        let b = HomerunWhiffGag.head(atClipTime: HomerunBatterMotion.loadDuration)
        #expect(simd_length(a.position - b.position) < 0.001)
        #expect(abs(simd_dot(a.rotation.vector, b.rotation.vector)) > 0.9999)
        // 構え（1 コマ目）から 20 コマ目までに頭は動く（表が全部同じ値ではない）。
        let first = HomerunWhiffGag.preSwingHead(atClipTime: 0)
        #expect(simd_length(first.position - a.position) > 0.02)
    }
}
