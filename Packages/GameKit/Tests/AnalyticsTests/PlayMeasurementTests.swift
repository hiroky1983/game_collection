import Testing
import Foundation
import SwiftUI
import Core
import GameKitTestSupport
import CoreTestSupport

// MARK: - Mocks

/// 視聴完了 / 未完了と、先読み済みかを指定できる広告。
private struct StubAdService: AdService {
    let earnsReward: Bool
    var isReady = true
    @MainActor func makeBannerView(width: CGFloat) -> AnyView? { nil }
    @MainActor func showInterstitial() async {}
    @MainActor func showRewardedAd() async -> Bool { earnsReward }
    @MainActor var isRewardedAdReady: Bool { isReady }
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
    isAdReady: Bool = true,
    snapshots: SnapshotStore = MemorySnapshotStore(),
    clock: TestClock = TestClock()
) -> (GameServices, SpyAnalyticsService) {
    let (analytics, spy) = makeAnalytics(clock: clock)
    let services = GameServices(
        snapshots: snapshots,
        ads: StubAdService(earnsReward: earnsReward, isReady: isAdReady),
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

    @Test("別の mode で始め直したとき、捨てたプレイの quit に載るのは前の mode（#820）")
    func quitCarriesThePreviousMode() {
        let (analytics, spy) = makeAnalytics()
        analytics.restartPlay(gameID: "solitaire", mode: .stage)
        analytics.recordProgress(gameID: "solitaire")
        analytics.restartPlay(gameID: "solitaire", mode: .endless)

        let ends = spy.events.compactMap { event -> (result: AnalyticsResult, mode: AnalyticsMode?)? in
            if case let .gameEnd(_, result, _, mode, _, _) = event { return (result, mode) } else { return nil }
        }
        #expect(ends.count == 1)
        #expect(ends.first?.result == .quit)
        #expect(ends.first?.mode == .stage, "開始時に焼き込んだ値。始め直した後の mode ではない")
    }

    @Test("決着の game_end の mode は直前の game_start と同じ（#820）")
    func finishCarriesTheStartMode() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "solitaire", mode: .singleHand)
        analytics.finishPlay(gameID: "solitaire", outcome: .win)
        analytics.restartPlay(gameID: "solitaire", mode: .tonpuu)
        analytics.finishPlay(gameID: "solitaire", outcome: .loss)
        analytics.restartPlay(gameID: "solitaire")
        analytics.recordProgress(gameID: "solitaire")
        analytics.finishPlay(gameID: "solitaire", outcome: .draw)

        let modes = spy.events.compactMap { event -> (name: String, mode: AnalyticsMode?)? in
            switch event {
            case let .gameStart(_, _, mode, _):     return ("start", mode)
            case let .gameEnd(_, _, _, mode, _, _): return ("end", mode)
            default:                             return nil
            }
        }
        #expect(modes.map(\.name) == ["start", "end", "start", "end", "start", "end"])
        #expect(modes.map(\.mode) == [.singleHand, .singleHand, .tonpuu, .tonpuu, nil, nil],
                "mode を付けずに始めたプレイの game_end に前のプレイの mode を持ち越さない")
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

    @Test("中断データを持っていても、局を復元しないゲームの離れ方は離脱")
    func unresumablePlayQuitsEvenWithSnapshot() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.markUnresumable(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: true)   // 中断データは在る

        #expect(spy.quits.map(\.gameID) == ["2048"],
                "チャリンコおじさんのように記録の控えを中断データとして残すゲームの経路")
    }

    @Test("復元しない宣言をしても、1手も指していなければ離脱にはならない")
    func unresumableWithoutProgressIsNotQuit() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.markUnresumable(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: true)

        #expect(spy.ends.isEmpty)
    }

    @Test("進行中のプレイが無いところで markUnresumable を呼んでも何も起きない")
    func markUnresumableWithoutPlayIsIgnored() {
        let (analytics, spy) = makeAnalytics()
        analytics.markUnresumable(gameID: "2048")
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: true)

        #expect(spy.ends.isEmpty, "宣言はプレイごとで、次のプレイへ持ち越さない")
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
        #expect(spy.requests.isEmpty, "要求も同じく捨てる（#659）")
    }
}

