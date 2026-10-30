import Testing
import Foundation
import Core
import Game2048
import GameShogi
import GameGomoku
import GameMinesweeper
import GameOthello
import GamePoker
import GameConcentration
import GameBlackjack
import GameDaifugo
import GameMahjongSolitaire
import GameMahjong
import GameSudoku
import GameGo
import GameSolitaire
import GameFreeCell
import GameRunner
import GameHanafuda
@testable import GameShiritori
import GameSpider
import GameChess
import MahjongTiles
import CoreTestSupport
import GameRunnerTestSupport

// MARK: - 共通のヘルパー

private let appVersion = "1.1.1"

/// テスト専用の UserDefaults を作る。テストごとに違う suite 名を渡すこと（並列実行のため）。
@MainActor
private func makeLog(suite: String) -> (PlayLog, UserDefaults, String) {
    let name = "asobiba.review.tests.\(suite)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (PlayLog(defaults: defaults), defaults, name)
}

/// 各ゲームの Model に渡す services と、そこに載せた評価リクエストサービス。
/// 遅延は 0 にして「呼ばれるかどうか」だけを見る（遅延そのものは別 Suite で検証する）。
@MainActor
private func makeServices(
    suite: String,
    now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) },
    delay: Duration = .zero
) -> (GameServices, ReviewRequestService) {
    let (log, _, _) = makeLog(suite: suite)
    let service = ReviewRequestService(log: log, appVersion: appVersion, now: now, delay: delay)
    let services = GameServices(
        snapshots: MemorySnapshotStore(),
        ads: NoopAdService(),
        review: service
    )
    return (services, service)
}

/// 勝利を n 回積む（判定条件を満たすところまで空回しする用）。
@MainActor
private func advanceWins(_ service: ReviewRequestService, count: Int) {
    for _ in 0..<count { service.gameDidFinish(outcome: .win) }
}

// MARK: - 発火条件（条件2〜5）

@Suite("評価リクエストの発火条件")
@MainActor
struct ReviewRequestPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("条件2: 4勝までは出ず、5勝目で初回が出る")
    func firstRequestAtFiveWins() {
        for wins in 0...4 {
            let state = ReviewRequestState(totalWins: wins)
            #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: appVersion, now: now) == false,
                    "\(wins)勝では出さない")
        }
        #expect(ReviewRequestPolicy.shouldRequest(
            state: ReviewRequestState(totalWins: 5), currentVersion: appVersion, now: now) == true)
    }

    @Test("条件3: 前回から15日経つまで出ない（#1471 で120日→60日、#3061 で15日）")
    func minimumElapsed() {
        func state(_ elapsed: TimeInterval) -> ReviewRequestState {
            .init(totalWins: 100, lastRequestedAt: now.addingTimeInterval(-elapsed),
                  lastRequestedWins: 5, lastRequestedVersion: "1.1.0")
        }
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(14 * 24 * 3600), currentVersion: appVersion, now: now) == false)
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(15 * 24 * 3600), currentVersion: appVersion, now: now) == true)
        #expect(ReviewRequestPolicy.minimumElapsed == 15 * 24 * 3600)
    }

    @Test("条件4: 前回から+5勝するまで出ない（#3061 で20勝から短縮）")
    func minimumWinsSinceLast() {
        let longAgo = now.addingTimeInterval(-ReviewRequestPolicy.minimumElapsed * 3)
        func state(_ total: Int) -> ReviewRequestState {
            .init(totalWins: total, lastRequestedAt: longAgo,
                  lastRequestedWins: 5, lastRequestedVersion: "1.1.0")
        }
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(9), currentVersion: appVersion, now: now) == false, "+4勝では出ない")
        #expect(ReviewRequestPolicy.shouldRequest(
            state: state(10), currentVersion: appVersion, now: now) == true, "+5勝で出る")
    }

    @Test("条件5: 同一バージョンでは期間・勝利数を満たしても2回目が出ない")
    func onceOverVersion() {
        let longAgo = now.addingTimeInterval(-ReviewRequestPolicy.minimumElapsed * 10)
        let state = ReviewRequestState(
            totalWins: 1_000, lastRequestedAt: longAgo,
            lastRequestedWins: 5, lastRequestedVersion: appVersion
        )
        #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: appVersion, now: now) == false)
        #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: "1.2.0", now: now) == true,
                "バージョンが上がれば条件3・4を満たしていれば出る")
    }

    @Test("端末の時計が巻き戻っていても出ない（条件3を満たさない扱い）")
    func clockWentBackwards() {
        let state = ReviewRequestState(
            totalWins: 1_000, lastRequestedAt: now.addingTimeInterval(60 * 60),
            lastRequestedWins: 5, lastRequestedVersion: "1.1.0"
        )
        #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: appVersion, now: now) == false)
    }
}

// MARK: - サービス（記録と1回だけの発火）

@Suite("評価リクエストの記録と発火")
@MainActor
struct ReviewRequestServiceTests {

    @Test("条件1: 敗北・引き分けでは勝利数が増えず、リクエストも予定されない")
    func ignoresNonWins() {
        let (_, service) = makeServices(suite: "service-non-win")
        for _ in 0..<50 {
            service.gameDidFinish(outcome: .loss)
            service.gameDidFinish(outcome: .draw)
        }
        #expect(service.log.totalWins == 0, "勝利以外は1回も数えない")
        #expect(service.pendingRequestID == nil, "何回負けてもリクエストしない")
    }

    @Test("4勝目までは予定されず、5勝目で予定される")
    func pendsOnFifthWin() {
        let (_, service) = makeServices(suite: "service-fifth")
        advanceWins(service, count: 4)
        #expect(service.pendingRequestID == nil)
        service.gameDidFinish(outcome: .win)
        #expect(service.pendingRequestID != nil)
    }

    @Test("呼んだ時点で記録され、直後の勝利では再度呼ばれない")
    func recordsOnCallAndStopsRepeating() async {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (_, service) = makeServices(suite: "service-record", now: { clock })
        var requested = 0

        advanceWins(service, count: 5)
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)
        #expect(service.pendingRequestID == nil)
        #expect(service.log.reviewState.lastRequestedAt == clock, "呼んだ時点を記録する")
        #expect(service.log.reviewState.lastRequestedWins == 5)
        #expect(service.log.reviewState.lastRequestedVersion == appVersion)

        // 同じバージョン・同じ日のまま勝ち続けても二度と呼ばれない（条件3〜5）。
        for _ in 0..<200 {
            service.gameDidFinish(outcome: .win)
            await service.performPendingRequest { requested += 1 }
        }
        #expect(requested == 1, "生涯で1回に収まっている（実際: \(requested)）")
        #expect(service.log.totalWins == 205, "勝利数の記録自体は続く")
    }

    @Test("2回目は15日以上かつ+5勝を満たしたときだけ呼ばれる")
    func secondRequestNeedsBothGates() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (log, _, _) = makeLog(suite: "service-second")
        var version = "1.1.1"
        let service = ReviewRequestService(
            log: log, appVersion: version, now: { clock }, delay: .zero
        )
        var requested = 0

        advanceWins(service, count: 5)
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)

        // 15日経過するが +5勝には届かない（+4勝）。
        clock = clock.addingTimeInterval(ReviewRequestPolicy.minimumElapsed)
        version = "1.1.2"
        let afterVersionUp = ReviewRequestService(
            log: log, appVersion: version, now: { clock }, delay: .zero
        )
        advanceWins(afterVersionUp, count: 4)
        await afterVersionUp.performPendingRequest { requested += 1 }
        #expect(requested == 1, "+4勝では出ない")

        afterVersionUp.gameDidFinish(outcome: .win) // +5勝目
        await afterVersionUp.performPendingRequest { requested += 1 }
        #expect(requested == 2, "15日 + 5勝の両方を満たして2回目")
    }

    @Test("バージョンが上がっても15日経っていなければ出ない")
    func versionUpAloneIsNotEnough() async {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let (log, _, _) = makeLog(suite: "service-version-up")
        let first = ReviewRequestService(log: log, appVersion: "1.1.1", now: { clock }, delay: .zero)
        var requested = 0
        advanceWins(first, count: 5)
        await first.performPendingRequest { requested += 1 }
        #expect(requested == 1)

        clock = clock.addingTimeInterval(7 * 24 * 3600) // 7日後（15日未満）に新バージョン
        let second = ReviewRequestService(log: log, appVersion: "1.2.0", now: { clock }, delay: .zero)
        advanceWins(second, count: 100)
        await second.performPendingRequest { requested += 1 }
        #expect(requested == 1, "期間の歯止めはバージョン更新で解除されない")
    }
}

