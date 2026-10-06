import Testing
import Foundation
import simd
@testable import HomerunCore
@testable import GameHomerun

/// 打ち上げた球が自分の頭に落ちてたんこぶ（#1793）の見た目の時間割・球の道・カメラ・たんこぶ・モデルとの結びつき。
@Suite("柵越えおじさんのたんこぶ（演出）")
@MainActor
struct HomerunTankobuGagTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    typealias G = HomerunTankobuGag

    // MARK: 時間割

    @Test("ヒットストップ: 当たる瞬間だけ時刻が止まり、その後は止めたぶん遅れる")
    func hitStop() {
        #expect(G.effective(1.0) == 1.0)
        #expect(G.effective(G.impactDelay) == G.impactDelay)
        #expect(G.effective(G.impactDelay + G.hitStop / 2) == G.impactDelay)
        #expect(abs(G.effective(G.impactDelay + G.hitStop + 0.5) - (G.impactDelay + 0.5)) < 1e-9)
    }

    @Test("骨の再生位置: 振り終わり（44 コマ）で球を待ち、当たったら 50 コマ目から流す。44〜50 コマは同じ姿勢なので飛ばない")
    func segmentTime() {
        let swing = HomerunBatterMotion.swingDuration
        #expect(G.holdFrame == 44 && abs((G.holdFrame - 1) / HomerunWhiffGag.frameRate - HomerunBatterMotion.loadDuration - swing) < 1e-9)
        #expect(G.segmentTime(effective: 0.3) == 0.3)
        #expect(G.segmentTime(effective: swing) == swing)
        #expect(G.segmentTime(effective: 1.5) == swing, "球を待つあいだは振り終わりで止まる")
        #expect(G.segmentTime(effective: G.impactDelay - 0.001) == swing)
        #expect(abs(G.segmentTime(effective: G.impactDelay) - G.resumeSegment) < 1e-9)
        #expect(abs(HomerunWhiffGag.frame(atClipTime: G.impactClipTime) - G.resumeFrame) < 1e-9)
        #expect(G.segmentTime(effective: 99) == HomerunWhiffGag.clipEnd - HomerunBatterMotion.loadDuration, "最後のコマで止まる")
        // 44 コマ目と 50 コマ目で頭の位置がほぼ同じ（つなぎ目が出ない）。
        let a = HomerunWhiffGag.head(atClipTime: HomerunBatterMotion.loadDuration + swing).position
        let b = HomerunWhiffGag.head(atClipTime: G.impactClipTime).position
        #expect(simd_distance(a, b) < 0.05, "44 → 50 コマの頭の動き \(simd_distance(a, b)) m")
    }

    @Test("会長決裁の長さ: 頭に当たるまで約 2.0 秒・結果のカードまで約 3.8 秒。カードは座り込んだ後で、次の球はカードの後")
    func durations() {
        #expect(G.impactDelay == 2.0 && G.cardDelay == 3.8)
        #expect(G.cardDelay > G.impactDelay + G.hitStop + G.reboundDuration + G.hopDuration, "球が止まってからカード")
        #expect(HomerunModel.resultDuration(for: tankobuBall()) == G.resultDuration)
        #expect(G.resultDuration >= G.cardDelay + HomerunBallChase.cardHold)
    }

    // MARK: 球の道

    private var contact: SIMD3<Float> { HomerunSwingContact.contactPoint(column: 1, offsetMilliseconds: 0) }
    private var contactOffset: TimeInterval { 0.2 }

    @Test("球は打点から始まり、頭のてっぺん（ヘルメットの頂上）に当たる時刻に着く。途中で打点より高く上がる")
    func ballFlight() {
        let start = G.ballPosition(effective: contactOffset, contact: contact, contactOffset: contactOffset)
        #expect(simd_distance(start, contact) < 1e-4)
        let hit = G.ballPosition(effective: G.impactDelay, contact: contact, contactOffset: contactOffset)
        #expect(simd_distance(hit, G.impactPoint) < 1e-4)
        let samples = stride(from: contactOffset, through: G.impactDelay, by: 0.05).map {
            G.ballPosition(effective: $0, contact: contact, contactOffset: contactOffset)
        }
        let apex = samples.map(\.y).max() ?? 0
        #expect(apex > contact.y + 3, "頂点 \(apex) m")
        #expect(apex > G.impactPoint.y + 3)
        // 飛距離 0: 横にはほとんど動かない（真上に上がって落ちる）。
        let drift = samples.map { simd_distance(SIMD2($0.x, $0.z), SIMD2(G.impactPoint.x, G.impactPoint.z)) }.max() ?? 0
        #expect(drift < 1.0, "水平のずれ \(drift) m")
        // 頂点は打点から当たるまでのほぼ真ん中。
        let apexIndex = samples.firstIndex { $0.y == apex } ?? 0
        let apexTime = contactOffset + Double(apexIndex) * 0.05
        #expect(abs(apexTime - (contactOffset + G.impactDelay) / 2) < 0.15)
    }

    @Test("当たった後は弾んで地面へ落ち、止まる。地面より下へは行かない")
    func rebound() {
        var lowest: Float = .infinity
        for i in 0...60 {
            let e = G.impactDelay + Double(i) * 0.03
            lowest = min(lowest, G.ballPosition(effective: e, contact: contact, contactOffset: contactOffset).y)
        }
        #expect(lowest >= Float(HomerunBallChase.ballRadius) - 1e-4)
        let a = G.ballPosition(effective: 20, contact: contact, contactOffset: contactOffset)
        let b = G.ballPosition(effective: 30, contact: contact, contactOffset: contactOffset)
        #expect(a == b, "止まった後は動かない")
    }

    // MARK: カメラ

    @Test("カメラ: 最初は一塁側の低い所から見上げ、当たる瞬間は斜め上から頭を見下ろす")
    func camera() {
        let first = G.frame(effective: contactOffset, contact: contact, contactOffset: contactOffset)
        #expect(first.camera.position.x > 0, "一塁側（+x）")
        #expect(first.camera.position.y < 1.5, "低い所")
        let mid = G.frame(effective: (contactOffset + G.impactDelay) / 2, contact: contact, contactOffset: contactOffset)
        #expect(mid.camera.target.y > first.camera.position.y + 2, "頂点では見上げている")
        let hit = G.frame(effective: G.impactDelay, contact: contact, contactOffset: contactOffset)
        let head = G.impactPoint
        #expect(hit.camera.position.y > head.y + 2, "斜め上")
        #expect(simd_distance(hit.camera.target, head) < 1e-3, "当たる瞬間の注視点は頭のてっぺん")
        #expect(simd_distance(hit.camera.position, head) > 3, "寄りすぎない")
        #expect(hit.ballScale > 0 && !hit.ballHidden)
        // 球はいつも画面に映る（画角の中）。
        for i in 0...40 {
            let e = contactOffset + (G.impactDelay - contactOffset) * Double(i) / 40
            let f = G.frame(effective: e, contact: contact, contactOffset: contactOffset)
            let p = f.camera.screenPoint(of: f.ball, aspect: 0.5)
            #expect(abs(p.x - 0.5) < 0.1 && abs(p.y - 0.5) < 0.1, "e=\(e) 球が画面の中央から外れた \(p)")
        }
    }

    @Test("カメラの下ろしは頂点より前から始まり、当たる瞬間までなだらかに動く（急に切り替えない）")
    func cameraDescendIsGradual() {
        var previous = G.frame(effective: contactOffset, contact: contact, contactOffset: contactOffset).camera.position
        var biggestStep: Float = 0
        for i in 1...100 {
            let e = contactOffset + (G.impactDelay - contactOffset) * Double(i) / 100
            let p = G.frame(effective: e, contact: contact, contactOffset: contactOffset).camera.position
            biggestStep = max(biggestStep, simd_distance(p, previous))
            previous = p
        }
        let total = simd_distance(G.lowCamera, G.impactPoint + G.highCameraOffset)
        #expect(biggestStep < total * 0.05, "1 コマの動きが全体の 5% 未満（実測 \(biggestStep / total)）")
        let atApex = G.frame(effective: (contactOffset + G.impactDelay) / 2, contact: contact, contactOffset: contactOffset).camera.position
        #expect(simd_distance(atApex, G.lowCamera) > 0, "頂点より前に下ろし始めている")
    }

    // MARK: 座る位置

    @Test("当たるまでの振り抜き・球待ちの間は補正しない（体が横へずれず、バットが打点に届く）")
    func noCorrectionBeforeImpact() {
        for i in 0..<20 {
            let e = G.impactDelay * Double(i) / 20
            #expect(G.sitCorrection(effective: e) == .zero, "e=\(e)")
        }
        #expect(G.overlayClipTime(effective: 99) > HomerunWhiffGag.clipEnd, "目・星は最後のコマの後も回し続ける")
        #expect(G.overlayClipTime(effective: 1.0) == HomerunBatterMotion.loadDuration + HomerunBatterMotion.swingDuration)
    }

    @Test("座るあいだ頭の水平のずれを打ち消し、本塁から離れる側（局所の -z）へ寄せる。当たる前は補正しない")
    func sitCorrection() {
        #expect(simd_length(G.sitCorrection(effective: 1.0)) < 1e-6)
        #expect(simd_length(G.sitCorrection(effective: G.impactDelay)) < 1e-6)
        let sat = G.sitCorrection(effective: 99)
        #expect(sat.y == 0)
        // 補正を足した頭は、振り終わりの頭の水平位置から sitOutward だけ外へ（打ち消し済み）。
        let held = HomerunWhiffGag.head(atClipTime: HomerunBatterMotion.loadDuration + HomerunBatterMotion.swingDuration).position
        let now = HomerunWhiffGag.head(atClipTime: HomerunWhiffGag.clipEnd).position + sat
        #expect(abs(now.x - held.x) < 1e-4 && abs(now.z - (held.z - G.sitOutward)) < 1e-4)
    }

    // MARK: たんこぶ

    @Test("たんこぶは当たる前は無く、当たった瞬間から膨らみすぎてから落ち着き、元の大きさに戻る")
    func swell() {
        #expect(G.swell(since: -0.1) == 0 && G.swell(since: 0) == 0)
        #expect(G.swell(since: G.swellRise) == G.swellOvershoot)
        #expect(G.swell(since: G.swellRise / 2) > 0 && G.swell(since: G.swellRise / 2) < G.swellOvershoot)
        #expect(G.swell(since: G.swellRise + G.swellSettle) == 1)
        #expect(G.swell(since: 5) == 1)
        #expect(G.swellOvershoot > 1)
        #expect(abs(G.throb(at: 0) - 1) < 1e-6 && G.throbDepth < 0.1)
    }

    @Test("たんこぶの色はモックのピンク（下側が濃く、光りは白に近い）。下側の濃い色は下へ・光りは上にのぞく")
    func lumpLook() {
        #expect(G.lumpPink == [1.0, 0.50, 0.62])
        #expect(G.lumpUnderside.x < G.lumpPink.x && G.lumpUnderside.y < G.lumpPink.y && G.lumpUnderside.z < G.lumpPink.z)
        #expect(G.lumpShine.x > G.lumpPink.x - 0.01 && G.lumpShine.y > G.lumpPink.y && G.lumpShine.z > G.lumpPink.z)
        #expect(G.undersideOffset.y < 0 && G.undersideRadius > 1, "濃い色は下の縁だけ外へのぞく")
        #expect(G.shineOffset.y > 0 && simd_length(G.shineOffset) + G.shineRadius > 1, "光りの点は上で、面の外へ少し出て見える")
    }

    @Test("黒い点々はカメラ側の上半分にばらけ、光りの点・絆創膏・ほかの点と重ならない。絆創膏は頂点あたりに白い 2 枚の十字")
    func lumpDotsAndBandage() {
        let dots = G.dotNormals.map(simd_normalize)
        #expect(dots.count >= 3)
        let shine = simd_normalize(G.shineOffset)
        // 球の面の上の距離（弦）で見る。
        for (i, d) in dots.enumerated() {
            #expect(d.y >= 0 && d.z > 0, "見える側: \(d)")
            #expect(simd_distance(d, shine) > G.shineRadius + G.dotRadius, "光りの点と重なる: \(d)")
            #expect(simd_distance(d, G.bandageNormal) > G.bandageLength / 2 + G.dotRadius, "絆創膏の下に隠れる: \(d)")
            for e in dots[(i + 1)...] { #expect(simd_distance(d, e) > 4 * G.dotRadius, "点がくっつく: \(d) \(e)") }
        }
        #expect(G.bandageNormal.y > 0.85, "頂点あたり")
        // 光りの点は絆創膏の板の下に隠れない（板の向きと、絆創膏の中心から見た光りの点の向きがずれている）。
        let n = G.bandageNormal, toShine = shine - n * simd_dot(shine, n)
        let frame = simd_quatf(from: [0, 1, 0], to: n)
        for a in G.bandageAngles {
            let along = (frame * simd_quatf(angle: a, axis: [0, 1, 0])).act([1, 0, 0])
            let cosine = abs(simd_dot(simd_normalize(toShine), along))
            #expect(cosine < 0.9, "板 \(a) が光りの点の上に掛かる")
        }
        #expect(G.bandageAngles.count == 2 && abs(abs(G.bandageAngles[0] - G.bandageAngles[1]) - .pi / 2) < 1e-5, "直角に重ねる")
        #expect(G.bandageLength > 3 * G.bandageWidth && G.bandageOutline < G.bandageWidth / 4, "細長い板・細い輪郭")
    }

    // MARK: 頭の位置

    @Test("ヘルメットの頂上は頭のてっぺんより上。球の当たる点は本塁の上ではなく打者の頭の上")
    func helmetTop() {
        let t = G.helmetTop(atClipTime: G.impactClipTime)
        let head = HomerunWhiffGag.head(atClipTime: G.impactClipTime)
        #expect(t.y > (head.position + head.rotation.act(HomerunWhiffGag.headTop)).y)
        #expect(G.impactPoint.y > 1.4 && G.impactPoint.y < 2.2, "身長 1.72m の頭の上 \(G.impactPoint.y) m")
        #expect(abs(G.impactPoint.x - HomerunAtBatLayout.batter.position.x) < 0.6)
    }

    // MARK: モデル・プランとの結びつき

    private func tankobuBall() -> HomerunBattedBall {
        let scrape = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunTankobu.scrapeFloor + 2)
        var c = HomerunChallenge()
        return c.swing(scrape, tankobuRoll: 0)!
    }

    private func makeModel(roll: Double) -> HomerunModel {
        let defaults = UserDefaults(suiteName: "HomerunTankobuGagTests.\(UUID())")!
        let model = HomerunModel(defaults: defaults, aimAssist: .off, now: Self.t0)
        model.tankobuRoll = { roll }
        model.whiffGagRoll = { 0.9 }
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        return model
    }

    @discardableResult
    private func swing(_ model: HomerunModel, dy: Double, offset: TimeInterval = 0) throws -> HomerunBattedBall? {
        let hit = try #require(model.arrival).addingTimeInterval(offset)
        let start = CGPoint(x: 150, y: 600)
        model.press(at: start, now: hit.addingTimeInterval(-0.5))
        let ball = model.ballPoint
        return model.release(at: CGPoint(x: start.x + ball.x - model.cursor.x, y: start.y + ball.y + dy - model.cursor.y), now: hit)
    }

    @Test("モデル: 擦り当たりで抽選に当たればたんこぶ。飛距離 0・結果の時間が延び、演出の間は素振りを受け付けない")
    func modelFlow() throws {
        let model = makeModel(roll: 0)
        let release = try #require(model.arrival)
        let ball = try #require(try swing(model, dy: HomerunTankobu.scrapeFloor + 2))
        #expect(ball.isTankobu && ball.distance == 0)
        #expect(model.faceMark == .none, "結果の間の記号は出さない（たんこぶは演出が描く）")
        #expect(model.waitingFaceMark == .waitingLump)
        #expect(model.isSwinging(at: release.addingTimeInterval(1.5)))
        let until = try #require(model.resultEnd)
        #expect(until.timeIntervalSince(release) >= G.cardDelay, "カードまで次の球を投げない")
        #expect(model.challenge?.totalDistance == 0)
    }

    @Test("モデル: 抽選に外れた・擦りでない当たりは今までどおり。見送りは乱数を使わない")
    func modelNoTankobu() throws {
        let miss = makeModel(roll: 0.5)
        let normal = try #require(try swing(miss, dy: HomerunTankobu.scrapeFloor + 2))
        #expect(!normal.isTankobu && normal.distance > 0 && miss.waitingFaceMark == .none)
        let shallow = makeModel(roll: 0)
        let ball = try #require(try swing(shallow, dy: HomerunLaunch.popFloor + 1))
        #expect(!ball.isTankobu)
    }

    @Test("構えのたんこぶは次の球だけ。10 球目の次・次の球を打ったあとは出さない")
    func waitingLump() {
        let ball = tankobuBall()
        #expect(HomerunFaceMark.waiting(after: ball, swung: true, challengeFinished: false) == .waitingLump)
        #expect(HomerunFaceMark.waiting(after: ball, swung: true, challengeFinished: true) == .none)
        #expect(HomerunFaceMark.waitingLump.isWaiting)
        #expect(HomerunFaceMark.decide(ball: ball, swung: true, isNewBest: true) == .none, "たんこぶの球はキラキラ目にしない")
    }

    @Test("プラン: たんこぶの球は振り抜きからたんこぶの動きを流し、打球を追うカメラではなく専用カメラ・カードは 3.8 秒後")
    func plan() throws {
        let model = makeModel(roll: 0)
        try swing(model, dy: HomerunTankobu.scrapeFloor + 2)
        let plan = HomerunSwingPlan(model: model)
        let clock = try #require(model.ballClock)
        let release = try #require(clock.releasedAt)
        let start = try #require(plan.tankobuStart)
        let motion = plan.batterMotion(at: release.addingTimeInterval(0.1))
        guard case .tankobu(let s, _) = motion else { Issue.record("たんこぶの動きになっていない: \(motion)"); return }
        #expect(s == start)
        #expect(plan.chaseTrack == nil)
        #expect(plan.chaseCardAt == start.addingTimeInterval(G.cardDelay))
        let contactAt = try #require(plan.contactAt)
        #expect(plan.chaseFrame(at: contactAt.addingTimeInterval(0.05)) == nil, "当たってすぐは打席のカメラのまま")
        let frame = try #require(plan.chaseFrame(at: contactAt.addingTimeInterval(HomerunBallChase.cutDelay + 0.01)))
        #expect(frame.camera.verticalFieldOfView == G.cameraFieldOfView)
        // 球はいつも描く位置と追うカメラの球が一致する。
        let at = start.addingTimeInterval(G.impactDelay)
        let ballAtImpact = try #require(plan.ballPosition(at: at))
        #expect(simd_distance(ballAtImpact, G.impactPoint) < 1e-3)
    }

    @Test("プラン: ふつうの当たり・空振りは今までどおり（たんこぶの動きにならない）")
    func planUnchangedForOthers() throws {
        let model = makeModel(roll: 0.9)
        try swing(model, dy: HomerunLaunch.fly.centerDY + 2)
        let plan = HomerunSwingPlan(model: model)
        #expect(plan.tankobuStart == nil && plan.chaseTrack != nil)
        let release = try #require(model.ballClock?.releasedAt)
        if case .tankobu = plan.batterMotion(at: release.addingTimeInterval(0.1)) { Issue.record("ふつうの当たりがたんこぶになった") }
    }
}
