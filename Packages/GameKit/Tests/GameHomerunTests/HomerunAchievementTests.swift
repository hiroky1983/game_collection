import Testing
import Foundation
import Core
import CoreTestSupport
import HomerunCore
@testable import GameHomerun
import GameKitTestSupport

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

    @Test("10 球の挑戦の合計が 1,500m を超えたときだけ「1 挑戦で 1,500m」")
    func farTotal() {
        var far = HomerunChallenge()
        for _ in 0..<HomerunChallenge.pitchCount { far.swing(justHomer) }
        #expect(far.totalDistance > HomerunAchievement.farTotalMeters)
        #expect(HomerunAchievement.earned(byFinished: far).contains(.farTotal))
        var near = HomerunChallenge()
        for _ in 0..<HomerunChallenge.pitchCount { near.swing(nil) }
        #expect(!HomerunAchievement.earned(byFinished: near).contains(.farTotal))
    }

    @Test("たんこぶになった球で「ゴツン！」。抽選に外れた同じ当たりでは解除されない")
    func tankobu() {
        let scrape = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunTankobu.scrapeFloor + 2)
        var hit = HomerunChallenge()
        let lump = hit.swing(scrape, tankobuRoll: 0)!
        #expect(lump.isTankobu)
        #expect(HomerunAchievement.earned(byBall: lump, outOfPark: false, whiffSpin: false).contains(.tankobu))
        var spared = HomerunChallenge()
        let plain = spared.swing(scrape, tankobuRoll: 0.99)!
        #expect(!plain.isTankobu)
        #expect(!HomerunAchievement.earned(byBall: plain, outOfPark: false, whiffSpin: false).contains(.tankobu))
    }

    @Test("同じ挑戦で月に 2 回当てて割れたら「月を割った」。1 回だけでは解除されない")
    func moonBroken() {
        let moon = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY)
        var once = HomerunChallenge()
        let first = once.swing(moon)!
        #expect(first.isMoon && !once.isMoonBroken)
        #expect(!HomerunAchievement.earned(byFinished: once).contains(.moonBroken))
        #expect(!HomerunAchievement.earned(byBall: first, outOfPark: false, whiffSpin: false).contains(.moonBroken))
        var twice = once
        twice.swing(moon)
        #expect(twice.isMoonBroken && twice.isFinished)
        #expect(HomerunAchievement.earned(byFinished: twice).contains(.moonBroken))
    }

    @Test("実績は 21 件。月の 2 つは隣り合い、末尾は 1 挑戦の距離 → 通算の距離 → 通算の柵越え本数の段階順")
    func listHas21() {
        let all = HomerunAchievement.allCases
        #expect(all.count == 21)
        let moon = all.firstIndex(of: .moon)!
        #expect(all[moon + 1] == .moonBroken)
        #expect(all.contains(.tankobu))
        #expect(Array(all.suffix(12)) == [.farTotal1000, .farTotal, .career3000, .career5000, .career8000,
                                           .career10000, .career50000, .career100000,
                                           .careerHomers10, .careerHomers30, .careerHomers50, .careerHomers100])
        #expect(all.compactMap(\.careerHomers) == [10, 30, 50, 100])
        #expect(all.compactMap(\.challengeMeters) == [1000, 1500])
        #expect(all.compactMap(\.careerMeters) == [3000, 5000, 8000, 10000, 50000, 100_000])
    }

    @Test("距離の実績の名前は 1 挑戦 / 通算が分かり、3 桁区切りで出る")
    func distanceTitles() {
        #expect(HomerunAchievement.farTotal1000.title == "1 挑戦で 1,000m")
        #expect(HomerunAchievement.farTotal.title == "1 挑戦で 1,500m")
        #expect(HomerunAchievement.career3000.title == "通算 3,000m")
        #expect(HomerunAchievement.career100000.title == "通算 100,000m")
        #expect(HomerunAchievement.farTotal1000.detail == "1 挑戦の合計飛距離が 1,000m を超えた")
        #expect(HomerunAchievement.career50000.detail == "これまでの飛距離の合計が 50,000m に届いた")
        #expect(HomerunAchievement.careerHomers10.title == "通算 柵越え 10本")
        #expect(HomerunAchievement.careerHomers100.title == "通算 柵越え 100本")
    }

    @Test("1 挑戦の合計: しきい値の手前・ちょうどでは解除されず、超えたら解除（1,000m・1,500m）")
    func challengeTotalThresholds() {
        #expect(HomerunAchievement.earned(byChallengeTotal: 999.9).isEmpty)
        #expect(HomerunAchievement.earned(byChallengeTotal: 1000).isEmpty)
        #expect(HomerunAchievement.earned(byChallengeTotal: 1000.1) == [.farTotal1000])
        #expect(HomerunAchievement.earned(byChallengeTotal: 1499.9) == [.farTotal1000])
        #expect(HomerunAchievement.earned(byChallengeTotal: 1500) == [.farTotal1000])
        #expect(HomerunAchievement.earned(byChallengeTotal: 1500.1) == [.farTotal1000, .farTotal])
    }

    @Test("通算: しきい値の手前では解除されず、ちょうど届いたら・超えたら解除（6 段階）")
    func careerThresholds() {
        let steps: [(HomerunAchievement, Int)] = [(.career3000, 3000), (.career5000, 5000), (.career8000, 8000),
                                                  (.career10000, 10000), (.career50000, 50000), (.career100000, 100_000)]
        for (achievement, meters) in steps {
            let tenths = meters * 10
            #expect(!HomerunAchievement.earned(byCareerTenths: tenths - 1).contains(achievement), "\(meters)m の手前")
            #expect(HomerunAchievement.earned(byCareerTenths: tenths).contains(achievement), "\(meters)m ちょうど")
            #expect(HomerunAchievement.earned(byCareerTenths: tenths + 1).contains(achievement), "\(meters)m 超え")
        }
        #expect(HomerunAchievement.earned(byCareerTenths: 0).isEmpty)
        #expect(HomerunAchievement.earned(byCareerTenths: 9_000 * 10) == [.career3000, .career5000, .career8000])
    }

    @Test("通算の柵越え本数: 手前では解除されず、ちょうど届いたら・超えたら解除（10・30・50・100 本）")
    func careerHomerThresholds() {
        let steps: [(HomerunAchievement, Int)] = [(.careerHomers10, 10), (.careerHomers30, 30),
                                                  (.careerHomers50, 50), (.careerHomers100, 100)]
        for (achievement, count) in steps {
            #expect(!HomerunAchievement.earned(byCareerHomers: count - 1).contains(achievement), "\(count) 本の手前")
            #expect(HomerunAchievement.earned(byCareerHomers: count).contains(achievement), "\(count) 本ちょうど")
            #expect(HomerunAchievement.earned(byCareerHomers: count + 1).contains(achievement), "\(count) 本超え")
        }
        #expect(HomerunAchievement.earned(byCareerHomers: 0).isEmpty)
        #expect(HomerunAchievement.earned(byCareerHomers: 49) == [.careerHomers10, .careerHomers30])
    }

    @Test("モデル: この版より前から累計が超えている人は、次に挑戦を終えたときにまとめて解除される")
    func careerFromExistingRecords() throws {
        let defaults = makeDefaults()
        var old = HomerunRecords()
        old.totalDistanceTenths = 12_000 * 10
        old.homers = 35
        HomerunStorage.saveRecords(old, defaults)
        let spy = SpyService()
        let model = makeModel(makeServices(spy), defaults: defaults, pitches: [HomerunPitch(zone: 4)])
        #expect(!model.achievements.contains(.career3000), "開いただけでは解除しない（挑戦を終えたとき）")
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        try swing(model, dy: 30) // 当たりが外れても累計はそのまま超えている
        #expect(model.challenge?.isFinished == true)
        for a in [HomerunAchievement.career3000, .career5000, .career8000, .career10000] {
            #expect(model.achievements.contains(a))
            #expect(model.unlockedThisChallenge.contains(a))
            #expect(spy.reported.map(\.achievementID).contains(a.gameCenterID))
        }
        #expect(!model.achievements.contains(.career50000))
        #expect(model.achievements.contains(.careerHomers10) && model.achievements.contains(.careerHomers30))
        #expect(!model.achievements.contains(.careerHomers50))
    }

    @Test("モデル: たんこぶの球は結果の演出が終わってから「実績解禁」に出て、Game Center に送る")
    func tankobuUnlocksThroughModel() throws {
        let defaults = makeDefaults()
        let spy = SpyService()
        let model = makeModel(makeServices(spy), defaults: defaults)
        model.tankobuRoll = { 0 }
        model.whiffGagRoll = { 0.9 }
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        let release = try #require(model.arrival)
        let ball = try #require(try swing(model, dy: HomerunTankobu.scrapeFloor + 2))
        #expect(ball.isTankobu)
        #expect(model.achievements.contains(.tankobu))
        #expect(spy.reported.map(\.achievementID).contains(HomerunAchievement.tankobu.gameCenterID))
        #expect(!model.unlockBanner(at: release).contains(.tankobu), "たんこぶの演出の間は出さない")
        let close = try #require(model.resultUntil)
        model.advance(now: close)
        #expect(model.unlockBanner(at: close).contains(.tankobu))
    }

    @Test("モデル: 2 回目の月で割れて挑戦が終わったとき「月を割った」が結果の画面に並ぶ")
    func moonBrokenUnlocksThroughModel() throws {
        let defaults = makeDefaults()
        let spy = SpyService()
        let model = makeModel(makeServices(spy), defaults: defaults,
                              pitches: [HomerunPitch(zone: 4), HomerunPitch(zone: 4), HomerunPitch(zone: 4)])
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        let first = try #require(try swing(model, dy: HomerunLaunch.fly.centerDY))
        #expect(first.isMoon)
        #expect(!model.achievements.contains(.moonBroken), "1 回目の月では割れない")
        model.advance(now: try #require(model.resultUntil))
        model.atBatDidAppear(now: Self.t0)
        let second = try #require(try swing(model, dy: HomerunLaunch.fly.centerDY))
        #expect(second.moon == .broken)
        #expect(model.challenge?.isFinished == true)
        #expect(model.achievements.contains(.moonBroken))
        #expect(model.unlockedThisChallenge.contains(.moonBroken))
        #expect(spy.reported.map(\.achievementID).contains(HomerunAchievement.moonBroken.gameCenterID))
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
        #expect(model.phase == .finale)
        model.advance(now: try #require(model.finaleUntil))
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
        #expect(model.phase == .finale)
        model.advance(now: try #require(model.finaleUntil))
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

    // MARK: 記録と実績のページ

    @Test("記録: 月の 2 行は 0 回のあいだ「？？？」で伏せ、1 回以上で回数を出す。行は常に 7 行")
    func recordsRowsHideMoonUntilFound() {
        let empty = HomerunRecordsCard.rows(HomerunRecords())
        #expect(empty.count == 7)
        #expect(empty.map(\.title).prefix(5) == ["自己ベスト（1 挑戦の合計）", "最長の 1 本", "通算の飛距離", "通算 柵越え", "挑戦回数"])
        #expect(empty.suffix(2).allSatisfy { $0.isHidden && $0.title == "？？？" && $0.value == "？？？" })

        let moon = HomerunSwing(timingOffset: 0, cursorDX: 0, cursorDY: HomerunLaunch.fly.centerDY)
        var once = HomerunChallenge()
        once.swing(moon)
        var r = HomerunRecords()
        r.record(once)
        let shot = HomerunRecordsCard.rows(r)
        #expect(shot[5] == HomerunRecordsCard.Row(title: "月まで飛ばした", value: "1 回"))
        #expect(shot[6].isHidden, "割れていなければ伏せたまま")

        var twice = HomerunChallenge()
        twice.swing(moon)
        twice.swing(moon)
        r.record(twice)
        let broken = HomerunRecordsCard.rows(r)
        #expect(broken[5] == HomerunRecordsCard.Row(title: "月まで飛ばした", value: "3 回"))
        #expect(broken[6] == HomerunRecordsCard.Row(title: "月を割った", value: "1 回"))
        #expect(broken[4].value == "2 回")
    }

    @Test("打席前は「記録と実績 ›」の 1 行で別ページへ。打席前に実績の一覧・きろくのカード・月の回数を並べない")
    func lobbyLinksToRecordsPage() throws {
        let view = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunView.swift"))
        #expect(view.contains("HomerunRecordsLink(model: model, ads: services.ads)"))
        #expect(!view.contains("HomerunAchievementsCard("))
        #expect(!view.contains("r.moonShots"))
        // きろく（自己ベスト・最長の 1 本・通算柵越え）は記録と実績のページだけ（会長指示 2026-10-04）。
        #expect(!view.contains("recordsCard"))
        #expect(!view.contains("Text(\"きろく\")"))
    }

    @Test("記録と実績のページは、記録と実績のあいだに 300×250 を 1 枠だけ置き、下の固定バナーは置かない（会長決裁 2026-10-04）")
    func recordsPageHasOneMediumRectangleBetweenCards() throws {
        let page = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameHomerun/HomerunRecordsPage.swift"))
        #expect(page.components(separatedBy: "MediumRectangleSlot(").count - 1 == 1, "広告は 1 枠")
        #expect(!page.contains("BannerSlot("), "このページは画面下の固定バナーを置かない")
        let records = try #require(page.range(of: "HomerunRecordsCard(records:"))
        let ad = try #require(page.range(of: "MediumRectangleSlot(ads: ads)"))
        let achievements = try #require(page.range(of: "HomerunAchievementsCard(model:"))
        #expect(records.lowerBound < ad.lowerBound && ad.lowerBound < achievements.lowerBound, "記録 → 広告 → 実績の順")
        #expect(page.contains(".padding(.vertical, HomerunRecordsAdGap.around)"), "広告の上下に余白（#1749）")
        #expect(HomerunRecordsAdGap.around >= 16)
        #expect(MediumRectangleSlot.size == CGSize(width: 300, height: 250), "読み込み前も 300×250 を確保する")
    }
}
