import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameSpeed

/// 時計を手で進める（反応の間・所要時間の計測を実時間に頼らない）。
@MainActor
private final class ManualClock {
    var current = Date(timeIntervalSince1970: 1_000_000)
    /// 勝利タイムを数える `ElapsedClock` に差し込む時計（`advance` と一緒に進む）。
    let elapsed = CoreTestSupport.ManualClock()
    func advance(_ seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
        elapsed.advance(by: .seconds(seconds))
    }
    func advance(_ duration: Duration) {
        let (s, attos) = duration.components
        advance(TimeInterval(s) + TimeInterval(attos) / 1e18)
    }
}

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil,
    feedback: SpyFeedbackService = SpyFeedbackService()
) -> GameServices {
    GameServices(
        snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [SpeedModel.gameID]) }
    )
}

@MainActor
private func makeLog(_ name: String) -> PlayLog {
    let suite = "asobiba.speed.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlayLog(defaults: defaults)
}

/// 既定オフの「ゆっくりモード」を使い捨ての suite で作る。
private func makeSlowMode(_ name: String, enabled: Bool) -> FeedbackPreference {
    let suite = "asobiba.speed.tests.slow.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let preference = FeedbackPreference(key: "slow", defaults: defaults, defaultValue: false)
    preference.isEnabled = enabled
    return preference
}

/// ヒント表示（#190）の設定を使い捨ての suite で作る。
private func makeHints(_ name: String, enabled: Bool) -> FeedbackPreference {
    let suite = "asobiba.speed.tests.hints.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let preference = FeedbackPreference(key: "hints", defaults: defaults, defaultValue: true)
    preference.isEnabled = enabled
    return preference
}

