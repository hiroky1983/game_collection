import Testing
import Foundation
import Core
import CoreTestSupport
import HomerunCore
@testable import GameHomerun

/// 実績（#1794）: 判定（純粋関数）・端末の記録・打席への表示・Game Center との突き合わせ。
@Suite("柵越えおじさんの実績")
@MainActor
struct HomerunAchievementTests {
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()
    /// 2027-01-15 12:00 JST。
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// 送信内容を溜め、解除済みの読み出しを差し替えられるスパイ。
    @MainActor
    private final class SpyService: GameCenterService {
        private(set) var reported: [GameCenterAchievement] = []
        var remote: Set<String>?
        func submit(_ score: GameCenterScore) {}
        func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) {
            reported += achievements
            completion(true)
        }
        func unlockedAchievementIDs() async -> Set<String>? { remote }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "asobiba.homerun.achievements.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeServices(_ spy: SpyService, signedIn: Bool = true) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: SpyFeedbackService(),
            gameCenter: GameCenterReporter(service: spy, allowedGameIDs: [HomerunModel.gameID], isAvailable: { signedIn })
        )
    }

    private func makeModel(_ services: GameServices?, defaults: UserDefaults,
                           pitches: [HomerunPitch] = [HomerunPitch(zone: 4), HomerunPitch(zone: 0)]) -> HomerunModel {
        HomerunModel(services: services, defaults: defaults, calendar: Self.calendar, pitches: pitches, aimAssist: .off,
                     now: Self.t0)
    }

    /// 押す → ボールの中心から (dx, dy) へずらす → `arrival + offset` 秒で離す。
    @discardableResult
    private func swing(_ model: HomerunModel, dx: Double = 0, dy: Double, offset: TimeInterval = 0) throws -> HomerunBattedBall? {
        let hit = try #require(model.arrival).addingTimeInterval(offset)
        let start = CGPoint(x: 150, y: 600)
        model.press(at: start)
        let ball = model.ballPoint
        let end = CGPoint(x: start.x + ball.x + dx - model.cursor.x, y: start.y + ball.y + dy - model.cursor.y)
        return model.release(at: end, now: hit)
    }

    private func swing(_ swing: HomerunSwing) -> HomerunBattedBall { HomerunJudge.judge(swing) }

    /// 月・ポールでない芯のジャスト（ボールの 8pt 下）。ふつうの柵越えで、ジャストミート・場外にもなる。
    private let justHomer = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: 8)

    // MARK: 判定

    @Test("柵越えで「はじめての柵越え」、空振り・ファウルでは何も解除されない")
    func firstHomer() {
        let homer = HomerunJudge.judge(justHomer)
        #expect(homer.kind == .homer)
        #expect(HomerunAchievement.earned(byBall: homer, outOfPark: false, whiffSpin: false).contains(.firstHomer))
        let miss = HomerunJudge.judge(nil)
        #expect(HomerunAchievement.earned(byBall: miss, outOfPark: false, whiffSpin: false).isEmpty)
    }

    @Test("ジャストミートで「ジャストミート」")
    func justMeet() {
        let ball = HomerunJudge.judge(justHomer)
        #expect(ball.isJustMeet)
        #expect(HomerunAchievement.earned(byBall: ball, outOfPark: false, whiffSpin: false).contains(.justMeet))
        let nice = HomerunJudge.judge(HomerunSwing(timingOffset: 40, cursorDX: 0, cursorDY: 8))
        #expect(!HomerunAchievement.earned(byBall: nice, outOfPark: false, whiffSpin: false).contains(.justMeet))
    }

    @Test("月まで飛ばすと「月まで飛ばした」。ポール直撃にも場外にもならない")
    func moon() {
        let ball = HomerunJudge.moonBall(HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY))
        let earned = HomerunAchievement.earned(byBall: ball, outOfPark: false, whiffSpin: false)
        #expect(earned.contains(.moon))
        #expect(earned.contains(.firstHomer), "月も柵越え")
        #expect(!earned.contains(.poleHit))
    }

    @Test("ポール直撃で「ポール直撃」")
    func pole() {
        let ball = HomerunJudge.forcedPoleBall(justHomer)
        #expect(HomerunAchievement.earned(byBall: ball, outOfPark: false, whiffSpin: false).contains(.poleHit))
        let plain = HomerunJudge.judge(justHomer)
        #expect(!HomerunAchievement.earned(byBall: plain, outOfPark: false, whiffSpin: false).contains(.poleHit))
    }

    @Test("場外・空振りの演出は呼び出し側が渡した事実のとおりに解除する")
    func passedFacts() {
        let ball = HomerunJudge.judge(justHomer)
        #expect(HomerunAchievement.earned(byBall: ball, outOfPark: true, whiffSpin: false).contains(.outOfPark))
        #expect(!HomerunAchievement.earned(byBall: ball, outOfPark: false, whiffSpin: false).contains(.outOfPark))
        let miss = HomerunJudge.judge(nil)
        #expect(HomerunAchievement.earned(byBall: miss, outOfPark: false, whiffSpin: true) == [.whiffSpin])
    }

    @Test("10 球すべて柵越えで「10球すべて柵越え」。1 球でも外せば解除されない")
    func allTen() {
        var perfect = HomerunChallenge()
        for _ in 0..<HomerunChallenge.pitchCount { perfect.swing(justHomer) }
        #expect(HomerunAchievement.earned(byFinished: perfect).contains(.allTenHomers))
        var one = HomerunChallenge()
        one.swing(nil)
        for _ in 1..<HomerunChallenge.pitchCount { one.swing(justHomer) }
        #expect(!HomerunAchievement.earned(byFinished: one).contains(.allTenHomers))
    }

    @Test("月が割れて 10 球に届かない挑戦は「10球すべて柵越え」にならない")
    func moonBrokenIsNotAllTen() {
        var c = HomerunChallenge()
        let moon = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY)
        c.swing(moon)
        c.swing(moon)
        #expect(c.isMoonBroken)
        #expect(!HomerunAchievement.earned(byFinished: c).contains(.allTenHomers))
    }

    @Test("合計が 1,500m を超えたときだけ「合計 1,500m 超え」")
    func farTotal() {
        var far = HomerunChallenge()
        for _ in 0..<HomerunChallenge.pitchCount { far.swing(justHomer) }
        #expect(far.totalDistance > HomerunAchievement.farTotalMeters)
        #expect(HomerunAchievement.earned(byFinished: far).contains(.farTotal))
        var near = HomerunChallenge()
        for _ in 0..<HomerunChallenge.pitchCount { near.swing(nil) }
        #expect(!HomerunAchievement.earned(byFinished: near).contains(.farTotal))
    }

    // MARK: 記録

    @Test("解除は新しく解除したものだけを返し、保存して読み戻せる。知らない値は持ち続ける")
    func logRoundTrip() throws {
        var log = HomerunAchievementLog()
        #expect(log.unlock([.moon, .moon, .justMeet]) == [.moon, .justMeet])
        #expect(log.unlock([.moon]).isEmpty, "解除済みは返さない")
        #expect(log.count == 2)
        let data = try JSONEncoder().encode(log)
        var restored = try JSONDecoder().decode(HomerunAchievementLog.self, from: data)
        #expect(restored == log)
        let future = try JSONDecoder().decode(HomerunAchievementLog.self, from: Data(#"["moon","someFutureOne"]"#.utf8))
        #expect(future.count == 1, "知らない実績は件数に入れない")
        #expect(String(decoding: try JSONEncoder().encode(future), as: UTF8.self).contains("someFutureOne"), "読み捨てない")
        restored.unlock([.poleHit])
        #expect(restored != log)
    }

    @Test("Game Center 側の解除済みとは和集合で合わせ、端末にだけあるものは送る対象になる")
    func mergeAndMissing() {
        var log = HomerunAchievementLog()
        log.unlock([.moon])
        let remote: Set<String> = [HomerunAchievement.poleHit.gameCenterID, "asobiba.achievement.firstwin"]
        #expect(log.missing(fromGameCenterIDs: remote) == [.moon])
        #expect(log.merge(gameCenterIDs: remote) == [.poleHit])
        #expect(log.contains(.moon) && log.contains(.poleHit))
        #expect(log.missing(fromGameCenterIDs: remote) == [.moon], "端末にあって向こうに無いものは変わらない")
    }

    @Test("実績 ID は Core の登録一覧と一致し、重複しない")
    func idsMatchCore() {
        #expect(HomerunAchievement.allCases.map(\.gameCenterID) == GameCenterAchievements.homerunIDs)
        #expect(Set(GameCenterAchievements.homerunIDs).count == GameCenterAchievements.homerunIDs.count)
        #expect(Set(GameCenterAchievements.homerunIDs).isDisjoint(with: GameCenterAchievements.allIDs))
    }

    // MARK: モデル

    @Test("柵越えを打つと端末に保存され、Game Center に連携していれば 100% で送られる")
    func modelSavesAndReports() throws {
        let defaults = makeDefaults()
        let spy = SpyService()
        let model = makeModel(makeServices(spy), defaults: defaults)
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try swing(model, dy: 8)
        #expect(model.achievements.contains(.firstHomer))
        #expect(model.achievements.contains(.justMeet))
        #expect(HomerunStorage.loadAchievements(defaults).contains(.firstHomer), "端末に保存される")
        #expect(spy.reported.contains(GameCenterAchievement(achievementID: HomerunAchievement.firstHomer.gameCenterID, percentComplete: 100)))
        // 2 本目でも、解除済みは二度送らない
        let count = spy.reported.count
        model.advance(now: try #require(model.resultUntil))
        model.atBatDidAppear(now: Self.t0)
        try swing(model, dy: 8)
        #expect(spy.reported.count == count)
    }

    @Test("連携していなくても端末には記録され、送信はしない")
    func modelWithoutGameCenter() throws {
        let defaults = makeDefaults()
        let spy = SpyService()
        let model = makeModel(makeServices(spy, signedIn: false), defaults: defaults)
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try swing(model, dy: 8)
        #expect(model.achievements.contains(.firstHomer))
        #expect(spy.reported.isEmpty)
        let reloaded = makeModel(nil, defaults: defaults)
        #expect(reloaded.achievements.contains(.firstHomer), "起動し直しても残る")
    }

    @Test("解禁の表示は 1 球の結果の演出が終わってから出て、一定時間で消える")
    func bannerAfterResult() throws {
        let model = makeModel(nil, defaults: makeDefaults())
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try swing(model, dy: 8)
        #expect(model.phase == .ballResult)
        #expect(model.unlockBanner(at: Self.t0).isEmpty, "結果の演出の間は出さない")
        let close = try #require(model.resultUntil)
        model.advance(now: close)
        #expect(model.phase == .pitching)
        #expect(Set(model.unlockBanner(at: close)) == [.firstHomer, .justMeet, .outOfPark])
        let end = close.addingTimeInterval(HomerunModel.unlockBannerDuration)
        #expect(model.unlockBanner(at: end).isEmpty, "一定時間で消える")
        #expect(model.unlockBannerOpacity(at: close) == 1)
        #expect(model.unlockBannerOpacity(at: end) == 0)
        #expect(model.nextWake == model.arrival?.addingTimeInterval(HomerunModel.lateLimit), "進行の待ちには関わらせない")
    }

    @Test("最後の球で解除したぶんは打席に出さず、結果の画面に並べる。次の挑戦では空に戻る")
    func lastBallGoesToResult() throws {
        let model = makeModel(nil, defaults: makeDefaults(), pitches: [HomerunPitch(zone: 4)])
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try swing(model, dy: 8)
        model.advance(now: try #require(model.resultUntil))
        #expect(model.phase == .finished)
        #expect(model.unlockBanner(at: Self.t0).isEmpty)
        #expect(Set(model.unlockedThisChallenge) == [.firstHomer, .justMeet, .outOfPark])
        model.backToLobby()
        model.start(now: Self.t0)
        #expect(model.unlockedThisChallenge.isEmpty)
    }

    @Test("10 球を打ち終えると挑戦単位の実績（10球すべて柵越え・合計超え）も保存と送信に載る")
    func finishedChallengeUnlocks() throws {
        let defaults = makeDefaults()
        let spy = SpyService()
        let pitches = Array(repeating: HomerunPitch(zone: 4), count: HomerunChallenge.pitchCount)
        let model = makeModel(makeServices(spy), defaults: defaults, pitches: pitches)
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        for _ in 0..<HomerunChallenge.pitchCount {
            try swing(model, dy: 8)
            model.advance(now: try #require(model.resultUntil))
            model.atBatDidAppear(now: Self.t0)
        }
        #expect(model.phase == .finished)
        #expect(model.achievements.contains(.allTenHomers))
        #expect(model.achievements.contains(.farTotal))
        #expect(HomerunStorage.loadAchievements(defaults).contains(.allTenHomers))
        #expect(spy.reported.map(\.achievementID).contains(HomerunAchievement.allTenHomers.gameCenterID))
        #expect(model.unlockedThisChallenge.contains(.allTenHomers))
    }

    @Test("空振りで回って倒れる演出が出たら「回って倒れた」を解除する")
    func whiffSpinUnlocks() throws {
        let model = makeModel(nil, defaults: makeDefaults())
        model.whiffGagRoll = { 0 }
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        // ボールから大きく外した振り = 空振り
        let ball = try swing(model, dy: 60)
        #expect(ball?.kind == .miss)
        #expect(model.showsWhiffGag)
        #expect(model.achievements.contains(.whiffSpin))
    }

    // MARK: Game Center との突き合わせ

    @Test("連携したとき、Game Center の解除済みを端末へ取り込み、端末にだけあるぶんを送る")
    func syncMergesBothWays() async {
        let defaults = makeDefaults()
        var local = HomerunAchievementLog()
        local.unlock([.moon])
        HomerunStorage.saveAchievements(local, defaults)
        let spy = SpyService()
        spy.remote = [HomerunAchievement.poleHit.gameCenterID]
        let model = makeModel(makeServices(spy), defaults: defaults)
        await model.syncGameCenterAchievements()
        #expect(model.gameCenterLinked)
        #expect(model.achievements.contains(.poleHit), "入れ直し・機種変更でも戻る")
        #expect(HomerunStorage.loadAchievements(defaults).contains(.poleHit), "取り込んだものは端末にも保存する")
        #expect(spy.reported.map(\.achievementID) == [HomerunAchievement.moon.gameCenterID], "あとから連携した人のそれまでの分を送る")
    }

    @Test("未連携・読めなかったときは何も変えない。未連携なら注意文の出し分け用に linked が false")
    func syncDoesNothingWhenUnavailable() async {
        let defaults = makeDefaults()
        let spy = SpyService()
        spy.remote = [HomerunAchievement.poleHit.gameCenterID]
        let signedOut = makeModel(makeServices(spy, signedIn: false), defaults: defaults)
        await signedOut.syncGameCenterAchievements()
        #expect(!signedOut.gameCenterLinked)
        #expect(signedOut.achievements.count == 0)
        #expect(spy.reported.isEmpty)

        spy.remote = nil
        let offline = makeModel(makeServices(spy), defaults: defaults)
        await offline.syncGameCenterAchievements()
        #expect(offline.gameCenterLinked)
        #expect(offline.achievements.count == 0)
        #expect(spy.reported.isEmpty)
    }

    @Test("注意文は連携していない人への案内として固定の文言")
    func unlinkedNotice() {
        #expect(HomerunAchievementsCard.unlinkedNotice.contains("Game Center と連携していないと"))
        #expect(HomerunAchievementsCard.unlinkedNotice.contains("消えます"))
    }
}