// MARK: - 見せ場（#1471）

@Suite("評価リクエストの見せ場")
@MainActor
struct ReviewHighlightTests {

    @Test("見せ場でない勝ちは勝利数に数えるが、5勝目でも予定を立てない")
    func nonHighlightWinsCountButDoNotPend() {
        let (_, service) = makeServices(suite: "highlight-non")
        for _ in 0..<10 { service.gameDidFinish(outcome: .win, isHighlight: false) }
        #expect(service.log.totalWins == 10, "勝利数は見せ場でなくても数える")
        #expect(service.pendingRequestID == nil)

        #expect(service.gameDidFinish(outcome: .win, isHighlight: true))
        #expect(service.pendingRequestID != nil, "見せ場の勝ちで初めて予定が立つ")
    }

    @Test("見せ場でも敗北では予定を立てない")
    func highlightLossDoesNothing() {
        let (_, service) = makeServices(suite: "highlight-loss")
        advanceWins(service, count: 4)
        #expect(service.gameDidFinish(outcome: .loss, isHighlight: true) == false)
        #expect(service.pendingRequestID == nil)
    }

    /// 記録つきの services（自己ベストの更新を見せ場にできる構成）。
    private func makeRecordingServices(suite: String) -> (GameServices, ReviewRequestService) {
        let (log, _, _) = makeLog(suite: suite)
        let service = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), review: service, playLog: log
        )
        return (services, service)
    }

    @Test("見せ場でない勝ちでも、得点の自己ベストを更新した回は見せ場になる")
    func newBestIsAHighlight() {
        let (services, service) = makeRecordingServices(suite: "highlight-best")
        for _ in 0..<4 {
            services.gameDidFinish(gameID: "g", outcome: .win,
                                   score: GameScore(metric: .points, points: 10), isReviewHighlight: false)
        }
        // 4勝目までは自己ベスト 10 のまま。5勝目で同点（更新ではない）。
        services.gameDidFinish(gameID: "g", outcome: .win,
                               score: GameScore(metric: .points, points: 10), isReviewHighlight: false)
        #expect(service.log.totalWins == 5)
        #expect(service.pendingRequestID == nil, "同点は更新ではないので見せ場でない")

        services.gameDidFinish(gameID: "g", outcome: .win,
                               score: GameScore(metric: .points, points: 50), isReviewHighlight: false)
        #expect(service.pendingRequestID != nil, "自己ベスト更新は全ゲーム共通で見せ場")
    }

    @Test("3 連勝は CPU の強さを問わず見せ場。4 連勝目は見せ場でない（#3097）")
    func threeWinStreakIsAHighlightOnlyOnce() {
        // 3 連勝に達する回で通算 5 勝になるよう、勝利数を 2 勝ぶん先に積んでおく。
        let (services, service) = makeRecordingServices(suite: "highlight-streak3")
        service.log.recordWin(); service.log.recordWin()
        for _ in 0..<2 {
            services.gameDidFinish(gameID: "g", outcome: .win, score: GameScore(metric: .winLoss), isReviewHighlight: false)
        }
        #expect(service.log.totalWins == 4)
        #expect(service.pendingRequestID == nil, "2 連勝までは見せ場でない")
        services.gameDidFinish(gameID: "g", outcome: .win, score: GameScore(metric: .winLoss), isReviewHighlight: false)
        #expect(service.log.totalWins == 5)
        #expect(service.pendingRequestID != nil, "ちょうど 3 連勝に達した回は見せ場")

        // 4 連勝目以降は見せ場にしない（3 連勝に達した時点では通算 5 勝に届かない流れで、5 連勝まで確かめる）。
        let (services2, service2) = makeRecordingServices(suite: "highlight-streak4")
        for _ in 0..<5 {
            services2.gameDidFinish(gameID: "g", outcome: .win, score: GameScore(metric: .winLoss), isReviewHighlight: false)
        }
        #expect(service2.log.totalWins == 5)
        #expect(service2.pendingRequestID == nil, "4・5 連勝目は見せ場でない")
    }

    @Test("連勝が途切れたら数え直し、3 連勝は 3 に戻ったときだけ")
    func brokenStreakRestarts() {
        let (services, service) = makeRecordingServices(suite: "highlight-streak-broken")
        for _ in 0..<5 { service.log.recordWin() }
        for outcome in [GameOutcome.win, .win, .loss, .win, .win] {
            services.gameDidFinish(gameID: "g", outcome: outcome, score: GameScore(metric: .winLoss), isReviewHighlight: false)
        }
        #expect(service.pendingRequestID == nil, "2 連勝・負け・2 連勝では 3 連勝にならない")
    }

    // MARK: 実績の新規達成（#3097）

    private func makeAchievementServices(
        suite: String, signedIn: Bool = true, priorWins: Int
    ) -> (GameServices, ReviewRequestService) {
        let (log, _, _) = makeLog(suite: suite)
        for _ in 0..<priorWins { log.recordWin() }
        let service = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        // 2 本登録にして、1 本遊んだだけでは「全ゲーム制覇」（playAll）に届かないようにする。
        let reporter = GameCenterReporter(service: NoopGameCenterService(), allowedGameIDs: ["g", "h"], isAvailable: { signedIn })
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), review: service, playLog: log, gameCenter: reporter
        )
        return (services, service)
    }

    private struct NoopGameCenterService: GameCenterService {
        func submit(_ score: GameCenterScore) {}
        func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
    }

    @Test("実績を新たに解除した決着は見せ場（通算 10 勝目）")
    func newAchievementIsAHighlight() {
        let (services, service) = makeAchievementServices(suite: "highlight-ach", priorWins: 9)
        // 9 勝済みの状態で 10 勝目（wins10 を初めて満たす）。連勝は 1 で、3 連勝でも自己ベストでもない。
        services.gameDidFinish(gameID: "g", outcome: .win, score: GameScore(metric: .winLoss), isReviewHighlight: false)
        #expect(service.pendingRequestID != nil)
    }

    @Test("達成済みの実績の再送は見せ場でない")
    func alreadyUnlockedAchievementIsNotAHighlight() {
        let (services, service) = makeAchievementServices(suite: "highlight-ach-already", priorWins: 10)
        services.gameDidFinish(gameID: "g", outcome: .win, score: GameScore(metric: .winLoss), isReviewHighlight: false)
        #expect(service.log.totalWins == 11)
        #expect(service.pendingRequestID == nil)
    }

    @Test("Game Center に未サインインなら、実績の達成は見せ場にしない")
    func achievementNeedsSignIn() {
        let (services, service) = makeAchievementServices(suite: "highlight-ach-signedout", signedIn: false, priorWins: 9)
        services.gameDidFinish(gameID: "g", outcome: .win, score: GameScore(metric: .winLoss), isReviewHighlight: false)
        #expect(service.pendingRequestID == nil)
    }

    @Test("実績の新規達成の判定: 勝利でない決着は勝利数の実績を解除しない・既達成は数えない")
    func unlocksAnyIsPure() {
        func unlocks(_ before: Int, _ after: Int, played: (Int, Int) = (0, 0), registered: Int = 12) -> Bool {
            GameCenterAchievements.unlocksAny(
                totalWinsBefore: before, totalWinsAfter: after,
                playedGameCountBefore: played.0, playedGameCountAfter: played.1, registeredGameCount: registered)
        }
        #expect(unlocks(0, 1), "初勝利")
        #expect(unlocks(9, 10))
        #expect(unlocks(49, 50))
        #expect(unlocks(10, 11) == false)
        #expect(unlocks(9, 9) == false, "負けは勝利数が増えない")
        #expect(unlocks(5, 5, played: (11, 12)), "最後の 1 本を初めて遊ぶと playAll")
        #expect(unlocks(5, 5, played: (12, 12)) == false)
        #expect(unlocks(5, 5, played: (4, 5)) == false)
    }

    @Test("既定（勝てば見せ場）のゲームは従来どおり5勝目で予定される")
    func defaultIsHighlight() {
        let (services, service) = makeRecordingServices(suite: "highlight-default")
        for _ in 0..<5 { services.gameDidFinish(gameID: "g", outcome: .win) }
        #expect(service.pendingRequestID != nil)
    }

    @Test("CPU の強さ: ふつう以上だけが見せ場")
    func cpuStrengthWorthiness() {
        #expect(CPUStrength.isReviewWorthy(level: CPUStrength.novice.rawValue) == false)
        #expect(CPUStrength.isReviewWorthy(level: CPUStrength.easy.rawValue) == false)
        #expect(CPUStrength.isReviewWorthy(level: CPUStrength.normal.rawValue))
        #expect(CPUStrength.isReviewWorthy(level: CPUStrength.hard.rawValue))
    }

    @Test("ブラックジャック: ブラックジャックで勝った回を含む勝ち越しで予定され、普通の勝ち越しでは予定されない（#2552）")
    func blackjackNaturalOnly() throws {
        func run(seed: UInt64, suite: String) -> (BlackjackModel, ReviewRequestService, hadNatural: Bool) {
            let (services, service) = makeServices(suite: suite)
            advanceWins(service, count: 4)
            // 自己ベストの更新も見せ場になるので、届かない点を先に記録しておく（10 回で最大 20 点）。
            service.log.recordResult(gameID: "blackjack", outcome: .loss,
                                     score: GameScore(metric: .points, points: 20, variant: "match10"))
            let model = BlackjackModel(services: services, seed: seed)
            var hadNatural = false
            model.deal()
            for _ in 0..<20 where !model.matchOver {
                while model.phase == .playerTurn { model.stand() }
                if model.outcome == .playerBlackjack { hadNatural = true }
                if !model.matchOver { model.nextRound() }
            }
            return (model, service, hadNatural)
        }
        var natural: (BlackjackModel, ReviewRequestService)?
        var plain: (BlackjackModel, ReviewRequestService)?
        for seed in 0..<3000 as Range<UInt64> where natural == nil || plain == nil {
            let (model, service, hadNatural) = run(seed: seed, suite: "highlight-bj-\(seed)")
            guard model.matchOutcome == .win else { continue }
            if hadNatural, natural == nil { natural = (model, service) }
            if !hadNatural, plain == nil { plain = (model, service) }
        }
        let n = try #require(natural)
        let p = try #require(plain)
        #expect(n.1.pendingRequestID != nil, "ブラックジャックの勝ちは見せ場")
        #expect(p.1.log.totalWins == 5)
        #expect(p.1.pendingRequestID == nil, "普通の勝ちは見せ場でない")
    }
}