private func card(_ suit: SpeedSuit, _ rank: Int) -> SpeedCard {
    SpeedCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

/// 反応の間の下限・上限（±20% の揺らぎ）。
private func reactionRange(_ level: SpeedLevel, multiplier: Double = 1) -> ClosedRange<Duration> {
    let base = Double(level.reactionMilliseconds) * multiplier
    return .milliseconds(Int((base * 0.8).rounded(.down)))...(.milliseconds(Int((base * 1.2).rounded(.up))))
}

@MainActor
@Suite("スピードの Model")
struct SpeedModelTests {

    @Test("開いた直後は何も始めず、速さは既定で、CPU の待ちも無い")
    func freshStart() {
        let model = SpeedModel(services: makeServices(), seed: 1)
        #expect(model.phase == .idle)
        #expect(model.settings == .standard)
        #expect(model.humanHand.isEmpty && model.cpuHand.isEmpty)
        #expect(model.nextCPUWait() == nil, "始める前は CPU が動かない")
        #expect(!model.canFlip)
        #expect(!model.canUseTimeout)
    }

    @Test("始めると赤 26 枚があなた、黒 26 枚が CPU に配られ、4 枚ずつの手札と 1 枚ずつの台札になる")
    func deal() {
        let model = SpeedModel(services: makeServices(), seed: 2)
        model.start(SpeedSettings(level: .fast))
        #expect(model.phase == .playing)
        #expect(model.settings.level == .fast)
        #expect(model.gameSerial == 1)
        #expect(model.humanHand.count == 4)
        #expect(model.cpuHand.count == 4)
        #expect(model.humanStock.count == 21)
        #expect(model.cpuStock.count == 21)
        #expect(model.piles.map(\.count) == [1, 1])
        let human = model.humanHand + model.humanStock + model.piles[0]
        let cpu = model.cpuHand + model.cpuStock + model.piles[1]
        #expect(human.count == 26 && human.allSatisfy { $0.suit.isRed })
        #expect(cpu.count == 26 && cpu.allSatisfy { !$0.suit.isRed })
        #expect(Set((human + cpu).map(\.id)).count == 52, "52 枚がちょうど 1 回ずつ")
        #expect(model.remaining(of: .human) == 25 && model.remaining(of: .cpu) == 25)
    }

    @Test("種が同じなら同じ配り、違えば違う配り")
    func seededDeal() {
        let a = SpeedModel(services: makeServices(), seed: 5)
        let b = SpeedModel(services: makeServices(), seed: 5)
        let c = SpeedModel(services: makeServices(), seed: 6)
        a.start(.standard); b.start(.standard); c.start(.standard)
        #expect(a.humanHand == b.humanHand && a.cpuHand == b.cpuHand)
        #expect(a.humanHand != c.humanHand || a.cpuHand != c.cpuHand)
    }

    @Test("出せる手札をタップすると台札に乗り、同じ位置に山札から補充される")
    func playFromHand() {
        let feedback = SpyFeedbackService()
        let model = SpeedModel(services: makeServices(feedback: feedback), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
            humanStock: [card(.diamonds, 3), card(.diamonds, 11)],
            cpuHand: [card(.spades, 2), card(.clubs, 10), card(.spades, 1), card(.spades, 8)],
            cpuStock: [card(.clubs, 4)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        let run = model.cpuRun
        #expect(model.humanPlayableIDs == [card(.hearts, 5).id, card(.hearts, 2).id])
        feedback.reset()
        model.tapHandCard(card(.hearts, 5))
        #expect(model.piles[0].last == card(.hearts, 5))
        #expect(model.humanHand == [card(.diamonds, 11), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
                "出した位置（先頭）に山札の一番上が入る")
        #expect(model.humanStock == [card(.diamonds, 3)])
        #expect(model.cpuRun == run + 1, "場が動いたので CPU の待ちが組み直される")
        #expect(feedback.impacts == [.card(.place)])
    }

    @Test("出せない手札をタップしても何も起きず、警告の触覚だけ鳴る")
    func tapUnplayable() {
        let feedback = SpyFeedbackService()
        let model = SpeedModel(services: makeServices(feedback: feedback), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            cpuHand: [card(.spades, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        let before = (model.humanHand, model.piles, model.cpuRun)
        feedback.reset()
        model.tapHandCard(card(.hearts, 9))
        #expect(model.humanHand == before.0 && model.piles == before.1 && model.cpuRun == before.2)
        #expect(feedback.notices(of: .warning) == 1)
        #expect(model.selectedID == nil)
    }

    @Test("両方の台札に置ける札は選択になり、台札のタップで置く")
    func selectThenPile() {
        let model = SpeedModel(services: makeServices(), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9)],
            humanStock: [card(.diamonds, 3)],
            cpuHand: [card(.spades, 2)],
            piles: [[card(.spades, 4)], [card(.clubs, 6)]]
        )
        model.tapHandCard(card(.hearts, 5))
        #expect(model.selectedID == card(.hearts, 5).id)
        #expect(model.humanHand.count == 2, "まだ出していない")
        model.tapHandCard(card(.hearts, 5))
        #expect(model.selectedID == nil, "もう一度タップで選択を外す")
        model.tapHandCard(card(.hearts, 5))
        model.tapPile(1)
        #expect(model.piles[1].last == card(.hearts, 5))
        #expect(model.selectedID == nil)
        #expect(model.humanHand == [card(.diamonds, 3), card(.hearts, 9)])
    }

    @Test("選択なしで台札をタップしたとき、そこに置ける手札がちょうど 1 枚なら出す")
    func tapPileWithoutSelection() {
        let feedback = SpyFeedbackService()
        let model = SpeedModel(services: makeServices(feedback: feedback), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9), card(.hearts, 7)],
            cpuHand: [card(.spades, 2)],
            piles: [[card(.spades, 4)], [card(.clubs, 8)]]
        )
        model.tapPile(0)
        #expect(model.piles[0].last == card(.hearts, 5), "左に置けるのは ♥5 だけ")
        // 右（♣8）には ♥9 と ♥7 の 2 枚が置けるので、どちらか分からず出さない。
        feedback.reset()
        model.tapPile(1)
        #expect(model.piles[1].last == card(.clubs, 8))
        #expect(feedback.notices(of: .warning) == 1)
    }

    @Test("どちらも出せなくなったら「めくる」で両方の山札から 1 枚ずつ台札に置く")
    func flipWhenStuck() {
        let feedback = SpyFeedbackService()
        let model = SpeedModel(services: makeServices(feedback: feedback), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 3), card(.diamonds, 10)],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 4), card(.clubs, 8)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(model.isStuck && model.canFlip)
        let run = model.cpuRun
        feedback.reset()
        model.flipStocks()
        #expect(model.piles[0] == [card(.spades, 6), card(.diamonds, 10)])
        #expect(model.piles[1] == [card(.clubs, 3), card(.clubs, 8)])
        #expect(model.humanStock == [card(.diamonds, 3)] && model.cpuStock == [card(.clubs, 4)])
        #expect(model.consecutiveFlips == 1)
        #expect(model.cpuRun == run + 1)
        #expect(feedback.impacts == [.card(.flip)])
        // めくった結果 ♥9 が左（♦10）と右（♣8）に、♥11 が左（♦10）に出せるようになった。
        #expect(!model.isStuck)
        #expect(model.humanPlayableIDs == [card(.hearts, 9).id, card(.hearts, 11).id])
        #expect(model.playableTargets(for: card(.hearts, 9)) == [0, 1])
    }

    @Test("出せる札があるときは「めくる」が押せず、警告だけ鳴る")
    func cannotFlipWhilePlayable() {
        let feedback = SpyFeedbackService()
        let model = SpeedModel(services: makeServices(feedback: feedback), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 5)], cpuHand: [card(.spades, 9)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(!model.canFlip)
        feedback.reset()
        let before = model.piles
        model.flipStocks()
        #expect(model.piles == before)
        #expect(feedback.notices(of: .warning) == 1)
    }

    @Test("山札が尽きた人はめくらない。台札を山札に抱え直さず、めくるのは山札が残っている側だけ")
    func exhaustedSideDoesNotFlip() {
        let model = SpeedModel(services: makeServices(), seed: 3)
        let leftPile = [card(.diamonds, 1), card(.diamonds, 6), card(.spades, 6)]
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 4)],
            piles: [leftPile, [card(.clubs, 3)]]
        )
        #expect(model.isStuck)
        model.flipStocks()
        // あなたの側（山札なし）は台札もそのまま。残りは手札の 2 枚のまま増えない。
        #expect(model.piles[0] == leftPile)
        #expect(model.humanStock.isEmpty)
        #expect(model.remaining(of: .human) == 2, "出し切りかけた人の残りが台札のぶん戻らない")
        // CPU 側は山札があるので普通にめくる。
        #expect(model.piles[1] == [card(.clubs, 3), card(.clubs, 4)])
        #expect(model.cpuStock.isEmpty)
        #expect(model.consecutiveFlips == 1)
    }

    @Test("両方の山札が尽きてどちらも出せなければ、台札をそれぞれ切り直すだけで、手札・山札の枚数は変えない")
    func bothExhaustedReshufflesPilesInPlace() {
        let model = SpeedModel(services: makeServices(), seed: 11)
        let left = [card(.diamonds, 1), card(.diamonds, 6), card(.spades, 6), card(.hearts, 2), card(.clubs, 7)]
        let right = [card(.clubs, 3), card(.spades, 13), card(.hearts, 4), card(.diamonds, 9), card(.clubs, 12)]
        model.configureForTesting(
            humanHand: [card(.hearts, 9)], humanStock: [],
            cpuHand: [card(.spades, 2)], cpuStock: [],
            piles: [left, right]
        )
        // 台札は 7 と Q。♥9・♠2 はどちらにも出せない。
        #expect(model.isStuck)
        model.flipStocks()
        #expect(model.humanStock.isEmpty && model.cpuStock.isEmpty, "台札を山札へ戻さない")
        #expect(model.remaining(of: .human) == 1 && model.remaining(of: .cpu) == 1)
        #expect(Set(model.piles[0].map(\.id)) == Set(left.map(\.id)), "左の台札の札はそのまま左に残る")
        #expect(Set(model.piles[1].map(\.id)) == Set(right.map(\.id)))
        #expect(model.consecutiveFlips == 1)
    }

    @Test("続けてめくるとき（2 回目以降）は、CPU がめくるまでの間が短い")
    func repeatFlipIsQuicker() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 3, now: { clock.current },
                               slowMode: makeSlowMode("repeatFlip", enabled: false))
        model.configureForTesting(
            humanHand: [card(.hearts, 9)], humanStock: [card(.diamonds, 7), card(.diamonds, 3)],
            cpuHand: [card(.spades, 12)], cpuStock: [card(.spades, 8), card(.clubs, 3)],
            piles: [[card(.diamonds, 1)], [card(.clubs, 5)]]
        )
        #expect(model.isStuck)
        #expect(model.nextCPUWait() == .milliseconds(SpeedRules.stuckDelayMilliseconds))
        clock.advance(.milliseconds(SpeedRules.stuckDelayMilliseconds))
        model.performCPUAction()
        #expect(model.consecutiveFlips == 1)
        // めくった台札は 3 と 3。♥9・♠Q はまだ出せない。
        #expect(model.isStuck)
        #expect(model.nextCPUWait() == .milliseconds(SpeedRules.stuckRepeatDelayMilliseconds))
        #expect(SpeedRules.stuckRepeatDelayMilliseconds < SpeedRules.stuckDelayMilliseconds)
    }

    @Test("めくるだけが 20 回続いて場が動かなければ引き分け")
    func drawAfterEndlessFlips() {
        let spy = SpyAnalyticsService()
        let model = SpeedModel(services: makeServices(analytics: spy), seed: 3)
        // 手札はどちらも 1 枚で、台札も 1 枚ずつ。切り直しても同じ札が戻るので永遠につながらない。
        model.configureForTesting(
            humanHand: [card(.hearts, 9)], humanStock: [],
            cpuHand: [card(.spades, 12)], cpuStock: [],
            piles: [[card(.diamonds, 1)], [card(.clubs, 3)]]
        )
        var flips = 0
        while model.phase == .playing, flips < 100 {
            model.flipStocks()
            flips += 1
        }
        #expect(flips == SpeedRules.maxConsecutiveFlips)
        #expect(model.phase == .result)
        #expect(model.isDraw && model.winner == nil)
        #expect(model.reviewOutcome == .draw)
        #expect(spy.ends.count == 1 && spy.ends.first?.result == .draw)
    }

    @Test("誰かが出せば、めくった回数は 0 に戻る")
    func flipsResetOnPlay() {
        let model = SpeedModel(services: makeServices(), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10)],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        model.flipStocks()
        #expect(model.consecutiveFlips == 1)
        model.tapHandCard(card(.hearts, 9))   // 左の ♦10 に出せる
        #expect(model.consecutiveFlips == 0)
    }

    @Test("手札と山札を出し切ったら勝ち。所要時間が記録され、連勝と最速が更新される")
    func humanWins() {
        let clock = ManualClock()
        let log = makeLog("win")
        let spy = SpyAnalyticsService()
        let feedback = SpyFeedbackService()
        let model = SpeedModel(services: makeServices(log: log, analytics: spy, feedback: feedback), seed: 3, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.start(SpeedSettings(level: .slow))
        clock.advance(41.2)
        model.configureForTesting(
            humanHand: [card(.hearts, 5)], humanStock: [],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        feedback.reset()
        model.tapHandCard(card(.hearts, 5))
        #expect(model.phase == .result)
        #expect(model.winner == .human && !model.isDraw)
        #expect(model.reviewOutcome == .win)
        #expect(model.winSeconds == 42, "切り上げ")
        #expect(model.remaining(of: .human) == 0)
        #expect(feedback.notices(of: .success) == 1)
        #expect(spy.ends.count == 1 && spy.ends.first?.result == .win)
        #expect(model.streak == 1)
        #expect(model.bestSeconds == 42)
        #expect(model.recordResult != nil)
        let record = log.record(gameID: SpeedModel.gameID, variant: "slow")
        #expect(record?.currentStreak == 1)
        #expect(record?.bestSeconds == 42)
        #expect(model.nextCPUWait() == nil, "決着後は CPU が動かない")
    }

    @Test("CPU を止めている間（シート・背面・広告）は勝利タイムに乗らない")
    func winSecondsExcludesHeldTime() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 3, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.start(SpeedSettings(level: .slow))
        clock.advance(10)
        model.holdCPU(.sheet, true)
        clock.advance(300)
        model.holdCPU(.inactive, true)   // シート中に背面へ回っても二重に数えない
        clock.advance(300)
        model.holdCPU(.sheet, false)
        clock.advance(300)
        model.holdCPU(.inactive, false)
        clock.advance(5)
        model.configureForTesting(
            humanHand: [card(.hearts, 5)], humanStock: [],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        model.tapHandCard(card(.hearts, 5))
        #expect(model.winner == .human)
        #expect(model.winSeconds == 15)
    }

    @Test("保留中に始まったゲームは、保留が解けるまで勝利タイムを数えない")
    func winSecondsStartsAfterHeldRelease() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 3, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.holdCPU(.sheet, true)
        model.start(SpeedSettings(level: .slow))
        clock.advance(300)
        model.holdCPU(.sheet, false)
        clock.advance(4)
        model.configureForTesting(
            humanHand: [card(.hearts, 5)], humanStock: [],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        model.tapHandCard(card(.hearts, 5))
        #expect(model.winSeconds == 4)
    }

    @Test("CPU が出し切ったら負け。時間は記録されず、連勝は 0 に戻る")
    func cpuWins() {
        let clock = ManualClock()
        let log = makeLog("lose")
        let spy = SpyAnalyticsService()
        let feedback = SpyFeedbackService()
        let model = SpeedModel(services: makeServices(log: log, analytics: spy, feedback: feedback), seed: 3, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10)],
            cpuHand: [card(.spades, 5)], cpuStock: [],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        let wait = model.nextCPUWait()
        #expect(wait != nil)
        clock.advance(wait!)
        feedback.reset()
        model.performCPUAction()
        #expect(model.phase == .result)
        #expect(model.winner == .cpu)
        #expect(model.reviewOutcome == .loss)
        #expect(model.winSeconds == nil)
        #expect(feedback.notices(of: .error) == 1)
        #expect(spy.ends.first?.result == .loss)
        #expect(model.streak == 0)
        #expect(log.record(gameID: SpeedModel.gameID, variant: "normal")?.bestSeconds == nil)
    }

    // MARK: - CPU の待ち

    @Test("CPU は出せる札を見つけてから反応の間だけ待ち、過ぎたら出す。途中で呼んでも出さない")
    func cpuReaction() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            cpuHand: [card(.spades, 5), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .normal)
        )
        let wait = model.nextCPUWait()
        #expect(wait != nil)
        #expect(reactionRange(.normal, multiplier: SpeedRules.humanStuckReactionRatio).contains(wait!), "あなたが出せないので反応は半分の間 ±20%: \(String(describing: wait))")
        // 半分だけ進めても出さない。残りは縮む。
        clock.advance(wait! / 2)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 6), "まだ出さない")
        let remaining = model.nextCPUWait()
        #expect(remaining != nil && remaining! < wait!)
        #expect(remaining! <= wait! - wait! / 2 + .milliseconds(1))
        clock.advance(remaining!)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 5), "反応の間が過ぎたら出す")
        #expect(model.cpuHand == [card(.clubs, 2), card(.spades, 12)], "出した位置に山札から補充")
    }

    @Test("あなたが出しても、CPU が見つけていた札の反応の間は持ち越される（連打で先送りできない）")
    func cpuReactionSurvivesHumanPlay() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 2), card(.hearts, 4)],
            humanStock: [card(.diamonds, 12), card(.diamonds, 11)],
            cpuHand: [card(.spades, 5), card(.spades, 12)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .normal)
        )
        let wait = model.nextCPUWait()!
        clock.advance(wait / 2)
        // あなたが右（♣3）に ♥2 → ♦11? いや ♥4 を出す。CPU の ♠5 は左（♠6）に出せるまま。
        model.tapHandCard(card(.hearts, 4))
        #expect(model.piles[1].last == card(.hearts, 4))
        let remaining = model.nextCPUWait()!
        #expect(remaining <= wait - wait / 2 + .milliseconds(1), "残りは減ったまま: \(remaining) / \(wait)")
    }

    @Test("CPU が見つけていた札が出せなくなったら仕切り直す")
    func cpuRearmsWhenTargetVanishes() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 7), card(.hearts, 10)],
            humanStock: [card(.diamonds, 8)],
            cpuHand: [card(.spades, 5), card(.spades, 12)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .normal)
        )
        let first = model.nextCPUWait()!
        clock.advance(first / 2)
        // あなたが左（♠6）に ♥7 を置くと、CPU の ♠5 は出せなくなる。補充された ♦8 はあなたが左に出せる。
        model.tapHandCard(card(.hearts, 7))
        #expect(!model.cpuHasPlayable && model.humanHasPlayable)
        #expect(model.nextCPUWait() == SpeedRules.scanInterval, "あなたが出せるあいだは場を見直すだけ")
        model.performCPUAction()
        #expect(model.piles[0].last == card(.hearts, 7), "CPU は何もしない")
        // ♦8 を出すと、あなたの ♥10 も CPU の ♠5・♠12 も出せない。両方つまるので、めくるまでの間を数え直す。
        model.tapHandCard(card(.diamonds, 8))
        #expect(model.piles[0].last == card(.diamonds, 8))
        #expect(model.isStuck)
        #expect(model.nextCPUWait() == .milliseconds(SpeedRules.stuckDelayMilliseconds), "仕切り直しなので満額")
    }

    @Test("CPU だけ出せず、あなたが出せるあいだは場を見直す間隔で待つ")
    func cpuScansWhileHumanCanPlay() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 5)],
            cpuHand: [card(.spades, 9)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(model.nextCPUWait() == SpeedRules.scanInterval)
        clock.advance(10)
        model.performCPUAction()
        #expect(model.piles == [[card(.spades, 6)], [card(.clubs, 3)]], "何もしない")
        #expect(model.nextCPUWait() == SpeedRules.scanInterval)
    }

    @Test("どちらも出せないときは間を置いてから CPU がめくる。あなたが先にめくってもよい")
    func cpuFlipsAfterStuckDelay() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10)],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        let wait = model.nextCPUWait()
        #expect(wait == .milliseconds(SpeedRules.stuckDelayMilliseconds))
        clock.advance(wait! / 2)
        model.performCPUAction()
        #expect(model.consecutiveFlips == 0, "まだめくらない")
        #expect(model.nextCPUWait()! <= wait! / 2 + .milliseconds(1))
        clock.advance(wait!)
        model.performCPUAction()
        #expect(model.consecutiveFlips == 1)
        #expect(model.piles[0].last == card(.diamonds, 10) && model.piles[1].last == card(.clubs, 2))
    }

    @Test("ゆっくりモードがオンだと反応の間とめくるまでの間が 1.5 倍になる")
    func slowMode() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now,
                               slowMode: makeSlowMode("on", enabled: true))
        model.configureForTesting(
            humanHand: [card(.hearts, 4)], cpuHand: [card(.spades, 5)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .fast)
        )
        let wait = model.nextCPUWait()!
        #expect(reactionRange(.fast, multiplier: SpeedRules.slowModeMultiplier).contains(wait), "\(wait)")
        #expect(wait > .milliseconds(Int(Double(SpeedLevel.fast.reactionMilliseconds) * 1.2)), "揺らぎの上限より長い")

        let stuck = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now,
                               slowMode: makeSlowMode("stuck", enabled: true))
        stuck.configureForTesting(
            humanHand: [card(.hearts, 9)], cpuHand: [card(.spades, 9)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(stuck.nextCPUWait() == .milliseconds(Int(Double(SpeedRules.stuckDelayMilliseconds) * SpeedRules.slowModeMultiplier)))
    }

    @Test("速さの段ごとに反応の間が違い、ゆっくり > ふつう > はやい")
    func levelsDiffer() {
        #expect(SpeedLevel.slow.reactionMilliseconds > SpeedLevel.normal.reactionMilliseconds)
        #expect(SpeedLevel.normal.reactionMilliseconds > SpeedLevel.fast.reactionMilliseconds)
        #expect(SpeedLevel.allCases.map(\.analyticsLevel) == [.beginner, .normal, .hard])
        #expect(Set(SpeedLevel.allCases.map(\.label)).count == 3)
        #expect(Set(SpeedLevel.allCases.map { SpeedSettings(level: $0).variant }).count == 3)
    }

    // MARK: - タイム（広告救済）

    @Test("タイムは負けそうなとき（CPU の残りが 8 枚以下で自分より少ない）だけ、1 ゲーム 1 回")
    func timeoutAvailability() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10), card(.diamonds, 2)],
            cpuHand: [card(.spades, 9), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(model.canUseTimeout, "CPU 3 枚 < あなた 4 枚")
        // 拮抗していると出ない。
        let even = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        even.configureForTesting(
            humanHand: [card(.hearts, 9)], cpuHand: [card(.spades, 9)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(!even.canUseTimeout)
        // CPU の残りが多いうちは出ない。
        let early = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        early.start(.standard)
        #expect(!early.canUseTimeout)

        let serial = model.gameSerial
        #expect(!model.grantTimeoutAfterAd(forGame: serial - 1), "別のゲームに対する広告は乗せない")
        #expect(model.grantTimeoutAfterAd(forGame: serial))
        #expect(model.timeoutUsed)
        #expect(model.isTimeoutActive)
        #expect(!model.canUseTimeout, "1 ゲーム 1 回")
        #expect(!model.grantTimeoutAfterAd(forGame: serial))
    }

    @Test("タイム中は CPU が休み、終わったら反応の間を数え直す")
    func timeoutPausesCPU() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10), card(.diamonds, 2)],
            cpuHand: [card(.spades, 5)], cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .fast)
        )
        let run = model.cpuRun
        #expect(model.grantTimeoutAfterAd(forGame: model.gameSerial))
        #expect(model.cpuRun == run + 1)
        #expect(model.nextCPUWait() == SpeedRules.timeoutDuration)
        clock.advance(SpeedRules.timeoutDuration / 2)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 6), "タイム中は出さない")
        #expect(model.nextCPUWait()! <= SpeedRules.timeoutDuration / 2 + .milliseconds(1))
        clock.advance(SpeedRules.timeoutDuration / 2)
        model.performCPUAction()
        #expect(!model.isTimeoutActive)
        #expect(model.piles[0].last == card(.spades, 6), "終わった直後も、反応の間を数え直してから出す")
        let wait = model.nextCPUWait()!
        #expect(reactionRange(.fast, multiplier: SpeedRules.humanStuckReactionRatio).contains(wait))
        clock.advance(wait)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 5))
    }

    @Test("タイム中に CPU を止めたあいだはタイムが進まず、戻ってから残りの秒数だけ休む（#3001）")
    func timeoutDoesNotRunWhileHeld() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10), card(.diamonds, 2)],
            cpuHand: [card(.spades, 5)], cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .fast)
        )
        #expect(model.grantTimeoutAfterAd(forGame: model.gameSerial))
        clock.advance(5)
        model.holdCPU(.inactive, true)
        clock.advance(20)
        model.holdCPU(.inactive, false)
        #expect(model.isTimeoutActive)
        let wait = model.nextCPUWait()!
        let expected: Duration = .seconds(3)
        #expect(wait <= expected && wait > expected - .milliseconds(10), "復帰時点で残り 3 秒")
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 6), "復帰直後は出さない")
    }

    // MARK: - あなたが出せないあいだの CPU（#2690）

    @Test("あなたが出せる札を持たないあいだだけ、CPU の反応の間が半分になり、出せるようになったら元に戻る")
    func cpuFasterWhileHumanHasNoPlayable() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 2)],
            cpuHand: [card(.spades, 5), card(.spades, 12)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .normal)
        )
        #expect(!model.humanHasPlayable && model.cpuHasPlayable)
        let fast = model.nextCPUWait()!
        #expect(reactionRange(.normal, multiplier: SpeedRules.humanStuckReactionRatio).contains(fast), "半分の間: \(fast)")

        // 台札が変わってあなたが出せるようになると、同じ見つけ方のまま元の長さに戻る。
        model.configureForTesting(
            humanHand: [card(.hearts, 4), card(.hearts, 11)],
            humanStock: [card(.diamonds, 2)],
            cpuHand: [card(.spades, 5), card(.spades, 12)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .normal)
        )
        #expect(model.humanHasPlayable && model.cpuHasPlayable)
        let normal = model.nextCPUWait()!
        #expect(reactionRange(.normal).contains(normal), "満額: \(normal)")
        #expect(normal > .milliseconds(Int(Double(SpeedLevel.normal.reactionMilliseconds) * 0.6)), "半分の上限より長い")
    }

    @Test("見つけたあとにあなたが出せなくなると、残りの待ちも半分の長さで数え直す")
    func cpuSpeedsUpWhenHumanBecomesStuckMidWait() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 4)],
            humanStock: [card(.diamonds, 12)],
            cpuHand: [card(.spades, 5), card(.spades, 12)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .normal)
        )
        let full = model.nextCPUWait()!
        // あなたが ♥4 を出すと、補充された ♦12 は出せず、あなたは詰まる。CPU の ♠5 は出せるまま。
        model.tapHandCard(card(.hearts, 4))
        #expect(!model.humanHasPlayable && model.cpuHasPlayable)
        let remaining = model.nextCPUWait()!
        #expect(remaining <= full / 2 + .milliseconds(1), "見つけた間の半分まで縮む: \(remaining) / \(full)")
    }

    @Test("両方つまったときの「めくる」までの間は、あなたが出せなくても短くならない")
    func stuckFlipDelayIsUnchanged() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9)], cpuHand: [card(.spades, 9)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(model.isStuck)
        #expect(model.nextCPUWait() == .milliseconds(SpeedRules.stuckDelayMilliseconds))
    }

    @Test("CPU を止めているあいだ（広告の視聴中・バックグラウンド）は待ちも動きも無く、解くと反応の間を数え直す")
    func holdCPU() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10), card(.diamonds, 2)],
            cpuHand: [card(.spades, 5)], cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .fast)
        )
        let wait = model.nextCPUWait()!
        clock.advance(wait / 2)
        let run = model.cpuRun
        model.holdCPU(.ad, true)
        #expect(model.isCPUHeld)
        #expect(model.nextCPUWait() == nil, "止めているあいだは View のループが抜ける")
        clock.advance(30)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 6), "30 秒経っても出さない")
        #expect(model.cpuRun == run, "止めるだけでは待ちを組み直さない")
        model.holdCPU(.ad, false)
        #expect(!model.isCPUHeld)
        #expect(model.cpuRun == run + 1, "解いたら View の待ちを組み直す")
        let restarted = model.nextCPUWait()!
        #expect(reactionRange(.fast, multiplier: SpeedRules.humanStuckReactionRatio).contains(restarted), "反応の間は満額から数え直す: \(restarted)")
        clock.advance(restarted)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 5))
        model.holdCPU(.ad, false)
        #expect(model.cpuRun == run + 2, "同じ値を重ねて渡しても組み直さない")
    }

    @Test("シートの提示中は CPU が着手せず、閉じたら再開する。ほかの理由が残っていれば解いても止まったまま（#1358）")
    func holdCPUWhileSheetIsOpen() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            humanStock: [card(.diamonds, 10), card(.diamonds, 2)],
            cpuHand: [card(.spades, 5)], cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]],
            settings: SpeedSettings(level: .fast)
        )
        model.holdCPU(.sheet, true)
        #expect(model.nextCPUWait() == nil, "シートを開いているあいだは待ちも無い")
        clock.advance(60)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 6), "60 秒置いても CPU は出さない")
        #expect(model.phase == .playing)

        // 広告を見終えても、シートが開いたままなら止まったまま。
        model.holdCPU(.ad, true)
        model.holdCPU(.ad, false)
        #expect(model.isCPUHeld && model.nextCPUWait() == nil)

        let run = model.cpuRun
        model.holdCPU(.sheet, false)
        #expect(!model.isCPUHeld)
        #expect(model.cpuRun == run + 1, "すべて解いたら View の待ちを組み直す")
        let wait = model.nextCPUWait()!
        #expect(reactionRange(.fast, multiplier: SpeedRules.humanStuckReactionRatio).contains(wait), "反応の間は満額から数え直す: \(wait)")
        clock.advance(wait)
        model.performCPUAction()
        #expect(model.piles[0].last == card(.spades, 5))
    }

    @Test("CPU が出しても、あなたの選択は外れない（外れると台札のタップで別の札が出る）")
    func selectionSurvivesCPUPlay() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 7, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9)],
            humanStock: [card(.diamonds, 3)],
            cpuHand: [card(.spades, 7), card(.spades, 12)],
            cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 4)], [card(.clubs, 6)]],
            settings: SpeedSettings(level: .fast)
        )
        model.tapHandCard(card(.hearts, 5))   // 左（4）にも右（6）にも置けるので選択
        #expect(model.selectedID == card(.hearts, 5).id)
        // CPU が ♠7 を右（♣6）に出す。♥5 は左（♠4）にまだ置けるので選択は残る。
        let wait = model.nextCPUWait()!
        clock.advance(wait)
        model.performCPUAction()
        #expect(model.piles[1].last == card(.spades, 7))
        #expect(model.selectedID == card(.hearts, 5).id, "CPU の着手では選択を保つ")
        // 選択中の札が置けない台札（右 7）をタップしても、別の札（♥9 なら置ける）は出ない。
        model.tapPile(1)
        #expect(model.piles[1].last == card(.spades, 7))
        #expect(model.selectedID == card(.hearts, 5).id)
        model.tapPile(0)
        #expect(model.piles[0].last == card(.hearts, 5))
        #expect(model.selectedID == nil)
    }

    @Test("タイムを使った勝ちは時間の記録から外れる（勝ち・連勝には数える）")
    func timeoutExcludesBestTime() {
        let clock = ManualClock()
        let log = makeLog("timeout-win")
        let model = SpeedModel(services: makeServices(log: log), seed: 3, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.configureForTesting(
            humanHand: [card(.hearts, 5)], humanStock: [card(.diamonds, 12)],
            cpuHand: [card(.spades, 9)], cpuStock: [],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(model.grantTimeoutAfterAd(forGame: model.gameSerial))
        clock.advance(5)
        model.tapHandCard(card(.hearts, 5))   // 補充された ♦12 が残る
        model.tapHandCard(card(.diamonds, 12))   // まだ出せない（左 ♥5・右 ♣3）
        #expect(model.phase == .playing)
        model.configureForTesting(
            humanHand: [card(.diamonds, 12)], humanStock: [],
            cpuHand: [card(.spades, 9)], cpuStock: [],
            piles: [[card(.spades, 13)], [card(.clubs, 3)]]
        )
        model.tapHandCard(card(.diamonds, 12))
        #expect(model.phase == .result && model.winner == .human)
        #expect(model.winSeconds != nil)
        #expect(model.streak == 1)
        #expect(log.record(gameID: SpeedModel.gameID, variant: "normal")?.bestSeconds == nil, "タイムを使った回の時間は残さない")
    }

    // MARK: - 解析・永続化

    @Test("解析は 1 ゲーム 1 組で、2 ゲーム目は再開として数え、level に速さを載せる")
    func analytics() {
        let clock = ManualClock()
        let spy = SpyAnalyticsService()
        let model = SpeedModel(services: makeServices(analytics: spy), seed: 3, now: { clock.current }, elapsedNow: clock.elapsed.now)
        model.start(SpeedSettings(level: .fast))
        #expect(spy.starts == [SpeedModel.gameID])
        #expect(spy.startLevels == [.hard])
        #expect(spy.ends.isEmpty)
        model.configureForTesting(
            humanHand: [card(.hearts, 5)], humanStock: [],
            cpuHand: [card(.spades, 9)], cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        model.tapHandCard(card(.hearts, 5))
        #expect(spy.starts(of: SpeedModel.gameID) == 1)
        #expect(spy.ends(of: SpeedModel.gameID) == 1)
        model.restart()
        #expect(model.phase == .playing && model.gameSerial == 2)
        #expect(spy.starts(of: SpeedModel.gameID) == 2, "2 ゲーム目は gameDidRestart で数える")
        #expect(spy.ends(of: SpeedModel.gameID) == 1)
    }

    @Test("中断データは速さの控えだけで、次に開いたときの初期値になる")
    func snapshotKeepsSettingsOnly() {
        let store = MemorySnapshotStore()
        let services = makeServices(store: store)
        let model = SpeedModel(services: services, seed: 3)
        model.start(SpeedSettings(level: .fast))
        #expect(store.exists(for: SpeedModel.gameID))
        #expect(store.load(SpeedSnapshot.self, for: SpeedModel.gameID) == SpeedSnapshot(settings: SpeedSettings(level: .fast)))
        let reopened = SpeedModel(services: services, seed: 3)
        #expect(reopened.settings.level == .fast)
        #expect(reopened.phase == .idle, "ゲームそのものは復元しない")
        #expect(!SpeedModule().hasResumableSnapshot(in: store), "「続きから」にはならない")
    }

    @Test("あなたも CPU も出せる手を出し続ければ、ゲームは必ず決着する（自動対戦）")
    func selfPlayConcludes() {
        for seed in UInt64(1)...UInt64(12) {
            let clock = ManualClock()
            let spy = SpyAnalyticsService()
            let model = SpeedModel(services: makeServices(analytics: spy), seed: seed, now: { clock.current }, elapsedNow: clock.elapsed.now)
            model.start(SpeedSettings(level: .fast))
            var steps = 0
            while model.phase == .playing, steps < 5000 {
                steps += 1
                // あなた: 出せる札があれば最初の 1 枚を出す（両方に置けるなら左）。
                if let id = model.humanPlayableIDs.min(), let card = model.humanHand.first(where: { $0.id == id }) {
                    let targets = model.playableTargets(for: card)
                    model.tapHandCard(card)
                    if targets.count > 1 { model.tapPile(0) }
                    continue
                }
                // CPU: 待ちを進めて動かす。
                guard let wait = model.nextCPUWait() else { break }
                clock.advance(wait)
                model.performCPUAction()
            }
            #expect(model.phase == .result, "seed \(seed) は \(steps) 手で決着しない")
            #expect(spy.starts(of: SpeedModel.gameID) == 1 && spy.ends(of: SpeedModel.gameID) == 1, "seed \(seed)")
            if model.winner == .human {
                #expect(model.remaining(of: .human) == 0)
            } else if model.winner == .cpu {
                #expect(model.remaining(of: .cpu) == 0)
            } else {
                #expect(model.isDraw)
            }
            let total = model.humanHand.count + model.humanStock.count + model.cpuHand.count + model.cpuStock.count
                + model.piles[0].count + model.piles[1].count
            #expect(total == 52, "seed \(seed): 札が増減していない")
        }
    }
}

// MARK: - 出せる札の案内（会長 QA 2026-10-24「5 秒ぐらいでナビゲーションを出したい」）

@MainActor
@Suite("スピードの出せる札の案内")
struct SpeedPlayableNavigationTests {
    /// ♥5 は左（♠6）に、♥2 は右（♣3）に出せる。CPU は出せない（あなたを待っている）。
    private func makeModel(_ name: String, clock: ManualClock, hints: Bool = true) -> SpeedModel {
        let model = SpeedModel(services: makeServices(), seed: 3, now: { clock.current },
                               hints: makeHints(name, enabled: hints), slowMode: makeSlowMode(name, enabled: false))
        model.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12), card(.hearts, 2)],
            humanStock: [card(.diamonds, 11), card(.diamonds, 7)],
            cpuHand: [card(.spades, 9), card(.clubs, 11)],
            cpuStock: [card(.clubs, 7)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        return model
    }

    /// View の `.task(id: navigationEpoch)` と同じ手順で、待ちを進めて案内を更新する。
    private func waitAndUpdate(_ model: SpeedModel, clock: ManualClock) {
        guard let wait = model.playableNavigationWait() else { return }
        clock.advance(wait)
        model.updatePlayableNavigation()
    }

    @Test("出せる札があるのに 5 秒何もしなければ、出せる手札と台札を全部光らせる")
    func showsAfterIdleDelay() {
        let clock = ManualClock()
        let model = makeModel("show", clock: clock)
        #expect(!model.cpuHasPlayable && model.humanHasPlayable)
        #expect(model.playableNavigationWait() == SpeedRules.playableNavigationDelay)
        #expect(SpeedRules.playableNavigationDelay == .seconds(5))
        clock.advance(4.9)
        model.updatePlayableNavigation()
        #expect(!model.isShowingPlayableNavigation, "5 秒より前には出さない")
        #expect(model.playableNavigationCardIDs.isEmpty && model.playableNavigationPiles.isEmpty)
        waitAndUpdate(model, clock: clock)
        #expect(model.isShowingPlayableNavigation)
        #expect(model.playableNavigationCardIDs == [card(.hearts, 5).id, card(.hearts, 2).id], "出せる札が複数なら全部")
        #expect(model.playableNavigationPiles == [0, 1])
        #expect(model.playableNavigationWait() == nil, "出したあとは待たない")
    }

    @Test("出せる札が無いときは案内しない")
    func noNavigationWithoutPlayable() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 3, now: { clock.current },
                               hints: makeHints("none", enabled: true), slowMode: makeSlowMode("none", enabled: false))
        model.configureForTesting(
            humanHand: [card(.hearts, 9), card(.hearts, 11)],
            cpuHand: [card(.spades, 7)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        #expect(!model.humanHasPlayable)
        #expect(model.playableNavigationWait() == nil)
        clock.advance(10)
        model.updatePlayableNavigation()
        #expect(!model.isShowingPlayableNavigation)
    }

    @Test("ヒント表示をオフにしていれば案内しない")
    func respectsHintSetting() {
        let clock = ManualClock()
        let model = makeModel("hintsOff", clock: clock, hints: false)
        #expect(model.playableNavigationWait() == nil)
        clock.advance(10)
        model.updatePlayableNavigation()
        #expect(!model.isShowingPlayableNavigation)
    }

    @Test("札に触れる・出せない札を払うと案内が消え、そこから 5 秒を数え直す")
    func humanActivityRestarts() {
        let clock = ManualClock()
        let model = makeModel("activity", clock: clock)
        waitAndUpdate(model, clock: clock)
        #expect(model.isShowingPlayableNavigation)
        var epoch = model.navigationEpoch
        model.noteHumanActivity()
        #expect(!model.isShowingPlayableNavigation)
        #expect(model.navigationEpoch == epoch + 1, "View の待ちが組み直される")
        #expect(model.playableNavigationWait() == SpeedRules.playableNavigationDelay)
        clock.advance(3)
        // 出せない札（♥9）を払っても操作として数える。
        epoch = model.navigationEpoch
        #expect(!model.swipeCard(card(.hearts, 9), onto: 0))
        #expect(model.navigationEpoch == epoch + 1)
        #expect(model.playableNavigationWait() == SpeedRules.playableNavigationDelay)
    }

    @Test("あなたが出す・CPU が出す・めくる、で場が動くと案内が消えて数え直す")
    func boardMovesRestart() {
        let clock = ManualClock()
        let model = makeModel("board", clock: clock)
        waitAndUpdate(model, clock: clock)
        #expect(model.isShowingPlayableNavigation)
        // あなたが ♥5 を左に出す。
        model.tapHandCard(card(.hearts, 5))
        #expect(!model.isShowingPlayableNavigation)
        #expect(model.playableNavigationCardIDs.isEmpty)

        // CPU が出す: ♠9 を、あなたの出せる札が残る局面で出させる。
        let cpuModel = SpeedModel(services: makeServices(), seed: 3, now: { clock.current },
                                  hints: makeHints("board.cpu", enabled: true), slowMode: makeSlowMode("board.cpu", enabled: false))
        cpuModel.configureForTesting(
            humanHand: [card(.hearts, 2), card(.hearts, 11)],
            cpuHand: [card(.spades, 9)],
            cpuStock: [card(.clubs, 7)],
            piles: [[card(.diamonds, 8)], [card(.clubs, 3)]]
        )
        #expect(cpuModel.humanHasPlayable && cpuModel.cpuHasPlayable)
        // CPU の反応（ふつうで最大 2.28 秒）より案内の 5 秒が長いので、先に CPU が出して数え直しになる。
        let cpuWait = cpuModel.nextCPUWait()!
        clock.advance(cpuWait)
        let epoch = cpuModel.navigationEpoch
        cpuModel.performCPUAction()
        #expect(cpuModel.piles[0].last == card(.spades, 9))
        #expect(cpuModel.navigationEpoch == epoch + 1)
        #expect(cpuModel.playableNavigationWait() == SpeedRules.playableNavigationDelay)

        // めくる。
        let flipModel = SpeedModel(services: makeServices(), seed: 3, now: { clock.current },
                                   hints: makeHints("board.flip", enabled: true), slowMode: makeSlowMode("board.flip", enabled: false))
        flipModel.configureForTesting(
            humanHand: [card(.hearts, 9)], humanStock: [card(.diamonds, 10)],
            cpuHand: [card(.spades, 12)], cpuStock: [card(.clubs, 2)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        let flipEpoch = flipModel.navigationEpoch
        flipModel.flipStocks()
        #expect(flipModel.navigationEpoch == flipEpoch + 1)
        // めくった ♦10 に ♥9 が出せる。ここから 5 秒。
        #expect(flipModel.humanHasPlayable)
        #expect(flipModel.playableNavigationWait() == SpeedRules.playableNavigationDelay)
    }

    @Test("広告の視聴中・シートの表示中・背面では数えず、解いたところから 5 秒を数え直す")
    func holdsPauseCounting() {
        for reason in [SpeedModel.CPUHold.ad, .sheet, .inactive] {
            let clock = ManualClock()
            let model = makeModel("hold.\(reason.rawValue)", clock: clock)
            clock.advance(4)
            model.holdCPU(reason, true)
            #expect(model.playableNavigationWait() == nil, "止めているあいだは数えない")
            clock.advance(30)
            model.updatePlayableNavigation()
            #expect(!model.isShowingPlayableNavigation)
            model.holdCPU(reason, false)
            #expect(model.playableNavigationWait() == SpeedRules.playableNavigationDelay, "止める前の 4 秒は持ち越さない")
            waitAndUpdate(model, clock: clock)
            #expect(model.isShowingPlayableNavigation)
            // 出ているあいだに止めたら消す。
            model.holdCPU(reason, true)
            #expect(!model.isShowingPlayableNavigation)
        }
    }

    @Test("決着したら案内は消える")
    func clearsOnResult() {
        let clock = ManualClock()
        let model = SpeedModel(services: makeServices(), seed: 3, now: { clock.current },
                               hints: makeHints("result", enabled: true), slowMode: makeSlowMode("result", enabled: false))
        model.configureForTesting(
            humanHand: [card(.hearts, 5)], humanStock: [],
            cpuHand: [card(.spades, 9)],
            piles: [[card(.spades, 6)], [card(.clubs, 3)]]
        )
        waitAndUpdate(model, clock: clock)
        #expect(model.isShowingPlayableNavigation)
        model.tapHandCard(card(.hearts, 5))
        #expect(model.phase == .result)
        #expect(!model.isShowingPlayableNavigation)
        #expect(model.playableNavigationWait() == nil)
    }
}

/// 通常の操作ではタップで札を出せない（会長 QA 2026-10-24・build 52「タップで押せると『はやい』でも割と勝てる」）。
/// 札を出す手段は払いだけ。VoiceOver・スイッチコントロールを使っているときだけ、タップ・アクションで出せる。
@MainActor
@Suite("スピード: タップでは出さない")
struct SpeedTapOnlyAssistiveTests {
    /// ♥5 は左（♠6）にだけ出せる。♥9 は右（♥10）にだけ出せる。
    private func model(feedback: SpyFeedbackService = SpyFeedbackService()) -> SpeedModel {
        let model = SpeedModel(services: makeServices(feedback: feedback), seed: 3)
        model.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9), card(.diamonds, 12)],
            humanStock: [card(.diamonds, 3)],
            cpuHand: [card(.spades, 2)],
            piles: [[card(.spades, 6)], [card(.hearts, 10)]]
        )
        return model
    }

    @Test("通常時は、出せる手札をタップしても台札に出ない（軽い触覚と一言だけ）")
    func fingerTapDoesNotPlay() {
        let feedback = SpyFeedbackService()
        let m = model(feedback: feedback)
        let before = (m.humanHand, m.piles, m.cpuRun)
        feedback.reset()
        #expect(m.fingerTapHandCard(card(.hearts, 5), assistive: false) == .nudged(showsTip: true))
        #expect(m.humanHand == before.0 && m.piles == before.1 && m.cpuRun == before.2, "場が動いた")
        #expect(m.selectedID == nil, "タップで札を選ばない")
        #expect(m.isShowingSwipeTip)
        #expect(feedback.impacts == [.light] && feedback.notices.isEmpty)
    }

    @Test("通常時は、台札をタップしても置けるただ 1 枚を出さない")
    func fingerTapPileDoesNotPlay() {
        let m = model()
        let before = (m.humanHand, m.piles)
        #expect(m.fingerTapPile(0, assistive: false) == false)
        #expect(m.humanHand == before.0 && m.piles == before.1)
    }

    @Test("一言は 1 局に 1 回まで。新しい局ではまた出る")
    func tipOncePerGame() {
        let m = model()
        #expect(m.fingerTapHandCard(card(.hearts, 5), assistive: false) == .nudged(showsTip: true))
        m.dismissSwipeTip()
        #expect(!m.isShowingSwipeTip)
        #expect(m.fingerTapHandCard(card(.hearts, 9), assistive: false) == .nudged(showsTip: false))
        #expect(!m.isShowingSwipeTip, "同じ局で 2 回目は出さない")
        m.start(SpeedSettings(level: .normal))
        #expect(m.fingerTapHandCard(m.humanHand[0], assistive: false) == .nudged(showsTip: true))
    }

    @Test("払って出したあとの局では一言を出さない（初めのうちだけ）")
    func noTipAfterSwipe() {
        let m = model()
        #expect(m.swipeCard(card(.hearts, 5), onto: 0))
        #expect(m.fingerTapHandCard(card(.hearts, 9), assistive: false) == .nudged(showsTip: false))
        #expect(!m.isShowingSwipeTip)
    }

    @Test("払って出すと、出ている一言は消える")
    func swipeDismissesTip() {
        let m = model()
        m.fingerTapHandCard(card(.diamonds, 12), assistive: false)
        #expect(m.isShowingSwipeTip)
        #expect(m.swipeCard(card(.hearts, 5), onto: 0))
        #expect(!m.isShowingSwipeTip)
    }

    @Test("VoiceOver・スイッチコントロールの使用中は、タップ（アクション）で出せる")
    func assistiveTapPlays() {
        let m = model()
        #expect(m.fingerTapHandCard(card(.hearts, 5), assistive: true) == .acted)
        #expect(m.piles[0].last == card(.hearts, 5))
        #expect(!m.isShowingSwipeTip, "支援機能では一言を出さない")
        // 台札のタップ: 右（♥10）に置けるのは ♥9 だけなので出す。
        #expect(m.fingerTapPile(1, assistive: true))
        #expect(m.piles[1].last == card(.hearts, 9))
    }

    @Test("支援機能で選んだ札は、台札のタップで置ける")
    func assistiveSelectionThenPile() {
        let m = SpeedModel(services: makeServices(), seed: 3)
        m.configureForTesting(
            humanHand: [card(.hearts, 5), card(.hearts, 9)],
            cpuHand: [card(.spades, 2)],
            piles: [[card(.spades, 4)], [card(.clubs, 6)]]
        )
        #expect(m.fingerTapHandCard(card(.hearts, 5), assistive: true) == .acted)
        #expect(m.selectedID == card(.hearts, 5).id, "両方に置けるので選択")
        #expect(m.fingerTapPile(1, assistive: false), "選択は支援機能でしか作られないので、台札のタップで置く")
        #expect(m.piles[1].last == card(.hearts, 5))
    }
}
