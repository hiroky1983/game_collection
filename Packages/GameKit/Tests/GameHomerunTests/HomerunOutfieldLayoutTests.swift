import Testing
import Foundation
import simd
import HomerunCore
@testable import GameHomerun

@Suite("柵越えおじさんの外野カメラの静止ショット")
struct HomerunOutfieldLayoutTests {
    private func swing(t: Double = 0, dx: Double = 0, band: HomerunLaunch = .fly, dy: Double = 0) -> HomerunSwing {
        HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: band.centerDY + dy)
    }

    @Test("柵越え・フェンス直撃・当たりのそれぞれで正しい種別の打球が作れる（判定ロジックの前提の確認）")
    func fixturesHaveExpectedKinds() {
        let homer = HomerunJudge.judge(swing())
        #expect(homer.kind == .homer)
        let fenceHit = HomerunJudge.judge(swing(t: 40))
        #expect(fenceHit.kind == .fenceHit)
        let inPlay = HomerunJudge.judge(swing(t: 90))
        #expect(inPlay.kind == .inPlay)
    }

    @Test("カメラ・注視点・外野手・打球は、すべて打球方向と同じ向きの線の上に乗る")
    func everythingIsOnTheDirectionLine() {
        for t in [-90.0, 0, 40] {
            let ball = HomerunJudge.judge(swing(t: t))
            let shot = HomerunOutfieldLayout.shot(for: ball)
            let radians = ball.direction * .pi / 180
            for p in [shot.cameraPosition, shot.cameraTarget, shot.fielderPosition, shot.ballPosition] {
                let r = Double(hypot(p.x, p.z))
                guard r > 0.5 else { continue }
                let expectedX = r * sin(radians), expectedZ = r * cos(radians)
                #expect(abs(Double(p.x) - expectedX) < 0.05, "\(p) が方向 \(ball.direction)° の線から外れている")
                #expect(abs(Double(p.z) - expectedZ) < 0.05, "\(p) が方向 \(ball.direction)° の線から外れている")
            }
        }
    }

    @Test("カメラは柵の 50m 手前・注視点は柵そのもの（打球の実際の距離によらない）")
    func cameraFramesTheFence() {
        for t in [-90.0, 0, 40] {
            let ball = HomerunJudge.judge(swing(t: t))
            let shot = HomerunOutfieldLayout.shot(for: ball)
            let camDistance = Double(hypot(shot.cameraPosition.x, shot.cameraPosition.z))
            let targetDistance = Double(hypot(shot.cameraTarget.x, shot.cameraTarget.z))
            #expect(abs(camDistance - (ball.fence - 50)) < 0.05)
            #expect(abs(targetDistance - ball.fence) < 0.05)
            #expect(shot.cameraPosition.y > 0 && shot.cameraTarget.y > 0)
        }
    }

    @Test("打球の高さは柵越え > フェンス直撃 > 当たり（地面）の順")
    func ballHeightByKind() {
        let homer = HomerunOutfieldLayout.shot(for: HomerunJudge.judge(swing())).ballPosition.y
        let fenceHit = HomerunOutfieldLayout.shot(for: HomerunJudge.judge(swing(t: 40))).ballPosition.y
        let inPlay = HomerunOutfieldLayout.shot(for: HomerunJudge.judge(swing(t: 90))).ballPosition.y
        #expect(homer > fenceHit && fenceHit > inPlay)
        #expect(inPlay < 1, "当たりの打球は地面近くに無いといけない")
    }

    @Test("深い柵越え（能力値で飛距離を伸ばす）でも打球の描画位置は柵の少し奥までに収まる")
    func deepHomerIsClamped() {
        let deep = HomerunJudge.judge(swing(), abilities: HomerunAbilities(power: 200))
        #expect(deep.distance > deep.fence + 50, "テストの前提（能力値が効いていない）")
        let shot = HomerunOutfieldLayout.shot(for: deep)
        let renderDistance = Double(hypot(shot.ballPosition.x, shot.ballPosition.z))
        #expect(renderDistance <= deep.fence + 10 + 0.05)
    }

    @Test("外野手はカメラより本塁側・柵の手前に立ち、打球が来た本塁側を向く")
    func fielderStandsInFrontOfTheFenceFacingHome() {
        let ball = HomerunJudge.judge(swing(t: 40))
        let shot = HomerunOutfieldLayout.shot(for: ball)
        let fielderDistance = Double(hypot(shot.fielderPosition.x, shot.fielderPosition.z))
        #expect(fielderDistance < ball.fence, "外野手が柵の外に立っている")
        #expect(fielderDistance >= 20, "外野手が本塁に寄り過ぎている")
        let expectedYaw = Float(ball.direction * .pi / 180) + .pi
        #expect(abs(shot.fielderYaw - expectedYaw) < 1e-5)
    }

    @Test("同じ打球からは常に同じショットになる（乱数を使わない）")
    func shotIsDeterministic() {
        let ball = HomerunJudge.judge(swing(t: 40))
        #expect(HomerunOutfieldLayout.shot(for: ball) == HomerunOutfieldLayout.shot(for: ball))
    }
}