// MARK: - 条件6（リザルトの1.0秒後・進行中には呼ばない）

@Suite("評価リクエストの表示タイミング")
@MainActor
struct ReviewRequestTimingTests {

    @Test("既定では即時に呼ばれない（リザルト表示の1.0秒後）")
    func doesNotFireImmediately() async {
        let (log, _, _) = makeLog(suite: "timing-default")
        let service = ReviewRequestService(log: log, appVersion: appVersion) // 既定 = 1.0秒
        advanceWins(service, count: 5)

        var requested = 0
        let task = Task { await service.performPendingRequest { requested += 1 } }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(requested == 0, "1.0秒経つ前には呼ばない")
        task.cancel()
        _ = await task.value
    }

    @Test("待っている間に画面を離れたら呼ばれず、予定も破棄される")
    func cancelledWhileWaiting() async {
        let (log, _, _) = makeLog(suite: "timing-cancel")
        let service = ReviewRequestService(
            log: log, appVersion: appVersion, delay: .milliseconds(300)
        )
        advanceWins(service, count: 5)
        #expect(service.pendingRequestID != nil)

        var requested = 0
        let task = Task { await service.performPendingRequest { requested += 1 } }
        task.cancel()
        _ = await task.value

        #expect(requested == 0, "キャンセルされたら呼ばない")
        #expect(service.pendingRequestID == nil, "別の画面で不意に出さないよう予定を破棄する")
        #expect(service.log.reviewState.lastRequestedAt == nil, "呼んでいないので記録もしない")
    }

    @Test("待ち時間が経てば呼ばれる")
    func firesAfterDelay() async {
        let (log, _, _) = makeLog(suite: "timing-fires")
        let service = ReviewRequestService(
            log: log, appVersion: appVersion, delay: .milliseconds(50)
        )
        advanceWins(service, count: 5)

        var requested = 0
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)
    }
}

// MARK: - レコメンド（#52）との競合調停

@Suite("同じリザルトでのレコメンドとの競合")
@MainActor
struct ReviewVersusRecommendationTests {

    private static let hubOrder = [
        "2048", "shogi", "gomoku", "minesweeper", "othello", "poker", "concentration", "blackjack",
    ]

    private func makeBoth(suite: String) -> (GameServices, ReviewRequestService, RecommendationService) {
        let (log, _, _) = makeLog(suite: suite)
        let registry = GameRegistry([
            Game2048Module(), ShogiModule(), GomokuModule(), MinesweeperModule(),
            OthelloModule(), PokerModule(), ConcentrationModule(), BlackjackModule(),
        ])
        let review = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        let recommend = RecommendationService(
            log: log,
            availableModules: { Self.hubOrder.compactMap { registry.module(id: $0) } }
        )
        let services = GameServices(
            snapshots: MemorySnapshotStore(),
            ads: NoopAdService(),
            recommendations: recommend,
            review: review
        )
        return (services, review, recommend)
    }

    @Test("評価リクエストが出る回はレコメンドを出さず、次のリザルトに送る")
    func reviewWinsTheSlot() {
        let (services, review, recommend) = makeBoth(suite: "conflict-review-wins")

        // レコメンドの条件（20回終了）と評価リクエストの条件（5勝）を同じ回で満たす。
        for _ in 0..<19 { services.gameDidFinish(gameID: "shogi", outcome: .loss) }
        for _ in 0..<4 { review.gameDidFinish(outcome: .win) }
        #expect(recommend.suggestedGameID == nil)

        services.gameDidFinish(gameID: "shogi", outcome: .win) // 20回目 かつ 5勝目
        #expect(review.pendingRequestID != nil, "評価リクエストが予定される")
        #expect(recommend.suggestedGameID == nil, "同じリザルトにレコメンドは出さない")
        #expect(recommend.log.state.lastShownAt == nil, "提示カウントも消費していない")

        services.gameDidFinish(gameID: "shogi", outcome: .loss) // 次のリザルト
        #expect(recommend.suggestedGameID == "gomoku", "次の回でレコメンドが出る")
    }

