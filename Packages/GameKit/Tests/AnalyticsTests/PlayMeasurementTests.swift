import Testing
import Foundation
import SwiftUI
import Core

// MARK: - Mocks

/// 送信されたイベントをそのまま溜めるスパイ。Firebase もネットワークも使わない。
@MainActor
private final class SpyAnalyticsService: AnalyticsService {
    private(set) var events: [AnalyticsEvent] = []
    func log(_ event: AnalyticsEvent) { events.append(event) }

    var starts: [(gameID: String, level: AnalyticsLevel?)] {
        events.compactMap {
            if case let .gameStart(gameID, level) = $0 { return (gameID, level) }
            return nil
        }
    }
    var ends: [(gameID: String, result: AnalyticsResult, durationSec: Int)] {
        events.compactMap {
            if case let .gameEnd(gameID, result, durationSec) = $0 { return (gameID, result, durationSec) }
            return nil
        }
    }
    var rewards: [(gameID: String, purpose: RewardPurpose)] {
        events.compactMap {
            if case let .rewardAd(gameID, purpose) = $0 { return (gameID, purpose) }
            return nil
        }
    }
    var quits: [(gameID: String, durationSec: Int)] {
        ends.filter { $0.result == .quit }.map { ($0.gameID, $0.durationSec) }
    }
}

/// 中断データの有無だけを持つ最小の保存先。`exists` が「続きから」の可否を表す。
private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}

/// 視聴完了 / 未完了を指定できる広告。
private struct StubAdService: AdService {
    let earnsReward: Bool
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { earnsReward }
}

/// 進む時計。**実時間を待たない**（実時間の待ち合わせは並列実行で落ちるため）。
@MainActor
private final class TestClock {
    private var seconds: TimeInterval = 0
    var now: Date { Date(timeIntervalSince1970: 1_800_000_000 + seconds) }
    func advance(_ interval: TimeInterval) { seconds += interval }
}

private let testGameIDs: Set<String> = ["2048", "sudoku", "solitaire"]

@MainActor
private func makeAnalytics(clock: TestClock = TestClock()) -> (GameAnalytics, SpyAnalyticsService) {
    let spy = SpyAnalyticsService()
    return (GameAnalytics(service: spy, allowedGameIDs: testGameIDs, now: { clock.now }), spy)
}

@MainActor
private func makeServices(
    earnsReward: Bool = true,
    snapshots: SnapshotStore = MemorySnapshotStore(),
    clock: TestClock = TestClock()
) -> (GameServices, SpyAnalyticsService) {
    let (analytics, spy) = makeAnalytics(clock: clock)
    let services = GameServices(
        snapshots: snapshots,
        ads: StubAdService(earnsReward: earnsReward),
        analytics: analytics
    )
    return (services, spy)
}

// MARK: - 途中離脱（#500）

@Suite("途中離脱の記録（#500）")
@MainActor
struct QuitTrackingTests {

    @Test("1手でも指した盤面を「新しいゲーム」で捨てると quit が出る")
    func restartAfterProgressSendsQuit() {
        let clock = TestClock()
        let (analytics, spy) = makeAnalytics(clock: clock)
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        clock.advance(35)
        analytics.restartPlay(gameID: "2048")

        #expect(spy.quits.map(\.gameID) == ["2048"])
        #expect(spy.quits.first?.durationSec == 35, "duration_sec は決着時と同じく開始からの経過")
        #expect(spy.starts.count == 2, "捨てたぶんと新しいぶんで game_start は2回")
    }

    @Test("1手も指していない配り直しでは quit を出さない")
    func restartWithoutProgressSendsNothing() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.restartPlay(gameID: "2048")
        analytics.restartPlay(gameID: "2048")

