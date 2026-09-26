import Testing
import Foundation
@testable import HomerunCore

@Suite("柵越えおじさんの判定")
struct HomerunJudgeTests {

    /// 帯の中心・ジャストで振った基準の入力。`dx` と `dy`（帯の中心からのずれ）と `t` だけ変える。
    private func swing(t: Double = 0, dx: Double = 0, band: HomerunLaunch = .fly, dy: Double = 0) -> HomerunSwing {
        HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: band.centerDY + dy)
    }

    @Test("柵は両翼 100m・中堅 122m・±45° で 100m")
    func fenceShape() {
        #expect(abs(HomerunJudge.fence(atDirection: 0) - 122) < 1e-9)
        #expect(abs(HomerunJudge.fence(atDirection: 45) - 100) < 1e-9)
        #expect(abs(HomerunJudge.fence(atDirection: -45) - 100) < 1e-9)
        #expect(abs(HomerunJudge.fence(atDirection: 35) - (100 + 22 * cos(70 * .pi / 180))) < 1e-9)
    }

    @Test("タイミングの窓は ±25 / 60 / 110ms（端は内側に入る）")
    func timingWindows() {
        #expect(HomerunTiming(offsetMilliseconds: 25) == .just)
        #expect(HomerunTiming(offsetMilliseconds: -25) == .just)
        #expect(HomerunTiming(offsetMilliseconds: 25.1) == .nice)
        #expect(HomerunTiming(offsetMilliseconds: -60) == .nice)
        #expect(HomerunTiming(offsetMilliseconds: 60.1) == .hit)
        #expect(HomerunTiming(offsetMilliseconds: 110) == .hit)
        #expect(HomerunTiming(offsetMilliseconds: -110.1) == .miss)
    }

    @Test("角度の帯は連続で、境界は角度の大きい方の帯に入る")
    func launchBands() {
        #expect(HomerunLaunch(cursorDY: -100) == .grounder)
        #expect(HomerunLaunch(cursorDY: -11.01) == .grounder)
        #expect(HomerunLaunch(cursorDY: -11) == .liner)
        #expect(HomerunLaunch(cursorDY: 10.99) == .liner)
        #expect(HomerunLaunch(cursorDY: 11) == .fly)
        #expect(HomerunLaunch(cursorDY: 32.99) == .fly)
        #expect(HomerunLaunch(cursorDY: 33) == .pop)
        #expect(HomerunLaunch(cursorDY: 500) == .pop)
    }

    @Test("打ち出し角は帯の境目でつながる（0〜10 / 10〜25 / 25〜35 / 35〜）")
    func launchAngles() {
        #expect(abs(HomerunLaunch.angle(cursorDY: -33) - 0) < 1e-9)
        #expect(abs(HomerunLaunch.angle(cursorDY: -11) - 10) < 1e-9)
        #expect(abs(HomerunLaunch.angle(cursorDY: 11) - 25) < 1e-9)
        #expect(abs(HomerunLaunch.angle(cursorDY: 33) - 35) < 1e-9)
        #expect(HomerunLaunch.angle(cursorDY: 1000) <= 55)
    }

    @Test("飛距離の係数はゴロ 0.3・ライナー 0.85・フライ 1.0・ポップ 0.5")
    func launchFactors() {
        #expect(HomerunLaunch.grounder.distanceFactor == 0.3)
        #expect(HomerunLaunch.liner.distanceFactor == 0.85)
        #expect(HomerunLaunch.fly.distanceFactor == 1.0)
        #expect(HomerunLaunch.pop.distanceFactor == 0.5)
    }

    @Test("ジャスト × フライの帯の中心 = 135m・中堅の柵 122m を越えて柵越え")
    func justFlyCenterIsHomer() {
        let ball = HomerunJudge.judge(swing())
        #expect(ball.kind == .homer)
        #expect(abs(ball.distance - 135) < 1e-9)
        #expect(ball.direction == 0)
        #expect(ball.timing == .just)
        #expect(ball.launch == .fly)
    }

    @Test("ナイス（120m）× フライで方向 0° に戻すと、芯が落ちて 114m 未満・中堅の柵には届かない")
    func niceExampleFromSpec() {
        // 芯 0.95 になる帯の中心からのずれ = 0.25 × 11 = 2.75pt（縦にずらして方向は動かさない）。
        // タイミング 40ms は方向を +5.45° 動かす（流し方向）ので、方向は dx で打ち消す。
        let t = 40.0
        let timingDirection = t / 110 * 15
        let dx0 = -timingDirection / 35 * 11  // 方向 0°（センター）に戻すカーソルの左右
        let center = HomerunJudge.judge(swing(t: t, dx: dx0, dy: 2.75))
        #expect(center.timing == .nice)
        #expect(abs(center.direction) < 1e-9)
        // 芯は dx0 ぶんも下がるので、方向 0° では 114m より少し短い。柵は 122m なので届かない。
        #expect(center.kind != .homer)
        #expect(center.distance > 100 && center.distance < 114)
    }

    @Test("芯: 帯の中心で 1.0・半径 11pt で 0.8・外は 0")
    func coreFalloff() {
        #expect(HomerunJudge.core(distanceFromBandCenter: 0) == 1)
        #expect(abs(HomerunJudge.core(distanceFromBandCenter: 11) - 0.8) < 1e-9)
        #expect(HomerunJudge.core(distanceFromBandCenter: 11.01) == 0)
        // ミートが上がると半径が広がる
        #expect(HomerunJudge.core(distanceFromBandCenter: 11.01, abilities: HomerunAbilities(meet: 1.5)) > 0)
    }

    @Test("芯の外に置くと空振り（距離 0）")
    func outsideCoreIsMiss() {
        let ball = HomerunJudge.judge(swing(dx: 12))
        #expect(ball.kind == .miss)
        #expect(ball.distance == 0)
    }

    @Test("タイミングが窓の外なら空振り・押さずに見送っても空振り")
    func lateOrNoSwingIsMiss() {
        #expect(HomerunJudge.judge(swing(t: 111)).kind == .miss)
        #expect(HomerunJudge.judge(swing(t: -111)).kind == .miss)
        let skipped = HomerunJudge.judge(nil)
        #expect(skipped.kind == .miss)
        #expect(skipped.distance == 0)
    }

    @Test("方向: 内側（左）+ 早い = 引っ張り（負）・外側（右）+ 遅い = 流し（正）・最大は 35 + 15")
    func directionSigns() {
        #expect(HomerunJudge.direction(swing(dx: -5)) < 0)
        #expect(HomerunJudge.direction(swing(dx: 5)) > 0)
        #expect(HomerunJudge.direction(swing(t: -50)) < 0)
        #expect(HomerunJudge.direction(swing(t: 50)) > 0)
        #expect(abs(HomerunJudge.direction(swing(t: 110, dx: 999)) - 50) < 1e-9)
        #expect(abs(HomerunJudge.direction(swing(t: -110, dx: -999)) + 50) < 1e-9)
    }

    @Test("±45° を越えるとファウル（両側）・ちょうど 45° まではフェア")
    func foulBoundary() {
        // dx = -11（-35°）+ 早い -110ms（-15°）= -50° → ファウル。ただし芯は 0.8 で当たり判定の内側。
        let pullFoul = HomerunJudge.judge(swing(t: -110, dx: -11))
        #expect(pullFoul.kind == .foul)
        #expect(pullFoul.distance == 0)
        let pushFoul = HomerunJudge.judge(swing(t: 110, dx: 11))
        #expect(pushFoul.kind == .foul)
        // 45° の際（±1e-9 / ±1e-6）: 110ms（±15°）に、カーソルで残りの 30° を足す
        func dx(forCursorDegrees d: Double) -> Double { d / 35 * 11 }
        #expect(HomerunJudge.judge(swing(t: 110, dx: dx(forCursorDegrees: 30 - 1e-9))).kind != .foul)
        #expect(HomerunJudge.judge(swing(t: 110, dx: dx(forCursorDegrees: 30 + 1e-6))).kind == .foul)
        #expect(HomerunJudge.judge(swing(t: -110, dx: -dx(forCursorDegrees: 30 + 1e-6))).kind == .foul)
        // -35 + (-9.5) = -44.5° はフェア・-35 + (-10.2) = -45.2° はファウル（早さ 70ms / 75ms）
        #expect(HomerunJudge.judge(swing(t: -70, dx: -11)).kind != .foul)
        #expect(HomerunJudge.judge(swing(t: -75, dx: -11)).kind == .foul)
    }

    @Test("土台: ナイス 120m・当たり 100m（芯 1.0 の帯の中心で）")
    func timingBaseDistances() {
        let nice = HomerunJudge.judge(swing(t: 40))
        #expect(nice.timing == .nice)
        #expect(abs(nice.distance - 120) < 1e-9)
        let hit = HomerunJudge.judge(swing(t: 100))
        #expect(hit.timing == .hit)
        #expect(abs(hit.distance - 100) < 1e-9)
    }

    @Test("ゴロは柵越えにならず、ポップフライも柵に届かない")
    func groundAndPopNeverHomer() {
        for band in [HomerunLaunch.grounder, .pop] {
            let ball = HomerunJudge.judge(swing(band: band))
            #expect(ball.kind == .inPlay, "\(band)")
            #expect(ball.distance == 135 * band.distanceFactor)
        }
    }

    @Test("ライナーは（135m でも）中堅の柵に届かず、引っ張って芯が落ちても届かない")
    func linerDependsOnDirection() {
        let center = HomerunJudge.judge(swing(band: .liner))
        #expect(abs(center.distance - 135 * 0.85) < 1e-9)
        #expect(center.kind != .homer)
        // 引っ張り側 -35°（柵 107.5m）: 芯 0.8 に落ちて 135 × 0.85 × 0.8 = 91.8m しか出ない
        let pulled = HomerunJudge.judge(swing(dx: -11, band: .liner))
        #expect(pulled.kind != .homer)
    }

    @Test("柵の一歩手前（6m 以内）はフェンス直撃")
    func fenceHit() {
        // ナイス（40ms）は方向を +5.45° 動かすので、dx で打ち消して中堅（柵 122m）に戻す。
        // 芯は dx ぶん下がり 120m を少し切るため 116〜122m に入る = 柵の 6m 手前以内。
        let near = HomerunJudge.judge(swing(t: 40, dx: -(40.0 / 110 * 15) / 35 * 11, dy: 0))
        #expect(abs(near.direction) < 1e-9)
        #expect(near.distance > 116 && near.distance < 122)
        #expect(near.kind == .fenceHit)
    }

    @Test("同じ入力は必ず同じ結果（乱数なし）")
    func deterministic() {
        let s = swing(t: 33, dx: 3, dy: -4)
        let first = HomerunJudge.judge(s)
        for _ in 0..<50 { #expect(HomerunJudge.judge(s) == first) }
    }

    @Test("能力値: パワーは土台に足し、バットは最終距離にかける")
    func abilitiesScaleDistance() {
        let base = HomerunJudge.judge(swing()).distance
        #expect(HomerunJudge.judge(swing(), abilities: HomerunAbilities(power: 5)).distance == base + 5)
        #expect(abs(HomerunJudge.judge(swing(), abilities: HomerunAbilities(bat: 1.1)).distance - base * 1.1) < 1e-9)
    }

    @Test("方向の呼び名は 5 区分で、境目は ±7・±21")
    func sectors() {
        #expect(HomerunSector(direction: -40) == .left)
        #expect(HomerunSector(direction: -21) == .leftCenter)
        #expect(HomerunSector(direction: -7) == .center)
        #expect(HomerunSector(direction: 7) == .center)
        #expect(HomerunSector(direction: 7.1) == .rightCenter)
        #expect(HomerunSector(direction: 21) == .rightCenter)
        #expect(HomerunSector(direction: 21.1) == .right)
    }
}