    @Test("評価リクエストが出ない回はレコメンドが通常どおり出る")
    func recommendationUnaffected() async {
        let (services, review, recommend) = makeBoth(suite: "conflict-no-review")
        for _ in 0..<5 { services.gameDidFinish(gameID: "shogi", outcome: .win) }
        // 予定を消化する（実機では同じリザルト画面が必ず消化するため、予定が残り続けることはない）。
        await review.performPendingRequest {}
        #expect(review.pendingRequestID == nil)

        // 以降は条件5（同一バージョンでは1回まで）で予定が立たないため、レコメンドは抑止されない。
        for _ in 0..<15 { services.gameDidFinish(gameID: "shogi", outcome: .win) }
        #expect(review.log.totalWins == 20)
        #expect(recommend.suggestedGameID == "gomoku", "20回目のリザルトでレコメンドが出る")
    }

    @Test("予定が残っている間はレコメンドを抑止し続ける")
    func suppressionLastsWhilePending() {
        let (services, review, recommend) = makeBoth(suite: "conflict-pending-lasts")
        for _ in 0..<20 { services.gameDidFinish(gameID: "shogi", outcome: .win) }
        // 5勝目で立った予定を消化しない間は、以降のリザルトでもレコメンドを出さない。
        #expect(review.pendingRequestID != nil)
        #expect(recommend.suggestedGameID == nil)
        #expect(recommend.log.state.lastShownAt == nil, "提示カウントも消費しない")
    }
}

// MARK: - 各ゲームの勝敗の振り分け（条件1）

@Suite("全9ゲームの勝敗の振り分け")
@MainActor
struct GameOutcomeRoutingTests {

    @Test("マインスイーパー: 全マス開放は勝利として数える")
    func minesweeperWin() {
        let (services, service) = makeServices(suite: "route-minesweeper-win")
        let model = MinesweeperModel(services: services)
        model.newGame(rows: 2, cols: 2, mines: 1)
        model.tap(row: 0, col: 0)
        for r in 0..<2 {
            for c in 0..<2 where !model.cells[r][c].isMine {
                model.tap(row: r, col: c)
            }
        }
        #expect(model.gameState == .won)
        #expect(service.log.totalWins == 1)
    }

    @Test("マインスイーパー: 地雷を踏んでも・諦めても勝利にならない")
    func minesweeperLoss() {
        let (services, service) = makeServices(suite: "route-minesweeper-loss")
        let model = MinesweeperModel(services: services)
        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 0, col: 0)
        guard let mine = model.cells.indices.flatMap({ r in
            model.cells[r].indices.map { (r, $0) }
        }).first(where: { model.cells[$0.0][$0.1].isMine }) else {
            Issue.record("地雷が見つからない")
            return
        }
        model.tap(row: mine.0, col: mine.1)
        #expect(model.gameState == .lost)

        model.newGame(rows: 9, cols: 9, mines: 10)
        model.tap(row: 4, col: 4)
        model.giveUp()
        #expect(model.gameState == .lost)

