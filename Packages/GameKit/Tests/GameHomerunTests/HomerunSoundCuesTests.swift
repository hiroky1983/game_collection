import Testing
import Foundation
import Core
import HomerunCore
@testable import GameHomerun

@MainActor
@Suite("柵越えおじさんの効果音を鳴らす時刻")
struct HomerunSoundCuesTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private var arrival: Date { t0.addingTimeInterval(TimeInterval(HomerunPitch.travelMilliseconds) / 1000) }

    private func swing(t: Double = 0, dx: Double = 0, dy: Double) -> HomerunSwing {
        HomerunSwing(timingOffset: t, cursorDX: dx, cursorDY: dy)
    }

    private func result(_ ball: HomerunBattedBall?, offset: Double? = 0, whiffGag: Bool = false) -> HomerunSwingPlan {
        let release = offset.map { arrival.addingTimeInterval($0 / 1000) }
        let clock = HomerunModel.BallClock(pitchStart: t0, zone: 4, pressedAt: release == nil ? nil : t0, releasedAt: release,
                                           timingOffset: offset)
        return HomerunSwingPlan(phase: .ballResult, clock: clock, lastBall: ball, whiffGag: whiffGag)
    }

    private func cues(_ plan: HomerunSwingPlan, banner: Date? = nil, finish: Bool = false) -> [HomerunSoundCue] {
        HomerunSoundCues.cues(plan: plan, bannerShownAt: banner, unlockedAtFinish: finish, now: t0)
    }

    private func sounds(_ list: [HomerunSoundCue]) -> [HomerunSound] {
        list.sorted { $0.at < $1.at }.map(\.sound)
    }

    @Test("投球: 的が出る瞬間に打ち出し、見送ればミットに収まる音。ミットは輪が重なった後・見送りの締め切りより前")
    func pitching() throws {
        let clock = HomerunModel.BallClock(pitchStart: t0, zone: 4)
        let list = cues(HomerunSwingPlan(phase: .pitching, clock: clock, lastBall: nil))
        #expect(sounds(list) == [.machine, .mitt])
        #expect(list.first { $0.sound == .machine }?.at == t0)
        let mitt = try #require(list.first { $0.sound == .mitt }?.at)
        #expect(mitt > arrival.addingTimeInterval(HomerunTiming.hitWindow / 1000), "当たり窓の終わり際に当てた球より先に鳴らない")
        #expect(mitt < arrival.addingTimeInterval(HomerunModel.lateLimit), "見送りで締めるより前に鳴る（締めた後の予定では過去になる）")
    }

    @Test("怒りマークは構えに入った瞬間、実績解禁は出した瞬間。素振りは離した瞬間に風切り")
    func pitchingExtras() {
        let practice = t0.addingTimeInterval(-0.5)
        let clock = HomerunModel.BallClock(pitchStart: t0, zone: 4, practiceSwingAt: practice)
        let banner = t0.addingTimeInterval(-HomerunModel.windup)
        let plan = HomerunSwingPlan(phase: .pitching, clock: clock, lastBall: nil, waitingFaceMark: .waitingAngry)
        let list = cues(plan, banner: banner)
        #expect(list.contains(HomerunSoundCue(at: t0.addingTimeInterval(-HomerunModel.windup), sound: .angry)))
        #expect(list.contains(HomerunSoundCue(at: banner, sound: .achievement)))
        #expect(list.contains(HomerunSoundCue(at: practice, sound: .swing)))
        // 怒りマークの無い構えでは鳴らさない。
        let calm = cues(HomerunSwingPlan(phase: .pitching, clock: clock, lastBall: nil, waitingFaceMark: .waitingSparkle))
        #expect(!calm.contains { $0.sound == .angry })
    }

    @Test("当たり: 離した瞬間に風切り、バットに当たる瞬間に当たりの音（打点の時刻 `contactAt` と同じ）")
    func hitAtContact() throws {
        let ball = HomerunJudge.judge(swing(t: 40, dx: 5, dy: HomerunLaunch.liner.centerDY))
        #expect(ball.kind != .miss && !ball.isJustMeet)
        let plan = result(ball, offset: 40)
        let list = cues(plan)
        let contact = try #require(plan.contactAt)
        #expect(list.contains(HomerunSoundCue(at: arrival.addingTimeInterval(0.04), sound: .swing)))
        #expect(list.contains(HomerunSoundCue(at: contact, sound: HomerunSoundCues.hitSound(for: ball))))
    }

    @Test("当たりの音の選び分け: ジャストミート > 芯 > 詰まり > 普通")
    func hitSoundChoice() {
        let just = HomerunJudge.judge(swing(dy: HomerunLaunch.fly.centerDY + 1))
        #expect(just.isJustMeet)
        #expect(HomerunSoundCues.hitSound(for: just) == .justMeet)
        var moon = HomerunJudge.moonBall(swing(dy: HomerunLaunch.fly.centerDY))
        moon.isJustMeet = true
        #expect(HomerunSoundCues.hitSound(for: moon) == .hitJust, "月はジャストミートの演出を出さないので芯の音")
        let foul = HomerunJudge.judge(swing(t: -100, dx: -11, dy: HomerunLaunch.fly.centerDY))
        #expect(foul.kind == .foul)
        #expect(HomerunSoundCues.hitSound(for: foul) == .hitWeak)
        let grounder = HomerunJudge.judge(swing(t: 100, dy: HomerunLaunch.grounder.centerDY))
        #expect(grounder.kind == .inPlay && grounder.timing == .hit)
        #expect(HomerunSoundCues.hitSound(for: grounder) == .hitWeak)
        let nice = HomerunJudge.judge(swing(t: 50, dy: HomerunLaunch.grounder.centerDY))
        #expect(nice.kind == .inPlay && nice.timing == .nice)
        #expect(HomerunSoundCues.hitSound(for: nice) == .hitGood)
    }

    @Test("柵越え: スタンドに落ちた瞬間に歓声。ジャストミートはヒットストップのぶん遅らせる")
    func homerLanding() throws {
        var just = HomerunJudge.judge(swing(dx: 1, dy: HomerunLaunch.fly.centerDY + 3))
        just.distance = just.fence + 10
        #expect(just.kind == .homer && just.isJustMeet && !just.isOutOfPark && !just.isPoleHit)
        let plan = result(just)
        let contact = try #require(plan.contactAt)
        let track = try #require(plan.chaseTrack)
        let cheer = try #require(cues(plan).first { $0.sound == .homerun })
        #expect(abs(cheer.at.timeIntervalSince(contact) - (track.flightDuration + HomerunJustMeet.extraDuration)) < 1e-9)
        // 歓声は結果のカードより前（落ちた瞬間）。
        #expect(cheer.at < plan.chaseCardAt!)
    }

    @Test("場外は柵を越える瞬間、ポール直撃はポールに当たる瞬間")
    func outOfParkAndPole() throws {
        var far = HomerunJudge.judge(swing(dx: 1, dy: HomerunLaunch.fly.centerDY + 3))
        far.distance = 200
        #expect(far.isOutOfPark)
        let plan = result(far)
        let contact = try #require(plan.contactAt)
        let track = try #require(plan.chaseTrack)
        let cheer = try #require(cues(plan).first { $0.sound == .outOfPark })
        let t = cheer.at.timeIntervalSince(contact) - (far.isJustMeet ? HomerunJustMeet.extraDuration : 0)
        #expect(t > 0 && t < track.flightDuration)
        #expect(track.point(at: t).s >= far.fence)
        #expect(track.point(at: t - 1.0 / 60).s < far.fence)
        #expect(!cues(plan).contains { $0.sound == .homerun })

        let pole = HomerunJudge.forcedPoleBall(swing(dx: 5, dy: HomerunLaunch.fly.centerDY))
        #expect(pole.isPoleHit)
        let polePlan = result(pole)
        let poleCue = try #require(cues(polePlan).first { $0.sound == .foulPole })
        let poleTrack = try #require(polePlan.chaseTrack)
        let poleHeld = pole.isJustMeet ? HomerunJustMeet.extraDuration : 0
        #expect(abs(poleCue.at.timeIntervalSince(polePlan.contactAt!) - poleTrack.flightDuration - poleHeld) < 1e-9)
    }

    @Test("月: 当たって少し後から上昇音、月に当たる瞬間に割れる音")
    func moon() throws {
        let ball = HomerunJudge.moonBall(swing(dy: HomerunLaunch.fly.centerDY))
        let plan = result(ball)
        let contact = try #require(plan.contactAt)
        let list = cues(plan)
        #expect(sounds(list) == [.swing, .hitJust, .moonRise, .moonCrack])
        #expect(list.contains(HomerunSoundCue(at: contact.addingTimeInterval(HomerunMoonShot.impact), sound: .moonCrack)))
        #expect(!list.contains { $0.sound == .homerun })
    }

    @Test("たんこぶ: 詰まった音のあと、頭に当たる瞬間（20 コマ目から 2 秒）にゴツン")
    func tankobu() throws {
        var ball = HomerunJudge.judge(swing(dy: HomerunLaunch.pop.centerDY))
        ball.isTankobu = true
        ball.isJustMeet = false
        let plan = result(ball)
        let start = try #require(plan.tankobuStart)
        let list = cues(plan)
        #expect(sounds(list).contains(.hitWeak))
        #expect(list.contains(HomerunSoundCue(at: start.addingTimeInterval(HomerunTankobuGag.impactDelay), sound: .tankobu)))
    }

    @Test("空振り: 風切りとミット。回って倒れる演出のときだけ尻もちの音（座り込む前・結果のカードより前）")
    func whiff() throws {
        let miss = HomerunJudge.judge(swing(t: -200, dy: 0))
        #expect(miss.kind == .miss)
        #expect(sounds(cues(result(miss, offset: -200))) == [.swing, .mitt])
        let gag = cues(result(miss, offset: -200, whiffGag: true))
        let fall = try #require(gag.first { $0.sound == .fall }?.at)
        let release = arrival.addingTimeInterval(-0.2)
        #expect(fall > release.addingTimeInterval(1))
        #expect(fall < release.addingTimeInterval(HomerunWhiffGag.cardDelay))
    }

    @Test("見送り: 結果に入っても風切りは鳴らさず、ミットは投球中と同じ時刻（出し直しても 2 回鳴らない鍵になる）")
    func takenPitch() {
        let taken = HomerunJudge.judge(nil)
        let list = cues(result(taken, offset: nil))
        #expect(sounds(list) == [.mitt])
        let pitching = cues(HomerunSwingPlan(phase: .pitching, clock: HomerunModel.BallClock(pitchStart: t0, zone: 4), lastBall: nil))
        #expect(list.first?.at == pitching.first { $0.sound == .mitt }?.at)
    }

    @Test("10 球の結果: 最後の球で実績を解除したときだけ実績解禁。打席前は何も鳴らさない")
    func finishedAndIdle() {
        let finished = HomerunSwingPlan(phase: .finished, clock: nil, lastBall: nil)
        #expect(cues(finished, finish: true) == [HomerunSoundCue(at: t0, sound: .achievement)])
        #expect(cues(finished, finish: false).isEmpty)
        #expect(cues(HomerunSwingPlan(phase: .idle, clock: nil, lastBall: nil)).isEmpty)
    }

    @Test("最後の球で解除した実績は 10 球の結果へ持ち越して知らせる（打席の表示は出さずに終わる）")
    func modelFlagsUnlockAtFinish() throws {
        let defaults = UserDefaults(suiteName: "HomerunSoundCuesTests.\(UUID().uuidString)")!
        let model = HomerunModel(defaults: defaults, pitches: [HomerunPitch(zone: 4)], aimAssist: .off, now: t0)
        #expect(model.start(now: t0))
        model.atBatDidAppear(now: t0)
        let pitchStart = try #require(model.pitchStart)
        let at = pitchStart.addingTimeInterval(HomerunModel.travel)
        model.press(at: .zero, now: pitchStart)
        model.drag(to: CGPoint(x: 0, y: HomerunLaunch.liner.centerDY))
        _ = model.release(at: CGPoint(x: 0, y: HomerunLaunch.liner.centerDY), now: at)
        #expect(model.phase == .ballResult)
        model.advance(now: at.addingTimeInterval(60))
        #expect(model.phase == .finished)
        #expect(model.unlockedAtFinish, "1 球目の柵越え・初プレイの実績が最後の球で解除される")
    }
}