// MARK: - リワード広告の要求・ハブからの遷移（#659）

@Suite("広告の要求とハブからの遷移の計測（#659）")
@MainActor
struct OpenAndRequestTrackingTests {
    @Test("reward_request は視聴の成否に関係なく、広告の結果より先に1回出る")
    func requestIsSentBeforeTheResult() async {
        let (earned, earnedSpy) = makeServices(earnsReward: true)
        _ = await earned.showRewardedAd(gameID: "solitaire", purpose: .undo)
        #expect(earnedSpy.events.map(\.name) == ["reward_request", "reward_ad"])

        let (skipped, skippedSpy) = makeServices(earnsReward: false)
        _ = await skipped.showRewardedAd(gameID: "solitaire", purpose: .hint)
        #expect(skippedSpy.requests.map(\.purpose) == [.hint],
                "ロード失敗・途中で閉じた回こそ完了率の分母に入れる")
        #expect(skippedSpy.rewards.isEmpty)
    }

    @Test("game_open は導線・位置・続きからをそのまま送り、プレイの数え方に触らない")
    func openIsSentWithoutTouchingPlayState() {
        let (services, spy) = makeServices()
        services.gameDidOpen(gameID: "sudoku", source: .recent, position: 1, resume: true)
        services.gameDidStart(gameID: "sudoku")
        services.gameDidProgress(gameID: "sudoku")
        services.gameDidFinish(gameID: "sudoku", outcome: .win)

        #expect(spy.events.first == .gameOpen(gameID: "sudoku", source: .recent, position: 1, resume: true))
        #expect(spy.starts.count == 1, "開いたことは game_start を増やさない")
        #expect(spy.ends.map(\.result) == [.win])
    }

    @Test("開いただけで遊ばずに戻っても、game_open だけが残り quit は出ない")
    func openThenLeaveIsNotQuit() {
        let (services, spy) = makeServices()
        services.gameDidOpen(gameID: "2048", source: .hub, position: 3, resume: false)
        services.gameDidLeave(gameID: "2048")
        #expect(spy.events.map(\.name) == ["game_open"])
    }

    @Test("ハブに無い gameID の遷移は送らない")
    func unknownGameIDOpenIsDropped() {
        let (services, spy) = makeServices()
        services.gameDidOpen(gameID: "device-1234", source: .hub, position: 1, resume: false)
        #expect(spy.events.isEmpty)
    }

    @Test("共有ボタンを押すと share_tap だけが出て、プレイの数え方に触らない（#1043）")
    func shareTapIsSentWithoutTouchingPlayState() {
        let (services, spy) = makeServices()
        services.gameDidStart(gameID: "2048")
        services.gameDidProgress(gameID: "2048")
        services.gameDidFinish(gameID: "2048", outcome: .loss)
        services.gameDidTapShare(gameID: "2048")
        services.gameDidTapShare(gameID: "2048")
        services.gameDidLeave(gameID: "2048")

        #expect(spy.events.map(\.name) == ["game_start", "game_end", "share_tap", "share_tap"],
                "押した回数だけ出る。終局済みのプレイに quit は足されない")
        #expect(spy.events.last == .shareTap(gameID: "2048"))
    }

    @Test("ハブに無い gameID の共有は送らない（#1043）")
    func unknownGameIDShareIsDropped() {
        let (services, spy) = makeServices()
        services.gameDidTapShare(gameID: "device-1234")
        #expect(spy.events.isEmpty)
    }

    @Test("設定で送信をオフにすると、どちらのイベントも送らない")
    func gatedOffSendsNothing() async {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(
            service: GatedAnalyticsService(base: spy) { false },
            allowedGameIDs: testGameIDs
        )
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: StubAdService(earnsReward: true), analytics: analytics
        )
        services.gameDidOpen(gameID: "2048", source: .hub, position: 1, resume: false)
        _ = await services.showRewardedAd(gameID: "2048", purpose: .continue)
        services.gameDidTapShare(gameID: "2048")
        #expect(spy.events.isEmpty)
    }
}