        #expect(service.log.totalWins == 0, "地雷・諦めは1回も数えない")
        #expect(service.pendingRequestID == nil)
    }

    @Test("神経衰弱: 人が勝てば数え、CPU が勝てば数えない")
    func concentration() {
        let (services, service) = makeServices(suite: "route-concentration")
        let model = ConcentrationModel(services: services)
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        for _ in 0..<model.cards.count where !model.isGameOver {
            let unmatched = model.cards.indices.filter { !model.cards[$0].isMatched }
            guard let first = unmatched.first,
                  let second = unmatched.first(where: {
                      $0 != first && model.cards[$0].symbol == model.cards[first].symbol
                  }) else { break }
            if model.firstFlippedIndex == nil { model.tap(index: first) }
            model.tap(index: second)
        }
        #expect(model.isGameOver)
        #expect(model.reviewOutcome == .win, "全ペアを人が取ったので勝利")
        #expect(service.log.totalWins == 1)
    }

    @Test("将棋: 投了は勝利にならない")
    func shogiResign() {
        let (services, service) = makeServices(suite: "route-shogi")
        let model = ShogiGameModel(services: services)
        model.resign()
        #expect(model.gameOver)
        #expect(service.log.totalWins == 0)
        #expect(service.pendingRequestID == nil)
    }

    @Test("五目並べ: 投了は勝利にならない")
    func gomokuResign() {
        let (services, service) = makeServices(suite: "route-gomoku")
        let model = GomokuModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(service.log.totalWins == 0)
    }

    @Test("ソリティア: 捨てた配札は勝利にならない")
    func solitaireAbandon() {
        let (services, service) = makeServices(suite: "route-solitaire")
        let model = SolitaireModel(services: services, seed: SolitaireDealer.verifiedSeeds[0])
        model.tapStock()
        model.newGame()
        #expect(service.log.totalWins == 0)
    }

    @Test("フリーセル: 捨てた配札は勝利にならない")
    func freeCellAbandon() {
        let (services, service) = makeServices(suite: "route-freecell")
        let model = FreeCellModel(services: services, seed: FreeCellDealer.verifiedSeeds[0])
        model.tapPile(0)
        model.tapCell(0)
        model.newGame()
        #expect(service.log.totalWins == 0)
    }

    @Test("チャリンコおじさん: ステージクリアは勝利になり、ミスはならない")
    func runnerStageClear() {
        let (services, service) = makeServices(suite: "route-runner")
        let model = RunnerModel(services: services, startingAt: 1)
        failCurrentStage(model)
        #expect(model.phase == .failed)
        #expect(service.log.totalWins == 0, "ミスは決着ではない")

        model.retryStage()
        autoPlayCurrentStage(model)
        #expect(model.phase == .cleared)
        #expect(service.log.totalWins == 1)
    }

    @Test("カードしりとり: 1 枚も取らずに時間切れになっても勝利にならない")
    func shiritoriTimeUpWithNothingTakenIsNotAWin() {
        let (services, service) = makeServices(suite: "route-shiritori")
        let model = ShiritoriModel(services: services, cpuDelay: .zero, seed: 2026)
        model.startGame(quota: .easy)
        model.tick(ShiritoriTime.initial)
        #expect(model.phase == .result)
        #expect(service.log.totalWins == 0)
    }

    @Test("花札こいこい: 投了は勝利にならない")
    func hanafudaResign() {
        let (services, service) = makeServices(suite: "route-hanafuda")
        let model = HanafudaModel(services: services, cpuDelay: .zero, seed: 4649)
        model.startMatch(options: HanafudaOptions(rounds: 6))
        model.resign()
        #expect(model.phase == .matchResult)
        #expect(service.log.totalWins == 0)
    }

    @Test("スパイダーソリティア: 捨てた配札は勝利にならない")
    func spiderAbandon() {
        let (services, service) = makeServices(suite: "route-spider")
        let model = SpiderModel(services: services, seed: SpiderDealer.verifiedSeeds(for: .one)[0])
        model.tapStock()
        model.newGame()
        #expect(service.log.totalWins == 0)
    }

    @Test("囲碁: 投了は勝利にならない")
    func goResign() {
        let (services, service) = makeServices(suite: "route-go")
        let model = GoModel(services: services)
        model.newGame(humanSide: .black, level: .easy)
        model.resign()
        #expect(service.log.totalWins == 0)
    }

    @Test("オセロ: 投了は勝利にならない")
    func othelloResign() {
        let (services, service) = makeServices(suite: "route-othello")
        let model = OthelloModel(services: services)
        model.newGame(humanSide: .black, aiLevel: 1)
        model.resign()
        #expect(model.reviewOutcome == .loss)
        #expect(service.log.totalWins == 0)
    }

    @Test("2048: ゲームオーバーは勝利にならない")
    func game2048() {
        let (services, service) = makeServices(suite: "route-2048")
        // 左へ寄せると 8 どうしが合体し、空いた 1 マスに何が沸いても終局する盤（2048 には届かない）。
        // 乱数任せに遊ばせると、まず起きないとはいえ 2048 到達で判定が揺れるため決め打ちする。
        let model = Game2048Model(services: services, board: [
            [8, 8, 4, 16],
            [4, 16, 4, 8],
            [8, 4, 8, 4],
            [4, 8, 4, 8],
        ])

        model.move(.left)

        #expect(model.gameOver)
        #expect(!model.hasWon, "2048 に届いていない")
        #expect(service.log.totalWins == 0, "2048 に届かない終局はゲームオーバー")
    }

    @Test("2048: 2048 到達は勝利として評価リクエストの条件に乗る（#438）")
    func game2048Win() {
        let (services, service) = makeServices(suite: "route-2048-win")
        // 左へ寄せると 1024 どうしが合体して 2048 になる盤。
        let winnableBoard = [
            [1024, 1024, 4, 8],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ]

        let first = Game2048Model(services: services, board: winnableBoard)
        first.move(.left)
        #expect(first.hasWon)
        #expect(!first.gameOver, "勝ってもゲームは続く")
        #expect(service.log.totalWins == 1, "2048 到達は勝利として数える")
        #expect(service.pendingRequestID == nil, "条件2（通算5勝）にはまだ届かない")

        // ここまで一度も乗れなかった経路（`outcome == .win`）に乗ったことを、
        // 初回リクエストの条件（通算5勝）まで到達できることで確かめる。
        for _ in 0..<(ReviewRequestPolicy.firstRequestWins - 1) {
            Game2048Model(services: services, board: winnableBoard).move(.left)
        }
        #expect(service.log.totalWins == ReviewRequestPolicy.firstRequestWins)
        #expect(service.pendingRequestID != nil, "評価リクエストが予定される")
    }

    @Test("ブラックジャック: 10 回勝負の結果どおりに振り分ける（#2552）")
    func blackjack() {
        let (services, service) = makeServices(suite: "route-blackjack")
        let model = BlackjackModel(services: services)
        model.restartMatch()
        model.deal()
        for _ in 0..<20 where !model.matchOver {
            while model.phase == .playerTurn { model.stand() }
            if !model.matchOver { model.nextRound() }
        }
        #expect(model.matchOver)

        switch model.matchOutcome {
        case .win:  #expect(service.log.totalWins == 1)
        default:    #expect(service.log.totalWins == 0)
        }
    }

    @Test("大富豪: 大富豪なら勝ち・大貧民なら負けに振り分ける")
    func daifugo() async {
        let (services, service) = makeServices(suite: "route-daifugo")
        let model = DaifugoModel(services: services, cpuDelay: .zero, seed: 2026)
        model.startGame()
        for _ in 0..<500 where model.phase == .playing {
            await model.runCPUTurnsIfNeeded()
            guard model.phase == .playing, model.isPlayerTurn else { continue }
            if let play = DaifugoRules.greedyPlay(
                hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
            ) {
                for card in play { model.toggleSelection(card) }
                model.playSelected()
            } else {
                model.pass()
            }
        }
        #expect(model.phase == .result)

        switch model.reviewOutcome {
        case .win:
            #expect(model.playerTitle == "大富豪")
            #expect(service.log.totalWins == 1)
        default:
            #expect(model.playerTitle != "大富豪")
            #expect(service.log.totalWins == 0)
        }
    }

    @Test("四人打ち麻雀: 1位なら勝ち・4位なら負け・中位は引き分けに振り分ける")
    func mahjongFourPlayer() async {
        let (services, service) = makeServices(suite: "route-mahjong4")
        let model = MahjongModel(services: services, cpuDelay: .zero, seed: 4649)
        model.startGame()
        await playMahjongFourPlayer(model)
        #expect(model.phase == .gameResult)

        switch model.reviewOutcome {
        case .win:
            #expect(model.playerPlace == 0)
            #expect(service.log.totalWins == 1)
        case .loss:
            #expect(model.playerPlace == MahjongModel.playerCount - 1)
            #expect(service.log.totalWins == 0)
        case .draw:
            #expect(model.playerPlace != 0)
            #expect(service.log.totalWins == 0)
        }
    }

    @Test("麻雀ソリティア: 取り切ったときだけ勝ちに数える（諦めた回は記録しない・#240）")
    func mahjong() {
        let (services, service) = makeServices(suite: "route-mahjong")
        let model = MahjongSolitaireModel(services: services, seed: 909)
        for pair in model.solution {
            model.tap(pair[0])
            model.tap(pair[1])
        }
        #expect(model.phase == .won)
        #expect(service.log.totalWins == 1, "クリアは勝ちとして数える")

        let (services2, service2) = makeServices(suite: "route-mahjong-loss")
        let giveUp = MahjongSolitaireModel(services: services2, seed: 910)
        giveUp.giveUpAndRestart()
        #expect(service2.log.totalWins == 0, "諦めた回は勝ちに数えない")
    }

    @Test("数独: 解き切れば勝ち・諦めれば負けに振り分ける")
    func sudoku() async {
        let (services, service) = makeServices(suite: "route-sudoku")
        let model = SudokuModel(services: services, seed: 777)
        await model.newGame(difficulty: .easy)
        for index in 0..<81 where model.board[index] == 0 {
            if model.selected != index { model.select(index: index) }
            model.enter(digit: model.solution[index])
        }
        #expect(model.state == .cleared)
        #expect(service.log.totalWins == 1, "クリアは勝ちとして数える")

        let (services2, service2) = makeServices(suite: "route-sudoku-loss")
        let giveUp = SudokuModel(services: services2, seed: 778)
        await giveUp.newGame(difficulty: .easy)
        giveUp.giveUp()
        #expect(service2.log.totalWins == 0, "諦めた回は勝ちに数えない")
    }

    @Test("ポーカー: 10 回勝負の結果どおりに振り分ける")
    func poker() {
        let (services, service) = makeServices(suite: "route-poker")
        let model = PokerModel(services: services)
        model.restartSession()
        model.startGame()
        // 10 回で 1 プレイ（#2551）。
        for _ in 0..<100 where !model.sessionOver {
            switch model.phase {
            case .exchange: model.confirmExchange()
            case .drawn:    model.showdown()
            case .result:   model.nextRound()
            case .idle:     break
            }
        }
        #expect(model.sessionOver)

        switch model.reviewOutcome {
        case .win:  #expect(service.log.totalWins == 1)
        default:    #expect(service.log.totalWins == 0)
        }
    }
}

// MARK: - 保存（再起動・キー数・消去）

@Suite("評価リクエストの記録の保存")
@MainActor
struct ReviewRequestStorageTests {

