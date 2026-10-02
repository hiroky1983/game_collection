import Testing
import Foundation
import simd
import HomerunCore
@testable import GameHomerun
#if canImport(RealityKit)
import RealityKit
#endif

/// 当たる瞬間の同期（`HomerunSwingContact` / `HomerunSwingPlan` / `HomerunBallFlight`）。
/// 打点のコマは USDZ から実寸で測った表（`HomerunBatPath`）から求める。
@Suite("柵越えおじさんのバットと球が当たる瞬間")
struct HomerunSwingContactTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let travel = TimeInterval(HomerunPitch.travelMilliseconds) / 1000
    private var arrival: Date { t0.addingTimeInterval(travel) }
    private func clock(zone: Int = 4, pressedAt: Date? = nil, releasedAt: Date? = nil, offset: Double? = nil,
                       practiceSwingAt: Date? = nil) -> HomerunModel.BallClock {
        HomerunModel.BallClock(pitchStart: t0, zone: zone, pressedAt: pressedAt, releasedAt: releasedAt, timingOffset: offset,
                               practiceSwingAt: practiceSwingAt)
    }

    @Test("バットの表は 44 コマ（43/30 秒）を 120Hz で持ち、長さ 0.80m のバットの両端を並べている")
    func batPathTable() {
        #expect(HomerunBatPath.sampleCount == 173)
        #expect(abs(HomerunBatPath.duration - 43.0 / 30) < 1e-6)
        for t in stride(from: 0.0, through: HomerunBatPath.duration, by: 0.1) {
            let s = HomerunBatPath.segment(atClipTime: t)
            #expect(abs(simd_distance(s.grip, s.tip) - 0.802) < 0.01, "t=\(t) でバットの長さ \(simd_distance(s.grip, s.tip))")
        }
        // 1 コマ目: 構えでバットは右肩の後ろ（-z・胸は +z）に上がっている。
        let stance = HomerunBatPath.segment(atClipTime: 0)
        #expect(stance.tip.y > 1.5 && stance.tip.z < -0.3, "構えの先端 \(stance.tip)")
        // 表の間は線形補間（真ん中は両端の平均）。
        let a = HomerunBatPath.segment(atClipTime: 0.8), b = HomerunBatPath.segment(atClipTime: 0.8 + 1 / 120), m = HomerunBatPath.segment(atClipTime: 0.8 + 1 / 240)
        #expect(simd_distance(m.tip, (a.tip + b.tip) / 2) < 1e-4)
    }

    // 実測（`HomerunBatPath` の表・打者 (0.30, 0, -0.10)）: 外の列 25.50〜26.25 コマ目・真ん中 25.25〜26.50・内の列 25.00〜26.75。
    // ジャスト（区間の真ん中）は 3 列とも 25.875 コマ目 = 振り抜きの起点（20 コマ目）の 0.196 秒後。
    @Test("打点のコマ: バットが本塁の上の球の通り道を横切るのは 25.0〜26.75 コマ目（1〜2 コマ・33〜58ms）で、3 列とも届く")
    func contactWindowByColumn() {
        for column in -1...1 {
            let w = HomerunSwingContact.contactWindow(column: column)
            let enter = HomerunBatPath.frame(atClipTime: w.enter), exit = HomerunBatPath.frame(atClipTime: w.exit)
            #expect(enter > 24.9 && enter < 25.6, "列 \(column): 入りが \(enter) コマ目")
            #expect(exit > 26.1 && exit < 26.9, "列 \(column): 出が \(exit) コマ目")
            #expect(abs(HomerunBatPath.frame(atClipTime: w.just) - 25.875) < 0.13, "列 \(column): ジャストが \(HomerunBatPath.frame(atClipTime: w.just)) コマ目")
            #expect(w.exit - w.enter >= 0.02 && w.exit - w.enter <= 0.06, "列 \(column): 横切る時間 \(w.exit - w.enter) 秒")
            // 区間の中で交点の z は前（投手側）へ単調に進む: 早い = 前で当たる、遅い = 本塁の上で当たる。
            let x = HomerunSwingContact.ballLineX(column: column)
            var last: Float = -.infinity
            for t in stride(from: w.enter, through: w.exit, by: HomerunSwingContact.scanStep) {
                let p = try! #require(HomerunSwingContact.crossing(atClipTime: t, x: x))
                #expect(p.z > last, "列 \(column): t=\(t) で z が戻った \(p.z) < \(last)")
                last = p.z
                // 高さは腰から胸の間（ゾーンの中心 0.9m の前後）。
                #expect(p.y > 0.7 && p.y < 1.1, "列 \(column): 打点の高さ \(p.y)")
            }
            // ジャストの打点は本塁の前縁（z = 0）の前 0.1〜0.5m。
            let just = try! #require(HomerunSwingContact.crossing(atClipTime: w.just, x: x))
            #expect(just.z > 0.05 && just.z < 0.55, "列 \(column): ジャストの打点 z = \(just.z)")
        }
    }

    // 実測: ジャストの打点は先端から 外の列 7cm・真ん中 20cm・内の列 36cm（バットの長さ 0.80m）。
    @Test("ジャストの打点はバットの打つ部分（先端から 4〜40cm）。外の列でも先端が届く")
    func justContactIsOnTheBarrel() {
        for column in -1...1 {
            let w = HomerunSwingContact.contactWindow(column: column)
            let s = HomerunBatPath.segment(atClipTime: w.just)
            let tip = HomerunAtBatLayout.batterWorld(s.tip)
            let p = try! #require(HomerunSwingContact.crossing(atClipTime: w.just, x: HomerunSwingContact.ballLineX(column: column)))
            let fromTip = simd_distance(p, tip)
            #expect(fromTip > 0.04 && fromTip < 0.4, "列 \(column): 先端から \(fromTip)m")
        }
    }

    @Test("早い/遅い: ずれが負（早い）ほど打点のコマは後ろ（前で当たる）、正（遅い）ほど前。当たり窓の端で区間の端")
    func contactClipTimeFollowsOffset() {
        let w = HomerunSwingContact.contactWindow(column: 0)
        #expect(HomerunSwingContact.contactClipTime(column: 0, offsetMilliseconds: 0) == w.just)
        #expect(abs(HomerunSwingContact.contactClipTime(column: 0, offsetMilliseconds: -HomerunTiming.hitWindow) - w.exit) < 1e-9)
        #expect(abs(HomerunSwingContact.contactClipTime(column: 0, offsetMilliseconds: HomerunTiming.hitWindow) - w.enter) < 1e-9)
        #expect(abs(HomerunSwingContact.contactClipTime(column: 0, offsetMilliseconds: -300) - w.exit) < 1e-9, "窓の外は端で止める")
        let early = HomerunSwingContact.contactPoint(column: 0, offsetMilliseconds: -60)
        let just = HomerunSwingContact.contactPoint(column: 0, offsetMilliseconds: 0)
        let late = HomerunSwingContact.contactPoint(column: 0, offsetMilliseconds: 60)
        #expect(early.z > just.z && just.z > late.z, "早い \(early.z) > ジャスト \(just.z) > 遅い \(late.z)")
        // 当たった球の中心はバットの軸から半径の和だけ上（表面が触れる）。
        let axis = try! #require(HomerunSwingContact.crossing(atClipTime: w.just, x: 0))
        #expect(abs(just.y - axis.y - (HomerunBatPath.barrelRadius + HomerunSwingContact.ballRadius)) < 1e-6)
    }

    @Test("輪が的に重なる瞬間 = 3D の球が打点に来る瞬間 = 判定の 0（#1594 会長決裁 A）。ジャストに離すとその瞬間にバットが打点のコマ")
    func ringBallAndJudgeZeroCoincide() {
        for column in -1...1 {
            let lead = HomerunSwingContact.lead(column: column)
            #expect(lead > 0.18 && lead < 0.22, "列 \(column): 先行 \(lead) 秒")
            let w = HomerunSwingContact.contactWindow(column: column)
            #expect(abs((w.just - HomerunSwingContact.swingClipStart) - lead) < 1e-9)
            // 3D の球が打点（の 10cm 上）に着く時刻 = 輪が的に重なる時刻（ずらさない）。
            let plan = HomerunSwingPlan(phase: .pitching, clock: clock(zone: 4 + column), lastBall: nil)
            let ballArrival = try! #require(plan.ballArrival)
            #expect(ballArrival == arrival)
            let atArrival = try! #require(plan.ballPosition(at: arrival))
            #expect(simd_distance(atArrival, HomerunSwingContact.approachTarget(column: column)) < 1e-4)
            // 輪の大きさ: その時刻にちょうど的の大きさ。
            #expect(abs(HomerunZoneGeometry.ringDiameter(elapsed: arrival.timeIntervalSince(t0)) - HomerunZoneGeometry.targetDiameter) < 1e-6)
            // ジャストに離すと、バットはその瞬間に打点のコマ（振り抜きの前半は飛ばす）。
            let just = HomerunSwingContact.contactTime(release: arrival, offsetMilliseconds: 0, column: column)
            #expect(just == arrival)
            let start = HomerunSwingContact.swingStart(release: arrival, offsetMilliseconds: 0, column: column)
            #expect(abs(arrival.timeIntervalSince(start) - lead) < 1e-9)
            // 早い: 投球の線の球がその打点（前寄り）の奥行きに来る時刻（離した後・輪の時刻の少し前）にバットが打点。
            // 遅い: 離した瞬間にバットが打点。
            let earlyRelease = arrival.addingTimeInterval(-0.06)
            let earlyHit = HomerunSwingContact.contactTime(release: earlyRelease, offsetMilliseconds: -60, column: column)
            #expect(earlyHit > earlyRelease && earlyHit < arrival)
            let ballThere = try! #require(plan.ballPosition(at: earlyHit))
            let early = HomerunSwingContact.contactPoint(column: column, offsetMilliseconds: -60)
            #expect(abs(ballThere.z - early.z) < 1e-3, "列 \(column): 早い当たりの瞬間の球の奥行き \(ballThere.z) / 打点 \(early.z)")
            let lateRelease = arrival.addingTimeInterval(0.06)
            #expect(HomerunSwingContact.contactTime(release: lateRelease, offsetMilliseconds: 60, column: column) == lateRelease)
            // どのずれでも、振りの 20 コマ目は離した時刻より前（離した瞬間に振り抜きの途中から流れる）。
            for offset in [-300.0, -110, -60, 0, 60, 110, 300] {
                let release = arrival.addingTimeInterval(offset / 1000)
                let s = HomerunSwingContact.swingStart(release: release, offsetMilliseconds: offset, column: column)
                #expect(s <= release && release.timeIntervalSince(s) <= lead + 0.03, "列 \(column)・ずれ \(offset)ms")
            }
        }
    }

    @Test("投球中: 当たり窓の始まりに 20 コマ目で待てるよう踏み込み、押しっぱなしでも振らない（先読みで振らない・#1594）")
    func motionWhilePitching() {
        let plan = HomerunSwingPlan(phase: .pitching, clock: clock(pressedAt: t0), lastBall: nil)
        let loadStart = try! #require(plan.loadStart)
        #expect(abs(arrival.timeIntervalSince(loadStart) - (HomerunTiming.hitWindow / 1000 + HomerunBatterMotion.loadDuration)) < 1e-9)
        let load = HomerunBatterMotion.load(start: loadStart)
        #expect(plan.batterMotion(at: t0.addingTimeInterval(-0.5)) == .stance, "モーション中は構え")
        #expect(plan.batterMotion(at: loadStart.addingTimeInterval(-0.01)) == .stance)
        #expect(plan.batterMotion(at: loadStart) == load)
        #expect(plan.batterMotion(at: arrival) == load, "押したまま輪が重なっても振らない")
        #expect(plan.batterMotion(at: arrival.addingTimeInterval(0.1)) == load)
        let notHeld = HomerunSwingPlan(phase: .pitching, clock: clock(pressedAt: nil), lastBall: nil)
        #expect(notHeld.batterMotion(at: arrival) == load)
    }

    @Test("素振り（的が出る前に離した）: 離した瞬間から頭で振り抜き、振り終わると構え・踏み込みへ戻る")
    func practiceSwingWhilePitching() {
        let plan0 = HomerunSwingPlan(phase: .pitching, clock: clock(), lastBall: nil)
        let loadStart = try! #require(plan0.loadStart)
        #expect(abs(HomerunBatterMotion.swingDuration - 24.0 / 30) < 1e-6, "振り抜き〜フォロースルーは 20〜44 コマ目")
        // モーションの早いうち（的が出る 0.5 秒前）に素振り: 振り終わりは踏み込みの始まりより前 → 構えへ戻る。
        let early = t0.addingTimeInterval(-0.5)
        let plan = HomerunSwingPlan(phase: .pitching, clock: clock(practiceSwingAt: early), lastBall: nil)
        #expect(plan.batterMotion(at: early.addingTimeInterval(-0.01)) == .stance)
        #expect(plan.batterMotion(at: early) == .swing(start: early))
        #expect(plan.batterMotion(at: early.addingTimeInterval(HomerunBatterMotion.swingDuration - 0.01)) == .swing(start: early))
        #expect(plan.batterMotion(at: early.addingTimeInterval(HomerunBatterMotion.swingDuration)) == .stance)
        #expect(plan.batterMotion(at: loadStart) == .load(start: loadStart), "その後は通常どおり踏み込む")
        // 的が出た頃まで振っている素振り: 振り終わりまで途切れず、その後は踏み込みへ戻る（途中から流す）。
        let late = t0.addingTimeInterval(0.1)
        #expect(late.addingTimeInterval(HomerunBatterMotion.swingDuration) > loadStart)
        let latePlan = HomerunSwingPlan(phase: .pitching, clock: clock(practiceSwingAt: late), lastBall: nil)
        #expect(latePlan.batterMotion(at: loadStart) == .swing(start: late))
        #expect(latePlan.batterMotion(at: late.addingTimeInterval(HomerunBatterMotion.swingDuration)) == .load(start: loadStart))
    }

    @Test("離した瞬間に振り始め（振り抜きの途中のコマから）、合わせ直さない（#1594）")
    func motionAfterRelease() {
        let ball = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 4))
        for offset in [-300.0, -110, -60, -25, 0, 25, 60, 110, 300] {
            let release = arrival.addingTimeInterval(offset / 1000)
            let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: t0, releasedAt: release, offset: offset), lastBall: ball)
            let start = HomerunSwingContact.swingStart(release: release, offsetMilliseconds: offset, column: 0)
            #expect(plan.batterMotion(at: release.addingTimeInterval(-0.001)) == .stance, "ずれ \(offset)ms: 離す前に振っている")
            let catchUp: Date? = start < release ? release : nil
            #expect(plan.batterMotion(at: release) == .swing(start: start, catchUpFrom: catchUp), "ずれ \(offset)ms")
            // 振り終わった後もフォロースルーで止めたまま（構えへ跳ばない）。
            #expect(plan.batterMotion(at: release.addingTimeInterval(1.0)) == .swing(start: start, catchUpFrom: catchUp))
        }
    }

    @Test("本番の振りは離した瞬間に 20 コマ目から速めに流し、予定に追いついたら等速（振り抜きの前半を飛ばさない・会長 QA）")
    func swingCatchesUpInsteadOfSkipping() {
        let release = arrival
        let start = HomerunSwingContact.swingStart(release: release, offsetMilliseconds: 0, column: 0)
        let lead = release.timeIntervalSince(start)
        #expect(lead > 0.15, "ジャストの振りの予定は離した \(lead) 秒前から")
        // 離した瞬間は 20 コマ目（打点のコマへ跳ばない）。
        #expect(HomerunBatterMotion.swingOffset(start: start, catchUpFrom: release, at: release) == 0)
        // 速めに流している間は予定より手前、追いついた後は予定どおり。
        let s = HomerunBatterMotion.catchUpSpeed
        let mid = release.addingTimeInterval(lead / s / 2)
        #expect(abs(HomerunBatterMotion.swingOffset(start: start, catchUpFrom: release, at: mid) - lead / 2) < 1e-9)
        let later = release.addingTimeInterval(lead / (s - 1) + 0.1)
        #expect(abs(HomerunBatterMotion.swingOffset(start: start, catchUpFrom: release, at: later) - later.timeIntervalSince(start)) < 1e-9)
        // 打点のコマを画面に出すのは離した lead / 倍率 秒後。球はそこで打点に着く。
        let shown = HomerunSwingContact.contactShownTime(release: release, offsetMilliseconds: 0, column: 0)
        #expect(abs(shown.timeIntervalSince(release) - lead / s) < 1e-6)
        // 素振り（start = 離した時刻）は速めに流さない。
        #expect(abs(HomerunBatterMotion.swingOffset(start: release, catchUpFrom: nil, at: release.addingTimeInterval(0.1)) - 0.1) < 1e-9)
    }

    @Test("結果の間の素振り: 本番の振りより後に始めた素振りは離した瞬間から振る（判定なし）")
    func practiceSwingDuringResult() {
        let release = arrival
        let practice = arrival.addingTimeInterval(1.0)
        let miss = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 40, cursorDY: 0))
        let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: t0, releasedAt: release, offset: 0, practiceSwingAt: practice),
                                    lastBall: miss)
        #expect(plan.batterMotion(at: practice.addingTimeInterval(-0.01))
                == .swing(start: HomerunSwingContact.swingStart(release: release, offsetMilliseconds: 0, column: 0)),
                "照準で外した空振りは速めに流さない")
        #expect(plan.batterMotion(at: practice) == .swing(start: practice))
        // 見送った球の結果の間でも振れる。
        let taken = HomerunSwingPlan(phase: .ballResult, clock: clock(practiceSwingAt: practice), lastBall: HomerunJudge.judge(nil))
        #expect(taken.batterMotion(at: practice.addingTimeInterval(-0.01)) == .stance)
        #expect(taken.batterMotion(at: practice) == .swing(start: practice))
    }

    @Test("見送り: 押したまま離さなくても振らない（構えに戻る）")
    func takenPitch() {
        let miss = HomerunJudge.judge(nil)
        let heldThrough = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: t0), lastBall: miss)
        #expect(heldThrough.batterMotion(at: arrival.addingTimeInterval(0.2)) == .stance)
        let untouched = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: nil), lastBall: miss)
        #expect(untouched.batterMotion(at: arrival.addingTimeInterval(0.2)) == .stance)
    }

    @Test("球: 的が出た瞬間に投手の手を離れ、輪が重なる時刻にジャストの打点の 10cm 上に着き、当たらなければミットへ抜けて消える")
    func pitchedBall() {
        let plan = HomerunSwingPlan(phase: .pitching, clock: clock(), lastBall: nil)
        let ballArrival = try! #require(plan.ballArrival)
        #expect(plan.ballPosition(at: t0.addingTimeInterval(-0.1)) == nil, "的が出る前は無い")
        let p0 = try! #require(plan.ballPosition(at: t0))
        #expect(simd_distance(p0, HomerunBallFlight.releasePoint) < 1e-4)
        let pA = try! #require(plan.ballPosition(at: ballArrival))
        let axis = try! #require(HomerunSwingContact.crossing(atClipTime: HomerunSwingContact.contactWindow(column: 0).just, x: 0))
        #expect(simd_distance(pA, axis + [0, HomerunSwingContact.approachLift, 0]) < 1e-4)
        // 等速の直線。
        let flight = ballArrival.timeIntervalSince(t0)
        let mid = try! #require(plan.ballPosition(at: t0.addingTimeInterval(flight / 2)))
        #expect(simd_distance(mid, (p0 + pA) / 2) < 1e-3)
        // 見送り: 結果に入っても同じ線をミットまで進み、ミットの奥で消える。
        let taken = HomerunSwingPlan(phase: .ballResult, clock: clock(), lastBall: HomerunJudge.judge(nil))
        let after = try! #require(taken.ballPosition(at: ballArrival.addingTimeInterval(0.05)))
        #expect(after.z < pA.z)
        #expect(taken.ballPosition(at: ballArrival.addingTimeInterval(1.0)) == nil, "ミットに入った後は消える")
    }

    @Test("画面の 3D の球は、輪が重なる瞬間に 2D の的（判定のボールの位置）にちょうど重なって映る（全ゾーン・前 / 後ろのカメラ・画面の大きさ違い・#1647）",
          arguments: [CGSize(width: 402, height: 874), CGSize(width: 375, height: 667), CGSize(width: 440, height: 956)])
    func pitchedBallOverlapsTarget(screen: CGSize) throws {
        for preset in HomerunAtBatLayout.CameraPreset.allCases {
            let camera = preset.camera
            let aspect = Double(screen.width / screen.height)
            for zone in 0..<9 {
                let plan = HomerunSwingPlan(phase: .pitching, clock: clock(zone: zone), lastBall: nil)
                let ball = try #require(plan.ballPosition(at: arrival, camera: camera, screen: screen))
                let p = camera.screenPoint(of: ball, aspect: aspect)
                let target = HomerunZoneGeometry.ballPoint(zone: zone)
                let dx = p.x * Double(screen.width) - (Double(screen.width) / 2 + Double(target.x))
                let dy = p.y * Double(screen.height) - (Double(screen.height) * HomerunAtBatLayout.zoneScreenFraction + Double(target.y))
                #expect(abs(dx) < 0.5 && abs(dy) < 0.5, "\(preset) zone \(zone) \(screen): 的からのずれ (\(dx), \(dy)) pt")
                // 奥行きは打点（の上）のまま: バットとの同期（投球の速さ・当たる瞬間の時刻）は変えない。
                let column = HomerunSwingContact.column(zone: zone)
                #expect(abs(ball.z - HomerunSwingContact.approachTarget(column: column).z) < 1e-4)
                // 球は手前のバッティングマシンの口から出る。
                #expect(simd_distance(try #require(plan.ballPosition(at: t0, camera: camera, screen: screen)),
                                      HomerunBallFlight.releasePoint) < 1e-4)
            }
        }
    }

    // #1655 会長 QA（2026-10-01）: 突き抜けて見えた。#1771 会長 QA（2026-10-02）: ミットへ曲げると吸い込まれる変化球に見えた。
    // 的に着いた後は投球の線のまま同じ速さでまっすぐ進み、ミットの深さで止まって `mittHold` 後に消える（前・後ろのカメラ・全ゾーン）。
    @Test("見送り・空振りの球は的に着いた後も投球の線のまま進み、ミットの深さで止まって少し後に消える（曲がらない・突き抜けない・#1771）")
    func takenBallStaysOnItsLineToMitt() throws {
        let screen = CGSize(width: 402, height: 874)
        for preset in HomerunAtBatLayout.CameraPreset.allCases {
            let camera = preset.camera
            let mitt = HomerunBallFlight.mittPoint(for: camera)
            for zone in 0..<9 {
                let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(zone: zone), lastBall: HomerunJudge.judge(nil))
                let target = try #require(plan.ballPosition(at: arrival, camera: camera, screen: screen))
                let release = HomerunBallFlight.releasePoint
                let line = simd_normalize(target - release)
                let reach = HomerunBallFlight.mittReach(target: target, mitt: mitt, travel: travel)
                #expect(reach > 0.05 && reach < 0.5, "\(preset) zone \(zone): ミットの深さまで \(reach) 秒")
                // 着いてからミットの深さまで: 常に打ち出し口からの直線の上にあり、速さも変わらない・ミットの深さより奥へ行かない。
                let speed = simd_distance(release, target) / Float(travel)
                var last = target
                for i in 1...Int(reach * 120) + 2 {
                    let p = try #require(plan.ballPosition(at: arrival.addingTimeInterval(Double(i) / 120), camera: camera, screen: screen))
                    let off = simd_length(simd_cross(p - release, line))
                    #expect(off < 1e-3, "\(preset) zone \(zone) \(i): 線から \(off) 外れた（曲がった）")
                    #expect(abs(simd_distance(p, last) - speed / 120) < 1e-3 || p.z <= mitt.z + 1e-4, "\(preset) zone \(zone) \(i): 速さが変わった")
                    #expect(p.z >= mitt.z - 1e-4, "\(preset) zone \(zone): ミットの深さより奥へ抜けた \(p)")
                    last = p
                }
                let held = try #require(plan.ballPosition(at: arrival.addingTimeInterval(reach + HomerunBallFlight.mittHold / 2),
                                                          camera: camera, screen: screen))
                #expect(abs(held.z - mitt.z) < 1e-3, "ミットの深さで止まる")
                #expect(simd_length(simd_cross(held - release, line)) < 1e-3, "止まった点も投球の線の上")
                #expect(plan.ballPosition(at: arrival.addingTimeInterval(reach + HomerunBallFlight.mittHold + 0.01),
                                          camera: camera, screen: screen) == nil, "止まった後に消える")
            }
        }
    }

    @Test("球の縫い目: 球面に乗る 1 本の閉じた曲線を赤い帯で描き、どの向きから見ても赤が見える（#1656）")
    func ballSeam() {
        for p in HomerunBallSeam.curve { #expect(abs(simd_length(p) - 1) < 1e-4) }
        let bytes = HomerunBallSeam.pixels()
        #expect(bytes.count == HomerunBallSeam.textureWidth * HomerunBallSeam.textureHeight * 4)
        let red = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] == HomerunBallSeam.stitch.0 && bytes[$0 + 1] == HomerunBallSeam.stitch.1 }.count
        let ratio = Double(red) / Double(bytes.count / 4)
        #expect(ratio > 0.08 && ratio < 0.3, "赤の割合 \(ratio)")
        // 6 方向それぞれの半球に縫い目がある（どちらから見ても C の字が見える）。
        let axes: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
        for axis in axes { #expect(HomerunBallSeam.curve.contains { simd_dot($0, axis) > 0.5 }, "\(axis)") }
        #expect(HomerunBallSeam.image() != nil)
        // 回転は時刻の大きさに関係なく正規化された四元数。
        let q = HomerunBallSeam.spin(at: Date(timeIntervalSinceReferenceDate: 8e8 + 0.123))
        #expect(abs(simd_length(q.vector) - 1) < 1e-5)
    }

    @Test("以前（打点の上へ着く球）は的と縦に大きくずれて映っていた（iPhone 17・前のカメラの上下の行・後ろのカメラの真ん中の行・#1647）")
    func legacyApproachWasMisaligned() {
        let screen = CGSize(width: 402, height: 874)
        func verticalGap(_ preset: HomerunAtBatLayout.CameraPreset, zone: Int) -> Double {
            let a = HomerunSwingContact.approachTarget(column: HomerunSwingContact.column(zone: zone))
            let y = preset.camera.screenPoint(of: a, aspect: Double(screen.width / screen.height)).y * Double(screen.height)
            return y - (Double(screen.height) * HomerunAtBatLayout.zoneScreenFraction + Double(HomerunZoneGeometry.ballPoint(zone: zone).y))
        }
        #expect(verticalGap(.front, zone: 1) > 25, "前・上の行: 球が的より下")
        #expect(verticalGap(.front, zone: 7) < -25, "前・下の行: 球が的より上")
        #expect(verticalGap(.back, zone: 4) < -20, "後ろ・真ん中: 球が的より上")
    }

    @Test("的に合わせた球でも、当たればバットが打点に来る時刻に打点（バットの上面）へ着く（#1647）")
    func alignedBallStillMeetsBat() throws {
        let screen = CGSize(width: 402, height: 874)
        let hit = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY))
        for preset in HomerunAtBatLayout.CameraPreset.allCases {
            for zone in [0, 4, 8] {
                let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(zone: zone, pressedAt: t0, releasedAt: arrival, offset: 0),
                                            lastBall: hit)
                let column = HomerunSwingContact.column(zone: zone)
                let hitAt = HomerunSwingContact.contactShownTime(release: arrival, offsetMilliseconds: 0, column: column)
                let ball = try #require(plan.ballPosition(at: hitAt, camera: preset.camera, screen: screen))
                #expect(simd_distance(ball, HomerunSwingContact.contactPoint(column: column, offsetMilliseconds: 0)) < 1e-3,
                        "\(preset) zone \(zone)")
            }
        }
    }

    @Test("当たり: 離した瞬間の球の位置から、バットが打点に来る時刻に打点（バットの上面）へ寄せ、判定の方向へ飛び出す")
    func battedBall() {
        let center = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 4))
        #expect(center.kind == .homer)
        let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: t0, releasedAt: arrival, offset: 0), lastBall: center)
        let pitching = HomerunSwingPlan(phase: .pitching, clock: clock(pressedAt: t0), lastBall: nil)
        // ジャストに離した瞬間が当たる瞬間: 球は投球の線から打点（バットの上面・3cm 下）へ移るだけ（跳ばない）。
        let r = try! #require(plan.ballPosition(at: arrival))
        #expect(simd_distance(r, try! #require(pitching.ballPosition(at: arrival))) < 0.03)
        #expect(HomerunSwingContact.contactTime(release: arrival, offsetMilliseconds: 0, column: 0) == arrival)
        // 画面でバットが打点のコマになるのは、振り抜きの前半を速めに流すぶん少し後（約 0.1 秒）。球はそこで打点に着く。
        let hitAt = HomerunSwingContact.contactShownTime(release: arrival, offsetMilliseconds: 0, column: 0)
        #expect(hitAt > arrival && hitAt.timeIntervalSince(arrival) < 0.12)
        // 早く離して当たった: 球は投球の線に沿ってほぼそのまま進み、バットが打点のコマを出す時刻に打点へ着く
        // （振り抜きの前半を速めに流すぶん、線の上の球より最大 0.3m ほど手前で待つ）。
        let earlyPlan = HomerunSwingPlan(phase: .ballResult,
                                         clock: clock(pressedAt: t0, releasedAt: arrival.addingTimeInterval(-0.06), offset: -60),
                                         lastBall: HomerunJudge.judge(HomerunSwing(timingOffset: -60, cursorDX: 0, cursorDY: 4)))
        let earlyHitAt = HomerunSwingContact.contactShownTime(release: arrival.addingTimeInterval(-0.06), offsetMilliseconds: -60, column: 0)
        for dt in stride(from: -0.06, through: earlyHitAt.timeIntervalSince(arrival), by: 0.005) {
            let now = arrival.addingTimeInterval(dt)
            let e = try! #require(earlyPlan.ballPosition(at: now))
            let d = simd_distance(e, try! #require(pitching.ballPosition(at: now)))
            #expect(d < 0.3, "dt \(dt): 投球の線から \(d)m")
        }
        let c = try! #require(plan.ballPosition(at: hitAt))
        #expect(simd_distance(c, HomerunSwingContact.contactPoint(column: 0, offsetMilliseconds: 0)) < 1e-5)
        let later = try! #require(plan.ballPosition(at: hitAt.addingTimeInterval(0.3)))
        #expect(later.z > c.z + 5 && later.y > c.y, "中堅へ上向きに飛ぶ \(later)")
        let pull = HomerunJudge.judge(HomerunSwing(timingOffset: -60, cursorDX: -11, cursorDY: 4))
        #expect(pull.direction < -20)
        let v = HomerunBallFlight.battedVelocity(pull)
        #expect(v.x > 0 && v.z > 0 && v.y > 0, "引っ張りは打者の立つ +x（三塁側・レフト）へ \(v)")
        let push = HomerunJudge.judge(HomerunSwing(timingOffset: 60, cursorDX: 11, cursorDY: 4))
        #expect(HomerunBallFlight.battedVelocity(push).x < 0, "流しは -x（一塁側・ライト）へ")
        // 柵越えの初速は 35〜50m/s（最高の当たり 180m のフライで約 45m/s・#1647）、ファウルは 28m/s。
        #expect(simd_length(HomerunBallFlight.battedVelocity(center)) > 35 && simd_length(HomerunBallFlight.battedVelocity(center)) < 50)
        let foul = HomerunJudge.judge(HomerunSwing(timingOffset: -110, cursorDX: -11, cursorDY: 4))
        #expect(foul.kind == .foul && abs(simd_length(HomerunBallFlight.battedVelocity(foul)) - 28) < 1e-3)
        // 空振り（照準を外した）は打点に寄せず、投球の線のままミットへ。
        let whiff = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 40, cursorDY: 0))
        #expect(whiff.kind == .miss)
        let whiffPlan = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: t0, releasedAt: arrival, offset: 0), lastBall: whiff)
        let w = try! #require(whiffPlan.ballPosition(at: arrival))
        let cAtArrival = HomerunSwingContact.contactPoint(column: 0, offsetMilliseconds: 0)
        #expect(abs(w.y - cAtArrival.y - (HomerunSwingContact.approachLift - HomerunSwingContact.contactLift)) < 1e-4, "空振りの球はバットの 10cm 上を抜ける")
    }

    // #1594 会長 QA（2026-09-30）: 前のカメラで引っ張った打球が打者と逆の側（ライト）へ飛んで見えた。描画のとおり
    // （`renderPose` のカメラ・反転なし・球は `placeBall` と同じく反転するカメラで x を鏡映）に画面へ投影し、
    // どちらのカメラでも「引っ張り（判定の負 = レフト）は画面の上で打者の立つ側へ、流しは反対側へ」動くことを固定する。
    @Test("打席の 3D の打球: 引っ張りは打者の立つ側（三塁側）へ・流しは反対側へ、前・後ろどちらのカメラの画面でも飛ぶ")
    func battedBallGoesToTheJudgedFieldOnScreen() {
        typealias L = HomerunAtBatLayout
        let pull = HomerunJudge.judge(HomerunSwing(timingOffset: -60, cursorDX: -11, cursorDY: 4))
        let push = HomerunJudge.judge(HomerunSwing(timingOffset: 60, cursorDX: 11, cursorDY: 4))
        #expect(pull.direction < -20 && push.direction > 20 && pull.kind != .foul && push.kind != .foul)
        for preset in L.CameraPreset.allCases {
            let cam = preset.camera
            let pose = cam.renderPose
            let render = L.Camera(position: pose.position, target: pose.target, verticalFieldOfView: cam.verticalFieldOfView)
            func place(_ p: SIMD3<Float>) -> SIMD3<Float> { L.castMirrored(for: cam) ? [-p.x, p.y, p.z] : p }
            let batterX = render.screenPoint(of: L.batter.position, aspect: 0.46).x
            // 右打者は前では画面の右、後ろでは画面の左（どちらも描画の世界では +x = 三塁側に立つ）。
            #expect(preset == .front ? batterX > 0.5 : batterX < 0.5, "\(preset): 打者 \(batterX)")
            for (ball, offset) in [(pull, -60.0), (push, 60.0)] {
                let release = arrival.addingTimeInterval(offset / 1000)
                let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: t0, releasedAt: release, offset: offset), lastBall: ball)
                let hitAt = HomerunSwingContact.contactShownTime(release: release, offsetMilliseconds: offset, column: 0)
                let c = place(try! #require(plan.ballPosition(at: hitAt, camera: cam)))
                let p = place(try! #require(plan.ballPosition(at: hitAt.addingTimeInterval(0.05), camera: cam)))
                #expect(ball.direction < 0 ? p.x > c.x + 0.5 : p.x < c.x - 0.5, "\(preset) 方向 \(ball.direction): 描画の x \(c.x) → \(p.x)")
                let dx = render.screenPoint(of: p, aspect: 0.46).x - render.screenPoint(of: c, aspect: 0.46).x
                let towardBatter = (batterX - 0.5) * dx > 0
                #expect(towardBatter == (ball.direction < 0), "\(preset) 方向 \(ball.direction): 画面の横の動き \(dx)・打者 \(batterX)")
            }
        }
    }

    /// バット（線分）と球（点）の距離。
    private func batDistance(clipTime: TimeInterval, ball: SIMD3<Float>) -> Float {
        let s = HomerunBatPath.segment(atClipTime: clipTime)
        let a = HomerunAtBatLayout.batterWorld(s.grip), b = HomerunAtBatLayout.batterWorld(s.tip)
        let ab = b - a
        let k = min(max(simd_dot(ball - a, ab) / simd_dot(ab, ab), 0), 1)
        return simd_distance(ball, a + ab * k)
    }

    @Test("当たった瞬間はバットと球が触れ（軸から半径の和）、ジャストで照準を外した空振りでは球がバットを通り抜けない")
    func contactAndNoPassThrough() {
        let touching = HomerunBatPath.barrelRadius + HomerunSwingContact.ballRadius
        for column in -1...1 {
            for offset in [-110.0, -60, 0, 60, 110] {
                let release = arrival.addingTimeInterval(offset / 1000)
                let ball = HomerunJudge.judge(HomerunSwing(timingOffset: offset, cursorDX: 0, cursorDY: 4))
                let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(zone: 4 + column, pressedAt: t0, releasedAt: release, offset: offset),
                                            lastBall: ball)
                guard case .swing(let start, let catchUpFrom) = plan.batterMotion(at: release) else { Issue.record("振っていない"); continue }
                #expect(start == HomerunSwingContact.swingStart(release: release, offsetMilliseconds: offset, column: column))
                let hitAt = HomerunSwingContact.contactShownTime(release: release, offsetMilliseconds: offset, column: column)
                let clip = HomerunSwingContact.swingClipStart
                    + HomerunBatterMotion.swingOffset(start: start, catchUpFrom: catchUpFrom, at: hitAt)
                let d = batDistance(clipTime: clip, ball: try! #require(plan.ballPosition(at: hitAt)))
                #expect(abs(d - touching) < 0.005, "列 \(column)・ずれ \(offset)ms: 当たった瞬間のバットと球の距離 \(d)")
            }
            // ジャストに離して照準を外した空振り: バットが球の通り道を通る間、球はバットの表面から 2cm 以上離れている。
            let whiff = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 40, cursorDY: 0))
            let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(zone: 4 + column, pressedAt: t0, releasedAt: arrival, offset: 0),
                                        lastBall: whiff)
            guard case .swing(let whiffStart, let whiffCatchUp) = plan.batterMotion(at: arrival) else { Issue.record("振っていない"); continue }
            var minGap: Float = .infinity
            for dt in stride(from: -0.3, through: 0.6, by: 1.0 / 240) {
                let now = arrival.addingTimeInterval(dt)
                guard let ball = plan.ballPosition(at: now) else { continue }
                // 離す前は踏み込み（20 コマ目）、離した瞬間から 20 コマ目を速めに流して振り抜きの予定に追いつく。
                let clip = HomerunSwingContact.swingClipStart
                    + (now < arrival ? 0 : HomerunBatterMotion.swingOffset(start: whiffStart, catchUpFrom: whiffCatchUp, at: now))
                minGap = min(minGap, batDistance(clipTime: clip, ball: ball) - touching)
            }
            #expect(minGap > 0.02, "列 \(column): 空振りで球がバットに \(minGap)m まで近づく")
        }
    }

    @Test("早い/遅い空振りでも球はバットを通り抜けない")
    func missNoPassThrough() {
        let touching = HomerunBatPath.barrelRadius + HomerunSwingContact.ballRadius
        for offset in [-300.0, -150, -111, 111, 150, 300] {
            let release = arrival.addingTimeInterval(offset / 1000)
            let miss = HomerunJudge.judge(HomerunSwing(timingOffset: offset, cursorDX: 0, cursorDY: 4))
            #expect(miss.kind == .miss)
            let plan = HomerunSwingPlan(phase: .ballResult, clock: clock(pressedAt: t0, releasedAt: release, offset: offset), lastBall: miss)
            guard case .swing(let start, let catchUpFrom) = plan.batterMotion(at: release) else { Issue.record("振っていない"); continue }
            var minGap: Float = .infinity
            for dt in stride(from: -0.4, through: 0.8, by: 1.0 / 240) {
                let now = arrival.addingTimeInterval(dt)
                guard let ball = plan.ballPosition(at: now) else { continue }
                let clip = HomerunSwingContact.swingClipStart
                    + (now < release ? 0 : HomerunBatterMotion.swingOffset(start: start, catchUpFrom: catchUpFrom, at: now))
                minGap = min(minGap, batDistance(clipTime: clip, ball: ball) - touching)
            }
            #expect(minGap > 0.02, "ずれ \(offset)ms の空振りで球がバットに \(minGap)m まで近づく")
        }
    }

    @Test("モデルは 1 球ごとに時刻の記録を持ち、押した・離した時刻とずれを残す。的が出る前に離すと押しは消え、素振りの時刻が残る")
    @MainActor
    func modelKeepsBallClock() throws {
        let defaults = UserDefaults(suiteName: "HomerunSwingContactTests.\(UUID())")!
        let model = HomerunModel(defaults: defaults, now: t0)
        #expect(model.ballClock == nil)
        model.start(now: t0)
        let clock = try #require(model.ballClock)
        #expect(clock.pitchStart == t0.addingTimeInterval(HomerunModel.windup) && clock.zone == 4 && clock.pressedAt == nil)
        model.press(at: .zero, now: t0.addingTimeInterval(0.2))
        #expect(model.ballClock?.pressedAt == t0.addingTimeInterval(0.2))
        _ = model.release(at: .zero, now: t0.addingTimeInterval(0.5))   // モーション中: 素振り（判定しない）
        #expect(model.ballClock?.pressedAt == nil && model.ballClock?.releasedAt == nil)
        #expect(model.ballClock?.practiceSwingAt == t0.addingTimeInterval(0.5))
        let arrival = try #require(model.arrival)
        model.press(at: .zero, now: arrival.addingTimeInterval(-0.5))
        _ = model.release(at: CGPoint(x: 0, y: 22), now: arrival.addingTimeInterval(-0.03))
        #expect(model.phase == .ballResult)
        #expect(model.ballClock?.releasedAt == arrival.addingTimeInterval(-0.03))
        #expect(abs((model.ballClock?.timingOffset ?? 0) + 30) < 1e-6)
        #expect(model.ballClock?.zone == 4, "結果の間も打った球の記録のまま（次の球ではない）")
        // 押したまま次の球へ: 押しは引き継ぐ（結果の時間 = 柵越えで約 5.25 秒・#1645 の後に次の球へ）。
        model.advance(now: arrival.addingTimeInterval(6))
        #expect(model.phase == .pitching && model.ballClock?.zone == 0)
        #expect(model.ballClock?.pressedAt == nil && model.ballClock?.releasedAt == nil)
        #expect(model.ballClock?.practiceSwingAt == nil, "振り終わった素振りは次の球に持ち越さない")
        model.press(at: .zero, now: arrival.addingTimeInterval(6.1))
        model.advance(now: arrival.addingTimeInterval(6 + HomerunModel.windup + HomerunModel.travel + 1))   // 見送り
        model.advance(now: arrival.addingTimeInterval(6 + HomerunModel.windup + HomerunModel.travel + 3))   // 次の球
        #expect(model.phase == .pitching && model.ballClock?.zone == 8)
        #expect(model.ballClock?.pressedAt == arrival.addingTimeInterval(6.1), "押したままなら前の押しの時刻を引き継ぐ")
    }

    #if canImport(RealityKit)
    @Test("表は RealityKit が再生する骨と一致する（打点のコマの先端の位置の差が 1cm 以内）")
    @MainActor
    func tableMatchesRig() throws {
        guard #available(macOS 15.0, iOS 18.0, *) else { return }
        let rig = try #require(HomerunBatterRig())
        let renderer = try RealityRenderer()
        renderer.entities.append(rig.entity)
        func rigTip() throws -> SIMD3<Float> {
            func findSkinned(_ e: Entity) -> ModelEntity? {
                if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
                for c in e.children { if let m = findSkinned(c) { return m } }
                return nil
            }
            let model = try #require(findSkinned(rig.entity))
            let names = model.jointNames
            let index = try #require(names.firstIndex { $0.hasSuffix("RightHand/Bat") })
            var m = matrix_identity_float4x4
            var path = names[index]
            while true {
                if let i = names.firstIndex(of: path) { m = model.jointTransforms[i].matrix * m }
                guard let slash = path.lastIndex(of: "/") else { break }
                path = String(path[..<slash])
            }
            let p = m * SIMD4<Float>(HomerunBatPath.tipInBatJoint, 1)
            return [p.x, p.y, p.z]
        }
        let now = Date()
        for clip in [0.0, 0.5, HomerunSwingContact.contactWindow(column: 0).just, 26.0 / 30, 1.2] {
            // `show(.swing(start:))` は start からの経過ぶん進めた所から流す。
            rig.show(.swing(start: now.addingTimeInterval(-(clip - HomerunSwingContact.swingClipStart))), now: now)
            if clip < HomerunSwingContact.swingClipStart { rig.show(.stance, now: now) }
            try renderer.update(0.001)
            let expected = HomerunBatPath.segment(atClipTime: clip).tip
            let actual = try rigTip()
            #expect(simd_distance(expected, actual) < 0.01 || clip < HomerunSwingContact.swingClipStart, "クリップ \(clip)s: 表 \(expected)・rig \(actual)")
        }
        // 構え（1 コマ目）も一致。
        rig.show(.stance, now: now)
        try renderer.update(0.001)
        #expect(simd_distance(HomerunBatPath.segment(atClipTime: 0).tip, try rigTip()) < 0.01)
    }
    #endif
}