// MARK: - リワード広告の提示（#780）

/// 救済の中で立つ `Task` が終わるまで待つ。実時間は待たない（スタブの広告は中断点を持たない）。
@MainActor
private func settle() async {
    for _ in 0..<10 { await Task.yield() }
}

@Suite("リワード広告の提示の計測（#780）")
@MainActor
struct RewardOfferTrackingTests {
    @Test("提示中に広告ボタンを押すと、広告を出す前に accepted を1回だけ送る")
    func acceptedIsSentOnceBeforeTheAd() async {
        let (services, spy) = makeServices()
        let rescue = RewardedRescue()
        rescue.offerDidShow(services, gameID: "2048", purpose: .continue)
        rescue.request(services, gameID: "2048", purpose: .continue, guardedBy: .checkedByGrant) { true }
        rescue.offerDidClose()   // 報酬を受け取って幕が閉じた
        await settle()

        #expect(spy.offers.map(\.result) == [.accepted])
        #expect(spy.offers.first?.gameID == "2048")
        #expect(spy.offers.first?.purpose == .continue)
        #expect(spy.events.map(\.name) == ["reward_offer", "reward_request", "reward_ad"],
                "先読みの有無は広告を出す前に読む")
    }

    @Test("先読みの広告が無いときに押すと not_ready")
    func notReadyWhenNoPreloadedAd() async {
        let (services, spy) = makeServices(isAdReady: false)
        let rescue = RewardedRescue()
        rescue.offerDidShow(services, gameID: "solitaire", purpose: .revival)
        rescue.requestHandledByModel(withOutcome: { .granted })
        await settle()

        #expect(spy.offers.map(\.result) == [.notReady])
    }

    @Test("押さずに閉じると declined を1回だけ送る（重ねて閉じても増えない）")
    func declinedWhenClosedWithoutTapping() {
        let (services, spy) = makeServices()
        let rescue = RewardedRescue()
        rescue.offerDidShow(services, gameID: "solitaire", purpose: .undo)
        rescue.offerDidShow(services, gameID: "solitaire", purpose: .undo)   // 再描画で重ねて呼ばれても1回の提示
        rescue.offerDidClose()
        rescue.offerDidClose()

        #expect(spy.offers.map(\.result) == [.declined])
        #expect(spy.requests.isEmpty)
    }

    @Test("見なかった後にもう一度押しても、同じ提示を2回目として数えない")
    func retryWithinTheSameOfferIsNotAnotherOffer() async {
        let (services, spy) = makeServices(earnsReward: false)
        let rescue = RewardedRescue()
        rescue.offerDidShow(services, gameID: "2048", purpose: .continue)
        rescue.request(services, gameID: "2048", purpose: .continue, guardedBy: .checkedByGrant) { true }
        await settle()
        rescue.request(services, gameID: "2048", purpose: .continue, guardedBy: .checkedByGrant) { true }
        await settle()
        rescue.offerDidClose()   // 結局あきらめて閉じた

        #expect(spy.offers.map(\.result) == [.accepted], "提示は1回")
        #expect(spy.requests.count == 2, "タップの数は reward_request が持つ")
    }

    @Test("提示が無い押し方（常設のボタン）は reward_offer を送らない")
    func noOfferWithoutPresentation() async {
        let (services, spy) = makeServices()
        let rescue = RewardedRescue()
        rescue.request(services, gameID: "sudoku", purpose: .hint, guardedBy: .checkedByGrant) { true }
        await settle()

        #expect(spy.offers.isEmpty)
        #expect(spy.requests.count == 1)
    }

    @Test("閉じたあとにまた出たら、次の1回の提示として数える")
    func nextPresentationIsCountedAgain() {
        let (services, spy) = makeServices()
        let rescue = RewardedRescue()
        for _ in 0..<3 {
            rescue.offerDidShow(services, gameID: "sudoku", purpose: .continue)
            rescue.offerDidClose()
        }
        #expect(spy.offers.map(\.result) == [.declined, .declined, .declined])
    }

    @Test("提示はプレイの数え方に影響せず、ハブに無い gameID・送信オフでは送らない")
    func offerDoesNotTouchPlayStateAndRespectsGates() {
        let (services, spy) = makeServices()
        services.gameDidStart(gameID: "2048")
        let rescue = RewardedRescue()
        rescue.offerDidShow(services, gameID: "2048", purpose: .continue)
        rescue.offerDidClose()
        services.gameDidFinish(gameID: "2048", outcome: .loss)
        #expect(spy.starts.count == 1)
        #expect(spy.ends.map(\.result) == [.loss])

        let unknown = RewardedRescue()
        unknown.offerDidShow(services, gameID: "device-1234", purpose: .continue)
        unknown.offerDidClose()
        #expect(spy.offers.count == 1, "登録されていない gameID は捨てる")

        let gatedSpy = SpyAnalyticsService()
        let gated = GameServices(
            snapshots: MemorySnapshotStore(), ads: StubAdService(earnsReward: true),
            analytics: GameAnalytics(service: GatedAnalyticsService(base: gatedSpy) { false },
                                     allowedGameIDs: testGameIDs)
        )
        let off = RewardedRescue()
        off.offerDidShow(gated, gameID: "2048", purpose: .continue)
        off.offerDidClose()
        #expect(gatedSpy.events.isEmpty)
    }
}

