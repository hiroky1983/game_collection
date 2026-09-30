import Testing
import Foundation
import simd
@testable import HomerunCore
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
        let fenceHit = HomerunJudge.judge(fenceHitSwing)
        #expect(fenceHit.kind == .fenceHit)
        let inPlay = HomerunJudge.judge(inPlaySwing)
        #expect(inPlay.kind == .inPlay)
    }

    /// フェンス直撃: ナイス（40ms）× ライナーを方向 0°（柵 122m）に戻し、縦に 5pt ずらして芯を落とす（≈ 119m）。
    private var fenceHitSwing: HomerunSwing { swing(t: 40, dx: -(40.0 / 110 * 15) / 35 * 11, band: .liner, dy: 5) }
    /// 当たり: 当たり（90ms）× ライナー（110m・柵 120m）。
    private var inPlaySwing: HomerunSwing { swing(t: 90, band: .liner) }

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

    @Test("カメラは柵の 50m 手前・注視点は柵そのもの（打球が柵の近くまで飛ぶ柵越え・フェンス直撃のケース）")
    func cameraFramesTheFence() {
        for t in [0.0, 40] {
            let ball = HomerunJudge.judge(swing(t: t))
            #expect(ball.kind != .inPlay, "テストの前提（柵の近くまで飛んでいるか）")
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
        let fenceHit = HomerunOutfieldLayout.shot(for: HomerunJudge.judge(fenceHitSwing)).ballPosition.y
        let inPlay = HomerunOutfieldLayout.shot(for: HomerunJudge.judge(inPlaySwing)).ballPosition.y
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

    /// 世界の点が、ショットのカメラ（`look(at:)` と同じ向き）の縦の画角に入るか。実装とは別に、3 次元のベクトルで求める。
    private func verticalAngleFromViewAxis(of point: SIMD3<Float>, in shot: HomerunOutfieldLayout.Shot) -> (depth: Float, degrees: Double) {
        let forward = simd_normalize(shot.cameraTarget - shot.cameraPosition)
        let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
        let up = simd_cross(right, forward)
        let v = point - shot.cameraPosition
        let depth = simd_dot(v, forward)
        return (depth, atan2(Double(simd_dot(v, up)), Double(depth)) * 180 / .pi)
    }

    /// 打球（球本体・外野手の足元と頭）が画角に収まっているか。収まっていなければ理由を返す。
    private func framingFailure(_ ball: HomerunBattedBall) -> String? {
        let shot = HomerunOutfieldLayout.shot(for: ball)
        let halfFOV = Double(HomerunOutfieldLayout.verticalFieldOfView) / 2
        let subjects: [(String, SIMD3<Float>)] = [
            ("打球", shot.ballPosition),
            ("外野手の足元", shot.fielderPosition),
            ("外野手の頭", shot.fielderPosition + [0, 2.0, 0]),
        ]
        for (name, p) in subjects {
            let (depth, degrees) = verticalAngleFromViewAxis(of: p, in: shot)
            if depth <= 0 { return "\(name)がカメラの後方にある（\(ball.kind) \(ball.distance)m 方向 \(ball.direction)°）" }
            if abs(degrees) > halfFOV { return "\(name)が画角の外（視線から \(degrees)°・半角 \(halfFOV)°）（\(ball.kind) \(ball.distance)m 方向 \(ball.direction)°）" }
        }
        return nil
    }

    private func ball(kind: HomerunKind, direction: Double, distance: Double) -> HomerunBattedBall {
        HomerunBattedBall(direction: direction, distance: distance, kind: kind, timing: .just, launch: .fly,
                          fence: HomerunJudge.fence(atDirection: direction))
    }

    @Test("あらゆる飛距離・方向の当たりで、打球と外野手が画角に収まる（近距離のゴロ・ポップを含む）")
    func ballAndFielderAreInsideTheFieldOfViewAtEveryDistance() {
        var checked = 0
        for direction in stride(from: -45.0, through: 45.0, by: 7.5) {
            let fence = HomerunJudge.fence(atDirection: direction)
            for distance in stride(from: 20.0, through: fence + 60, by: 1.0) {
                let kind: HomerunKind = distance >= fence ? .homer : (distance >= fence - HomerunJudge.fenceHitMargin ? .fenceHit : .inPlay)
                let failure = framingFailure(ball(kind: kind, direction: direction, distance: distance))
                #expect(failure == nil, Comment(rawValue: failure ?? ""))
                checked += 1
            }
        }
        #expect(checked > 1000, "走査が空振りしていないか")
    }

    @Test("実際の判定が作る近距離の当たり（ゴロ・ポップ・ライナー）も画角に収まる")
    func realJudgedWeakHitsAreInsideTheFieldOfView() {
        var inPlayDistances: [Double] = []
        for band in [HomerunLaunch.grounder, .liner, .fly, .pop] {
            for t in stride(from: -90.0, through: 90.0, by: 15) {
                let judged = HomerunJudge.judge(swing(t: t, band: band))
                guard judged.kind == .inPlay else { continue }
                inPlayDistances.append(judged.distance)
                let failure = framingFailure(judged)
                #expect(failure == nil, Comment(rawValue: failure ?? ""))
            }
        }
        #expect(inPlayDistances.contains { $0 < 50 }, "テストの前提（近距離の当たりを作れているか）")
        #expect(inPlayDistances.contains { $0 > 85 && $0 < 115 }, "テストの前提（中距離 90〜110m 前後の当たりを作れているか）")
    }

    @Test("画角の確認そのものが効いている: 従来の固定カメラ（柵の 50m 手前・柵を注視）だと近距離の打球は画角の外になる")
    func legacyFixedCameraMissesNearBalls() {
        let near = ball(kind: .inPlay, direction: 0, distance: 40)
        var shot = HomerunOutfieldLayout.shot(for: near)
        shot.cameraPosition = HomerunOutfieldLayout.point(direction: 0, distance: near.fence - 50, height: 9)
        shot.cameraTarget = HomerunOutfieldLayout.point(direction: 0, distance: near.fence, height: 5.5)
        let (depth, degrees) = verticalAngleFromViewAxis(of: shot.ballPosition, in: shot)
        #expect(depth <= 0 || abs(degrees) > Double(HomerunOutfieldLayout.verticalFieldOfView) / 2)
    }

    @Test("同じ打球からは常に同じショットになる（乱数を使わない）")
    func shotIsDeterministic() {
        let ball = HomerunJudge.judge(swing(t: 40))
        #expect(HomerunOutfieldLayout.shot(for: ball) == HomerunOutfieldLayout.shot(for: ball))
    }
}