    /// 保存内容のバイト数（バイナリ plist 換算）。
    private func storedSize(_ domain: [String: Any]) -> Int {
        (try? PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0))?.count ?? -1
    }

    @Test("アプリ再起動をまたいで勝利数と前回リクエストが保持される")
    func survivesRelaunch() {
        let name = "asobiba.review.tests.persist"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let requestedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let first = PlayLog(defaults: defaults)
        for _ in 0..<7 { first.recordWin() }
        first.markReviewRequested(at: requestedAt, version: appVersion)

        // 再起動相当: 同じ保存先から作り直す。
        let second = PlayLog(defaults: defaults)
        #expect(second.totalWins == 7)
        #expect(second.reviewState.lastRequestedAt == requestedAt)
        #expect(second.reviewState.lastRequestedWins == 7)
        #expect(second.reviewState.lastRequestedVersion == appVersion)

        defaults.removePersistentDomain(forName: name)
    }

    @Test("勝ち続けてもキーは9つのまま。データ量も増えない")
    func keysAndSizeAreBounded() {
        let name = "asobiba.review.tests.size"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let log = PlayLog(defaults: defaults)
        for _ in 0..<20 { log.recordWin() }
        log.markReviewRequested(at: Date(timeIntervalSince1970: 1_800_000_000), version: appVersion)
        let after20 = defaults.persistentDomain(forName: name) ?? [:]

        for _ in 0..<10_000 { log.recordWin() }
        log.markReviewRequested(at: Date(timeIntervalSince1970: 1_900_000_000), version: appVersion)
        let after10020 = defaults.persistentDomain(forName: name) ?? [:]

        #expect(Set(after20.keys) == Set(PlayLog.reviewRequestKeys), "書き込むキーは4つだけ")
        #expect(Set(after10020.keys) == Set(after20.keys), "1万回勝ってもキーは増えない")
        // 増えうるのは整数の桁だけ（バイナリ plist の整数幅）。追記型ログなら数百 KB になる。
        #expect(storedSize(after10020) - storedSize(after20) <= 16, "データ量はほぼ一定")
        #expect(storedSize(after10020) <= 512, "キー名と plist の枠を含めても 512 バイト以内")

        defaults.removePersistentDomain(forName: name)
    }

    @Test("「プレイ記録を消去」で評価リクエストの記録も消える")
    func clearRemovesReviewKeys() {
        let name = "asobiba.review.tests.clear"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)

        let log = PlayLog(defaults: defaults)
        for _ in 0..<10 { log.recordWin() }
        log.recordFinish(gameID: "shogi")
        log.markReviewRequested(at: Date(timeIntervalSince1970: 1_800_000_000), version: appVersion)

        log.clear()
        for key in PlayLog.allKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key) が残っている")
        }
        #expect(log.totalWins == 0)
        #expect(log.reviewState == ReviewRequestState(), "判定用の状態も初期化される")

        defaults.removePersistentDomain(forName: name)
    }

    @Test("消去した直後は5勝するまで再びリクエストされない")
    func requestsRestartAfterClear() {
        let (log, _, _) = makeLog(suite: "clear-then-request")
        let service = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        advanceWins(service, count: 5)
        #expect(service.pendingRequestID != nil)

        log.clear()
        let afterClear = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero)
        advanceWins(afterClear, count: 4)
        #expect(afterClear.pendingRequestID == nil)
        afterClear.gameDidFinish(outcome: .win)
        #expect(afterClear.pendingRequestID != nil)
    }
}

/// 四人打ち麻雀: 常に自摸切り・和了できるときは必ず和了する方針で東風戦を最後まで進める。
/// CPU の間合いは 0 なので実時間は待たない。
@MainActor
private func playMahjongFourPlayer(_ model: MahjongModel, rejectOnce: Bool = false) async {
    var didReject = !rejectOnce
    var guardCount = 0
    while model.phase != .gameResult, guardCount < 800 {
        guardCount += 1
        switch model.phase {
        case .playing:
            if model.currentPlayer == MahjongModel.humanIndex, let drawn = model.drawnTile {
                if !didReject {
                    didReject = true
                    // 手牌にもツモ牌にも無い牌を指定すると拒否される（警告の発火を確かめる）。
                    let absent = MahjongTileOrder.all.first {
                        model.playerHand.count(of: $0) == 0 && $0 != drawn
                    }
                    if let absent { model.discard(absent) }
                }
                if model.canDeclareTsumo {
                    model.declareTsumo()
                } else {
                    model.discard(drawn)
                }
            } else {
                await model.runCPUTurnsIfNeeded()
            }
        case .ronOffer:
            model.declareRon()
        case .callOffer:
            // この通しテストは「常に自摸切り」の方針なので鳴かない。
            model.declineCall()
        case .handResult:
            model.advanceToNextHand()
        case .idle, .gameResult:
            return
        }
    }
}

/// 花札こいこい（#495）で 1 試合を決着まで通す。人間側は「出せる先頭の札」を出し、
/// こいこいは聞かれたらあがる。CPU は製品コードと同じ `HanafudaAI`。
@MainActor
private func playHanafudaMatch(_ services: GameServices, seed: UInt64 = 4649, rounds: Int = 6) -> HanafudaModel {
    let model = HanafudaModel(services: services, cpuDelay: .zero, seed: seed)
    model.startMatch(options: HanafudaOptions(rounds: rounds))
    for _ in 0..<2000 {
        switch model.phase {
        case .matchResult, .idle:
            return model
        case .roundResult:
            model.advanceAfterRound()
        case .koiKoiPrompt:
            if model.canStop { model.declareStop() } else { model.declareKoiKoi() }
        case .playing:
            if let selection = model.selection {
                model.chooseFieldCard(selection.candidates[0])
            } else if model.turn == .human {
                guard let card = model.humanHand.first(where: { model.canPlay($0) }) else { return model }
                model.play(card)
            } else {
                model.stepCPU()
            }
        }
    }
    return model
}


// MARK: - 答えた人・新しいゲームの感想カード（#3061）

