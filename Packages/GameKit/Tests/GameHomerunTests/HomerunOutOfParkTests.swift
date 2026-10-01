import Testing
import Foundation
import simd
@testable import HomerunCore
@testable import GameHomerun

@Suite("柵越えおじさんの場外（#1654・会長決裁 2026-10-01）")
struct HomerunOutOfParkTests {
    typealias Chase = HomerunBallChase
    typealias Stand = HomerunToonModel.Stand
    typealias Shadow = HomerunBallShadow

    private func homer(direction: Double, distance: Double) -> HomerunBattedBall {
        HomerunBattedBall(direction: direction, distance: distance, kind: .homer, timing: .just, launch: .fly,
                          fence: HomerunJudge.fence(atDirection: direction))
    }

    /// 柵越えになる打球の総当たり（ジャスト〜当たりの窓・照準の横・フライ / ライナー）。
    private var allHomers: [HomerunBattedBall] {
        var balls: [HomerunBattedBall] = []
        for t in stride(from: -100.0, through: 100, by: 5) {
            for dx in stride(from: -11.0, through: 11, by: 1) {
                for band in [HomerunLaunch.liner, .fly] {
                    for dy in [-4.0, -2, 0, 2, 4] {
                        let ball = HomerunJudge.judge(HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: band.centerDY + dy))
                        if ball.kind == .homer { balls.append(ball) }
                    }
                }
            }
        }
        return balls
    }

    @Test("場外の距離はスタンドの最後列の後端（球場の見た目と同じ式）: 両翼 ≈ 126.5m・中堅 ≈ 148.5m")
    func distanceByDirection() {
        let back = Double(Stand.treadBack(row: Stand.rows - 1))
        #expect(abs(back - 24.45) < 1e-4)
        #expect(abs(Chase.outOfParkDistance(atDirection: 0) - (122 + 2 + back)) < 1e-3)
        #expect(abs(Chase.outOfParkDistance(atDirection: 45) - (100 + 2 + back)) < 1e-3)
        #expect(abs(Chase.outOfParkDistance(atDirection: -45) - (100 + 2 + back)) < 1e-3)
        for deg in stride(from: -45.0, through: 45, by: 0.5) {
            // 見た目のスタンドの後端（`standFront` の最後列の段の奥）と同じ。柵 + 2m + 後端の奥行き。
            let visual = Double(HomerunToonModel.standFront(deg, depth: Stand.treadBack(row: Stand.rows - 1)))
            #expect(abs(Chase.outOfParkDistance(atDirection: deg) - visual) < 1e-9)
            #expect(abs(Chase.outOfParkDistance(atDirection: deg) - (HomerunJudge.fence(atDirection: deg) + 2 + back)) < 1e-3)
        }
        // 中堅ほど遠い（左右対称）。
        #expect(Chase.outOfParkDistance(atDirection: 20) < Chase.outOfParkDistance(atDirection: 10))
        #expect(Chase.outOfParkDistance(atDirection: 20) == Chase.outOfParkDistance(atDirection: -20))
    }

    @Test("境界: 後端ちょうどから場外・手前は柵越えのまま。柵越え以外は距離があっても場外にしない")
    func boundary() {
        // ±45° ちょうどの柵越えはファウルポール直撃（#1686・場外より優先）なので、両翼は 44.5° で見る。
        for deg in [-44.5, -30, -6, 0, 3, 15, 44] {
            let edge = Chase.outOfParkDistance(atDirection: deg)
            #expect(homer(direction: deg, distance: edge).isOutOfPark)
            #expect(homer(direction: deg, distance: edge + 20).isOutOfPark)
            #expect(!homer(direction: deg, distance: edge - 0.01).isOutOfPark)
        }
        var notHomer = homer(direction: 0, distance: 170)
        for kind in [HomerunKind.inPlay, .fenceHit, .foul, .miss] {
            notHomer.kind = kind
            #expect(!notHomer.isOutOfPark)
        }
        // 最高の当たり（ジャスト 0ms・フライの芯・中堅 180m）は場外。得点（飛距離）はそのまま。
        let best = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY))
        #expect(best.isOutOfPark && abs(best.distance - HomerunJudge.bestDistance) < 1e-9)
    }

    @Test("保存した 1 球（方向・距離・種別）から戻しても場外は同じ（保存の形は変えない）")
    func survivesRecords() throws {
        for ball in allHomers {
            let data = try JSONEncoder().encode(HomerunShot(ball))
            let back = try JSONDecoder().decode(HomerunShot.self, from: data)
            let restored = homer(direction: back.direction, distance: back.distance)
            let edge = Chase.outOfParkDistance(atDirection: ball.direction)
            guard abs(ball.distance - edge) > 0.2 else { continue }   // 0.1 単位の丸めの境目は除く
            #expect(restored.isOutOfPark == ball.isOutOfPark)
        }
    }

    @Test("表示: 結果の見出し・1 球ずつの内訳・読み上げは「場外」。種別は柵越えのまま（本数に数える）")
    func text() {
        let out = homer(direction: -20, distance: 160)
        let inStands = homer(direction: -20, distance: 120)
        #expect(out.isOutOfPark && !inStands.isOutOfPark)
        #expect(HomerunText.kind(of: out) == "場外！")
        #expect(HomerunText.kind(of: inStands) == "柵越え！")
        #expect(HomerunBallResultCard.headline(out, tookPitch: false) == "場外！")
        #expect(HomerunBallResultCard.headline(inStands, tookPitch: false) == "柵越え！")
        #expect(HomerunText.place(out) == "場外")
        #expect(HomerunText.place(inStands) == "左中間")
        #expect(HomerunText.headline(out) == "場外！ 160 m 左中間")
        #expect(HomerunText.spoken(out, number: 2) == "2球目、場外、160メートル、左中間、ジャスト")
        #expect(out.kind == .homer)
    }

    @Test("総当たりの柵越えに場外とスタンドに落ちる柵越えの両方が含まれる（テストの前提）")
    func bothKindsExist() {
        let homers = allHomers
        #expect(homers.contains { $0.isOutOfPark })
        #expect(homers.contains { !$0.isOutOfPark })
    }

    @Test("場外の打球: 柵・スタンドの上を越え、最後列の後端の上を抜けて、その先 3m で道が終わる（スタンドに落ちない）")
    func trackPassesOverTheStands() throws {
        for ball in allHomers where ball.isOutOfPark {
            let tr = try #require(Chase.track(for: ball))
            #expect(tr.vanishesAtEnd)
            let edge = Chase.outOfParkDistance(atDirection: ball.direction)
            #expect(abs(tr.rest.s - (edge + Chase.vanishBeyond)) < 1e-6, "消える点 \(tr.rest.s)")
            #expect(tr.rest.y > Chase.standBackTop, "後端の先で座席の高さより下にいる: \(tr.rest.y)")
            let front = ball.fence + 2
            let radians = ball.direction * .pi / 180
            let inScreen = abs(Chase.battersEyeZ * tan(radians)) < Chase.battersEyeHalfWidth
            let inBoard = abs(Chase.scoreboardZ * tan(radians)) < Chase.scoreboardHalfWidth
            var t = 0.0
            while t <= tr.duration {
                let p = tr.point(at: t)
                if abs(p.s - ball.fence) < 0.5 {
                    #expect(p.y >= Chase.fenceClearance - 0.3, "柵の上 \(p.y)m")
                }
                // スタンドの段・座席（背もたれの上端）より上を通る。
                if p.s > front, p.s <= edge {
                    let seatTop = Chase.standSurface(depth: p.s - front) + Double(Stand.seatBackHeight)
                    #expect(p.y - Chase.ballRadius > seatTop, "\(ball.direction)° \(p.s)m で座席 \(seatTop) に当たる: \(p.y)")
                }
                let z = p.s * cos(radians)
                if inScreen, abs(z - Chase.battersEyeZ) < 0.5 { #expect(p.y > Chase.battersEyeHeight + Chase.ballRadius) }
                if inBoard, abs(z - Chase.scoreboardZ) < 0.5 { #expect(p.y > Chase.scoreboardTop + Chase.ballRadius) }
                t += 1.0 / 120
            }
            // 後端の真上の高さ。
            let atEdge = tr.segments[0].to
            #expect(abs(atEdge.s - edge) < 1e-9 && atEdge.y >= Chase.standBackTop + Chase.outOfParkClearance - 1e-9)
            #expect(tr.duration + Chase.restHold <= Chase.limit(for: .homer) + 1e-9)
        }
    }

    @Test("場外の打球の道は 1 本の放物線（後端でつないだ所で向き・水平の速さが変わらない）")
    func trackIsSmooth() throws {
        for ball in allHomers where ball.isOutOfPark {
            let tr = try #require(Chase.track(for: ball))
            #expect(tr.segments.count == 2)
            let a = tr.segments[0], b = tr.segments[1]
            func slope(_ s: HomerunBallChase.Segment, at u: Double) -> Double {
                let e = 1e-4
                let p0 = s.point(at: u - e), p1 = s.point(at: u + e)
                return (p1.y - p0.y) / (p1.s - p0.s)
            }
            #expect(abs(slope(a, at: 1 - 1e-3) - slope(b, at: 1e-3)) < 0.01, "\(ball.direction)°")
            let va = (a.to.s - a.from.s) / a.duration, vb = (b.to.s - b.from.s) / b.duration
            #expect(abs(va - vb) / va < 1e-6)
        }
    }

    @Test("球が消えるのは道の終わり（後端の 3m 先）から。それまでは見え、消えた後は球も影も描かない。スタンドに落ちる柵越えは消えない")
    func vanishTiming() throws {
        for ball in allHomers {
            let tr = try #require(Chase.track(for: ball))
            let before = Chase.frame(tr, at: tr.duration - 0.01)
            let after = Chase.frame(tr, at: tr.duration)
            let later = Chase.frame(tr, at: tr.duration + Chase.restHold)
            #expect(before.visibleBall != nil)
            if ball.isOutOfPark {
                #expect(after.visibleBall == nil && later.visibleBall == nil)
                #expect(after.ballHidden)
                // 後端を越えるまでは必ず見えている。
                let edge = Chase.outOfParkDistance(atDirection: ball.direction)
                var t = Chase.cutDelay
                while t < tr.duration {
                    if tr.point(at: t).s <= edge { #expect(Chase.frame(tr, at: t).visibleBall != nil) }
                    t += 0.02
                }
                // 消えた後もカメラは止まったまま。
                #expect(after.camera == later.camera)
            } else {
                #expect(after.visibleBall != nil && later.visibleBall != nil)
            }
        }
    }

    @Test("影は後端より先では地面（0）へ落ちる（スタンドの後ろの宙に浮かない）")
    func shadowBeyondTheBackEdge() {
        for deg in [-40.0, -20, 10, 30] {
            let edge = Chase.outOfParkDistance(atDirection: deg)
            let inside = Shadow.groundHeight(below: Chase.world(.init(s: edge - 0.3, y: 30), direction: deg))
            let beyond = Shadow.groundHeight(below: Chase.world(.init(s: edge + 0.5, y: 30), direction: deg))
            #expect(inside > 10, "\(deg)° の最後列の座面 \(inside)")
            #expect(beyond == 0, "\(deg)° の後端の先 \(beyond)")
        }
    }
}
