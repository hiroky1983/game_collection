import Testing
import Foundation
import Core
import CoreTestSupport
import HomerunCore
@testable import GameHomerun

/// 10 球後の結果の演出（会長決裁 2026-10-05）: 区分の判定・結果画面の前に挟む進行・評価のお願いの順序。
@Suite("柵越えおじさんの結果の演出")
@MainActor
struct HomerunFinaleTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeDefaults() -> UserDefaults {
        let suite = "asobiba.homerun.finale.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// 1 球だけの挑戦（最後の球 = 1 球目）。照準の吸い寄せは切る。
    private func makeModel(services: GameServices? = nil) -> HomerunModel {
        HomerunModel(services: services, defaults: makeDefaults(), calendar: Self.calendar,
                     pitches: [HomerunPitch(zone: 4)], aimAssist: .off, now: Self.t0)
    }

    /// 打席に立って、真ん中の球をボールの 4pt 下・ジャストで打つ（180 m の柵越え・#1647）。
    @discardableResult
    private func startAndHomer(_ model: HomerunModel) throws -> HomerunBattedBall? {
        #expect(model.start(now: Self.t0))
        model.atBatDidAppear(now: Self.t0)
        let hit = try #require(model.arrival)
        let start = CGPoint(x: 150, y: 600)
        model.press(at: start)
        let ball = model.ballPoint
        return model.release(at: CGPoint(x: start.x + ball.x, y: start.y + ball.y + 4), now: hit)
    }

    // MARK: 区分

    @Test("区分は柵越えの本数で決まる（0〜3 ドンマイ・4〜7 グッド・8〜9 エクセレント・10 パーフェクト）",
          arguments: [(0, HomerunFinale.donmai), (3, .donmai), (4, .good), (7, .good), (8, .excellent),
                      (9, .excellent), (10, .perfect)])
    func tierByHomers(homers: Int, expected: HomerunFinale) {
        #expect(HomerunFinale(homers: homers, moonBroken: false) == expected)
    }

    @Test("月が割れたら本数を問わず「月が割れた」（下敷きの絵）")
    func moonBrokenWins() {
        for homers in [0, 2, 4, 9, 10] {
            #expect(HomerunFinale(homers: homers, moonBroken: true) == .moonBroken)
        }
        #expect(HomerunFinale.moonBroken.title == "月が割れた！")
    }

    @Test("区分ごとに表示名と絵がある（絵はパッケージに入っていて読める）")
    func everyTierHasTitleAndArt() {
        let all: [HomerunFinale] = [.perfect, .excellent, .good, .donmai, .moonBroken]
        #expect(all.map(\.title) == ["パーフェクト！", "エクセレント！", "グッド！", "ドンマイ…", "月が割れた！"])
        for finale in all {
            let image = HomerunFinaleArt.image(finale.artName)
            #expect(image != nil, "\(finale.artName) が読めない")
            #expect(max(image?.width ?? 0, image?.height ?? 0) == 750, "長辺 750px")
        }
    }

    // MARK: 進行

