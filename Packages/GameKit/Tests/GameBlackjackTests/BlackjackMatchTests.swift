import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

/// 10 回勝負の進み方・点・連勝（#2552）。
@Suite("ブラックジャック: 10 回勝負（#2552）")
@MainActor
struct BlackjackMatchTests {

    /// ディーラー 17 に対して、プレイヤーが 19（勝ち）/ 16（負け）/ 17（引き分け）の局を注入する。
    private func play(_ player: [Int], dealer: [Int] = [10, 7], roundsPlayed: Int = 0, score: Int = 0,
                      streak: Int = 0, store: MemorySnapshotStore = MemorySnapshotStore(),
                      playLog: PlayLog? = nil) -> BlackjackModel {
        let model = makeInjectedModel(player: player, dealer: dealer, deck: [], roundsPlayed: roundsPlayed,
                                      score: score, streak: streak, store: store, playLog: playLog).0
        model.stand()
        return model
    }

    @Test("勝つと 1 点、負けと引き分けは 0 点")
    func pointsPerRound() {
        let win = play([10, 9])
        #expect(win.outcome == .win)
        #expect(win.score == 1)
        #expect(win.roundPoints == 1)

        let lose = play([10, 6])
        #expect(lose.outcome == .lose)
        #expect(lose.score == 0)

        let push = play([10, 7])
        #expect(push.outcome == .push)
        #expect(push.score == 0)
    }

    @Test("ブラックジャックで勝つと 2 点")
    func blackjackScoresTwo() {
        // 配った時点でプレイヤーだけナチュラルの局を、実際の配りから探す。
        for seed in UInt64(0)..<5000 {
            let model = BlackjackModel(seed: seed)
            model.deal()
            guard model.outcome == .playerBlackjack else { continue }
            #expect(model.score == 2)
            #expect(model.roundPoints == 2)
            #expect(model.reviewOutcome == .win)
            #expect(model.streak == 1)
            return
        }
        Issue.record("ブラックジャックで勝つ種が 5000 件の中に無かった")
    }

    @Test("1 回終えるごとに回数が進み、決着の画では終えた回を指す")
    func roundNumberAdvances() {
        let model = BlackjackModel(seed: 3)
        #expect(model.roundNumber == 1)
        #expect(model.roundsPlayed == 0)
        model.deal()
        #expect(model.roundNumber == 1, "遊んでいる回")
        while model.phase == .playerTurn { model.stand() }
        #expect(model.roundsPlayed == 1)
        #expect(model.roundNumber == 1, "決着の画は終えた回")
        model.nextRound()
        #expect(model.roundNumber == 2, "次に遊ぶ回")
    }

    @Test("10 回で終わり、11 回目は配れない。締めるまで記録は出ない")
    func matchEndsAfterTenRounds() {
        let model = BlackjackModel(seed: 11)
        var total = 0
        for round in 1...BlackjackModel.roundsPerMatch {
            #expect(!model.isMatchOver)
            model.deal()
            while model.phase == .playerTurn { model.stand() }
            #expect(model.phase == .result)
            #expect(model.roundsPlayed == round)
            total += model.roundPoints ?? -1000
            if round < BlackjackModel.roundsPerMatch { model.nextRound() }
        }
        #expect(model.isMatchOver)
        #expect(!model.isMatchClosed, "10 回目のあとも、締めるまでは勝負の途中")
        #expect(model.score == total)

        // 終わった勝負は次の回へ進めず、配れもしない。
        model.nextRound()
        #expect(model.phase == .result)
        model.deal()
        #expect(model.roundsPlayed == BlackjackModel.roundsPerMatch)
        #expect(model.roundNumber == BlackjackModel.roundsPerMatch)

        model.finishMatch()
        #expect(model.isMatchClosed)
    }

    @Test("連勝は勝ちで伸び、負けと引き分けで切れる")
    func streakRules() {
        let afterWin = play([10, 9], streak: 2)
        #expect(afterWin.streak == 3)
        #expect(afterWin.bestStreakInMatch == 3)

        let afterPush = play([10, 7], streak: 2)
        #expect(afterPush.streak == 0, "引き分けは勝ち点が入らないので連勝が切れる")

        let afterLose = play([10, 6], streak: 2)
        #expect(afterLose.streak == 0)
        #expect(afterLose.bestStreakInMatch == 2, "切れる前の最高は残る")
    }