@Suite("評価のお願いの強化（#3061）")
@MainActor
struct ReviewPromptEnhancementTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let newGame = NewGames.currentVersionIDs.sorted().first!

    @Test("答えた人には条件を全部満たしても出ない")
    func answeredNeverRequested() {
        let state = ReviewRequestState(totalWins: 1_000, hasAnswered: true)
        #expect(ReviewRequestPolicy.shouldRequest(state: state, currentVersion: appVersion, now: now) == false)
        #expect(ReviewRequestPolicy.shouldRequest(
            state: ReviewRequestState(totalWins: 1_000), currentVersion: appVersion, now: now) == true)
    }

    @Test("感想カードの判定: 新着のゲームだけ・答えていない人だけ・一度だけ")
    func cardPolicyBranches() {
        func ask(_ id: String, _ state: ReviewRequestState = .init()) -> Bool {
            ReviewRequestPolicy.shouldAskAboutNewGame(state: state, gameID: id)
        }
        #expect(ask(newGame) == true, "勝利数 0 でも条件1〜6 を飛び越える")
        #expect(ask("shogi") == false, "新着でないゲームでは出ない")
        #expect(ask(newGame, .init(hasAnswered: true)) == false, "答えた人には出ない")
        #expect(ask(newGame, .init(hasAskedAboutNewGame: true)) == false, "出し済みなら出ない")
        #expect(ask("") == false)
    }

    @Test("新着ゲームの決着（負けでも）でカードの予定が立ち、通常の評価リクエストは立たない")
    func finishSchedulesCardInsteadOfRequest() {
        let (_, service) = makeServices(suite: "card-schedule")
        advanceWins(service, count: 10) // 通常の条件は満たす
        #expect(service.pendingRequestID != nil)

        let (_, loss) = makeServices(suite: "card-schedule-loss")
        #expect(loss.gameDidFinish(outcome: .loss, gameID: newGame) == true)
        #expect(loss.pendingNewGameCardID != nil)
        #expect(loss.pendingRequestID == nil)

        let (_, plain) = makeServices(suite: "card-schedule-plain")
        #expect(plain.gameDidFinish(outcome: .loss, gameID: "shogi") == false, "新着でない負けは何も立てない")
        #expect(plain.pendingNewGameCardID == nil)
    }

    @Test("新着ゲームで 5 勝済みでも、その回はカードが優先され OS ダイアログは立たない")
    func cardWinsOverRequestOnSameFinish() async {
        let (_, service) = makeServices(suite: "card-priority")
        advanceWins(service, count: 4)
        service.gameDidFinish(outcome: .win, gameID: newGame) // 5 勝目・新着
        #expect(service.pendingNewGameCardID != nil)
        #expect(service.pendingRequestID == nil)
        var requested = 0
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 0)
    }

    @Test("カードは一人一度きり: 出した後はどの新着ゲームでも予定が立たない")
    func cardOnlyOnce() async {
        let (_, service) = makeServices(suite: "card-once")
        service.gameDidFinish(outcome: .win, gameID: newGame)
        await service.presentPendingNewGameCard()
        #expect(service.isNewGameCardPresented)
        #expect(service.log.reviewState.hasAskedAboutNewGame)

        service.newGameCardDismissed()
        #expect(!service.isNewGameCardPresented)
        for id in NewGames.currentVersionIDs {
            service.gameDidFinish(outcome: .win, gameID: id)
            #expect(service.pendingNewGameCardID == nil, "\(id) でも二度と出ない")
        }
        #expect(service.log.reviewState.hasAnswered == false, "「あとで」は答えた人に数えない")
    }

    @Test("出す前に画面を離れた（キャンセルされた）カードは、出し済みに数えない")
    func cancelledCardIsNotCounted() async {
        let (log, _, _) = makeLog(suite: "card-cancel")
        let service = ReviewRequestService(log: log, appVersion: appVersion, delay: .seconds(60))
        service.gameDidFinish(outcome: .win, gameID: newGame)
        let task = Task { await service.presentPendingNewGameCard() }
        task.cancel()
        await task.value
        #expect(!service.isNewGameCardPresented)
        #expect(service.log.reviewState.hasAskedAboutNewGame == false)
        #expect(service.pendingNewGameCardID == nil)
    }

    @Test("「App Store で感想を書く」で答えた人になり、以後 A・B とも出ない。再起動しても残る")
    func writeReviewMarksAnswered() async {
        let name = "asobiba.review.tests.card-answer"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let log = PlayLog(defaults: defaults)
        let service = ReviewRequestService(log: log, appVersion: appVersion, now: { Date(timeIntervalSince1970: 1_800_000_000) }, delay: .zero)

        service.gameDidFinish(outcome: .win, gameID: newGame)
        await service.presentPendingNewGameCard()
        service.newGameCardWriteReviewTapped()
        #expect(!service.isNewGameCardPresented)
        #expect(log.reviewState.hasAnswered)

        // 通常の条件を満たし続けても、新着の別ゲームを遊んでも出ない。
        advanceWins(service, count: 100)
        service.gameDidFinish(outcome: .win, gameID: newGame)
        #expect(service.pendingRequestID == nil)
        #expect(service.pendingNewGameCardID == nil)

        let reopened = PlayLog(defaults: defaults)
        #expect(reopened.reviewState.hasAnswered, "端末内に残る")
        #expect(reopened.reviewState.hasAskedAboutNewGame)

        reopened.clear()
        for key in PlayLog.allKeys { #expect(defaults.object(forKey: key) == nil, "\(key) が残っている") }
        #expect(reopened.reviewState == ReviewRequestState(), "プレイ記録の消去で答えた印も消える")
        defaults.removePersistentDomain(forName: name)
    }

    @Test("演出中は予定を伏せ、リザルトに移ってから出る")
    func cardIsDeferredDuringStory() {
        let (_, service) = makeServices(suite: "card-defer")
        service.gameDidFinish(outcome: .win, gameID: newGame)
        service.deferUntilResultIsVisible()
        #expect(service.pendingNewGameCardID == nil)
        service.resultDidBecomeVisible()
        #expect(service.pendingNewGameCardID != nil)
    }

    @Test("解析: カードを出した・どれを押した・OS ダイアログを依頼した")
    func analyticsSteps() async {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: [newGame])
        let (log, _, _) = makeLog(suite: "card-analytics")
        let service = ReviewRequestService(log: log, appVersion: appVersion, delay: .zero, analytics: analytics)

        service.gameDidFinish(outcome: .win, gameID: newGame)
        await service.presentPendingNewGameCard()
        service.newGameCardWriteReviewTapped()
        #expect(spy.events == [
            .reviewPrompt(kind: .newGameCard, step: .shown),
            .reviewPrompt(kind: .newGameCard, step: .writeReview),
        ])

        let (log2, _, _) = makeLog(suite: "card-analytics-2")
        let spy2 = SpyAnalyticsService()
        let later = ReviewRequestService(
            log: log2, appVersion: appVersion, delay: .zero,
            analytics: GameAnalytics(service: spy2, allowedGameIDs: [newGame]))
        later.gameDidFinish(outcome: .win, gameID: newGame)
        await later.presentPendingNewGameCard()
        later.newGameCardDismissed()
        #expect(spy2.events.map(\.parameters["step"]) == [.string("shown"), .string("later")])

        let (log3, _, _) = makeLog(suite: "card-analytics-3")
        let spy3 = SpyAnalyticsService()
        let regular = ReviewRequestService(
            log: log3, appVersion: appVersion, delay: .zero,
            analytics: GameAnalytics(service: spy3, allowedGameIDs: ["shogi"]))
        advanceWins(regular, count: 5)
        await regular.performPendingRequest {}
        #expect(spy3.events == [.reviewPrompt(kind: .regular, step: .osRequested)])
    }
}

// MARK: - 遊んだ日数の節目（#3078）

/// 進められる時計。日をまたぐ検証で使う。
@MainActor
private final class DaysClock {
    /// 正午（UTC）。どのタイムゾーンでも日付の境目から遠い。
    var date = Date(timeIntervalSince1970: 1_800_000_000 + 4 * 3600)
    func advance(days: Int) { date = date.addingTimeInterval(TimeInterval(days) * 86_400) }
}

@MainActor
private func makeDaysService(
    suite: String,
    clock: DaysClock,
    analytics: GameAnalytics? = nil
) -> (PlayLog, ReviewRequestService) {
    let (log, _, _) = makeLog(suite: suite)
    let service = ReviewRequestService(
        log: log, appVersion: appVersion, now: { clock.date }, delay: .zero, analytics: analytics)
    return (log, service)
}

/// n 日目まで 1 日ずつ進めながらアプリを開く（起動のたびに `appDidOpen`）。
@MainActor
private func openApp(_ service: ReviewRequestService, clock: DaysClock, days: Int) {
    for day in 0..<days {
        if day > 0 { clock.advance(days: 1) }
        service.appDidOpen()
    }
}

@Suite("遊んだ日数の節目の評価のお願い（#3078）")
@MainActor
struct DaysMilestoneReviewTests {

    @Test("同じ日に何度開いても 1 日と数える")
    func sameDayCountsOnce() {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-same-day", clock: clock)
        for _ in 0..<5 { service.appDidOpen() }
        service.hubDidBecomeVisible()
        #expect(log.reviewState.openDays == 1)
        clock.advance(days: 1)
        service.appDidOpen()
        #expect(log.reviewState.openDays == 2)
    }

