import Testing
import Foundation
@testable import HomerunCore

/// ファウルポール直撃（#1686・会長決裁 2026-10-02）の判定・優先順位・保存の互換。
@Suite("柵越えおじさんのファウルポール直撃（判定）")
struct HomerunPoleTests {
    /// 方向がちょうど `degrees`（右 = 正）になる振り: 遅い 110ms（+15°）にカーソルで残りを足す（左は早い -110ms）。
    /// フライの帯の芯の基準点の高さで振るので、飛距離は約 116m（柵 100m を越える）。
    private func swing(direction degrees: Double, band: HomerunLaunch = .fly) -> HomerunSwing {
        let side = degrees < 0 ? -1.0 : 1.0
        let cursorDegrees = abs(degrees) - HomerunJudge.maxTimingDirection
        return HomerunSwing(timingOffset: side * HomerunTiming.hitWindow,
                            cursorDX: side * cursorDegrees / HomerunJudge.maxCursorDirection * HomerunJudge.fullDeflection,
                            cursorDY: band.centerDY)
    }

    private var w: Double { HomerunJudge.poleHalfAngle }

    @Test("ポールの幅は柵 100m の所でポールの半径 0.3m + 球の半径が見込む角度（約 0.19°）")
    func width() {
        #expect(HomerunJudge.poleRadius == 0.3)
        #expect(HomerunJudge.poleHeight == 20)
        #expect(abs(w - atan(0.337 / 100) * 180 / .pi) < 1e-12)
        #expect(w > 0.19 && w < 0.2)
        // 振りの組み立ての前提: 方向がねらいどおり。
        for d in [44.9, 45.0, 45.1, -45.1] {
            #expect(abs(HomerunJudge.direction(swing(direction: d)) - d) < 1e-9)
        }
    }

    @Test("幅の内側（45° の内外どちらも・両翼）で柵を越える飛距離ならポール直撃: 柵越え・方向はポールの線 ±45°・飛距離はそのまま")
    func insideWidth() {
        for side in [-1.0, 1.0] {
            // 幅の端ちょうどは方向の計算の丸め（1e-15 程度）で内外がぶれるので、端のごく内側で見る。
            for d in [45 - w * 0.999, 45 - w / 2, 45, 45 + w / 2, 45 + w * 0.999] {
                let ball = HomerunJudge.judge(swing(direction: side * d))
                #expect(ball.kind == .homer)
                #expect(ball.isPoleHit)
                #expect(ball.direction == side * 45)
                #expect(ball.fence == 100)
                #expect(ball.distance > 110 && ball.distance < 120)
                #expect(!ball.isMoon)
            }
        }
    }

    @Test("幅の外: 45° を越える側はファウルのまま・内側はふつうの柵越え（ポール直撃にしない）")
    func outsideWidth() {
        for side in [-1.0, 1.0] {
            let foul = HomerunJudge.judge(swing(direction: side * (45 + w + 1e-6)))
            #expect(foul.kind == .foul)
            #expect(!foul.isPoleHit)
            let fair = HomerunJudge.judge(swing(direction: side * (45 - w - 1e-6)))
            #expect(fair.kind == .homer)
            #expect(!fair.isPoleHit)
            #expect(abs(fair.direction) < 45)
            #expect(HomerunJudge.judge(swing(direction: side * 46)).kind == .foul)
        }
    }

    @Test("高さ・飛距離が足りない打球はポールに当たらない: 幅の中でも柵（100m）に届かなければ、内側は当たり・直撃、外側はファウル")
    func notEnoughDistance() {
        for side in [-1.0, 1.0] {
            // ゴロ（低い打球）は幅の中でも当たらない。
            let lowFair = HomerunJudge.judge(swing(direction: side * (45 - w / 2), band: .grounder))
            #expect(lowFair.kind == .inPlay && !lowFair.isPoleHit)
            let lowFoul = HomerunJudge.judge(swing(direction: side * (45 + w / 2), band: .grounder))
            #expect(lowFoul.kind == .foul && !lowFoul.isPoleHit)
            // 柵のちょうど手前（99.9m）と柵ちょうど（100m）: バットの倍率で飛距離だけを動かす。
            let s = swing(direction: side * (45 + w / 2))
            let base = HomerunJudge.judge(s).distance
            let short = HomerunJudge.judge(s, abilities: HomerunAbilities(bat: 99.9 / base))
            #expect(short.kind == .foul && !short.isPoleHit)
            let over = HomerunJudge.judge(s, abilities: HomerunAbilities(bat: 100.0001 / base))
            #expect(over.kind == .homer && over.isPoleHit)
            let shortFair = HomerunJudge.judge(swing(direction: side * (45 - w / 2)), abilities: HomerunAbilities(bat: 99.9 / base))
            #expect(shortFair.kind == .fenceHit && !shortFair.isPoleHit)
        }
    }