    @Test("新しい勝負を始めると、回数・点・連勝が戻り中断データは消える")
    func restartResetsMatch() {
        let store = MemorySnapshotStore()
        let model = play([10, 9], roundsPlayed: 4, score: 3, streak: 2, store: store)
        #expect(store.exists(for: "blackjack"))

        model.restartSession()

        #expect(model.phase == .ready)
        #expect(model.roundsPlayed == 0)
        #expect(model.score == 0)
        #expect(model.streak == 0)
        #expect(model.bestStreakInMatch == 0)
        #expect(model.winsInMatch == 0 && model.lossesInMatch == 0)
        #expect(!model.isMatchOver)
        #expect(!model.isMatchClosed)
        #expect(!store.exists(for: "blackjack"))
    }

    // MARK: 中断データ

    @Test("ラウンドの合間に離れても、回数・点・連勝が復元される（配る前から再開）")
    func betweenRoundsProgressIsKept() {
        let store = MemorySnapshotStore()
        let model = play([10, 9], roundsPlayed: 4, score: 3, streak: 2, store: store)
        model.nextRound()

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: StubAdService()))
        #expect(reopened.phase == .ready, "決着の画は持ち越さず、配る前へ戻す")
        #expect(reopened.roundsPlayed == 5)
        #expect(reopened.score == 4)
        #expect(reopened.streak == 3)
        #expect(reopened.hands.isEmpty)
    }

    @Test("10 回目の結果で離れても、開き直すと勝負を締めて記録が残る")
    func leavingAtTheFinalResultSettlesOnReopen() {
        let store = MemorySnapshotStore()
        let defaults = UserDefaults(suiteName: "bj-final-\(UUID().uuidString)")!
        let log = PlayLog(defaults: defaults)
        let model = play([10, 9], roundsPlayed: 9, score: 5, store: store, playLog: log)
        #expect(model.isMatchOver && !model.isMatchClosed)
        #expect(log.record(gameID: "blackjack", variant: "match10") == nil, "締めるまで記録は出ない")
        #expect(store.exists(for: "blackjack"), "10 回目の結果は締めるまで残す")

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: StubAdService(), playLog: log))
        #expect(reopened.isMatchClosed)
        #expect(reopened.score == 6)
        #expect(log.record(gameID: "blackjack", variant: "match10")?.bestPoints == 6)
        #expect(!store.exists(for: "blackjack"))
    }

    @Test("勝負を締めると中断データは消える")
    func finishClearsSnapshot() {
        let store = MemorySnapshotStore()
        let model = play([10, 9], roundsPlayed: 9, score: 5, store: store)
        model.finishMatch()
        #expect(model.isMatchClosed)
        #expect(!store.exists(for: "blackjack"))
    }

    @Test("ラウンドの合間の中断データは「続きから」に数えず、途中の手があれば数える")
    func resumableOnlyWithHands() throws {
        let store = MemorySnapshotStore()
        let module = BlackjackModule()
        #expect(!module.hasResumableSnapshot(in: store))

        try store.save(BlackjackSnapshot(
            dealerHand: [], deck: [], phase: .ready, hands: [], activeHandIndex: 0,
            roundsPlayed: 3, score: 2, streak: 1, retryUsed: false,
            winsInMatch: 2, lossesInMatch: 1, bestStreak: 1
        ), for: "blackjack")
        #expect(!module.hasResumableSnapshot(in: store), "戻った先は配る前で続きではない")

        let cards = blackjackCards([10, 5])
        try store.save(BlackjackSnapshot(
            dealerHand: cards, deck: [], phase: .playerTurn,
            hands: [BlackjackHand(id: 0, cards: cards)], activeHandIndex: 0,
            roundsPlayed: 3, score: 2, streak: 1, retryUsed: false,
            winsInMatch: 2, lossesInMatch: 1, bestStreak: 1
        ), for: "blackjack")
        #expect(module.hasResumableSnapshot(in: store), "進行中の手が続きから外れている")
    }

    @Test("再起動後に開いて戻っても「途中のままです」を予約しない（#1145）")
    func betweenRoundsSnapshotSchedulesNoReminderAfterRelaunch() async {
        let store = MemorySnapshotStore()
        let model = play([10, 9], roundsPlayed: 4, score: 3, store: store)
        model.nextRound()
        #expect(store.exists(for: "blackjack"), "前提が崩れた: 進み具合だけの中断データが残るはず")

        let (services, reminders, spy) = makeRelaunchedServices(
            store: store, ads: StubAdService(),
            reminderTitle: { $0 == "blackjack" ? "ブラックジャック" : nil }
        )
        _ = BlackjackModel(services: services, seed: 20260918)
        services.gameDidLeave(gameID: "blackjack")
        await reminders.pendingWork?.value

        #expect(spy.reminders.isEmpty, "続きの無い局に「途中のままです」を予約した")
    }

    /// 上の対照。手が残っている中断データまで黙らせていたら、本物の中断が知らされなくなる。
    @Test("途中の手が残っているときは、再起動後でも従来どおり予約する（#1145）")
    func inRoundSnapshotStillSchedulesReminderAfterRelaunch() async {
        let store = MemorySnapshotStore()
        _ = makeInjectedModel(player: [10, 5], dealer: [10, 5], deck: [], roundsPlayed: 2, store: store)

        let (services, reminders, spy) = makeRelaunchedServices(
            store: store, ads: StubAdService(),
            reminderTitle: { $0 == "blackjack" ? "ブラックジャック" : nil }
        )
        let model = BlackjackModel(services: services)
        #expect(model.phase == .playerTurn, "前提が崩れた: 途中の手を復元しているはず")
        services.gameDidLeave(gameID: "blackjack")
        await reminders.pendingWork?.value

        #expect(spy.reminders["blackjack"] != nil, "途中の手が残っているのに予約しなかった")
    }

    // MARK: 記録

    @Test("記録・game_end は勝負を締めたとき 1 回だけ。合計点が自己ベストになる")
    func recordsOnceAtFinish() {
        let defaults = UserDefaults(suiteName: "bj-match-\(UUID().uuidString)")!
        let log = PlayLog(defaults: defaults)
        let model = makeInjectedModel(player: [10, 9], dealer: [10, 7], deck: [], roundsPlayed: 9, score: 5,
                                      streak: 3, winsInMatch: 6, lossesInMatch: 3, playLog: log).0
        model.stand()
        #expect(log.record(gameID: "blackjack", variant: "match10") == nil, "締める前は何も記録しない")

        model.finishMatch()
        model.finishMatch()   // 二重に押しても 1 回だけ
        let record = log.record(gameID: "blackjack", variant: "match10")
        #expect(record?.plays == 1)
        #expect(record?.wins == 1, "勝ち越し（7 勝 3 敗）の勝負は勝ち")
        #expect(record?.bestPoints == 6)
        #expect(model.recordResult?.update.points == true)
    }

    @Test("勝負の勝ち負けは勝ち越しで決め、同数は引き分け")
    func matchOutcomeByMajority() {
        func finish(wins: Int, losses: Int) -> PlayRecord? {
            let defaults = UserDefaults(suiteName: "bj-maj-\(UUID().uuidString)")!
            let log = PlayLog(defaults: defaults)
            let model = makeInjectedModel(player: [10, 7], dealer: [10, 7], deck: [], roundsPlayed: 9, score: 0,
                                          winsInMatch: wins, lossesInMatch: losses, playLog: log).0
            model.stand()   // 引き分けの 10 回目
            model.finishMatch()
            return log.record(gameID: "blackjack", variant: "match10")
        }
        #expect(finish(wins: 5, losses: 4)?.wins == 1)
        #expect(finish(wins: 4, losses: 5)?.losses == 1)
        #expect(finish(wins: 4, losses: 4)?.draws == 1)
    }

    @Test("旧チップ制の記録は読み込み時に捨てる。新しい区分の記録は消えない（#2552）")
    func chipEraRecordIsRetired() {
        let defaults = UserDefaults(suiteName: "bj-migrate-\(UUID().uuidString)")!
        let old = """
        {"blackjack": {"metric": "points", "plays": 30, "wins": 14, "losses": 12, "draws": 4,
                       "currentStreak": 0, "bestStreak": 5, "bestPoints": 2350}}
        """
        defaults.set(Data(old.utf8), forKey: PlayLog.recordsKey)

        let log = PlayLog(defaults: defaults)

        #expect(log.record(gameID: "blackjack") == nil, "区分なしの旧記録は残らない")
        #expect(log.records(gameID: "blackjack").isEmpty)
        #expect(log.summaryLine(gameID: "blackjack") == nil)

        // 新しい勝負の点がそのまま自己ベストになり、開き直しても消えない。
        let model = makeInjectedModel(player: [10, 9], dealer: [10, 7], deck: [], roundsPlayed: 9, score: 3,
                                      winsInMatch: 5, lossesInMatch: 4, playLog: log).0
        model.stand()
        model.finishMatch()
        #expect(log.record(gameID: "blackjack", variant: "match10")?.bestPoints == 4)
        let reopened = PlayLog(defaults: defaults)
        #expect(reopened.record(gameID: "blackjack", variant: "match10")?.bestPoints == 4)
    }
}
