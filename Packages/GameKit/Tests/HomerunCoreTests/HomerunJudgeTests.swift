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
        #expect(HomerunLaunch(cursorDY: -17.01) == .grounder)
        #expect(HomerunLaunch(cursorDY: -17) == .liner)
        #expect(HomerunLaunch(cursorDY: -3.01) == .liner)
        #expect(HomerunLaunch(cursorDY: -3) == .fly)
        #expect(HomerunLaunch(cursorDY: 10.99) == .fly)
        #expect(HomerunLaunch(cursorDY: 11) == .pop)
        // ポップの境目は芯の円の半径（芯の円の外の下側はポップ・#1647）
        #expect(HomerunLaunch.popFloor == HomerunJudge.coreRadius)
        #expect(HomerunLaunch(cursorDY: 500) == .pop)
    }

    @Test("打ち出し角は帯の境目でつながる（0〜10 / 10〜25 / 25〜35 / 35〜55）")
    func launchAngles() {
        #expect(abs(HomerunLaunch.angle(cursorDY: -39) - 0) < 1e-9)
        #expect(abs(HomerunLaunch.angle(cursorDY: -17) - 10) < 1e-9)
        #expect(abs(HomerunLaunch.angle(cursorDY: -3) - 25) < 1e-9)
        #expect(abs(HomerunLaunch.angle(cursorDY: 11) - 35) < 1e-9)
        #expect(abs(HomerunLaunch.angle(cursorDY: 33) - 55) < 1e-9)
        #expect(HomerunLaunch.angle(cursorDY: 1000) <= 55)
    }

    @Test("下で当てるほど打球角度が上がる（縦のずれに対して打ち出し角も帯も単調に増える・#1647）")
    func lowerContactLaunchesHigher() {
        var previousAngle = -Double.infinity
        var previousBand = HomerunLaunch.grounder
        for dy in stride(from: -40.0, through: 60, by: 0.5) {
            let angle = HomerunLaunch.angle(cursorDY: dy)
            let band = HomerunLaunch(cursorDY: dy)
            #expect(angle >= previousAngle, "dy \(dy)")
            #expect(band.rawValue >= previousBand.rawValue, "dy \(dy)")
            previousAngle = angle
            previousBand = band
        }
        // 当たり判定の円の中（-29〜+29pt）で、上からゴロ → ライナー → フライ → ポップが全部出る
        #expect(HomerunLaunch.angle(cursorDY: 10) > HomerunLaunch.angle(cursorDY: 0))
        #expect(HomerunLaunch(cursorDY: -20) == .grounder && HomerunLaunch(cursorDY: 28) == .pop)
        #expect(HomerunLaunch(cursorDY: -10) == .liner && HomerunLaunch(cursorDY: 4) == .fly)
    }

    @Test("ボールの真ん中〜少し下（芯の円の内側）で当てるとフライで柵越えの距離に届き、最も飛ぶ（#1647）")
    func lowerInsideCoreReachesHomerDistance() {
        // フライの芯の基準点はボールの中心の少し下（芯の円の内側）
        #expect(HomerunLaunch.fly.centerDY > 0 && HomerunLaunch.fly.centerDY < HomerunJudge.coreRadius / 2)
        // ジャスト・センター: 縦のずれ 0〜11pt 未満（ボールの真ん中〜芯の円の下の縁）は全部フライで柵越え
        for dy in stride(from: 0.0, to: HomerunJudge.coreRadius, by: 0.5) {
            let ball = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: dy))
            #expect(ball.launch == .fly, "dy \(dy)")
            #expect(ball.kind == .homer, "dy \(dy)")
        }
        // 最も飛ぶのは芯の円の内側（以前は 22pt = 芯の円の外だった）
        var best = (dy: 0.0, distance: 0.0)
        for dy in stride(from: -29.0, through: 29, by: 0.5) {
            let d = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: dy)).distance
            if d > best.distance { best = (dy, d) }
        }
        #expect(best.dy > 0 && best.dy < HomerunJudge.coreRadius, "最長 \(best)")
        // ナイス・当たりのタイミングでも、芯の円の上寄り（9pt）なら中堅の柵を越える
        func centered(_ t: Double, dy: Double) -> HomerunBattedBall {
            HomerunJudge.judge(HomerunSwing(timingOffset: t, cursorDX: -(t / 110 * 15) / 35 * 11, cursorDY: dy))
        }
        #expect(centered(40, dy: 4).kind == .homer)
        #expect(centered(80, dy: 4).kind == .homer)
        // 真ん中（ずれ 0）もフライの柵越え
        let straight = HomerunJudge.judge(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 0))
        #expect(straight.launch == .fly && straight.kind == .homer)
    }

    @Test("最高の当たりの上乗せ（#1647）: フライ・ジャストの窓の中・芯の円の中だけで効き、0ms × 基準点ちょうどで 180m。ナイス・当たり・芯の外・ライナーは上乗せ前の式のまま")
    func sweetSpotBonusOnlyForBestContact() {
        #expect(HomerunJudge.judge(swing()).distance == HomerunJudge.bestDistance)
        #expect(HomerunJudge.sweetSpot(timingOffset: 0, distanceFromBandCenter: 0) == 1)
        // タイミング・芯のどちらかが外れると上乗せ無し
        #expect(HomerunJudge.sweetSpot(timingOffset: 25, distanceFromBandCenter: 0) == 0)
        #expect(HomerunJudge.sweetSpot(timingOffset: 40, distanceFromBandCenter: 0) == 0)
        #expect(HomerunJudge.sweetSpot(timingOffset: 0, distanceFromBandCenter: HomerunJudge.coreRadius) == 0)
        #expect(HomerunJudge.sweetSpot(timingOffset: 0, distanceFromBandCenter: 20) == 0)
        // 近いほど大きい（両方の近さの積）
        let a = HomerunJudge.judge(swing(t: 5, dy: 1)).distance
        let b = HomerunJudge.judge(swing(t: 15, dy: 1)).distance
        let c = HomerunJudge.judge(swing(t: 15, dy: 6)).distance
        #expect(a > b && b > c)
        // ライナーは上乗せしない
        #expect(abs(HomerunJudge.judge(swing(band: .liner)).distance - 140 * 1.05) < 1e-9)
        // ナイス・当たりの飛距離は上乗せ前の式どおり
        for t in [-100.0, -60, -40, 30, 50, 90] {
            let ball = HomerunJudge.judge(swing(t: t))
            #expect(abs(ball.distance - HomerunTiming(offsetMilliseconds: t).baseDistance * 1.15) < 1e-9, "t \(t)")
        }
    }

    @Test("芯の円の外の下側（ボールの下を大きく外す）はどのタイミング・左右でも柵越えにならない（ポップ・#1647）")
    func farBelowNeverHomer() {
        for t in stride(from: -110.0, through: 110, by: 5) {
            for dx in stride(from: -30.0, through: 30, by: 1) {
                for dy in stride(from: HomerunJudge.coreRadius, through: 40, by: 0.5) {
                    let ball = HomerunJudge.judge(HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: dy))
                    #expect(ball.kind != .homer && ball.kind != .fenceHit, "t \(t) dx \(dx) dy \(dy): \(ball.kind) \(ball.distance)")
                    if ball.kind == .inPlay { #expect(ball.launch == .pop && ball.distance < 80) }
                }
            }
        }
    }

    @Test("飛距離の係数はゴロ 0.3・ライナー 1.05・フライ 1.15・ポップ 0.5")
    func launchFactors() {
        #expect(HomerunLaunch.grounder.distanceFactor == 0.3)
        #expect(HomerunLaunch.liner.distanceFactor == 1.05)
        #expect(HomerunLaunch.fly.distanceFactor == 1.15)
        #expect(HomerunLaunch.pop.distanceFactor == 0.5)
    }

    @Test("ジャスト 0ms × フライの帯の中心 = 最高の当たり 180m（140 × 1.15 = 161m に上乗せ・#1647）・中堅の柵 122m を越えて柵越え")
    func justFlyCenterIsHomer() {
        let ball = HomerunJudge.judge(swing())
        #expect(ball.kind == .homer)
        #expect(abs(ball.distance - 180) < 1e-9)
        #expect(ball.direction == 0)
        #expect(ball.timing == .just)
        #expect(ball.launch == .fly)
    }

    @Test("ナイス（125m）× フライで方向 0° に戻しても、芯が少し落ちるだけで中堅の柵（122m）を越える（#1594）")
    func niceExampleFromSpec() {
        // 帯の中心から縦に 2.75pt ずらす（方向は動かさない）。
        // タイミング 40ms は方向を +5.45° 動かす（流し方向）ので、方向は dx で打ち消す。
        let t = 40.0
        let timingDirection = t / 110 * 15
        let dx0 = -timingDirection / 35 * 11  // 方向 0°（センター）に戻すカーソルの左右
        let center = HomerunJudge.judge(swing(t: t, dx: dx0, dy: 2.75))
        #expect(center.timing == .nice)
        #expect(abs(center.direction) < 1e-9)
        // 芯は dx0 ぶんも合わせて約 3.2pt のずれで 0.97 程度。125 × 1.15 × 0.97 ≈ 139m で中堅の柵 122m を越える。
        #expect(center.kind == .homer)
        #expect(center.distance > 135 && center.distance < 125 * 1.15)
    }

    @Test("芯: 帯の中心で 1.0・芯の半径 11pt で 0.9・当たり判定の半径（1 マス ≈ 29.3pt）で 0.8・外は 0")
    func coreFalloff() {
        #expect(abs(HomerunJudge.contactRadius - HomerunLaunch.bandWidth * 4 / 3) < 1e-9)
        #expect(HomerunJudge.coreEdgeFactor == 0.9)
        #expect(HomerunJudge.edgeFactor == 0.8)
        #expect(HomerunJudge.core(distanceFromBandCenter: 0) == 1)
        #expect(abs(HomerunJudge.core(distanceFromBandCenter: 11) - 0.9) < 1e-9)
        #expect(HomerunJudge.core(distanceFromBandCenter: 11.01) < 0.9 && HomerunJudge.core(distanceFromBandCenter: 11.01) > 0.89)
        #expect(abs(HomerunJudge.core(distanceFromBandCenter: HomerunJudge.contactRadius) - HomerunJudge.edgeFactor) < 1e-9)
        #expect(HomerunJudge.core(distanceFromBandCenter: HomerunJudge.contactRadius + 0.01) == 0)
        // ミートが上がると半径が広がる
        #expect(HomerunJudge.core(distanceFromBandCenter: HomerunJudge.contactRadius + 0.01, abilities: HomerunAbilities(meet: 1.5)) > 0)
    }

    @Test("芯の外でも当たり判定の中なら当たる（距離は落ちる）。当たり判定の外に置くと空振り（距離 0）")
    func outsideCoreIsMiss() {
        let weak = HomerunJudge.judge(swing(dx: 12))
        #expect(weak.kind != .miss)
        #expect(weak.distance < HomerunJudge.judge(swing()).distance)
        let ball = HomerunJudge.judge(swing(dx: 30))
        #expect(ball.kind == .miss)
        #expect(ball.distance == 0)
    }

    @Test("空振りの理由: タイミングが窓の外なら早い / 遅い（照準より先）、窓の中で照準の外なら照準のずれ。当たり・見送りは nil")
    func missReason() {
        #expect(HomerunJudge.missReason(swing(t: -111)) == .early)
        #expect(HomerunJudge.missReason(swing(t: 111)) == .late)
        #expect(HomerunJudge.missReason(swing(t: -200, dx: 40)) == .early)
        #expect(HomerunJudge.missReason(swing(dx: 30)) == .aim)
        #expect(HomerunJudge.missReason(swing()) == nil)
        #expect(HomerunJudge.missReason(swing(t: -110, dx: -11)) == nil, "ファウルは空振りではない")
        #expect(HomerunJudge.missReason(nil) == nil)
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
        // 45° のすぐ外はファウルポールの幅（#1686）なので、ファウルになるのはポールの幅の外から。
        let outside = 30 + HomerunJudge.poleHalfAngle + 1e-6
        #expect(HomerunJudge.judge(swing(t: 110, dx: dx(forCursorDegrees: outside))).kind == .foul)
        #expect(HomerunJudge.judge(swing(t: -110, dx: -dx(forCursorDegrees: outside))).kind == .foul)
        // -35 + (-9.5) = -44.5° はフェア・-35 + (-10.2) = -45.2° はファウル（早さ 70ms / 75ms）
        #expect(HomerunJudge.judge(swing(t: -70, dx: -11)).kind != .foul)
        #expect(HomerunJudge.judge(swing(t: -75, dx: -11)).kind == .foul)
    }

    @Test("土台: ナイス 125m・当たり 110m（芯 1.0 の帯の中心で・フライの 1.15 倍がかかる）")
    func timingBaseDistances() {
        let nice = HomerunJudge.judge(swing(t: 40))
        #expect(nice.timing == .nice)
        #expect(abs(nice.distance - 125 * 1.15) < 1e-9)
        let hit = HomerunJudge.judge(swing(t: 100))
        #expect(hit.timing == .hit)
        #expect(abs(hit.distance - 110 * 1.15) < 1e-9)
    }

    @Test("ゴロは柵越えにならず、ポップフライも柵に届かない")
    func groundAndPopNeverHomer() {
        for band in [HomerunLaunch.grounder, .pop] {
            let ball = HomerunJudge.judge(swing(band: band))
            #expect(ball.kind == .inPlay, "\(band)")
            #expect(ball.distance == 140 * band.distanceFactor)
        }
    }

    @Test("ジャストのライナーは中堅でも柵越え（147m）・引っ張って芯が落ちても柵越え。当たりのライナーは中堅に届かない")
    func linerDependsOnDirection() {
        let center = HomerunJudge.judge(swing(band: .liner))
        #expect(abs(center.distance - 140 * 1.05) < 1e-9)
        #expect(center.kind == .homer)
        // 引っ張り側 -35°（柵 107.5m）: 芯 0.9 に落ちても 147 × 0.9 ≈ 132m
        let pulled = HomerunJudge.judge(swing(dx: -11, band: .liner))
        #expect(pulled.kind == .homer)
        // 当たり（100ms）で方向を中堅に戻す: 110 × 1.05 × 芯 0.96 ≈ 111m で柵 122m に届かない
        let t = 100.0
        let late = HomerunJudge.judge(swing(t: t, dx: -(t / 110 * 15) / 35 * 11, band: .liner))
        #expect(late.timing == .hit)
        #expect(late.kind == .inPlay)
    }

    @Test("柵の一歩手前（6m 以内）はフェンス直撃")
    func fenceHit() {
        // ナイス（40ms）× ライナーは方向を +5.45° 動かすので、dx で打ち消して中堅（柵 122m）に戻す。
        // 縦に上へ 8pt ずらすと芯は約 0.93 に下がり、125m × 1.05 × 0.93 ≈ 121m で 116〜122m に入る = 柵の 6m 手前以内。
        let near = HomerunJudge.judge(swing(t: 40, dx: -(40.0 / 110 * 15) / 35 * 11, band: .liner, dy: -8))
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
        #expect(abs(HomerunJudge.judge(swing(), abilities: HomerunAbilities(power: 5)).distance - (base + 5 * HomerunLaunch.fly.distanceFactor)) < 1e-9)
        #expect(base == HomerunJudge.bestDistance)
        #expect(abs(HomerunJudge.judge(swing(), abilities: HomerunAbilities(bat: 1.1)).distance - base * 1.1) < 1e-9)
    }

    /// 入力の格子（タイミング −110〜+110ms を 5ms 刻み・照準のずれ dx / dy をボールの中心から当たり判定の半径以内で 2pt 刻み）を
    /// 総当たりし、当たった球（空振り以外）のうち柵越え・ファウルの割合（%）をタイミングの段階別と全体で返す。
    private func homerRates() -> (just: Double, nice: Double, hit: Double, all: Double, foul: Double) {
        var total: [HomerunTiming: Int] = [:], homers: [HomerunTiming: Int] = [:], fouls = 0
        for t in stride(from: -110.0, through: 110, by: 5) {
            for dx in stride(from: -30.0, through: 30, by: 2) {
                for dy in stride(from: -30.0, through: 30, by: 2) where hypot(dx, dy) <= HomerunJudge.contactRadius {
                    let ball = HomerunJudge.judge(HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: dy))
                    guard ball.kind != .miss else { continue }
                    total[ball.timing, default: 0] += 1
                    if ball.kind == .homer { homers[ball.timing, default: 0] += 1 }
                    if ball.kind == .foul { fouls += 1 }
                }
            }
        }
        func rate(_ ts: [HomerunTiming]) -> Double {
            let n = ts.reduce(0) { $0 + total[$1, default: 0] }
            return Double(ts.reduce(0) { $0 + homers[$1, default: 0] }) / Double(n) * 100
        }
        let all = total.values.reduce(0, +)
        return (rate([.just]), rate([.nice]), rate([.hit]), rate([.just, .nice, .hit]), Double(fouls) / Double(all) * 100)
    }

    @Test("柵越え率（#1594 会長 QA）: ジャスト 55〜65%・ナイス 50〜60%・当たり 5〜12%・全体 33〜45%・ファウルは 12% 以下（#1647 で芯の円の外の下側をポップにして、ジャスト 70% → 58%・全体 36.7% → 35.4%）")
    func homerRatesStayInTarget() {
        let r = homerRates()
        #expect((55...65).contains(r.just), "ジャスト \(r.just)%")
        #expect((50...60).contains(r.nice), "ナイス \(r.nice)%")
        #expect((5...12).contains(r.hit), "当たり \(r.hit)%")
        #expect((33...45).contains(r.all), "全体 \(r.all)%")
        #expect(r.foul <= 12, "ファウル \(r.foul)%")
    }

    @Test("柵越えの飛距離は最長でもジャスト 0ms × フライの芯の基準点（180m・#1647）まで。ゴロ・ポップは柵越えにならない")
    func homerDistanceStaysPlausible() {
        var longest = 0.0
        var homerBands: Set<HomerunLaunch> = []
        for t in stride(from: -110.0, through: 110, by: 5) {
            for dx in stride(from: -30.0, through: 30, by: 2) {
                for dy in stride(from: -50.0, through: 76, by: 2) {
                    let ball = HomerunJudge.judge(HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: dy))
                    longest = max(longest, ball.distance)
                    if ball.kind == .homer, let launch = ball.launch { homerBands.insert(launch) }
                }
            }
        }
        #expect(abs(longest - HomerunJudge.bestDistance) < 1e-9)
        #expect(homerBands == [.liner, .fly])
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

