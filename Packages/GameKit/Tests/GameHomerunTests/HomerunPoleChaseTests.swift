import Testing
import Foundation
import simd
@testable import HomerunCore
@testable import GameHomerun

/// ファウルポール直撃（#1686・会長決裁 2026-10-02）の打球の道・影・表示・球場のポール。
@Suite("柵越えおじさんのファウルポール直撃（見せ方）")
struct HomerunPoleChaseTests {
    typealias Chase = HomerunBallChase
    typealias Shadow = HomerunBallShadow

    private func pole(_ side: Double, distance: Double, launch: HomerunLaunch = .fly) -> HomerunBattedBall {
        HomerunBattedBall(direction: side * 45, distance: distance, kind: .homer, timing: .hit, launch: launch,
                          fence: HomerunJudge.fence(atDirection: 45))
    }

    /// ポール直撃になる打球の例（両翼・ライナー / フライ・柵のすぐ上〜最長まで）。
    private var balls: [HomerunBattedBall] {
        [-1.0, 1.0].flatMap { side in
            [HomerunLaunch.liner, .fly].flatMap { launch in
                [100.0, 105, 116, 140, 180].map { pole(side, distance: $0, launch: launch) }
            }
        }
    }

    @Test("打球の道: ポールの面まで飛んで当たり（柵より高く・ポールの先より低く）、本塁側へ跳ね返って柵の手前の地面に落ちて止まる")
    func track() throws {
        for ball in balls {
            #expect(ball.isPoleHit && !ball.isOutOfPark)
            let track = try #require(Chase.track(for: ball))
            #expect(track.direction == ball.direction)
            let hit = track.landing
            #expect(abs(hit.s - Chase.poleContactS) < 1e-9)
            #expect(hit.y >= Chase.fenceClearance - 0.2)
            #expect(hit.y <= Chase.poleContactMaxY + 1e-9)
            // 跳ね返り: 2 区間目は本塁側（s が減る）へ動き、地面に着く。
            let back = track.segments[1]
            #expect(back.from == hit)
            #expect(back.to.s < hit.s && abs(back.to.y - Chase.ballRadius) < 1e-9)
            // 当たった直後は少し上へ跳ねる（「カーン」）。
            #expect(back.point(at: 0.05).y > hit.y)
            // 止まる所はポールの手前（柵の内側のウォーニングトラック）の地面。
            #expect(abs(track.rest.s - (Chase.poleS - Chase.poleRestBack)) < 1e-9)
            #expect(abs(track.rest.y - Chase.ballRadius) < 1e-9)
            #expect(!track.vanishesAtEnd)
            // どの時刻もポールを越えない（すり抜けない）・地面に潜らない。
            for t in stride(from: 0.0, through: track.duration, by: 0.01) {
                let p = track.point(at: t)
                #expect(p.s <= Chase.poleContactS + 1e-9)
                #expect(p.y >= Chase.ballRadius - 1e-9)
            }
            // カードの上限（ポール直撃は長め）の内に止まる。
            #expect(track.duration <= Chase.poleLimit - Chase.restHold + 1e-9)
            #expect(Chase.poleLimit > Chase.limit(for: .homer))
        }
    }

    @Test("当たる所はポールの面: 球の中心からポールの軸まで、ポールの半径 + 球の半径。ポールは球場の 3D と同じ所（両翼の柵の上）")
    func touchesThePole() throws {
        for side in [-1.0, 1.0] {
            let track = try #require(Chase.track(for: pole(side, distance: 116)))
            let hitTime = track.flightDuration
            let ball = track.position(at: hitTime)
            // 球場の `fencePoint` の角度は +x（三塁側）が正 = 判定の方向の負（レフト）。
            let axis = HomerunToonModel.fencePoint(-side * HomerunJudge.foulLimit)
            let gap = hypot(Double(ball.x - axis.x), Double(ball.z - axis.y))
            #expect(abs(gap - (HomerunJudge.poleRadius + Chase.ballRadius)) < 1e-3)
            #expect(Double(ball.y) < HomerunJudge.poleHeight)
            // 判定の負（レフト）は +x（三塁側）。
            #expect((ball.x > 0) == (side < 0))
        }
    }

    @Test("影は球の真下の地面に追従する（柵の手前は地面 0・スタンドの座面に乗らない）")
    func shadowFollows() throws {
        let track = try #require(Chase.track(for: pole(1, distance: 130)))
        for t in stride(from: track.flightDuration, through: track.duration, by: 0.05) {
            let frame = Chase.frame(track, at: t)
            let shape = Shadow.shape(ball: frame.ball, ballRadius: 0.1, camera: frame.camera.position)
            #expect(abs(shape.center.x - frame.ball.x) < 1e-4 && abs(shape.center.z - frame.ball.z) < 1e-4)
            #expect(Shadow.groundHeight(below: frame.ball) == 0)
        }
    }

    @Test("カメラは柵越しに持ち上げない（球は柵の手前で止まる）・球はいつも見える")
    func camera() throws {
        let track = try #require(Chase.track(for: pole(-1, distance: 150)))
        #expect(Chase.overFenceHeight(track) == 0)
        let last = Chase.frame(track, at: track.duration + 1)
        #expect(last.visibleBall != nil)
    }

    @Test("場外より優先: 場外の距離を越えてもポール直撃（球は消えずにポールで跳ね返る）")
    func beatsOutOfPark() throws {
        let far = pole(1, distance: Chase.outOfParkDistance(atDirection: 45) + 10)
        #expect(far.isPoleHit && !far.isOutOfPark)
        #expect(Chase.track(for: far)?.vanishesAtEnd == false)
    }

    @Test("表示: 結果カード・1 球ずつの記録・読み上げは「ポール直撃」。種別は柵越えのまま（本数に数える）")
    func labels() {
        let ball = pole(-1, distance: 116.4)
        #expect(HomerunText.kind(of: ball) == "ポール直撃！")
        #expect(HomerunBallResultCard.headline(ball, tookPitch: false) == "ポール直撃！")
        #expect(HomerunText.headline(ball) == "ポール直撃！ 116 m レフト")
        #expect(HomerunText.place(ball) == "ポール")
        #expect(HomerunText.spoken(ball, number: 3).hasPrefix("3球目、ポール直撃、116メートル、レフト"))
        #expect(HomerunText.kind(of: pole(1, distance: 116)) == "ポール直撃！")
        var c = HomerunChallenge(forcesPole: true)
        c.swing(HomerunSwing(timingOffset: 0, cursorDX: 3, cursorDY: 4))
        #expect(c.homerCount == 1)
    }

    @Test("1 球の結果の時間はポール直撃のぶん長い（カードは時間の内に出る）") @MainActor
    func resultDuration() throws {
        let ball = pole(1, distance: 116)
        #expect(HomerunModel.resultDuration(for: ball) == Chase.poleResultDuration)
        #expect(HomerunModel.resultDuration(for: ball) > HomerunModel.resultDuration(for: .homer))
        let track = try #require(Chase.track(for: ball))
        #expect(Chase.contactLeadMax + track.duration + Chase.restHold <= Chase.poleResultDuration - Chase.cardHold + 1e-9)
    }
}
