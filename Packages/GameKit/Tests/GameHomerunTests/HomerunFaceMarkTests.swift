import Testing
import Foundation
@testable import HomerunCore
@testable import GameHomerun

/// 結果に応じて頭に重ねる記号（キラキラ目・怒りマーク・#1760）: 発生条件はモデル側の純粋な値で固定する。
@Suite("柵越えおじさんの頭の記号")
@MainActor
struct HomerunFaceMarkTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func ball(_ kind: HomerunKind, _ timing: HomerunTiming) -> HomerunBattedBall {
        HomerunBattedBall(direction: 0, distance: 0, kind: kind, timing: timing, launch: kind == .miss ? nil : .fly, fence: 100)
    }

    private func decide(_ kind: HomerunKind, _ timing: HomerunTiming, swung: Bool = true, gag: Bool = false,
                        streak: Int = 0, best: Bool = false) -> HomerunFaceMark {
        .decide(ball: ball(kind, timing), swung: swung, whiffGag: gag, whiffStreak: streak, isNewBest: best)
    }

    @Test("ジャストの当たり・柵越え・自己ベスト更新ではキラキラ目。ふつうの当たり・ファウル・見送りでは出ない")
    func sparkleRule() {
        #expect(decide(.inPlay, .just) == .sparkle)
        #expect(decide(.fenceHit, .just) == .sparkle)
        #expect(decide(.homer, .just) == .sparkle)
        #expect(decide(.homer, .hit) == .sparkle, "柵越えならジャストでなくても")
        #expect(decide(.inPlay, .nice, best: true) == .sparkle, "自己ベスト更新")
        #expect(decide(.inPlay, .nice) == .none)
        #expect(decide(.fenceHit, .hit) == .none)
        #expect(decide(.foul, .just) == .none, "ファウルはジャストでも出さない")
        #expect(decide(.foul, .nice, best: true) == .none)
        #expect(decide(.homer, .just, swung: false) == .none, "見送りは出さない")
        #expect(HomerunFaceMark.decide(ball: nil, swung: true, whiffGag: false, whiffStreak: 0, isNewBest: true) == .none)
    }

    @Test("空振りが 2 球連続以上で怒りマーク。ぐるぐる目の演出が出る球は怒りマークを重ねない")
    func angryRule() {
        #expect(HomerunFaceMark.angryStreak == 2)
        #expect(decide(.miss, .miss, streak: 1) == .none)
        #expect(decide(.miss, .miss, streak: 2) == .angry)
        #expect(decide(.miss, .nice, streak: 5) == .angry, "照準を外した空振りも空振り")
        #expect(decide(.miss, .miss, gag: true, streak: 2) == .none, "ぐるぐる目を優先")
        #expect(decide(.miss, .miss, gag: true, streak: 9) == .none)
        #expect(decide(.miss, .miss, swung: false, streak: 3) == .none, "見送りは出さない")
        #expect(decide(.inPlay, .hit, streak: 3) == .none, "当たりに怒りマークは付かない")
    }

    // MARK: モデル

    private func makeModel(roll: Double = 0.9) -> HomerunModel {
        let defaults = UserDefaults(suiteName: "HomerunFaceMarkTests.\(UUID())")!
        let model = HomerunModel(defaults: defaults, aimAssist: .off, now: Self.t0)
        model.whiffGagRoll = { roll }
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        return model
    }

    private func whiff(_ model: HomerunModel) throws {
        let release = try #require(model.arrival).addingTimeInterval(-0.3)
        model.press(at: CGPoint(x: 150, y: 600), now: release.addingTimeInterval(-0.2))
        #expect(model.release(at: CGPoint(x: 150, y: 600), now: release)?.kind == .miss)
    }

    private func hit(_ model: HomerunModel) throws {
        let release = try #require(model.arrival)
        model.press(at: CGPoint(x: 150, y: 600), now: release.addingTimeInterval(-0.5))
        let ball = model.ballPoint
        #expect(model.release(at: CGPoint(x: 150 + ball.x, y: 600 + ball.y + 4), now: release)?.kind != .miss)
    }

    private func take(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.nextWake))
    }

    private func next(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.nextWake))
        #expect(model.phase == .pitching)
    }

    @Test("連続の空振りを数える: 当たりで戻り、見送りは数えず戻しもしない。2 回目の空振りはぐるぐる目なので怒りは 3 球目から")
    func streakInModel() throws {
        let model = makeModel()
        try whiff(model)
        #expect(model.whiffStreak == 1 && model.faceMark == .none)
        try next(model)
        try take(model)
        #expect(model.whiffStreak == 1 && model.faceMark == .none, "見送りは数えず、戻しもしない")
        try next(model)
        try whiff(model)
        #expect(model.showsWhiffGag && model.whiffStreak == 2 && model.faceMark == .none, "ぐるぐる目を優先")
        try next(model)
        try whiff(model)
        #expect(!model.showsWhiffGag && model.whiffStreak == 3 && model.faceMark == .angry)
        try next(model)
        try hit(model)
        #expect(model.whiffStreak == 0)
        #expect(model.faceMark == .sparkle, "ジャストの当たり")
        try next(model)
        try whiff(model)
        #expect(model.whiffStreak == 1 && model.faceMark == .none, "当たりで連続は切れる")
    }

    @Test("挑戦をやり直すと連続の空振りも記号も消える")
    func resetOnNewChallenge() throws {
        let model = makeModel(roll: 0.9)
        try whiff(model)
        try next(model)
        try whiff(model)
        try next(model)
        try whiff(model)
        #expect(model.faceMark == .angry)
        model.pause(now: Self.t0.addingTimeInterval(100))
        model.quitChallenge()
        model.start(now: Self.t0.addingTimeInterval(100))
        #expect(model.whiffStreak == 0 && model.faceMark == .none)
    }

    @Test("判定は変えない: 記号の有無で飛距離・種別・結果の時間が変わらない")
    func judgementUnchanged() throws {
        let model = makeModel()
        try hit(model)
        let ball = try #require(model.lastBall)
        #expect(model.faceMark == .sparkle)
        #expect(ball.timing == .just)
        #expect(model.nextWake == model.resultUntil, "結果の時間は延ばさない")
    }

    // MARK: 見せる局面

    @Test("記号は結果の間だけ見せる")
    func shownOnlyDuringResult() {
        for phase in [HomerunModel.Phase.idle, .pitching, .finished] {
            #expect(HomerunSwingPlan(phase: phase, clock: nil, lastBall: nil, faceMark: .sparkle).faceMark == .none)
        }
        #expect(HomerunSwingPlan(phase: .ballResult, clock: nil, lastBall: nil, faceMark: .angry).faceMark == .angry)
    }

    @Test("記号の出始めはフォロースルーの頭（打点の後）、振り抜きの終わりより前")
    func appearTiming() {
        // どの列でも打点の窓が終わった後。
        let contact = (0..<3).map { HomerunSwingContact.contactWindow(column: $0).exit }.max() ?? 0
        let appear = (HomerunFaceMark.appearFrame - 1) / HomerunWhiffGag.frameRate
        #expect(appear > contact, "打点（\(contact) 秒）より後")
        #expect(appear < HomerunBatPath.duration, "振り終わりの前")
        #expect(HomerunFaceMark.appearGrow > 0 && HomerunFaceMark.pulse(since: 0, rate: 3, depth: 0.2) == 1)
    }
}
