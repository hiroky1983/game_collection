import Testing
import Foundation
import Core
import HomerunCore
@testable import GameHomerun

/// 図で見る「はじめての遊び方」（#2826）の図と文言が、実装のルールのとおりになっていること。
@MainActor
@Suite("柵越えおじさん: はじめての遊び方")
struct HomerunOnboardingTests {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    /// 2027-01-15 12:00 JST。
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(_ name: String) -> HomerunModel {
        let suite = "asobiba.homerun.onboarding.tests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return HomerunModel(defaults: defaults, calendar: Self.calendar, aimAssist: .off,
                            weeklyLeaderboardID: nil, now: Self.t0)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(HomerunOnboarding.guide.isWellFormed)
        #expect(HomerunOnboarding.guide.gameID == HomerunModel.gameID)
        #expect(HomerunOnboarding.guide.gameID == HomerunModule().id)
    }

    @Test("目的: 1 回の挑戦は 10 球で、記録は 10 球の合計飛距離")
    func tenPitches() {
        #expect(HomerunChallenge.pitchCount == 10)
        #expect(HomerunPitch.standardSequence.count == 10)
        var challenge = HomerunChallenge()
        let swings = [HomerunOnboarding.homerSwing, HomerunOnboarding.foulSwing, HomerunOnboarding.missSwing]
        var balls: [HomerunBattedBall] = []
        for index in 0..<HomerunChallenge.pitchCount {
            #expect(!challenge.isFinished)
            if let ball = challenge.swing(swings[index % swings.count]) { balls.append(ball) }
        }
        #expect(challenge.isFinished, "10 球で終わる")
        #expect(balls.count == HomerunChallenge.pitchCount)
        // 自己ベストに入るのは 10 球の合計（柵越え 4 本 = 1 本の飛距離の 4 倍。ファウル・空振りは 0 m）。
        let homer = HomerunJudge.judge(HomerunOnboarding.homerSwing).distance
        var records = HomerunRecords()
        records.record(challenge)
        #expect(records.bestTotalTenths == Int((homer * 4 * 10).rounded()))
    }

    @Test("ねらう: 押したままずらすと、ミートカーソルが指の動いたぶんだけ動く")
    func cursorFollowsFinger() {
        let model = makeModel("cursor")
        #expect(model.start(now: Self.t0))
        #expect(model.cursor == .zero)
        model.press(at: CGPoint(x: 100, y: 500))
        model.drag(to: CGPoint(x: 106, y: 504))
        #expect(model.cursor == CGPoint(x: 6, y: 4))
    }

    @Test("振る: 輪が的に重なった瞬間に近いほど遠くへ飛び、早すぎ・遅すぎは空振り")
    func timingDecidesDistance() {
        func ball(_ offset: Double) -> HomerunBattedBall {
            HomerunJudge.judge(HomerunSwing(timingOffset: offset, cursorDX: 0, cursorDY: 6))
        }
        #expect(ball(0).distance > ball(50).distance)
        #expect(ball(50).distance > ball(100).distance)
        #expect(ball(100).kind != .miss)
        #expect(ball(-150).kind == .miss)
        #expect(ball(150).kind == .miss)
        #expect(HomerunJudge.missReason(HomerunSwing(timingOffset: -150, cursorDX: 0, cursorDY: 6)) == .early)
        #expect(HomerunJudge.missReason(HomerunSwing(timingOffset: 150, cursorDX: 0, cursorDY: 6)) == .late)
    }

    @Test("角度と方向: ボールの少し下で打つと上がる。左右と離す早さで方向が決まり、寄せすぎるとファウル")
    func launchAndDirection() {
        #expect(HomerunLaunch(cursorDY: 6) == .fly, "ボールの少し下はフライ")
        #expect(HomerunLaunch(cursorDY: -20) == .grounder, "ボールより上はゴロ")
        #expect(HomerunLaunch.angle(cursorDY: 6) > HomerunLaunch.angle(cursorDY: -20))
        let left = HomerunJudge.direction(HomerunSwing(timingOffset: 0, cursorDX: -5, cursorDY: 6))
        let right = HomerunJudge.direction(HomerunSwing(timingOffset: 0, cursorDX: 5, cursorDY: 6))
        #expect(left < 0 && right > 0, "カーソルの左右で向きが変わる")
        let early = HomerunJudge.direction(HomerunSwing(timingOffset: -50, cursorDX: 0, cursorDY: 6))
        let late = HomerunJudge.direction(HomerunSwing(timingOffset: 50, cursorDX: 0, cursorDY: 6))
        #expect(early < 0 && late > 0, "離す早さで向きが変わる")
        let foul = HomerunJudge.judge(HomerunOnboarding.foulSwing)
        #expect(foul.kind == .foul)
        #expect(abs(HomerunJudge.direction(HomerunOnboarding.foulSwing)) > HomerunJudge.foulLimit)
    }

    @Test("記録の図: 柵越えの 1 球は飛距離が付き、ファウル・空振り・見送りは 0 m")
    func resultFigure() {
        let homer = HomerunJudge.judge(HomerunOnboarding.homerSwing)
        #expect(homer.kind == .homer)
        #expect(homer.distance >= homer.fence)
        #expect(!HomerunJudge.isMoonShot(HomerunOnboarding.homerSwing), "隠し演出（月）の条件には入らない")
        #expect(!homer.isPoleHit)
        let foul = HomerunJudge.judge(HomerunOnboarding.foulSwing)
        #expect(foul.kind == .foul && foul.distance == 0)
        let miss = HomerunJudge.judge(HomerunOnboarding.missSwing)
        #expect(miss.kind == .miss && miss.distance == 0)
        let taken = HomerunJudge.judge(nil)
        #expect(taken.kind == .miss && taken.distance == 0, "見送りも 0 m")
        // 1 挑戦の中で振っても同じ結果（月・たんこぶにならない）。
        var challenge = HomerunChallenge()
        let inChallenge = [HomerunOnboarding.homerSwing, HomerunOnboarding.foulSwing, HomerunOnboarding.missSwing]
            .map { challenge.swing($0) }
        #expect(inChallenge == [homer, foul, miss])
    }

    @Test("回数: 1 日 3 回。打席に立った時点で 1 回減り、0:00 に戻る。0 回のときだけ広告で 1 回（上限あり）")
    func dailyAllowance() {
        #expect(HomerunLedger.freePerDay == 3)
        #expect(HomerunLedger.adLimitPerDay != nil, "広告で遊べる本数には上限がある")
        let model = makeModel("daily")
        #expect(model.ledger.remaining == 3)
        #expect(model.start(now: Self.t0))
        #expect(model.ledger.remaining == 2, "打席に立った時点で減る")

        var ledger = HomerunLedger(dayKey: HomerunLedger.dayKey(for: Self.t0, calendar: Self.calendar))
        #expect(!ledger.canPlayWithAd, "回数が残っているあいだは広告で遊ばない")
        for _ in 0..<HomerunLedger.freePerDay {
            let consumed = ledger.consume()
            #expect(consumed)
        }
        #expect(ledger.remaining == 0)
        let overConsumed = ledger.consume()
        #expect(!overConsumed)
        #expect(ledger.canPlayWithAd)
        let adPlay = ledger.consumeAdPlay()
        #expect(adPlay)
        #expect(ledger.remaining == 0, "広告で遊んでも回数は増えない")
        let tomorrow = Self.calendar.date(byAdding: .day, value: 1, to: Self.calendar.startOfDay(for: Self.t0))!
        ledger.roll(to: HomerunLedger.dayKey(for: tomorrow, calendar: Self.calendar))
        #expect(ledger.remaining == HomerunLedger.freePerDay, "0:00 に 3 回へ戻る")
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let figureTexts = ["空振り・ファウルは 0 m", "柵越え！", "ファウル", "空振り", "10 球の合計飛距離が記録",
                           "少し下で打つと上がる", "打席に立つと 1 回減る", "0:00 に 3 回に戻る"]
        for text in HomerunOnboarding.guide.texts + figureTexts {
            #expect(GameHomerun.tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
