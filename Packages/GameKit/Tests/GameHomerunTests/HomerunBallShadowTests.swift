import Testing
import Foundation
import simd
@testable import HomerunCore
@testable import GameHomerun

@Suite("柵越えおじさんの球の影（#1648）")
struct HomerunBallShadowTests {
    typealias Shadow = HomerunBallShadow
    typealias Chase = HomerunBallChase
    typealias Stand = HomerunToonModel.Stand

    private let r = HomerunSwingContact.ballRadius

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

    @Test("地面に着いた球の影は真下・浮かせた高さに、球の 1.4 倍の半径で濃く（0.55）")
    func onGround() {
        let s = Shadow.shape(ball: [3, r, 40], ballRadius: r)
        #expect(s.center == [3, Shadow.lift, 40])
        #expect(abs(s.radius - r * Shadow.groundRadiusFactor) < 1e-6)
        #expect(abs(s.opacity - Shadow.groundOpacity) < 1e-6)
    }

    @Test("高いほど薄く大きく、8m 以上は 2.6 倍・0.25 で止まる")
    func fadesWithHeight() {
        var last = Shadow.shape(ball: [0, r, 40], ballRadius: r)
        for h in stride(from: 0.5, through: 7.5, by: 0.5) {
            let s = Shadow.shape(ball: [0, r + Float(h), 40], ballRadius: r)
            #expect(s.radius > last.radius, "高さ \(h)m で大きくならない")
            #expect(s.opacity < last.opacity, "高さ \(h)m で薄くならない")
            #expect(s.center.y == Shadow.lift)
            last = s
        }
        for h: Float in [8, 12, 30] {
            let s = Shadow.shape(ball: [0, r + h, 40], ballRadius: r)
            #expect(abs(s.radius - r * Shadow.highRadiusFactor) < 1e-6)
            #expect(abs(s.opacity - Shadow.highOpacity) < 1e-6)
        }
    }

    @Test("影の半径は球の見かけの半径に比例する（追う球を大きく見せても見えすぎ・消えすぎない）")
    func scalesWithBallRadius() {
        let small = Shadow.shape(ball: [0, 2, 40], ballRadius: r)
        let big = Shadow.shape(ball: [0, 2, 40], ballRadius: r * 4)
        #expect(abs(big.radius / small.radius - 4) < 0.05)
    }

    @Test("濃さの段: 0〜12 の整数に丸め、段から戻した濃さは半段以内")
    func opacitySteps() {
        for o in stride(from: 0.0, through: 1.0, by: 0.01) {
            let step = Shadow.opacityStep(Float(o))
            #expect((0...Shadow.opacitySteps).contains(step))
            #expect(abs(Shadow.opacity(step: step) - Float(o)) <= 0.5 / Float(Shadow.opacitySteps) + 1e-6)
        }
        #expect(Shadow.opacityStep(Shadow.groundOpacity) != Shadow.opacityStep(Shadow.highOpacity))
    }

    @Test("地面の高さ: グラウンドは 0、マウンド（マシンの放つ所の真下）は 0.3、スタンドの列はその座面、バックスクリーンの裏は 0")
    func groundHeight() {
        #expect(Shadow.groundHeight(below: [0, 1, 0]) == 0)
        #expect(Shadow.groundHeight(below: [0, 1, 60]) == 0)
        #expect(Shadow.groundHeight(below: HomerunBallFlight.releasePoint) == Shadow.moundHeight)
        #expect(Shadow.groundHeight(below: [0, 1, Shadow.moundCenterZ + Shadow.moundRadius + 0.1]) == 0)
        let degrees = 20.0
        let fence = HomerunJudge.fence(atDirection: degrees)
        // 柵の手前・柵とスタンドの間は地面。
        #expect(Shadow.groundHeight(below: Chase.world(.init(s: fence - 1, y: 5), direction: degrees)) == 0)
        #expect(Shadow.groundHeight(below: Chase.world(.init(s: fence + 2.5, y: 5), direction: degrees)) == 0)
        for row in 0..<Stand.rows {
            let s = fence + 2 + Double(Stand.depth(row: row))
            let expected = Stand.height(row: row) + Stand.seatHeight / 2
            #expect(abs(Shadow.groundHeight(below: Chase.world(.init(s: s, y: 20), direction: degrees)) - expected) < 1e-4, "列 \(row)")
            #expect(abs(Shadow.groundHeight(below: Chase.world(.init(s: s, y: 20), direction: -degrees)) - expected) < 1e-4, "列 \(row)・左")
        }
        // 中堅（|方向| < 6°）は座席が無い。
        let center = HomerunJudge.fence(atDirection: 0) + 2 + Double(Stand.depth(row: 3))
        #expect(Shadow.groundHeight(below: Chase.world(.init(s: center, y: 20), direction: 0)) == 0)
        #expect(Shadow.groundHeight(below: Chase.world(.init(s: center, y: 20), direction: 5)) == 0)
        #expect(Shadow.groundHeight(below: Chase.world(.init(s: center, y: 20), direction: 7)) > 0)
    }