/// 提示の計測は各画面の View が「出ているか」を渡さないと出ない。View はテストから動かせないので、
/// `RewardGuardCallSiteTests` と同じくソースを走査して、救済ごとに提示の結線があることを固定する（#780）。
@Suite("リワード広告の提示の結線（#780）")
struct RewardOfferWiringTests {
    private static let sourcesRoot = SourceScan.packageRoot.appendingPathComponent("Sources")

    /// モジュール名 → そのモジュールの全ソースを連結した文字列。
    private static func modules() throws -> [String: String] {
        var joined: [String: String] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: sourcesRoot.path)
        where path.hasSuffix(".swift") {
            let module = String(path.prefix(while: { $0 != "/" }))
            joined[module, default: ""] += try String(contentsOf: sourcesRoot.appendingPathComponent(path), encoding: .utf8)
        }
        return joined
    }

    /// 提示の瞬間が無いので数えない救済（モジュール名.変数名）。常設の「ヒント」ボタンで、
    /// 押すと確認を挟まずに広告へ進む（`reward_request ÷ game_start` で読む）。
    private static let unpresentedRescues: Set<String> = ["GameSudoku.hintRescue"]

    @Test("各ゲームの救済は、提示の結線を持つか Core の部品（待った・コンティニューの幕）へ渡している")
    func everyRescueIsWiredToAnOffer() throws {
        let modules = try Self.modules()
        let declaration = try NSRegularExpression(pattern: #"var (\w+) = RewardedRescue\(\)"#)
        var declared: [String] = []
        var unwired: [String] = []
        for (module, text) in modules where module != "Core" {
            let range = NSRange(text.startIndex..., in: text)
            for match in declaration.matches(in: text, range: range) {
                guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
                let name = String(text[nameRange])
                let key = "\(module).\(name)"
                declared.append(key)
                let wired = text.contains(".rewardOffer(\(name),") || text.contains("rescue: \(name)")
                if !wired && !Self.unpresentedRescues.contains(key) { unwired.append(key) }
            }
        }
        #expect(declared.count >= 20, "走査のパターンが壊れている可能性（宣言 \(declared.count) 件）")
        #expect(unwired.isEmpty, "提示を数えていない救済がある: \(unwired.sorted())")
        // 除外は実在して、かつ本当に結線していないものだけ（直したら除外から外す）。
        for key in Self.unpresentedRescues {
            #expect(declared.contains(key), "除外リストの \(key) が見つからない")
            let parts = key.split(separator: ".")
            #expect(modules[String(parts[0])]?.contains(".rewardOffer(\(parts[1]),") == false,
                    "\(key) は結線済みなので除外から外す")
        }
    }

    @Test("Core の待ったとコンティニューの幕は、自分で提示を数えている")
    func coreComponentsTrackTheirOffers() throws {
        let core = try #require(try Self.modules()["Core"])
        #expect(core.contains(".rewardOffer(undoRescue, for: .undo, isPresented: showUndoConfirm && model.undoUsed"),
                "盤ゲームの待った（無料の確認は数えない）")
        #expect(core.contains(".rewardOffer(continueRescue, for: .continue, isPresented: canContinue"),
                "コンティニューの幕")
    }

    @Test("救済の3つの入口は、広告を出す前に提示を受諾として閉じる")
    func everyEntryResolvesTheOfferFirst() throws {
        let core = try #require(try Self.modules()["Core"])
        let entries = core.components(separatedBy: "isWatching = true\n        offerDidAccept()").count - 1
        #expect(entries == 3, "request・requestHandledByModel 2種のどれかで受諾を閉じていない（\(entries) 件）")
    }
}