        #expect(spy.quits.isEmpty, "捨てた盤面が無いので離脱にならない")
        #expect(spy.starts.count == 3)
    }

    @Test("決着したあとの「もう一度」は quit にならない（game_end は決着ぶんの1回だけ）")
    func restartAfterFinishSendsNoQuit() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .loss)
        analytics.restartPlay(gameID: "2048")

        #expect(spy.ends.map(\.result) == [.loss], "決着済みのプレイに quit を重ねない")
    }

    @Test("中断データが残る離れ方は「休憩」で、戻って終局すれば決着として出る")
    func leavingWithSnapshotIsNotQuit() {
        let clock = TestClock()
        let (analytics, spy) = makeAnalytics(clock: clock)
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        clock.advance(40)
        analytics.leaveGame(gameID: "2048", isResumable: true)   // 「続きから」で戻れる
        clock.advance(20)
        analytics.startPlay(gameID: "2048")                      // 再開は数え直さない
        clock.advance(30)
        analytics.finishPlay(gameID: "2048", outcome: .win)

        #expect(spy.quits.isEmpty, "休憩を離脱として数えない")
        #expect(spy.ends.map(\.result) == [.win])
        #expect(spy.ends.first?.durationSec == 90, "経過秒は最初の開始からの通算")
        #expect(spy.starts.count == 1, "再開で game_start は増えない")
    }

    @Test("中断データが残らない離れ方は、1手でも指していれば quit")
    func leavingWithoutSnapshotAfterProgressIsQuit() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: false)

        #expect(spy.quits.map(\.gameID) == ["2048"])
    }

    @Test("開いただけで何もせず離れたら quit を出さない")
    func leavingWithoutProgressIsNotQuit() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: false)

        #expect(spy.ends.isEmpty, "捨てた盤面が無いので game_end を作らない")
        #expect(spy.starts.count == 1)
    }

    @Test("離脱で数え終えたプレイは、次に開いたときに新しい1プレイになる")
    func quitClosesThePlay() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: false)
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .win)

        #expect(spy.starts.count == 2)
        #expect(spy.ends.map(\.result) == [.quit, .win], "1プレイに game_end はちょうど1回ずつ")
    }

    @Test("recordProgress は冪等で、game_end を増やさない")
    func recordProgressIsIdempotent() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        for _ in 0..<50 { analytics.recordProgress(gameID: "2048") }
        analytics.leaveGame(gameID: "2048", isResumable: false)

        #expect(spy.ends.count == 1)
    }

    @Test("進行中のプレイが無いところで recordProgress を呼んでも何も起きない")
    func recordProgressWithoutPlayIsIgnored() {
        let (analytics, spy) = makeAnalytics()
        analytics.recordProgress(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: false)

        #expect(spy.events.isEmpty)
    }

    @Test("ハブに無い gameID の離脱は送らない")
    func unknownGameIDCannotQuit() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "device-1234")
        analytics.recordProgress(gameID: "device-1234")
        analytics.restartPlay(gameID: "device-1234")

        #expect(spy.events.isEmpty)
    }

    @Test("GameServices は中断データの有無から休憩と離脱を切り分ける")
    func gameServicesDerivesResumabilityFromSnapshotStore() throws {
        let store = MemorySnapshotStore()
        let (services, spy) = makeServices(snapshots: store)

        services.gameDidStart(gameID: "2048")
        services.gameDidProgress(gameID: "2048")
        try store.save(["board": 1], for: "2048")     // 中断データが在る = 続きから戻れる
        services.gameDidLeave(gameID: "2048")
        #expect(spy.quits.isEmpty, "中断データが在るので休憩")

        store.clear(for: "2048")                       // 盤面を捨てた
        services.gameDidLeave(gameID: "2048")
        #expect(spy.quits.map(\.gameID) == ["2048"])
    }
}

// MARK: - リワード広告（#500）

@Suite("リワード広告の計測（#500）")
@MainActor
struct RewardAdTrackingTests {

    @Test("視聴完了したときだけ reward_ad を送る")
    func onlyCompletedViewsAreSent() async {
        let (earned, earnedSpy) = makeServices(earnsReward: true)
        #expect(await earned.showRewardedAd(gameID: "solitaire", purpose: .undo))
        #expect(earnedSpy.rewards.map(\.purpose) == [.undo])

        let (skipped, skippedSpy) = makeServices(earnsReward: false)
        #expect(await skipped.showRewardedAd(gameID: "solitaire", purpose: .undo) == false)
        #expect(skippedSpy.rewards.isEmpty, "途中で閉じた視聴は報酬も計測も出ない")
    }

    @Test("reward_ad はプレイの数え方に影響しない")
    func rewardAdDoesNotTouchPlayState() async {
        let (services, spy) = makeServices()
        services.gameDidStart(gameID: "solitaire")
        _ = await services.showRewardedAd(gameID: "solitaire", purpose: .joker)
        services.gameDidFinish(gameID: "solitaire", outcome: .win)

        #expect(spy.starts.count == 1)
        #expect(spy.ends.map(\.result) == [.win], "広告が game_end を増やしたり quit にしたりしない")
    }

    @Test("ハブに無い gameID の視聴は送らない")
    func unknownGameIDIsDropped() async {
        let (services, spy) = makeServices()
        _ = await services.showRewardedAd(gameID: "../../etc/passwd", purpose: .hint)
        #expect(spy.rewards.isEmpty)
    }
}

// MARK: - 発火箇所の1対1対応（#500）

/// リワード広告の面が増えたときに計測を付け忘れないよう、ソースを走査して固定する。
///
/// `GameServices.showRewardedAd(gameID:purpose:)` を通さない直呼びが1つでも残ると、
/// その面の視聴だけ `reward_ad` に出ない。テストからは各ゲームの View を実行できないため、
/// 呼び出しの形そのものを検査対象にする（`MotionTests` の走査と同じ考え方）。
@Suite("リワード広告の発火箇所（#500）")
struct RewardAdCallSiteTests {

    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AnalyticsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // GameKit
        .appendingPathComponent("Sources")