    @Test("端末の時計を戻しても日数は増えない")
    func clockRewindDoesNotInflate() {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-rewind", clock: clock)
        service.appDidOpen()
        clock.advance(days: 3)
        service.appDidOpen()
        clock.advance(days: -2)
        service.appDidOpen()
        #expect(log.reviewState.openDays == 2)
    }

    @Test("7 日目に達した日にハブへ戻ると予定が立ち、実行で OS に依頼して節目を記録する")
    func sevenDaysSchedulesAtHub() async {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-7", clock: clock)
        openApp(service, clock: clock, days: 6)
        #expect(service.hubDidBecomeVisible() == false, "6 日目までは出さない")
        clock.advance(days: 1)
        service.appDidOpen()
        #expect(service.pendingRequestID == nil, "起動直後（appDidOpen）には予定を立てない")
        #expect(service.hubDidBecomeVisible() == true)
        var requested = 0
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)
        #expect(log.reviewState.daysMilestoneAsked == 7)
        #expect(service.hubDidBecomeVisible() == false, "7 日では 1 回まで")
    }

    @Test("勝敗を問わず、リザルト（敗北）でも節目なら予定が立つ")
    func resultScreenAlsoSchedules() async {
        let clock = DaysClock()
        let (_, service) = makeDaysService(suite: "days-result", clock: clock)
        openApp(service, clock: clock, days: 7)
        #expect(service.gameDidFinish(outcome: .loss, gameID: "shogi") == true)
        var requested = 0
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)
    }

    @Test("30 日目にもう一度出る。15 日以内なら出さず、明けた最初の区切りで出す")
    func thirtyDaysAfterInterval() async {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-30", clock: clock)
        openApp(service, clock: clock, days: 7)
        service.hubDidBecomeVisible()
        await service.performPendingRequest {}
        #expect(log.reviewState.daysMilestoneAsked == 7)
        // 7 日目から 23 日後に 30 日目（前回から 15 日以上空いている）。
        for _ in 0..<23 { clock.advance(days: 1); service.appDidOpen() }
        #expect(log.reviewState.openDays == 30)
        #expect(service.hubDidBecomeVisible() == true)
        var requested = 0
        await service.performPendingRequest { requested += 1 }
        #expect(requested == 1)
        #expect(log.reviewState.daysMilestoneAsked == 30)
        #expect(service.hubDidBecomeVisible() == false)
    }

    @Test("A: 前回のお願いから 15 日以内なら出さず、間隔が明けた最初の区切りで出す")
    func intervalHoldsThenReleases() async {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-interval", clock: clock)
        log.markReviewRequested(at: clock.date, version: "0.9")
        // 前回のお願いの 15 日後より前に 7 日に達する。
        openApp(service, clock: clock, days: 7)
        #expect(service.hubDidBecomeVisible() == false, "前回から 6 日")
        for _ in 0..<8 { clock.advance(days: 1); service.appDidOpen() }
        #expect(service.hubDidBecomeVisible() == false, "前回から 14 日")
        clock.advance(days: 1)
        #expect(service.hubDidBecomeVisible() == true, "前回から 15 日")
    }

    @Test("C: 答えた人には出さない")
    func answeredNeverAsked() {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-answered", clock: clock)
        log.markReviewAnswered()
        openApp(service, clock: clock, days: 30)
        #expect(service.hubDidBecomeVisible() == false)
        #expect(service.gameDidFinish(outcome: .loss, gameID: "shogi") == false)
    }

    @Test("感想カードの予定があるときはカードを優先し、節目は次の区切りに回す")
    func newGameCardTakesPriority() async {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-card", clock: clock)
        openApp(service, clock: clock, days: 7)
        let newGame = NewGames.currentVersionIDs.sorted().first ?? "shogi"
        guard NewGames.currentVersionIDs.contains(newGame) else { return }
        service.gameDidFinish(outcome: .win, gameID: newGame)
        #expect(service.pendingNewGameCardID != nil)
        #expect(service.hubDidBecomeVisible() == false)
        #expect(service.pendingRequestID == nil, "カードの間は OS の依頼を立てない")
        await service.presentPendingNewGameCard()
        service.newGameCardDismissed()
        // カードを出したのは「前回のお願い」ではないので、次の区切りでそのまま出る。
        #expect(log.reviewState.daysMilestoneAsked == 0)
        #expect(service.hubDidBecomeVisible() == true)
        #expect(service.pendingRequestID != nil)
    }

    @Test("プレイ中・待っている間に画面を離れたら取り消し、節目は消費しない")
    func cancelledWhenLeftBeforeDelay() async {
        let clock = DaysClock()
        let (log, _, _) = makeLog(suite: "days-cancel")
        let service = ReviewRequestService(
            log: log, appVersion: appVersion, now: { clock.date }, delay: .seconds(30))
        openApp(service, clock: clock, days: 7)
        #expect(service.hubDidBecomeVisible() == true)
        var requested = 0
        let task = Task { await service.performPendingRequest { requested += 1 } }
        task.cancel()
        await task.value
        #expect(requested == 0)
        #expect(service.pendingRequestID == nil)
        #expect(log.reviewState.daysMilestoneAsked == 0)
        #expect(log.reviewState.lastRequestedAt == nil)
        // 次の区切りでもう一度立つ。
        #expect(service.hubDidBecomeVisible() == true)
    }

    @Test("7 日と 30 日が両方未消化なら、1 回で両方を済ませる")
    func bothDueAskedOnce() async {
        let clock = DaysClock()
        let (log, service) = makeDaysService(suite: "days-both", clock: clock)
        log.markReviewRequested(at: clock.date, version: "0.9")
        openApp(service, clock: clock, days: 30)
        #expect(service.hubDidBecomeVisible() == true)
        await service.performPendingRequest {}
        #expect(log.reviewState.daysMilestoneAsked == 30)
        clock.advance(days: 20)
        service.appDidOpen()
        #expect(service.hubDidBecomeVisible() == false)
    }

    @Test("解析: trigger に days_7 / days_30 が載り、勝ちの見せ場には載らない")
    func analyticsTrigger() async {
        let clock = DaysClock()
        let spy = SpyAnalyticsService()
        let (_, service) = makeDaysService(
            suite: "days-analytics", clock: clock,
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["shogi"]))
        openApp(service, clock: clock, days: 7)
        service.hubDidBecomeVisible()
        await service.performPendingRequest {}
        #expect(spy.events == [.reviewPrompt(kind: .regular, step: .osRequested, trigger: .days7)])
        #expect(spy.events.first?.parameters["trigger"] == .string("days_7"))
        #expect(ReviewPromptTrigger(milestone: 30)?.rawValue == "days_30")
        #expect(AnalyticsEvent.reviewPrompt(kind: .regular, step: .osRequested).parameters["trigger"] == nil)
    }

    @Test("キーは PlayLog.allKeys に入り、プレイ記録の消去で消える")
    func clearedWithPlayLog() {
        let clock = DaysClock()
        let (log, defaults, _) = makeLog(suite: "days-clear")
        log.recordAppOpenDay(at: clock.date)
        log.markDaysMilestoneAsked(7)
        for key in [PlayLog.openDaysKey, PlayLog.lastOpenDayKey, PlayLog.daysMilestoneAskedKey] {
            #expect(PlayLog.allKeys.contains(key))
            #expect(defaults.object(forKey: key) != nil)
        }
        log.clear()
        for key in PlayLog.allKeys { #expect(defaults.object(forKey: key) == nil) }
        #expect(log.reviewState.openDays == 0)
        #expect(log.reviewState.daysMilestoneAsked == 0)
    }
}