    /// マウンドの上か（打球の道はマウンドの高さを持たず、転がる球はマウンドを突き抜ける = 既存の見た目。影はマウンドの上に乗せる）。
    private func onMound(_ p: SIMD3<Float>) -> Bool { hypot(p.x, p.z - Shadow.moundCenterZ) <= Shadow.moundRadius }

    @Test("追う球の道: 飛んでいる間は影の地面より下へ行かず、着いた点・止まった点では影の地面に接する（スタンドの段に埋まらない・浮かない）")
    func chaseTrackSitsOnShadowGround() {
        let hits = allHits
        #expect(hits.contains { $0.kind == .homer })
        for ball in hits {
            guard let track = Chase.track(for: ball) else { continue }
            // 止まった点（スタンドの座面・芝）。
            let rest = track.rest
            let restWorld = Chase.world(rest, direction: track.direction)
            if !onMound(restWorld) {
                let ground = Shadow.groundHeight(below: restWorld)
                #expect(abs(Double(ground) - (rest.y - Chase.ballRadius)) < 1e-3, "\(ball.kind) 方向 \(ball.direction) 距離 \(ball.distance): 止まった高さ \(rest.y) 地面 \(ground)")
            }
            // 最初に着いた点（フェンス直撃は柵の面・中堅（|方向| < 6°）の柵越えはバックスクリーンの面に当たることがあるので除く）。
            let landing = Chase.world(track.landing, direction: track.direction)
            if ball.kind != .fenceHit, !(ball.kind == .homer && abs(ball.direction) < 6), !onMound(landing) {
                let ground = Shadow.groundHeight(below: landing)
                #expect(abs(Double(ground) - (track.landing.y - Chase.ballRadius)) < 1e-3, "\(ball.kind) 方向 \(ball.direction): 着いた高さ \(track.landing.y) 地面 \(ground)")
            }
            // 飛んでいる間（弾みは除く: 列の縁に着いた球の小さな弾みは次の列の座席をかすめる = 打球の道の既存の見た目）。
            var t = 0.0
            while t <= track.flightDuration {
                let p = track.position(at: t)
                if !onMound(p) {
                    let g = Shadow.groundHeight(below: p)
                    #expect(p.y - Float(Chase.ballRadius) >= g - 0.02, "\(ball.kind) 方向 \(ball.direction) t=\(t) 球 \(p.y) 地面 \(g)")
                }
                t += 1.0 / 30
            }
        }
    }

    @Test("追う球が止まったコマ: 大きく見せた球の下端が影の面に乗り、影は濃い（地面の濃さ）")
    func restingChaseFrame() {
        for ball in allHits {
            guard let track = Chase.track(for: ball) else { continue }
            let frame = Chase.frame(track, at: track.duration + 0.1)
            let shape = Shadow.shape(ball: frame.ball, ballRadius: frame.ballScale * r)
            #expect(abs(shape.opacity - Shadow.groundOpacity) < 1e-3, "\(ball.kind) 方向 \(ball.direction)")
            #expect(abs(shape.radius - frame.ballScale * r * Shadow.groundRadiusFactor) < 1e-4)
            #expect(shape.center.x == frame.ball.x && shape.center.z == frame.ball.z)
        }
    }
}