    /// `Sources/` 配下の Swift ファイル（Core を除く）を読み込む。
    private static func gameSources() throws -> [(path: String, text: String)] {
        try FileManager.default
            .subpathsOfDirectory(atPath: sourcesRoot.path)
            .filter { $0.hasSuffix(".swift") }
            // Core は `AdService` の宣言とラッパーの実装そのものなので対象外。
            .filter { !$0.hasPrefix("Core/") }
            .map { ($0, try String(contentsOf: sourcesRoot.appendingPathComponent($0), encoding: .utf8)) }
    }

    @Test("各ゲームは ads.showRewardedAd() を直接呼ばない（計測を必ず通す）")
    func noDirectAdServiceCalls() throws {
        let sources = try Self.gameSources()
        #expect(sources.count > 20, "走査対象が見つからない（パスの導出が壊れている可能性）")

        let offenders = sources
            .filter { $0.text.contains("ads.showRewardedAd(") }
            .map(\.path)
        #expect(offenders.isEmpty,
                "GameServices.showRewardedAd(gameID:purpose:) を通していない: \(offenders)")
    }

    @Test("purpose は全種が実際に使われていて、使われない値を定義していない")
    func everyPurposeHasACallSite() throws {
        let sources = try Self.gameSources()
        let counts = Dictionary(uniqueKeysWithValues: RewardPurpose.allCases.map { purpose in
            (purpose, sources.reduce(0) { $0 + $1.text.components(
                separatedBy: "purpose: .\(purpose.rawValue))"
            ).count - 1 })
        })

        let unused = counts.filter { $0.value == 0 }.keys.map(\.rawValue).sorted()
        #expect(unused.isEmpty, "発火箇所の無い purpose がある: \(unused)")

        // 呼び出しの総数 = すべての面の数。面を増やしたらここも動くので、
        // 「増やしたのに purpose を付け忘れた」も上のテストと合わせて検出できる。
        #expect(counts.values.reduce(0, +) == 21, "リワード広告の面は21箇所")
    }
}

// MARK: - 計測の付け忘れ（#500）

/// 途中離脱と難易度は**ゲーム側が伝えないと出ない**ので、伝えているかをソース走査で固定する。
///
/// `gameDidProgress` を呼ばないゲームは、盤面を捨てても `quit` が一切出ない。テストからは
/// 各ゲームの操作を通しで再現できないため、呼び出しの存在そのものを検査対象にする。
@Suite("プレイ計測の付け忘れ（#500）")
struct PlayMeasurementCallSiteTests {

    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AnalyticsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // GameKit
        .appendingPathComponent("Sources")

    /// モジュール名 → そのモジュールの全ソースを連結した文字列。
    private static func modules() throws -> [String: String] {
        var joined: [String: String] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: sourcesRoot.path)
        where path.hasSuffix(".swift") {
            let module = String(path.prefix(while: { $0 != "/" }))
            guard module != "Core" else { continue }
            let text = try String(contentsOf: sourcesRoot.appendingPathComponent(path), encoding: .utf8)
            joined[module, default: ""] += text
        }
        return joined
    }

    /// プレイを数えているモジュール（= ハブに並ぶ 20 本のゲーム）。
    private static func playingModules() throws -> [String: String] {
        try modules().filter {
            $0.value.contains("gameDidStart(") || $0.value.contains("gameDidRestart(")
        }
    }

    @Test("プレイを数えるゲームは全て gameDidProgress も呼んでいる")
    func everyGameReportsProgress() throws {
        let games = try Self.playingModules()
        #expect(games.count == 20, "ハブに並ぶゲームは20本")

        let silent = games.filter { !$0.value.contains("gameDidProgress(") }.keys.sorted()
        #expect(silent.isEmpty,
                "1手指したことを伝えないゲームがある（盤面を捨てても quit が出ない）: \(silent)")
    }

    @Test("game_start に level を載せるゲームの顔ぶれを固定する")
    func levelIsSentByExactlyTheseGames() throws {
        let leveled = try Self.playingModules()
            .filter { $0.value.contains("level: ") }
            .keys.sorted()
        // 難易度・段階を選べるゲームだけが対象。増減はプライバシー確認の対象になるので、
        // 「いつの間にか増えていた」を作らないためここで固定する（#500 の受け入れ条件）。
        #expect(leveled == [
            "GameBlocks",        // 面番号 1〜12
            "GameChess",         // CPU の強さ 3 段階
            "GameConcentration", // CPU の強さ 3 段階
            "GameGo",            // CPU の強さ 3 段階
            "GameGomoku",        // CPU の強さ 3 段階
            "GameHanafuda",      // CPU の強さ 3 段階
            "GameMinesweeper",   // 初級 / 中級 / 上級
            "GameOthello",       // CPU の強さ 3 段階
            "GameRunner",        // 面番号 1〜15
            "GameShogi",         // CPU の強さ 3 段階
            "GameSudoku",        // かんたん / ふつう / むずかしい
        ])
    }
}
