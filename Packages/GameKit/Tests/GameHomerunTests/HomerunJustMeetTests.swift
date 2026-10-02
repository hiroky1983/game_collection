import Testing
import Foundation
import simd
import HomerunCore
@testable import GameHomerun

@Suite("柵越えおじさんのジャストミート演出（#1775）")
struct HomerunJustMeetTests {
    typealias JM = HomerunJustMeet

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private var arrival: Date { t0.addingTimeInterval(TimeInterval(HomerunPitch.travelMilliseconds) / 1000) }

    private func swing(t: Double = 0, dx: Double = 0, band: HomerunLaunch = .fly, dy: Double = 0) -> HomerunSwing {
        HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: band.centerDY + dy)
    }

    private func plan(ball: HomerunBattedBall, offset: Double = 0, zone: Int = 4) -> HomerunSwingPlan {
        let release = arrival.addingTimeInterval(offset / 1000)
        let clock = HomerunModel.BallClock(pitchStart: t0, zone: zone, pressedAt: t0, releasedAt: release, timingOffset: offset)
        return HomerunSwingPlan(phase: .ballResult, clock: clock, lastBall: ball)
    }

    @Test("演出を出すのはジャストミートの当たりだけ。月まで飛んだ打球・ナイス・空振りは出さない")
    func appliesOnlyToJustMeet() {
        #expect(JM.applies(to: HomerunJudge.judge(swing())))
        #expect(!JM.applies(to: HomerunJudge.judge(swing(t: 40))))
        #expect(!JM.applies(to: HomerunJudge.judge(swing(dx: 100))))
        #expect(!JM.applies(to: nil))
        var moon = HomerunJudge.judge(swing())
        moon.moon = .hit
        #expect(!JM.applies(to: moon))
    }

    @Test("表示の時間は、ヒットストップの間はほぼ止まり、明けたら増えたぶんだけ遅れて進む（連続）")
    func displayElapsed() {
        #expect(JM.displayElapsed(realElapsed: -0.1) == -0.1)
        #expect(JM.displayElapsed(realElapsed: 0) == 0)
        #expect(abs(JM.displayElapsed(realElapsed: JM.hitStop) - JM.slowdown * JM.hitStop) < 1e-9)
        // 止めている間に進むのは ほんの少しだけ（0 ではない）。
        let mid = JM.displayElapsed(realElapsed: JM.hitStop / 2)
        #expect(mid > 0 && mid < 0.02)
        // 明けた後は実時間より `extraDuration` だけ遅れる。
        for real in [JM.hitStop, 0.3, 1, 3] {
            #expect(abs(JM.displayElapsed(realElapsed: real) - (real - JM.extraDuration)) < 1e-9 || real == JM.hitStop)
        }
        // 単調に増える。
        var last = -1.0
        for real in stride(from: 0.0, through: 2, by: 0.005) {
            let d = JM.displayElapsed(realElapsed: real)
            #expect(d >= last)
            last = d
        }
    }

    @Test("引き終わりは打球を追うカメラへ移る前に収まる。ヒットストップは 0.12〜0.25 秒")
    func pullBackFinishesBeforeChase() {
        #expect(JM.hitStop >= 0.12 && JM.hitStop <= 0.25)
        #expect(JM.hitStop + JM.pullBackDuration <= JM.effectDuration + 1e-9)
        // 演出の終わりは表示の時間が打球を追うカメラへ移る（cutDelay）瞬間。
        #expect(abs(JM.displayElapsed(realElapsed: JM.effectDuration) - HomerunBallChase.cutDelay) < 1e-9)
        #expect(JM.zoom(realElapsed: JM.effectDuration) == 0)
    }

    @Test("寄りは当たった瞬間から寄り、ヒットストップの間は寄りきり、明けたら引く")
    func zoomCurve() {
        #expect(JM.zoom(realElapsed: -0.01) == 0 && JM.zoom(realElapsed: 0) == 0)
        #expect(JM.zoom(realElapsed: JM.zoomInDuration) == 1)
        #expect(JM.zoom(realElapsed: JM.hitStop - 0.001) == 1)
        let pulled = JM.zoom(realElapsed: JM.hitStop + JM.pullBackDuration / 2)
        #expect(pulled > 0 && pulled < 1)
        #expect(JM.zoom(realElapsed: JM.hitStop + JM.pullBackDuration) == 0)
    }

    @Test("寄りのカメラは位置を動かさず、画角を狭めて打点を画面の中央に置く。寄りが無ければ打席のカメラのまま")
    func zoomCamera() throws {
        let base = HomerunAtBatLayout.camera
        let point = HomerunSwingContact.contactPoint(column: 0, offsetMilliseconds: 0)
        #expect(JM.camera(base: base, contact: point, zoom: 0) == base)
        let full = JM.camera(base: base, contact: point, zoom: 1)
        #expect(full.position == base.position)
        #expect(abs(full.verticalFieldOfView - JM.zoomFieldOfView) < 1e-5)
        #expect(JM.zoomFieldOfView < base.verticalFieldOfView)
        let screen = full.screenPoint(of: point, aspect: 0.5)
        #expect(abs(screen.x - 0.5) < 1e-4 && abs(screen.y - 0.5) < 1e-4)
        // 寄るほど画角が狭くなる。
        let half = JM.camera(base: base, contact: point, zoom: 0.5)
        #expect(half.verticalFieldOfView < base.verticalFieldOfView && half.verticalFieldOfView > full.verticalFieldOfView)
    }

    @Test("ジャストミートの球は表示の時刻が当たった後だけ遅れ、結果のカードと次の球が増えたぶん遅れる。判定は変わらない")
    @MainActor
    func planTimeline() throws {
        let ball = HomerunJudge.judge(swing())
        #expect(ball.isJustMeet)
        let p = plan(ball: ball)
        let contact = try #require(p.contactAt)
        #expect(p.justMeetContactAt == contact)
        // 当たる前は実時刻のまま。
        let before = contact.addingTimeInterval(-0.1)
        #expect(p.displayTime(at: before) == before)
        #expect(p.justMeetElapsed(at: before) == nil)
        // ヒットストップの間は時間がほぼ止まる。
        let during = contact.addingTimeInterval(JM.hitStop / 2)
        #expect(p.displayTime(at: during).timeIntervalSince(contact) < 0.02)
        #expect(p.justMeetElapsed(at: during) != nil && p.holdsBatterClock(at: during))
        #expect(p.justMeetCamera(at: during) != nil)
        // 打球を追うカメラは、表示の時間が cutDelay に届いたときに切り替わる。
        let cut = contact.addingTimeInterval(JM.effectDuration)
        #expect(p.chaseFrame(at: p.displayTime(at: cut)) != nil)
        #expect(p.chaseFrame(at: p.displayTime(at: cut.addingTimeInterval(-0.01))) == nil)
        let after = cut.addingTimeInterval(0.001)
        #expect(p.justMeetElapsed(at: after) == nil && p.justMeetCamera(at: after) == nil)
        // カードは増えたぶんだけ遅れ、次の球までに cardHold 以上見せる。
        let track = try #require(p.chaseTrack)
        let card = try #require(p.chaseCardAt)
        #expect(abs(card.timeIntervalSince(contact) - (track.duration + HomerunBallChase.restHold + JM.extraDuration)) < 1e-6)
        let release = try #require(p.clock?.releasedAt)
        let end = release.addingTimeInterval(HomerunModel.resultDuration(for: ball))
        #expect(end.timeIntervalSince(card) >= HomerunBallChase.cardHold - 1e-6)
        // 演出の無い当たり（ナイス）は今までどおり。
        let nice = HomerunJudge.judge(swing(t: 40))
        #expect(!nice.isJustMeet)
        let np = plan(ball: nice, offset: 40)
        let nContact = try #require(np.contactAt)
        #expect(np.displayTime(at: nContact.addingTimeInterval(1)) == nContact.addingTimeInterval(1))
        #expect(np.justMeetCamera(at: nContact.addingTimeInterval(0.1)) == nil && !np.holdsBatterClock(at: nContact.addingTimeInterval(0.1)))
        #expect(HomerunModel.resultDuration(for: nice) == HomerunModel.resultDuration(for: nice.kind))
        #expect(abs(HomerunModel.resultDuration(for: ball) - HomerunModel.resultDuration(for: ball.kind) - JM.extraDuration) < 1e-9)
    }

    @Test("空振りには演出が無い")
    func missHasNoEffect() {
        let miss = HomerunJudge.judge(swing(dx: 100))
        let p = plan(ball: miss)
        #expect(p.justMeetContactAt == nil && p.justMeetPoint == nil && p.justMeetElapsed(at: arrival.addingTimeInterval(0.1)) == nil)
    }

    @Test("月まで飛んだ打球はジャストミートでも月の演出を優先する")
    @MainActor
    func moonWins() throws {
        var moon = HomerunJudge.judge(swing())
        moon.moon = .hit
        let p = plan(ball: moon)
        #expect(p.justMeetContactAt == nil)
        let contact = try #require(p.contactAt)
        #expect(p.displayTime(at: contact.addingTimeInterval(0.1)) == contact.addingTimeInterval(0.1))
        #expect(HomerunModel.resultDuration(for: moon) == HomerunMoonShot.resultDuration(.hit))
    }
}