    @Test("最後の球の結果を閉じたら、結果画面の前に演出を挟み、決まった時間で結果画面へ")
    func finaleBeforeResult() throws {
        let model = makeModel()
        #expect(model.start(now: Self.t0))
        model.atBatDidAppear(now: Self.t0)
        model.advance(now: try #require(model.nextWake))   // 見送り
        #expect(model.phase == .ballResult)
        let close = try #require(model.resultUntil)
        model.advance(now: close)
        #expect(model.phase == .finale)
        #expect(model.finale == .donmai)
        #expect(model.finaleStart == close)
        #expect(model.finaleUntil == close.addingTimeInterval(HomerunModel.finaleDuration))
        #expect(model.nextWake == model.finaleUntil)
        model.advance(now: close.addingTimeInterval(HomerunModel.finaleDuration - 0.1))
        #expect(model.phase == .finale, "時間までは演出のまま")
        model.advance(now: close.addingTimeInterval(HomerunModel.finaleDuration))
        #expect(model.phase == .finished)
        #expect(model.nextWake == nil)
        #expect(model.finaleUntil == nil)
    }

    @Test("タップで飛ばすと、すぐ結果画面へ。演出の間でなければ何もしない")
    func skipFinale() throws {
        let model = makeModel()
        #expect(model.start(now: Self.t0))
        model.atBatDidAppear(now: Self.t0)
        model.skipFinale()
        #expect(model.phase == .pitching)
        model.advance(now: try #require(model.nextWake))
        model.advance(now: try #require(model.resultUntil))
        #expect(model.phase == .finale)
        model.skipFinale()
        #expect(model.phase == .finished)
    }

    @Test("演出の間に止めたら、戻ったときに止めていた間ぶん後ろへずらす")
    func holdShiftsFinale() throws {
        let model = makeModel()
        #expect(model.start(now: Self.t0))
        model.atBatDidAppear(now: Self.t0)
        model.advance(now: try #require(model.nextWake))
        let close = try #require(model.resultUntil)
        model.advance(now: close)
        let until = try #require(model.finaleUntil)
        model.hold(.inactive, true, now: close.addingTimeInterval(1))
        #expect(model.nextWake == nil)
        model.hold(.inactive, false, now: close.addingTimeInterval(11))
        #expect(model.finaleUntil == until.addingTimeInterval(10))
        #expect(model.phase == .finale)
    }

    @Test("自己ベストを更新した挑戦は、演出の間にニューレコードを出す（isNewBest）")
    func newRecordDuringFinale() throws {
        let model = makeModel()
        let ball = try #require(try startAndHomer(model))
        #expect(ball.kind == .homer)
        model.advance(now: try #require(model.resultUntil))
        #expect(model.phase == .finale)
        #expect(model.finale == .donmai, "柵越え 1 本")
        #expect(model.isNewBest)
        #expect(HomerunFinaleView.accessibilityText(.donmai, homers: 1, total: 180, isNewBest: true)
                == "ドンマイ… 柵越え 1 本、合計 180 m、ニューレコード")
    }

    // MARK: 評価のお願い

    /// 次の 1 勝で評価のお願いの予定が立つ記録と、それを持つ評価リクエストの司令塔。
    private func makeReview() -> ReviewRequestService {
        let name = "asobiba.homerun.finale.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        for _ in 0..<(ReviewRequestPolicy.firstRequestWins - 1) { log.recordWin() }
        return ReviewRequestService(log: log, appVersion: "1.1.9", delay: .zero)
    }

    @Test("評価のお願いは、最後の球の結果と演出のあいだは伏せ、結果画面に移ってから出る")
    func reviewAfterFinale() throws {
        let review = makeReview()
        let model = makeModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), review: review))
        try startAndHomer(model)   // 柵越え 1 本 = 勝ち（予定が立つ）
        #expect(model.phase == .ballResult)
        #expect(review.isDeferredUntilResultIsVisible)
        #expect(review.pendingRequestID == nil, "最後の球の結果の間は出さない")
        model.advance(now: try #require(model.resultUntil))
        #expect(model.phase == .finale)
        #expect(review.pendingRequestID == nil, "演出の間は出さない")
        model.advance(now: try #require(model.finaleUntil))
        #expect(model.phase == .finished)
        #expect(!review.isDeferredUntilResultIsVisible)
        #expect(review.pendingRequestID != nil, "結果画面に移ってから出る")
    }

    @Test("演出をタップで飛ばしても、結果画面に移った時点で評価のお願いが出る")
    func reviewAfterSkippedFinale() throws {
        let review = makeReview()
        let model = makeModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), review: review))
        try startAndHomer(model)
        model.advance(now: try #require(model.resultUntil))
        #expect(review.pendingRequestID == nil)
        model.skipFinale()
        #expect(review.pendingRequestID != nil)
    }
}