// MARK: - ハブの遷移計測の結線（#659）

/// `game_open` の発火点は App ターゲット（`HubView`）にあり GameKit のテストから import できないため、
/// `HubRecentRowWiringTests` と同じく `App/` 一式を走査して結線を固定する。
@Suite("ハブの遷移計測の結線（#659）")
struct GameOpenWiringTests {
    private static func count(_ needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    @Test("送るのは path が空 → 非空になった1か所だけ")
    func openIsSentFromTheSinglePathTransition() throws {
        let source = try SourceScan.appSources()
        #expect(Self.count("gameDidOpen(", in: source) == 1, "game_open の発火点が1か所ではない")
        #expect(
            source.range(
                of: #"if oldPath\.isEmpty, let opened = newPath\.first \{\s*services\.gameDidOpen\("#,
                options: .regularExpression
            ) != nil,
            "空 → 非空の遷移と gameDidOpen の結線が切れている"
        )
    }

    @Test("ハブのすべての遷移が導線を持つ HubRoute で積まれる")
    func everyLinkCarriesItsSource() throws {
        let source = try SourceScan.appSources()
        let links = Self.count("NavigationLink(value:", in: source)
        #expect(links >= 2, "走査のパターンが壊れている可能性")
        #expect(Self.count("NavigationLink(value: HubRoute(", in: source) == links,
                "導線を持たない遷移がある（game_open の source が分からない）")
        // 導線ごとに正しい source を載せている。
        #expect(source.range(of: #"gameID: module\.id, source: \.hub, position: index \+ 1"#,
                             options: .regularExpression) != nil, "グリッド")
        #expect(source.range(of: #"gameID: candidate\.gameID, source: \.recent,\s*position: offset \+ 1"#,
                             options: .regularExpression) != nil, "つづき・最近")
        #expect(source.range(of: #"gameID: id, source: \.recommendation, position: nil"#,
                             options: .regularExpression) != nil, "レコメンド")
        #expect(source.range(of: #"gameID: pick, source: \.firstPick, position: nil"#,
                             options: .regularExpression) != nil, "はじめの1本")
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
    private static let sourcesRoot = SourceScan.packageRoot.appendingPathComponent("Sources")

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
        // 区切りの直後まで見ないのは、#526 で救済の段取りを `RewardedRescue.request` へ
        // 移したときに `purpose: .undo)` が `purpose: .undo,` に変わったため。
        // 引数の並びに依存させると、次に並びが変わったときも同じ理由で空振りする。
        let counts = Dictionary(uniqueKeysWithValues: RewardPurpose.allCases.map { purpose in
            (purpose, sources.reduce(0) { $0 + $1.text.components(
                separatedBy: "purpose: .\(purpose.rawValue)"
            ).count - 1 })
        })

        let unused = counts.filter { $0.value == 0 }.keys.map(\.rawValue).sorted()
        #expect(unused.isEmpty, "発火箇所の無い purpose がある: \(unused)")

        // 呼び出しの総数 = すべての面の数。面を増やしたらここも動くので、
        // 「増やしたのに purpose を付け忘れた」も上のテストと合わせて検出できる。
        // 盤ゲーム 5 本の待ったは Core の `BoardUndoButton` 1 か所に寄せた（#828）ので、ここには数えない。
        // 2048・ブロックならべ・ナンプレの広告コンティニューの幕も Core の `RewardedContinueOverlay` に寄せた（#829）。
        // 麻雀の最終局延長（#1201）で 1 か所増えて 17。ルーレットのチップ切れ復活（#1318）で 18。
        // いろリレーの引き札の免除（#1320）で 19。ぱっと暗算の見直し（#1321）で 20。スピードのタイム（#1323）で 21。
        #expect(counts.values.reduce(0, +) == 21, "リワード広告の面は21箇所（Core に寄せた待った・コンティニューの幕を除く）")
    }
}

