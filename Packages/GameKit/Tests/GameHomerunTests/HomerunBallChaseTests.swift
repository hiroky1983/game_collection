import Testing
import Foundation
import simd
import GameKitTestSupport
@testable import HomerunCore
@testable import GameHomerun

@Suite("柵越えおじさんの打球を追うカメラ（#1613）")
struct HomerunBallChaseTests {
    typealias Chase = HomerunBallChase

    private func swing(t: Double = 0, dx: Double = 0, band: HomerunLaunch = .fly, dy: Double = 0) -> HomerunSwing {
        HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: band.centerDY + dy)
    }

    /// 当たり窓の中のずれ・照準の横のずれ・4 つの帯を総当たりした、当たり以上の打球。
    private var allHits: [HomerunBattedBall] {
        var balls: [HomerunBattedBall] = []
        for t in stride(from: -100.0, through: 100, by: 20) {
            for dx in stride(from: -11.0, through: 11, by: 5.5) {
                for band in [HomerunLaunch.grounder, .liner, .fly, .pop] {
                    for dy in [-8.0, 0, 8] {
                        let ball = HomerunJudge.judge(swing(t: t, dx: dx, band: band, dy: dy))
                        if ball.kind != .miss { balls.append(ball) }
                    }
                }
            }
        }
        return balls
    }

    private func track(_ ball: HomerunBattedBall) throws -> Chase.Track {
        try #require(Chase.track(for: ball), "\(ball) の打球の道が無い")
    }

    /// 道を細かく刻んだ点。
    private func samples(_ track: Chase.Track, step: TimeInterval = 1.0 / 120) -> [Chase.Point] {
        stride(from: 0, through: track.duration + 0.2, by: step).map { track.point(at: $0) }
    }

    @Test("総当たりに柵越え・フェンス直撃・当たり・ファウルがそれぞれ含まれる（テストの前提）")
    func fixturesCoverAllKinds() {
        let kinds = Set(allHits.map(\.kind))
        #expect(kinds == [.homer, .fenceHit, .inPlay, .foul], "\(kinds)")
    }

    @Test("空振りは打球の道が無く、当たり以上はすべて道がある")
    func onlyHitsHaveTracks() {
        #expect(Chase.track(for: HomerunJudge.judge(nil)) == nil)
        for ball in allHits { #expect(Chase.track(for: ball) != nil) }
    }

    @Test("球は判定の方向の線の上を動き、引っ張り（負 = レフト）は +x（三塁側・#1616）")
    func ballStaysOnTheDirectionLine() throws {
        for ball in allHits {
            let tr = try track(ball)
            let radians = ball.direction * .pi / 180
            for t in stride(from: 0.0, through: tr.duration, by: 0.1) {
                let p = tr.position(at: t)
                let s = Double(tr.point(at: t).s)
                #expect(abs(Double(p.x) + s * sin(radians)) < 0.01 && abs(Double(p.z) - s * cos(radians)) < 0.01)
            }
            if ball.direction < -1 { #expect(tr.rest.s > 0 && tr.position(at: tr.duration).x > 0, "レフトの打球が +x に無い") }
            if ball.direction > 1 { #expect(tr.position(at: tr.duration).x < 0, "ライトの打球が -x に無い") }
        }
    }

    @Test("当たり: 判定の飛距離より手前に落ち、弾んで転がり、判定の飛距離で止まる")
    func inPlayStopsAtTheJudgedDistance() throws {
        let balls = allHits.filter { $0.kind == .inPlay }
        #expect(!balls.isEmpty)
        for ball in balls {
            let tr = try track(ball)
            #expect(abs(tr.rest.s - ball.distance) < 0.01, "止まる点 \(tr.rest.s) ≠ 飛距離 \(ball.distance)")
            #expect(abs(tr.rest.y - Chase.ballRadius) < 1e-9, "止まった球が地面に無い")
            #expect(tr.landing.s < ball.distance && abs(tr.landing.y - Chase.ballRadius) < 1e-9, "先に地面へ落ちていない")
            #expect(tr.segments.count >= 3, "弾み・転がりが無い")
            #expect(tr.segments.last?.motion == .roll, "最後は転がって止まる")
            // 柵を越えず、地面より下へ行かない。
            for p in samples(tr) {
                #expect(p.s < ball.fence - 1 && p.y >= Chase.ballRadius - 1e-6)
            }
        }
    }

    @Test("フェンス直撃: 柵の面まで飛んで当たり、跳ね返って柵の手前（判定の飛距離）で止まる")
    func fenceHitBouncesBack() throws {
        let balls = allHits.filter { $0.kind == .fenceHit }
        #expect(!balls.isEmpty)
        for ball in balls {
            let tr = try track(ball)
            let wall = ball.fence - Chase.fenceContactInset
            #expect(abs(tr.landing.s - wall) < 1e-9, "最初に着くのが柵の面ではない")
            #expect(tr.landing.y > 1 && tr.landing.y < 3.2, "柵（高さ 3.2m）の面の途中に当たっていない: \(tr.landing.y)")
            #expect(samples(tr).allSatisfy { $0.s <= wall + 1e-9 }, "柵を突き抜けた")
            #expect(tr.rest.s < wall && abs(tr.rest.s - ball.distance) < 0.5, "止まる点 \(tr.rest.s)・飛距離 \(ball.distance)")
            #expect(abs(tr.rest.y - Chase.ballRadius) < 1e-9)
        }
    }

    @Test("柵越え: 柵の真上を柵より高く越え、判定の飛距離（スタンドの最後列まで）でスタンドに落ちる")
    func homerClearsTheFenceAndLandsInTheStands() throws {
        let balls = allHits.filter { $0.kind == .homer }
        #expect(!balls.isEmpty)
        let farthest: (Double) -> Double = { $0 + 2 + Double(HomerunToonModel.Stand.depth(row: HomerunToonModel.Stand.rows - 1)) }
        for ball in balls {
            let tr = try track(ball)
            // 柵の真上の高さ（最初の区間 = 飛んでいる放物線の、柵の位置の点）。
            let flight = try #require(tr.segments.first)
            #expect(flight.to.s > ball.fence, "柵まで届いていない")
            let overFence = flight.point(at: (ball.fence - flight.from.s) / (flight.to.s - flight.from.s))
            #expect(overFence.y >= Chase.fenceClearance - 1e-6, "柵の上 \(overFence.y)m で越えていない（\(ball.direction)°）")
            let screen = Chase.battersEyeZ / cos(ball.direction * .pi / 180)
            let hitsScreen = abs(screen * sin(ball.direction * .pi / 180)) < Chase.battersEyeHalfWidth && tr.rest.s < screen - 1
            if hitsScreen {
                // バックスクリーン直撃: スクリーンの面で跳ね返り、足元に落ちる。
                #expect(abs(tr.landing.s - (screen - Chase.ballRadius)) < 1e-6)
                #expect(tr.rest.s > ball.fence && tr.rest.y == Chase.ballRadius)
            } else {
                let nearest = ball.fence + 2 + Double(HomerunToonModel.Stand.depth(row: 0))
                let expected = min(max(ball.distance, nearest), farthest(ball.fence))
                #expect(abs(tr.landing.s - expected) < 0.01, "落ちる点 \(tr.landing.s) ≠ \(expected)")
                if abs(ball.direction) >= 6 {
                    #expect(tr.landing.y > 1, "スタンド（座面）の上に落ちていない: \(tr.landing.y)")
                    // 弾んで止まる所の座面に埋まらない（#1645）。
                    let seat = Chase.standSurface(depth: tr.rest.s - (ball.fence + 2))
                    #expect(tr.rest.y >= seat + Chase.ballRadius - 1e-9, "止まった球が座席に埋まる: \(tr.rest.y) < \(seat)")
                }
                #expect(tr.rest.s > ball.fence, "柵の手前に戻ってきた")
            }
        }
    }

    @Test("ファウル: ファウルゾーン（±45° の外）の芝に落ちて転がり、スタンド（ファウルラインの 16m 外）の手前で止まる")
    func foulRollsInFoulTerritory() throws {
        let balls = allHits.filter { $0.kind == .foul }
        #expect(!balls.isEmpty)
        for ball in balls {
            let tr = try track(ball)
            #expect(abs(ball.direction) > HomerunJudge.foulLimit)
            #expect(abs(tr.rest.s - Chase.foulRestDistance(for: ball.launch)) < 0.01)
            let offLine = tr.rest.s * sin((abs(ball.direction) - 45) * .pi / 180)
            #expect(offLine > 0 && offLine < 16, "ファウルラインから \(offLine)m")
            #expect(abs(tr.rest.y - Chase.ballRadius) < 1e-9)
        }
    }

    @Test("打球は結果のカードの上限（柵越え 3.6 秒・その他 2.8 秒・ファウル 2.3 秒）から止めて見せる時間を引いた内に止まる")
    func trackFitsTheTimeLimit() throws {
        for ball in allHits {
            let tr = try track(ball)
            #expect(tr.duration + Chase.restHold <= Chase.limit(for: ball.kind) + 1e-9, "\(ball.kind) \(tr.duration) 秒")
            #expect(tr.point(at: tr.duration + 5) == tr.rest, "止まった後も動いている")
        }
        #expect(Chase.limit(for: .homer) == 3.6)
        #expect(Chase.limit(for: .inPlay) <= 2.8 && Chase.limit(for: .fenceHit) <= 2.8 && Chase.limit(for: .foul) <= 2.8)
    }

    @Test("追う球はカメラから遠ざかるほど小さく映り、下限より小さくはならない（#1645 会長 QA「球が大きすぎる」）")
    func ballShrinksWithDistance() throws {
        let halfTan = tan(Double(Chase.verticalFieldOfView) * .pi / 360)
        // 見かけの直径（画面の高さに対する割合）。
        func apparent(_ f: Chase.Frame) -> Double {
            let radius = Double(f.ballScale) * Double(HomerunSwingContact.ballRadius)
            return radius / Double(simd_distance(f.camera.position, f.ball)) / halfTan
        }
        let floor = Chase.minApparentRadius / halfTan
        for ball in allHits {
            let tr = try track(ball)
            let first = Chase.frame(tr, at: Chase.cutDelay)
            // 切り替え直後でも画面の高さの 3% 未満（以前の 0.3m の球は約 6%）。
            #expect(apparent(first) < 0.03, "\(ball.kind) の切り替え直後の球が大きい: \(apparent(first))")
            for t in stride(from: Chase.cutDelay, through: tr.duration, by: 0.05) {
                #expect(apparent(Chase.frame(tr, at: t)) >= floor - 1e-6, "\(ball.kind) の球が \(t) 秒で下限より小さい")
            }
        }
        // 柵越えは、スタンドに落ちるときには切り替え直後より小さく映る（遠くへ飛んだ感じ）。
        for ball in allHits where ball.kind == .homer {
            let tr = try track(ball)
            #expect(apparent(Chase.frame(tr, at: tr.flightDuration)) < apparent(Chase.frame(tr, at: Chase.cutDelay)) * 0.6)
        }
    }

    @Test("遠くで大きく見せた球も、止まったとき地面に埋まらない（#1646 CodeRabbit）")
    func enlargedBallDoesNotSinkIntoGround() throws {
        for ball in allHits where ball.kind != .homer {
            let tr = try track(ball)
            let f = Chase.frame(tr, at: tr.duration)
            let radius = Double(f.ballScale) * Double(HomerunSwingContact.ballRadius)
            #expect(Double(f.ball.y) - radius >= -1e-4, "\(ball.kind) の球が地面に埋まっている: 中心 \(f.ball.y) 半径 \(radius)")
        }
    }

    @Test("球もカメラもコマの間で跳ばない（1/60 秒で 2.5m 以内）")
    func noJumps() throws {
        for ball in allHits {
            let tr = try track(ball)
            var last: Chase.Frame?
            for t in stride(from: Chase.cutDelay, through: tr.duration + 0.1, by: 1.0 / 60) {
                let f = Chase.frame(tr, at: t)
                if let last {
                    #expect(simd_distance(f.ball, last.ball) < 2.5, "\(ball.kind) の球が \(t) 秒で跳んだ")
                    #expect(simd_distance(f.camera.position, last.camera.position) < 2.5, "\(ball.kind) のカメラが \(t) 秒で跳んだ")
                }
                last = f
            }
        }
    }

    @Test("カメラは球の後ろ（本塁側）・柵の手前から球を見て、球は画面の真ん中に映る")
    func cameraLooksAtTheBallFromBehind() throws {
        for ball in allHits {
            let tr = try track(ball)
            for t in stride(from: Chase.cutDelay, through: tr.duration, by: 0.1) {
                let f = Chase.frame(tr, at: t)
                let p = tr.point(at: t)
                let camS = Double(simd_dot(SIMD2(f.camera.position.x, f.camera.position.z),
                                           SIMD2(Float(-sin(ball.direction * .pi / 180)), Float(cos(ball.direction * .pi / 180)))))
                #expect(camS < p.s - 5, "カメラが球の後ろにいない")
                #expect(camS <= ball.fence - Chase.cameraFenceMargin + 0.01, "カメラが柵の近く・外へ出た")
                #expect(f.camera.target == f.ball)
                #expect(!f.camera.mirrored)
                let screen = f.camera.screenPoint(of: f.ball, aspect: 0.46)
                #expect(abs(screen.x - 0.5) < 1e-3 && abs(screen.y - 0.5) < 1e-3)
            }
        }
    }

    @Test("柵越えでスタンドに止まった球は、カメラから柵越しに見える（柵に隠れない・#1645）")
    func homerRestIsVisibleOverTheFence() throws {
        var checked = 0
        for ball in allHits where ball.kind == .homer {
            let tr = try track(ball)
            guard Chase.overFenceHeight(tr) < Chase.maxCameraHeight else { continue }   // 上限で頭打ちの球（バックスクリーンの足元）は除く
            let f = Chase.frame(tr, at: tr.duration)
            let camera = f.camera.position
            let radians = ball.direction * .pi / 180
            let camS = Double(camera.z) / cos(radians)
            let u = (ball.fence - camS) / (tr.rest.s - camS)
            let sightAtFence = Double(camera.y) + (tr.rest.y - Double(camera.y)) * u
            #expect(sightAtFence >= Chase.fenceTop, "\(ball.direction)° \(ball.distance)m の球が柵に隠れる（視線 \(sightAtFence)m）")
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test("同じ打球は同じ道になる（乱数なし）")
    func deterministic() {
        for ball in allHits.prefix(40) { #expect(Chase.track(for: ball) == Chase.track(for: ball)) }
    }

    // MARK: 時刻（`HomerunSwingPlan`）

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private var arrival: Date { t0.addingTimeInterval(TimeInterval(HomerunPitch.travelMilliseconds) / 1000) }

    private func plan(offset: Double, ball: HomerunBattedBall, zone: Int = 4) -> (HomerunSwingPlan, Date) {
        let release = arrival.addingTimeInterval(offset / 1000)
        let clock = HomerunModel.BallClock(pitchStart: t0, zone: zone, pressedAt: t0, releasedAt: release, timingOffset: offset)
        return (HomerunSwingPlan(phase: .ballResult, clock: clock, lastBall: ball), release)
    }

    @Test("離してからバットに当たるまでは `contactLeadMax` 以内（1 球の結果の時間の見積もりの前提）")
    func contactLeadIsBounded() {
        for offset in stride(from: -110.0, through: 110, by: 5) {
            for column in -1...1 {
                let release = arrival.addingTimeInterval(offset / 1000)
                let lead = HomerunSwingContact.contactShownTime(release: release, offsetMilliseconds: offset, column: column)
                    .timeIntervalSince(release)
                #expect(lead >= 0 && lead <= Chase.contactLeadMax, "ずれ \(offset)ms・列 \(column): \(lead) 秒")
            }
        }
    }

    @Test("当たってから少しの間は打席のカメラのまま、その後は追うカメラ。カードは止まってから・次の球より前に出る")
    @MainActor
    func planTimeline() throws {
        for (offset, ball) in [(0.0, HomerunJudge.judge(swing())), (60, HomerunJudge.judge(swing(t: 60, band: .liner))),
                               (-90, HomerunJudge.judge(swing(t: -90, dx: 11, band: .grounder)))] {
            let (plan, release) = plan(offset: offset, ball: ball)
            let contact = try #require(plan.contactAt)
            let tr = try #require(plan.chaseTrack)
            #expect(plan.chaseFrame(at: contact.addingTimeInterval(Chase.cutDelay - 0.01)) == nil)
            let first = try #require(plan.chaseFrame(at: contact.addingTimeInterval(Chase.cutDelay)))
            #expect(first == Chase.frame(tr, at: Chase.cutDelay))
            let card = try #require(plan.chaseCardAt)
            #expect(abs(card.timeIntervalSince(contact) - (tr.duration + Chase.restHold)) < 1e-6)
            // 次の球（`resultUntil`）までにカードを `cardHold` 秒以上見せる。
            let resultEnd = release.addingTimeInterval(HomerunModel.resultDuration(for: ball.kind))
            #expect(resultEnd.timeIntervalSince(card) >= Chase.cardHold - 1e-6, "\(ball.kind): カードが \(resultEnd.timeIntervalSince(card)) 秒しか出ない")
            // カードを出した後も止まった球を映し続ける。
            #expect(plan.chaseFrame(at: card.addingTimeInterval(1)) == Chase.frame(tr, at: tr.duration))
        }
    }

    @Test("空振り・見送り・投球中は追うカメラにしない")
    func noChaseForMisses() {
        let miss = HomerunJudge.judge(swing(t: 300))
        #expect(miss.kind == .miss)
        let (missPlan, _) = plan(offset: 300, ball: miss)
        #expect(missPlan.contactAt == nil && missPlan.chaseCardAt == nil && missPlan.chaseFrame(at: arrival.addingTimeInterval(1)) == nil)
        let took = HomerunSwingPlan(phase: .ballResult, clock: HomerunModel.BallClock(pitchStart: t0, zone: 4), lastBall: HomerunJudge.judge(nil))
        #expect(took.chaseFrame(at: arrival.addingTimeInterval(1)) == nil)
        let pitching = HomerunSwingPlan(phase: .pitching, clock: HomerunModel.BallClock(pitchStart: t0, zone: 4), lastBall: HomerunJudge.judge(swing()))
        #expect(pitching.chaseFrame(at: arrival.addingTimeInterval(1)) == nil)
    }

    @Test("上端の合計・柵越え本数は、結果のカードを出すまで直前の球を数えない（ネタバレ防止・会長 QA 2026-09-30）")
    @MainActor
    func hudHidesTheLastBallUntilTheCard() {
        let homer = HomerunJudge.judge(swing())
        let inPlay = HomerunJudge.judge(swing(t: 90, band: .liner, dy: -8))
        #expect(homer.kind == .homer && inPlay.kind == .inPlay)
        let hidden = HomerunAtBatView.hudTotals(results: [inPlay, homer], revealsLast: false)
        #expect(hidden.distance == inPlay.distance && hidden.homers == 0)
        let shown = HomerunAtBatView.hudTotals(results: [inPlay, homer], revealsLast: true)
        #expect(shown.distance == inPlay.distance + homer.distance && shown.homers == 1)
        #expect(HomerunAtBatView.hudTotals(results: [], revealsLast: false) == (0, 0))
    }

    @Test("打席の上端に直前 2 球のチップ（「◯ 球目 …」）を置かない")
    func noRecentBallChips() throws {
        let url = SourceScan.packageRoot.appendingPathComponent("Sources/GameHomerun/HomerunAtBatView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("results.enumerated().suffix(2)"), "直前 2 球のチップが残っている")
    }

    @Test("1 球の結果の時間: 柵越えが一番長く、空振りが一番短い")
    @MainActor
    func resultDurations() {
        #expect(HomerunModel.resultDuration(for: .homer) > HomerunModel.resultDuration(for: .inPlay))
        #expect(HomerunModel.resultDuration(for: .inPlay) >= HomerunModel.resultDuration(for: .foul))
        #expect(HomerunModel.resultDuration(for: .foul) > HomerunModel.resultDuration(for: .miss))
        for kind in [HomerunKind.homer, .fenceHit, .inPlay, .foul] {
            #expect(HomerunModel.resultDuration(for: kind) == Chase.contactLeadMax + Chase.limit(for: kind) + Chase.cardHold)
        }
    }
}
