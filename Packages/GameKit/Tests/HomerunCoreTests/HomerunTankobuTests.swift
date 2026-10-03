import Testing
import Foundation
@testable import HomerunCore

/// 打ち上げた球が自分の頭に落ちてたんこぶ（#1793）の発生条件。
@Suite("柵越えおじさんのたんこぶ（発生条件）")
struct HomerunTankobuTests {
    /// ジャストで、ポップの帯の芯の基準点（22pt）より下を叩いた振り（球の結構下を擦った当たり）。
    private let scrape = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunTankobu.scrapeFloor + 2)
    /// 擦りの下限のすぐ上（ポップのままだが、下限より上）。
    private let shallowPop = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.popFloor + 1)

    /// 1 球ぶん振る（`#require` の中では mutating を呼べない）。
    private func toss(_ c: inout HomerunChallenge, _ swing: HomerunSwing?, tankobuRoll: Double = 1) -> HomerunBattedBall {
        c.swing(swing, tankobuRoll: tankobuRoll)!
    }

    @Test("初期値: 確率 1/5・1 挑戦に 1 度・帯の下限はポップの帯の芯の基準点")
    func defaults() {
        #expect(HomerunTankobu.chance == 0.2)
        #expect(HomerunTankobu.perChallenge == 1)
        #expect(HomerunTankobu.scrapeFloor == HomerunLaunch.pop.centerDY)
        #expect(HomerunTankobu.scrapeFloor > HomerunLaunch.popFloor)
    }

    @Test("擦りの帯のポップは、乱数が確率未満ならたんこぶ。飛距離 0・方向 0・種別は元のまま")
    func scrapeBecomesTankobu() throws {
        let plain = HomerunJudge.judge(scrape)
        #expect(plain.kind == .inPlay && plain.launch == .pop && plain.distance > 0, "前提: そのままならフェアの当たり")
        var c = HomerunChallenge()
        let ball = toss(&c, scrape, tankobuRoll: 0)
        #expect(ball.isTankobu)
        #expect(ball.distance == 0 && ball.direction == 0)
        #expect(ball.kind == .inPlay && ball.launch == .pop && ball.timing == plain.timing)
        #expect(!ball.isJustMeet)
        #expect(c.totalDistance == 0)
    }

    @Test("乱数が確率以上なら出ない（既定の乱数 1 も出ない）")
    func rollAtOrAboveChance() throws {
        var c = HomerunChallenge()
        let r1 = toss(&c, scrape, tankobuRoll: HomerunTankobu.chance)
        #expect(!r1.isTankobu)
        let r2 = toss(&c, scrape)
        #expect(!r2.isTankobu)
        let r3 = toss(&c, scrape, tankobuRoll: 0.19)
        #expect(r3.isTankobu)
    }

    @Test("擦りの帯より上のポップ・ほかの帯・ファウル・空振り・見送りは出ない")
    func nonQualifying() throws {
        var c = HomerunChallenge()
        let r4 = toss(&c, shallowPop, tankobuRoll: 0)
        #expect(!r4.isTankobu)
        let fly = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY + 2)
        let r5 = toss(&c, fly, tankobuRoll: 0)
        #expect(!r5.isTankobu)
        let foul = HomerunSwing(timingOffset: 0, cursorDX: 11, cursorDY: scrape.cursorDY)
        let foulBall = HomerunJudge.judge(foul)
        let r6 = toss(&c, foul, tankobuRoll: 0)
        if foulBall.kind != .inPlay { #expect(!r6.isTankobu) }
        let late = HomerunSwing(timingOffset: 300, cursorDX: 0, cursorDY: scrape.cursorDY)
        let miss = toss(&c, late, tankobuRoll: 0)
        #expect(miss.kind == .miss && !miss.isTankobu)
        let r7 = toss(&c, nil, tankobuRoll: 0)
        #expect(!r7.isTankobu)
    }

    @Test("1 挑戦に 1 度まで。挑戦が変われば数え直す")
    func oncePerChallenge() throws {
        var c = HomerunChallenge()
        let r8 = toss(&c, scrape, tankobuRoll: 0)
        #expect(r8.isTankobu)
        let r9 = toss(&c, scrape, tankobuRoll: 0)
        #expect(!r9.isTankobu, "2 回目は抽選に当たっても出さない")
        #expect(c.tankobuCount == 1)
        var next = HomerunChallenge()
        let r10 = toss(&next, scrape, tankobuRoll: 0)
        #expect(r10.isTankobu)
    }

    @Test("判定そのもの（judge）は変えない: たんこぶは挑戦の中の置き換えだけ")
    func judgeUnchanged() {
        #expect(HomerunJudge.judge(scrape).isTankobu == false)
        #expect(HomerunJudge.judge(scrape) == HomerunJudge.judge(scrape))
    }
}