// MARK: - 計測の付け忘れ（#500）

/// 途中離脱と難易度は**ゲーム側が伝えないと出ない**ので、伝えているかをソース走査で固定する。
///
/// `gameDidProgress` を呼ばないゲームは、盤面を捨てても `quit` が一切出ない。テストからは
/// 各ゲームの操作を通しで再現できないため、呼び出しの存在そのものを検査対象にする。
@Suite("プレイ計測の付け忘れ（#500）")
struct PlayMeasurementCallSiteTests {
    private static let sourcesRoot = SourceScan.packageRoot.appendingPathComponent("Sources")

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

    /// プレイを数えているモジュール（= ハブに並ぶ 23 本のゲーム + 企画倉庫のルーレット #1318・くっつきフルーツ #1319・いろリレー #1320・ぱっと暗算 #1321・バックギャモン #1322）。
    private static func playingModules() throws -> [String: String] {
        try modules().filter {
            $0.value.contains("gameDidStart(") || $0.value.contains("gameDidRestart(")
        }
    }

    @Test("プレイを数えるゲームは全て gameDidProgress も呼んでいる")
    func everyGameReportsProgress() throws {
        let games = try Self.playingModules()
        #expect(games.count == 29, "ハブに並ぶゲームは23本 + 企画倉庫のルーレット（#1318）・くっつきフルーツ（#1319）・いろリレー（#1320）・ぱっと暗算（#1321）・バックギャモン（#1322）・スピード（#1323）")

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
            "GameAnzan",         // 桁数・個数・速さの段の和を 4 段階へ丸める（#1321・企画倉庫）
            "GameBackgammon",    // CPU の強さ 4 段階（#1322・企画倉庫）
            "GameBlocks",        // 面番号 1〜12
            "GameChess",         // CPU の強さ 3 段階
            "GameConcentration", // CPU の強さ 3 段階
            "GameGo",            // CPU の強さ 3 段階
            "GameGomoku",        // CPU の強さ 3 段階
            "GameHanafuda",      // CPU の強さ 3 段階
            "GameMinesweeper",   // 初級 / 中級 / 上級
            "GameOthello",       // CPU の強さ 3 段階
            "GameRunner",        // 面番号 1〜15
            "GameShiritori",     // ノルマ 3 段階（やさしい / ふつう / むずかしい・#1243）
            "GameShogi",         // CPU の強さ 3 段階
            "GameSpeed",         // CPU の速さ 3 段階（#1323・企画倉庫）
            "GameSpider",        // 1 / 2 / 4 スート（#717）
            "GameSudoku",        // かんたん / ふつう / むずかしい
        ])
    }
}