    @Test("優先順位: 月 > ポール直撃（月の打球はポール直撃にしない・強制は月が先）")
    func priority() {
        var both = HomerunChallenge(forcesMoon: true, forcesPole: true)
        let ball = both.swing(swing(direction: 45))
        #expect(ball?.isMoon == true)
        #expect(ball?.isPoleHit == false)
        // 月の打球を ±45° に置いても（作れない形だが）ポール直撃とは数えない。
        var moon = HomerunJudge.moonBall(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY))
        moon.direction = 45
        #expect(!moon.isPoleHit)
        // 柵越え以外は ±45° でもポール直撃にしない。
        var notHomer = HomerunJudge.judge(swing(direction: 45))
        for kind in [HomerunKind.foul, .fenceHit, .inPlay, .miss] {
            notHomer.kind = kind
            #expect(!notHomer.isPoleHit)
        }
    }

    @Test("確認用の強制（-homerunForcePole）: どこで振っても方向の側のポールに当たる・見送りは空振りのまま")
    func forced() {
        var c = HomerunChallenge(forcesPole: true)
        let left = c.swing(HomerunSwing(timingOffset: -200, cursorDX: -30, cursorDY: 30))
        #expect(left?.isPoleHit == true && left?.direction == -45 && left?.kind == .homer)
        #expect((left?.distance ?? 0) >= 100)
        let s = HomerunSwing(timingOffset: 20, cursorDX: 5, cursorDY: HomerunLaunch.fly.centerDY)
        let right = c.swing(s)
        #expect(right?.isPoleHit == true && right?.direction == 45)
        // 飛距離がふだんの式で柵を越えるならその値。
        #expect(right?.distance == HomerunJudge.judge(s).distance)
        let took = c.swing(nil)
        #expect(took?.kind == .miss && took?.isPoleHit == false)
        #expect(HomerunChallenge().forcesPole == false)
    }

    @Test("保存（方向・距離・種別）から戻してもポール直撃のまま（保存の形は変えない）")
    func survivesRecords() throws {
        for d in [45.0, -45.0, 45 + w / 2, -(45 - w / 2)] {
            let ball = HomerunJudge.judge(swing(direction: d))
            let data = try JSONEncoder().encode(HomerunShot(ball))
            let back = try JSONDecoder().decode(HomerunShot.self, from: data)
            let restored = HomerunBattedBall(direction: back.direction, distance: back.distance, kind: back.kind,
                                             timing: ball.timing, launch: ball.launch, fence: ball.fence)
            #expect(restored.isPoleHit)
        }
    }

    @Test("発生率の見込み: 総当たり（タイミング ±110ms × 照準の横 ±11pt × 縦 ライナー〜フライ）でまれ（1% 未満）")
    func rarity() {
        var swings = 0, poles = 0, homers = 0
        for t in stride(from: -110.0, through: 110, by: 0.5) {
            for dx in stride(from: -11.0, through: 11, by: 0.25) {
                for dy in stride(from: -17.0, through: 10.5, by: 0.5) {
                    let ball = HomerunJudge.judge(HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: dy))
                    swings += 1
                    if ball.isPoleHit { poles += 1 }
                    if ball.kind == .homer { homers += 1 }
                }
            }
        }
        let rate = Double(poles) / Double(swings)
        print("ポール直撃 \(poles) / \(swings) = \(rate)、柵越え \(homers)")
        #expect(poles > 0)
        #expect(rate < 0.01, "ポール直撃 \(poles) / \(swings) = \(rate)、柵越え \(homers)")
    }
}
