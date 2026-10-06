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

    @Test("吹き出しは脈打ちと弾みが最大でもヘルメットに重ならず、頭から離れすぎない（#1785・#1797）")
    func angryBubbleStaysClearOfHelmet() {
        let gap = HomerunFaceMark.angryMinClearance
        #expect(gap > 0.03, "重ならない余白")
        let nominal = gap + HomerunFaceMark.angryHop + HomerunFaceMark.angryBubbleRadius * HomerunFaceMark.angryPulseDepth
        #expect(nominal < 0.15, "離れすぎない（尾が届く）")
        #expect(HomerunFaceMark.angryBounce(since: 0.125) <= HomerunFaceMark.angryHop)
        let markRadius = HomerunFaceMark.angrySize * HomerunFaceMark.angryExtent
        #expect(markRadius <= HomerunFaceMark.angryBubbleRadius * 0.8, "💢 は吹き出しに余白をもって収まる")
        #expect(markRadius < 0.22 * 0.6, "モック v3（0.22）より小さい")
        #expect(HomerunFaceMark.angrySide > 0, "頭の左横")
        #expect(HomerunFaceMark.angryTailDirection.x > 0 && HomerunFaceMark.angryTailDirection.y < 0, "尾は頭（右下）の方へ")
    }

    @Test("💢 は太さ一定の「く」の字 4 本: 曲がり角が中心を向き腕は外へ・上下左右（−8°）・左右対称・中心の空白と外側の半径（会長確定 2026-10-04）")
    func angryStrokeShape() {
        let half = HomerunFaceMark.angryStrokeHalfWidth
        var innermost: Float = 9, outermost: Float = 0
        var cornerAngles: [Int] = []
        for index in 0..<4 {
            let line = HomerunFaceMark.angryStrokeCenterline(index)
            #expect(line.count > 20)
            let distances = line.map(simd_length)
            let corner = distances.enumerated().min { $0.element < $1.element }!
            #expect(corner.offset > 5 && corner.offset < line.count - 6, "曲がり角（中心にいちばん近い点）は線の真ん中あたり")
            #expect(distances.first! > corner.element + 0.15 && distances.last! > corner.element + 0.15, "両腕は中心から外へ伸びる")
            #expect(abs(distances.first! - distances.last!) < 0.01, "自分の軸について左右対称")
            innermost = min(innermost, corner.element - half)
            outermost = max(outermost, distances.max()! + half)
            let c = line[corner.offset]
            cornerAngles.append(((Int((atan2(c.y, c.x) * 180 / .pi).rounded()) % 360) + 360) % 360)
            #expect(HomerunFaceMark.angryStrokeCenterline(index) == line, "決まった形")
        }
        #expect(abs(outermost - HomerunFaceMark.angryExtent) < 0.02, "外側の半径")
        #expect(abs(innermost / outermost - HomerunFaceMark.angryGapRatio) < 0.03, "中心の空白は直径の約 4 割")
        #expect(cornerAngles.sorted() == [82, 172, 262, 352], "上下左右から −8°")
    }

    // MARK: 怒りゲージ（#1797）

    @Test("怒りゲージ: 振った空振りで +1、当たり（ファウル含む）で −1（0 未満にしない）、見送りは変えない")
    func angerGaugeRule() {
        func g(_ kind: HomerunKind, from: Int, swung: Bool = true) -> Int {
            HomerunFaceMark.angerGauge(after: ball(kind, .nice), swung: swung, from: from)
        }
        #expect(g(.miss, from: 0) == 1)
        #expect(g(.miss, from: 2) == 3)
        #expect(g(.foul, from: 2) == 1, "ファウルは当たり")
        #expect(g(.inPlay, from: 2) == 1)
        #expect(g(.fenceHit, from: 2) == 1)
        #expect(g(.homer, from: 2) == 1)
        #expect(g(.homer, from: 0) == 0, "0 未満にしない")
        #expect(g(.miss, from: 2, swung: false) == 2, "見送りは変えない")
        #expect(HomerunFaceMark.angerGauge(after: nil, swung: true, from: 2) == 2)
    }

    @Test("怒りゲージが閾値に届いたら、振った空振りの次の構えは段階②（顔の赤み・湯気）。届かなければ段階①")
    func angerStageRule() {
        let n = HomerunFaceMark.angerStageThreshold
        let miss = ball(.miss, .miss)
        #expect(HomerunFaceMark.waiting(after: miss, swung: true, challengeFinished: false, anger: n - 1) == .waitingAngry)
        #expect(HomerunFaceMark.waiting(after: miss, swung: true, challengeFinished: false, anger: n) == .waitingAngryHot)
        #expect(HomerunFaceMark.waiting(after: miss, swung: true, challengeFinished: false, anger: n + 5) == .waitingAngryHot)
        #expect(HomerunFaceMark.waiting(after: miss, swung: true, challengeFinished: true, anger: n) == .none, "最後の球の次は無い")
        #expect(HomerunFaceMark.waiting(after: miss, swung: false, challengeFinished: false, anger: n) == .none, "見送りは出さない")
        #expect(HomerunFaceMark.waiting(after: ball(.foul, .just), swung: true, challengeFinished: false, anger: n) == .none)
        #expect(HomerunFaceMark.waitingAngryHot.isWaiting && HomerunFaceMark.waitingAngryHot.showsAngryMark)
        #expect(HomerunFaceMark.waitingAngry.showsAngryMark && !HomerunFaceMark.waitingSparkle.showsAngryMark)
    }

    @Test("モック: 空振りを重ねて閾値で段階②・当たりで下がる・挑戦の開始で 0")
    func angerGaugeInModel() throws {
        let model = makeModel()
        #expect(model.angerGauge == 0)
        try whiff(model)
        try next(model)
        try whiff(model)
        #expect(model.angerGauge == 2)
        #expect(model.waitingFaceMark == .waitingAngry, "閾値の手前は段階①")
        try next(model)
        try take(model)
        #expect(model.angerGauge == 2, "見送りは変えない")
        try next(model)
        try whiff(model)
        #expect(model.angerGauge == 3)
        #expect(model.waitingFaceMark == .waitingAngryHot, "3 回目で段階②")
        try next(model)
        try hit(model)
        #expect(model.angerGauge == 2, "当たりで −1")
        #expect(model.waitingFaceMark != .waitingAngryHot)
        model.pause(now: Self.t0.addingTimeInterval(100))
        model.quitChallenge()
        model.start(now: Self.t0.addingTimeInterval(100))
        #expect(model.angerGauge == 0, "挑戦の開始で 0")
        #expect(model.waitingFaceMark == .none)
    }

    @Test("湯気は最初に勢いよく噴き出して膨らみ、終わりで薄れて少し広がって消える")
    func steamPhaseShape() {
        let start = HomerunFaceMark.steamPhase(0), burst = HomerunFaceMark.steamPhase(HomerunFaceMark.steamBurst)
        #expect(start.burst == 0 && start.fade == 1 && abs(start.size - 0.25) < 0.001)
        #expect(abs(burst.burst - 1) < 0.001 && abs(burst.size - 1) < 0.001, "噴き出しきったら等倍")
        let quarter = HomerunFaceMark.steamPhase(HomerunFaceMark.steamBurst / 4)
        #expect(quarter.burst > 0.25, "出始めが速い（ease-out）")
        let mid = HomerunFaceMark.steamPhase((HomerunFaceMark.steamBurst + HomerunFaceMark.steamFadeFrom) / 2)
        #expect(mid.fade == 1 && abs(mid.size - 1) < 0.001, "漂う間は等倍で薄れない")
        let late = HomerunFaceMark.steamPhase((HomerunFaceMark.steamFadeFrom + 1) / 2)
        #expect(late.fade > 0.49 && late.fade < 0.51 && late.size > 1, "薄れながら少し広がる")
        let end = HomerunFaceMark.steamPhase(1)
        #expect(end.fade == 0 && abs(end.size - 1.18) < 0.001)
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