// MARK: - 無料ヒントの使用回数（#1326）

@Suite("game_end の hints_used（#1326）")
@MainActor
struct HintsUsedTrackingTests {
    private func endParameters(_ spy: SpyAnalyticsService) -> [[String: AnalyticsValue]] {
        spy.events.compactMap { if case .gameEnd = $0 { return $0.parameters } else { return nil } }
    }

    @Test("パラメータ: 0 のときは鍵ごと送らず、1 以上のときだけ Int で載る")
    func parameterOnlyWhenUsed() {
        let none = AnalyticsEvent.gameEnd(gameID: "2048", result: .win, durationSec: 1)
        #expect(none.parameters["hints_used"] == nil)
        #expect(Set(none.parameters.keys) == ["game_id", "result", "duration_sec"])

        let used = AnalyticsEvent.gameEnd(gameID: "2048", result: .win, durationSec: 1, hintsUsed: 3)
        #expect(used.parameters["hints_used"] == .int(3))
        #expect(Set(used.parameters.keys) == ["game_id", "result", "duration_sec", "hints_used"])
    }

    @Test("ヒントを使ってから途中離脱（leaveGame）しても quit に載る")
    func quitAfterHintCarriesCount() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.recordHintUsed(gameID: "2048")
        analytics.recordHintUsed(gameID: "2048")

        analytics.leaveGame(gameID: "2048", isResumable: false)

        #expect(endParameters(spy).first?["result"] == .string("quit"))
        #expect(endParameters(spy).first?["hints_used"] == .int(2))
    }

    @Test("ヒントを使ってから決着（finishPlay）しても載る")
    func finishAfterHintCarriesCount() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordHintUsed(gameID: "2048")

        analytics.finishPlay(gameID: "2048", outcome: .loss)

        #expect(endParameters(spy).first?["hints_used"] == .int(1))
    }

    @Test("休憩（再開できる離脱）をまたいでも数えは残り、再開後の決着に載る")
    func hintCountSurvivesResumableLeave() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.recordHintUsed(gameID: "2048")
        analytics.leaveGame(gameID: "2048", isResumable: true)
        #expect(endParameters(spy).isEmpty)

        analytics.finishPlay(gameID: "2048", outcome: .win)

        #expect(endParameters(spy).first?["hints_used"] == .int(1))
    }

    @Test("次のプレイへ持ち越さない（始め直すと 0 に戻り、鍵も出ない）")
    func restartResetsCount() {
        let (analytics, spy) = makeAnalytics()
        analytics.startPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")
        analytics.recordHintUsed(gameID: "2048")
        analytics.restartPlay(gameID: "2048")
        analytics.recordProgress(gameID: "2048")

        analytics.finishPlay(gameID: "2048", outcome: .win)

        let ends = endParameters(spy)
        #expect(ends.count == 2)
        #expect(ends.first?["hints_used"] == .int(1))
        #expect(ends.last?.keys.contains("hints_used") == false)
    }

    @Test("決着後や開始を数えていないプレイのヒントは数えない")
    func hintOutsideInFlightIsIgnored() {
        let (analytics, spy) = makeAnalytics()
        analytics.recordHintUsed(gameID: "2048")           // 開始前
        analytics.startPlay(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .win)
        analytics.recordHintUsed(gameID: "2048")           // 決着後
        analytics.restartPlay(gameID: "2048")
        analytics.finishPlay(gameID: "2048", outcome: .win)

        #expect(endParameters(spy).allSatisfy { $0.keys.contains("hints_used") == false })
    }
}
