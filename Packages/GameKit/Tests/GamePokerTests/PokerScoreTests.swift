import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GamePoker

/// 10 回勝負の役の点数制（#2551）。
@Suite("ポーカー: 10 回勝負の役の点数")
@MainActor
struct PokerScoreTests {

    @Test("点数表は会長決裁の仮置きの値（強い役ほど大きい・全 10 役）")
    func pointsTable() {
        let expected: [(PokerHandRank, Int)] = [
            (.highCard, 1), (.onePair, 2), (.twoPair, 4), (.threeOfAKind, 6), (.straight, 10),
            (.flush, 12), (.fullHouse, 18), (.fourOfAKind, 30), (.straightFlush, 40), (.royalFlush, 50),
        ]
        for (rank, points) in expected {
            #expect(PokerScoreTable.points(for: rank) == points, "\(rank)")
        }
        #expect(PokerScoreTable.table.count == 10)
        let values = PokerScoreTable.table.map(\.points)
        #expect(values == values.sorted(by: >), "点数表は強い役から順に並び、強い役ほど点が大きい")
    }

    @Test("勝つと自分の役の点が入る")
    func winScoresOwnHand() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.fullHouse, cpu: PokerHands.straight))
        model.showdown()
        #expect(model.phase == .result)
        #expect(model.winner == .player)
        #expect(model.roundPoints == 18)
        #expect(model.playerPoints == 18)
        #expect(model.cpuPoints == 0)
        #expect(model.playerWins == 1)
    }

    @Test("負けると自分は 0 点・CPU に CPU の役の点が入る")
    func lossScoresNothing() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.flush, playerPoints: 5))
        model.showdown()
        #expect(model.winner == .cpu)
        #expect(model.playerPoints == 5, "負けた回は点が増えも減りもしない")
        #expect(model.cpuPoints == 12)
        #expect(model.cpuWins == 1)
    }

    @Test("引き分けはどちらも 0 点")
    func tieScoresNothing() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.straight, cpu: PokerHands.sameStraight))
        model.showdown()
        #expect(model.winner == .tie)
        #expect(model.roundPoints == 0)
        #expect(model.playerPoints == 0)
        #expect(model.cpuPoints == 0)
    }

    @Test("作った一番強い役は、負けた回の手も含めて残る")
    func bestRankTracksStrongestHand() {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.straight, cpu: PokerHands.fullHouse, bestRank: .onePair))
        model.showdown()
        #expect(model.winner == .cpu)
        #expect(model.bestRank == .straight)
    }

    @Test("10 回で終わり、記録は 10 回目の決着で 1 回だけ付く")
    func tenRoundsThenFinish() {
        let log = makePokerPlayLog()
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["poker"])
        let store = MemorySnapshotStore()
        let model = PokerModel(services: GameServices(
            snapshots: store, ads: PokerStubAdService(), playLog: log, analytics: analytics
        ))
        model.startGame()
        #expect(model.round == 1)
        var rounds = 0
        while !model.sessionOver {
            if model.phase == .exchange { model.confirmExchange() }
            if model.phase == .drawn { model.showdown() }
            #expect(model.phase == .result)
            rounds += 1
            #expect(model.round == rounds)
            if rounds < PokerModel.roundsPerSession {
                #expect(!model.sessionOver, "\(rounds) 回目ではまだ終わらない")
                #expect(model.recordResult == nil, "途中の回では記録しない")
                #expect(spy.ends.isEmpty, "途中の回では game_end を送らない")
                model.nextRound()
            }
        }
        #expect(rounds == 10)
        #expect(model.playerWins + model.cpuWins <= 10)
        model.nextRound()
        #expect(model.round == 10, "決着のあとは次の回へ進まない")
        #expect(spy.starts.count == 1, "10 回で game_start は 1 回")
        #expect(spy.ends.count == 1, "10 回で game_end は 1 回")
        let expected: AnalyticsResult = model.playerPoints > model.cpuPoints ? .win
            : model.playerPoints < model.cpuPoints ? .loss : .draw
        #expect(spy.ends.first?.result == expected, "合計点で決着する")
        let record = log.record(gameID: "poker", variant: PokerModel.recordVariant)
        #expect(record?.metric == .points)
        #expect(record?.bestPoints == model.playerPoints)
        #expect(record?.plays == 1)
        #expect(log.record(gameID: "poker") == nil, "チップ制の頃の保存先には書かない")
        #expect(store.isEmpty, "決着したら中断データは残らない")
    }

    @Test("10 回目の決着: 合計点の多い側が勝ち、自己ベストは合計点")
    func finalRoundDecidesByTotal() {
        let log = makePokerPlayLog()
        let win = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.fullHouse, cpu: PokerHands.straight, playerPoints: 10, cpuPoints: 20),
            playLog: log
        )
        win.showdown()
        #expect(win.sessionOver)
        #expect(win.playerPoints == 28)
        #expect(win.sessionWinner == .player)
        #expect(win.reviewOutcome == .win)
        #expect(win.recordResult?.record.bestPoints == 28)

        let lose = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.highCard, cpu: PokerHands.flush, playerPoints: 30, cpuPoints: 20)
        )
        lose.showdown()
        #expect(lose.sessionWinner == .cpu, "30 対 32")
        #expect(lose.reviewOutcome == .loss)

        let draw = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.straight, cpu: PokerHands.sameStraight, playerPoints: 7, cpuPoints: 7)
        )
        draw.showdown()
        #expect(draw.sessionWinner == .tie)
        #expect(draw.reviewOutcome == .draw)
    }

    @Test("Game Center の順位表（旧チップの表）へは送らない")
    func doesNotSubmitToGameCenter() {
        let spy = PokerSpyGameCenterService()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["poker"])
        let model = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.fullHouse, cpu: PokerHands.straight, playerPoints: 40),
            playLog: makePokerPlayLog(), gameCenter: reporter
        )
        model.showdown()
        #expect(model.sessionOver)
        #expect(spy.scores.isEmpty, "\(spy.scores)")
        #expect(!spy.scores.contains { $0.leaderboardID == GameCenterLeaderboard.pokerChips })
    }

    @Test("連勝: 勝つたびに +1、負け・引き分けで 0 に戻り、最高連勝は残る（#2590）")
    func streakCountsWinsAndResets() {
        let win = makePokerModel(pokerSnapshot(player: PokerHands.fullHouse, cpu: PokerHands.straight, streak: 2, bestStreak: 2))
        win.showdown()
        #expect(win.streak == 3)
        #expect(win.bestStreak == 3)

        let lose = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.flush, streak: 2, bestStreak: 2))
        lose.showdown()
        #expect(lose.streak == 0)
        #expect(lose.bestStreak == 2)

        let tie = makePokerModel(pokerSnapshot(player: PokerHands.straight, cpu: PokerHands.sameStraight, streak: 2, bestStreak: 2))
        tie.showdown()
        #expect(tie.streak == 0)
        #expect(tie.bestStreak == 2)
    }

    @Test("連勝は中断→再開で保たれ、連勝の項目が無い旧い中断データでも続きが消えない（#2590）")
    func streakSurvivesResume() {
        let store = MemorySnapshotStore()
        let model = makePokerModel(
            pokerSnapshot(round: 3, player: PokerHands.fullHouse, cpu: PokerHands.straight, streak: 1, bestStreak: 4),
            store: store
        )
        model.showdown()
        let reopened = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(reopened.streak == 2)
        #expect(reopened.bestStreak == 4)

        let legacy = MemorySnapshotStore()
        try? legacy.save(pokerSnapshot(round: 3, player: PokerHands.fullHouse, cpu: PokerHands.straight), for: "poker")
        let old = PokerModel(services: GameServices(snapshots: legacy, ads: PokerStubAdService()))
        #expect(old.round == 3)
        #expect(old.streak == 0)
    }

    @Test("新しい勝負を始めると連勝は 0 から数え直す（#2590）")
    func newSessionResetsStreak() {
        let model = makePokerModel(
            pokerSnapshot(round: 10, player: PokerHands.fullHouse, cpu: PokerHands.straight, streak: 3, bestStreak: 3)
        )
        model.showdown()
        #expect(model.sessionOver)
        #expect(model.bestStreak == 4)
        model.startGame()
        #expect(model.streak == 0)
        #expect(model.bestStreak == 0)
    }

    @Test("途中の回の決着は中断データに残り、開き直すと同じ回の結果から続く")
    func resultBetweenRoundsIsResumable() {
        let store = MemorySnapshotStore()
        let model = makePokerModel(
            pokerSnapshot(round: 3, player: PokerHands.fullHouse, cpu: PokerHands.straight, playerPoints: 4),
            store: store
        )
        model.showdown()
        #expect(model.phase == .result)
        let reopened = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(reopened.phase == .result)
        #expect(reopened.round == 3)
        #expect(reopened.playerPoints == 22)
        #expect(reopened.winner == .player)
        #expect(PokerModule().hasResumableSnapshot(in: store))
        reopened.nextRound()
        #expect(reopened.round == 4)
        #expect(reopened.phase == .exchange)
    }

    @Test("交換すると、もう 1 回の交換が残っていれば選ぶ段へ、使い切っていればそのまま勝負")
    func exchangeLeadsToDrawnOrShowdown() {
        let fresh = makePokerModel(pokerSnapshot(phase: .exchange, player: PokerHands.fullHouse, cpu: PokerHands.straight))
        fresh.confirmExchange()
        #expect(fresh.phase == .drawn)
        #expect(fresh.canUseExtraExchange)

        let used = makePokerModel(pokerSnapshot(
            phase: .exchange, player: PokerHands.fullHouse, cpu: PokerHands.straight, extraExchangeUsed: true
        ))
        used.confirmExchange()
        #expect(used.phase == .result, "使い切った勝負では交換したらそのまま勝負になる")
    }

    @Test("決着の表示: 見出し・役の対比・その回の点。持ち点の増減は出さない")
    func handResult() throws {
        let model = makePokerModel(pokerSnapshot(player: PokerHands.fullHouse, cpu: PokerHands.straight))
        #expect(model.handResult == nil, "決着するまでは出さない")
        model.showdown()
        let result = try #require(model.handResult)
        #expect(result.kind == .win)
        #expect(result.headline == "勝ち！")
        #expect(result.reason == "フルハウス 対 ストレート・+18点")
        #expect(result.chipDelta == nil)
        #expect(result.chipText == nil)

        let lose = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.flush))
        lose.showdown()
        #expect(lose.handResult?.reason == "ハイカード 対 フラッシュ・CPUに+12点")

        let tie = makePokerModel(pokerSnapshot(player: PokerHands.straight, cpu: PokerHands.sameStraight))
        tie.showdown()
        #expect(tie.handResult?.reason == "どちらもストレート")
        #expect(tie.handResult?.kind == .draw)
    }

    @Test("決着の幕の強調（#2593）: スリーカード以上の勝ちだけ。ワンペア以下の勝ち・強い役での負け・引き分けは強めない")
    func handResultEmphasis() throws {
        let pair = [pc(30, 12, .spades), pc(31, 12, .hearts), pc(32, 9, .diamonds), pc(33, 5, .clubs), pc(34, 3, .spades)]
        func result(player: [PokerCard], cpu: [PokerCard]) throws -> HandResult {
            let model = makePokerModel(pokerSnapshot(player: player, cpu: cpu))
            model.showdown()
            return try #require(model.handResult)
        }
        #expect(try result(player: PokerHands.fullHouse, cpu: PokerHands.straight).isEmphasized)
        #expect(try result(player: PokerHands.flush, cpu: PokerHands.highCard).isEmphasized)
        #expect(try !result(player: pair, cpu: PokerHands.highCard).isEmphasized, "ワンペアの勝ちは今のまま")
        #expect(try !result(player: PokerHands.highCard, cpu: PokerHands.flush).isEmphasized, "CPU が強い役で勝っても強めない")
        #expect(try !result(player: PokerHands.straight, cpu: PokerHands.sameStraight).isEmphasized)
    }

    @Test("開始の連打は 1 回ぶん（#2416）・勝負の途中では始め直さない")
    func startingTwiceIsIgnored() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["poker"])
        let model = PokerModel(services: GameServices(
            snapshots: MemorySnapshotStore(), ads: PokerStubAdService(), analytics: analytics
        ))
        model.startGame()
        let hand = model.playerHand
        model.startGame()
        #expect(model.playerHand == hand, "配り直されない")
        #expect(model.round == 1)
        #expect(spy.starts.count == 1, "game_start が二重に数えられない")
        playPokerToEnd(model)
        model.startGame()
        #expect(model.round == 1, "決着のあとの「もう一度」は新しい勝負を始める")
        #expect(model.playerPoints == 0)
        #expect(spy.starts.count == 2)
    }

    @Test("遅れがあれば勝敗の触覚だけを役名が出るまで待たせ、次の回へ進んだら鳴らさない（#667）")
    func noticeWaitsForTheReveal() async {
        let spy = SpyFeedbackService()
        let model = makePokerModel(
            pokerSnapshot(player: PokerHands.fullHouse, cpu: PokerHands.straight),
            feedback: spy, showdownRevealDelay: .milliseconds(1)
        )
        model.showdown()
        #expect(model.playerPoints == 18, "点の精算は決着の瞬間")
        #expect(spy.notices.isEmpty, "CPU の手札が裏向きのうちに勝敗が伝わっていない")
        await model.outcomeNoticeTask?.value
        #expect(spy.notices == [.success])

        let spy2 = SpyFeedbackService()
        let stale = makePokerModel(
            pokerSnapshot(player: PokerHands.fullHouse, cpu: PokerHands.straight),
            feedback: spy2, showdownRevealDelay: .milliseconds(1)
        )
        stale.showdown()
        let task = stale.outcomeNoticeTask
        stale.nextRound()
        await task?.value
        #expect(spy2.notices.isEmpty, "次の回の配りのあとに前の回の勝敗が鳴っている")
    }
}

/// 送信内容をそのまま溜めるスパイ。Apple の GameKit にもネットワークにも触れない。
@MainActor
final class PokerSpyGameCenterService: GameCenterService {
    private(set) var scores: [GameCenterScore] = []
    func submit(_ score: GameCenterScore) { scores.append(score) }
    func report(
        _ achievements: [GameCenterAchievement],
        completion: @escaping @MainActor (Bool) -> Void
    ) { completion(true) }
}