@Suite("ジャストミートの判定（#1775）")
struct HomerunJustMeetJudgeTests {
    private func swing(t: Double = 0, dx: Double = 0, band: HomerunLaunch = .fly, dy: Double = 0) -> HomerunSwing {
        HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: band.centerDY + dy)
    }

    @Test("ジャストの窓の中で芯の円の中に当たるとジャストミート。飛距離・種別は同じ式のまま")
    func justInCore() {
        for t in [-25.0, -10, 0, 10, 25] {
            for band in [HomerunLaunch.grounder, .liner, .fly, .pop] {
                let ball = HomerunJudge.judge(swing(t: t, band: band))
                #expect(ball.isJustMeet, "\(t)ms・\(band)")
            }
        }
        // 芯の円の縁（11pt）まで。
        #expect(HomerunJudge.judge(swing(dx: HomerunJudge.coreRadius)).isJustMeet)
        #expect(HomerunJudge.judge(swing(dy: HomerunJudge.coreRadius)).isJustMeet)
    }

    @Test("ナイス以下・芯の円の外・空振り・ファウルはジャストミートではない")
    func notJust() {
        #expect(!HomerunJudge.judge(swing(t: 26)).isJustMeet)
        #expect(!HomerunJudge.judge(swing(t: -60)).isJustMeet)
        #expect(!HomerunJudge.judge(swing(t: 100)).isJustMeet)
        // 当たりにはなるが芯の円の外（当たり判定の半径の中）。
        let edge = HomerunJudge.judge(swing(dx: HomerunJudge.coreRadius + 0.5))
        #expect(edge.kind != .miss && !edge.isJustMeet)
        // 空振り（ジャストでも照準が外れた）・見送り。
        let aim = HomerunJudge.judge(swing(dx: 100))
        #expect(aim.kind == .miss && aim.timing == .just && !aim.isJustMeet)
        #expect(!HomerunJudge.judge(nil).isJustMeet)
        // ファウル（方向が ±45° を越える・ポールの幅の外）。ジャストの窓の中では方向が 45° を越えない（35 + 15 × 25/110）ので、ファウルは必ずジャスト以外。
        let foul = HomerunJudge.judge(swing(t: 110, dx: HomerunJudge.fullDeflection))
        #expect(foul.kind == .foul && !foul.isJustMeet)
    }

    @Test("ミートの能力値で芯の円が広がれば、その分ジャストミートの範囲も広がる")
    func meetWidensCore() {
        let wide = HomerunAbilities(meet: 2)
        let s = swing(dx: HomerunJudge.coreRadius + 5)
        #expect(!HomerunJudge.judge(s).isJustMeet)
        #expect(HomerunJudge.judge(s, abilities: wide).isJustMeet)
    }

    @Test("ポールに当たった柵越えでもジャストミートの印は残る。確認用の強制ポールも判定を引き継ぐ")
    func poleKeepsMark() {
        let forced = HomerunJudge.forcedPoleBall(swing())
        #expect(forced.kind == .homer && forced.isJustMeet == HomerunJudge.judge(swing()).isJustMeet)
        let pole = HomerunJudge.poleBall(direction: 45, distance: 120, timing: .just, launch: .fly, isJustMeet: true)
        #expect(pole.isJustMeet)
    }

    @Test("月まで飛んだ打球（判定の外で作る）にはジャストミートの印を付けない")
    func moonBallIsNotMarked() {
        #expect(!HomerunJudge.moonBall(swing()).isJustMeet)
    }
}
