import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
@testable import GamePoker

@Suite("ポーカー 役の点数・10 回勝負（#2551）")
@MainActor
struct PokerMatchTests {

    // MARK: - 役の点

    @Test("役の点は仕様どおりで、強い役ほど大きい")
    func pointTable() {
        let expected: [PokerHandRank: Int] = [
            .highCard: 1, .onePair: 2, .twoPair: 4, .threeOfAKind: 6, .straight: 10, .flush: 12,
            .fullHouse: 18, .fourOfAKind: 30, .straightFlush: 40, .royalFlush: 50,
        ]
        #expect(PokerPointTable.entries.count == 10)
        for (rank, points) in expected {
            #expect(PokerPointTable.points(for: rank) == points, "\(rank)")
        }
        let ascending = PokerPointTable.entries.reversed().map(\.points)
        #expect(ascending == ascending.sorted())
        #expect(Set(ascending).count == ascending.count, "同じ点の役が無い")
    }

    @Test("勝つと自分の役の点が入り、勝ち数が増える")
    func winAddsPoints() {
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.flush))
        model.confirmExchange()                  // 交換しない → CPU は全部残す
        #expect(model.phase == .exchanged)
        model.finishExchange()

        #expect(model.phase == .result)
        #expect(model.winner == .player)
        #expect(model.lastRoundPoints == 12)
        #expect(model.totalPoints == 12)
        #expect(model.playerWins == 1)
        #expect(model.bestRank == .flush)
    }

    @Test("負け・引き分けは 0 点")
    func lossAndTieScoreNothing() {
        let (lost, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk))
        lost.confirmExchange()
        lost.finishExchange()
        #expect(lost.winner == .cpu)
        #expect(lost.totalPoints == 0)
        #expect(lost.cpuWins == 1)

        let (tied, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.tieStraight))
        tied.confirmExchange()
        tied.finishExchange()
        #expect(tied.winner == .tie)
        #expect(tied.totalPoints == 0)
        #expect(tied.draws == 1)
    }

    @Test("作った一番強い役は、負けた回の役も含めて更新される")
    func bestRankTracksStrongest() {
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk, bestRank: .flush))
        model.confirmExchange()
        model.finishExchange()
        #expect(model.bestRank == .flush, "弱い役では下がらない")
    }

    // MARK: - 10 回で終わる

    @Test("10 回目の決着で勝負が終わり、記録を 1 回だけ確定する")
    func tenthRoundEndsTheMatch() {
        let playLog = PokerFixture.freshPlayLog()
        let (model, store) = PokerFixture.model(
            PokerFixture.snapshot(player: PokerFixture.flush, round: 10, totalPoints: 30, playerWins: 3),
            playLog: playLog
        )
        model.confirmExchange()
        model.finishExchange()

        #expect(model.isMatchOver)
        #expect(model.totalPoints == 42)
        #expect(model.recordResult != nil)
        let record = playLog.record(gameID: "poker", variant: PokerMatch.recordVariant)
        #expect(record?.bestPoints == 42)
        #expect(record?.plays == 1)
        #expect(!store.exists(for: "poker"), "終わった勝負の中断データは残さない")

        model.nextRound()
        #expect(model.round == 10, "10 回を超えて配らない")
        #expect(playLog.record(gameID: "poker", variant: PokerMatch.recordVariant)?.plays == 1)
    }

    @Test("途中の回では記録を確定せず、次の回へ進める")
    func midMatchDoesNotRecord() {
        let playLog = PokerFixture.freshPlayLog()
        let (model, store) = PokerFixture.model(
            PokerFixture.snapshot(player: PokerFixture.flush, round: 3), playLog: playLog
        )
        model.confirmExchange()
        model.finishExchange()

        #expect(!model.isMatchOver)
        #expect(model.recordResult == nil)
        #expect(playLog.record(gameID: "poker", variant: PokerMatch.recordVariant) == nil)
        #expect(store.exists(for: "poker"), "決着の途中でも続きから戻れる")

        model.nextRound()
        #expect(model.round == 4)
        #expect(model.phase == .exchange)
        #expect(model.totalPoints == 12, "合計点は回をまたいで持ち越す")
    }

    @Test("新しい勝負を始めると 1 回目から数え直す")
    func startGameResetsTheMatch() {
        let (model, _) = PokerFixture.model(
            PokerFixture.snapshot(player: PokerFixture.flush, round: 10, totalPoints: 30, playerWins: 3),
            playLog: PokerFixture.freshPlayLog()
        )
        model.confirmExchange()
        model.finishExchange()
        #expect(model.isMatchOver)

        model.startGame()
        #expect(model.round == 1)
        #expect(model.phase == .exchange)
        #expect(model.totalPoints == 0)
        #expect(model.playerWins == 0 && model.cpuWins == 0 && model.draws == 0)
        #expect(model.bestRank == nil)
        #expect(!model.extraExchangeUsed)
        #expect(model.recordResult == nil)
    }

    @Test("勝負の最中の startGame は無視する（連打で game_start を二重に数えない・#2416）")
    func startingTwiceIsIgnored() {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["poker"])
        let (model, _) = PokerFixture.model(analytics: analytics)
        model.startGame()
        let hand = model.playerHand
        model.startGame()

        #expect(model.round == 1)
        #expect(model.playerHand == hand, "配り直されない")
        #expect(spy.starts.count == 1)
    }

    @Test("ちょうど 10 回配ると終わる（実際の配りで通す）")
    func fullMatchWithRealDeals() {
        let (model, _) = PokerFixture.model(playLog: PokerFixture.freshPlayLog())
        model.startGame()
        var rounds = 1
        while true {
            model.confirmExchange()
            if model.phase == .exchanged { model.finishExchange() }
            #expect(model.phase == .result)
            #expect(model.playerWins + model.cpuWins + model.draws == rounds)
            if model.isMatchOver { break }
            model.nextRound()
            rounds += 1
        }
        #expect(rounds == PokerMatch.roundsPerMatch)
        #expect(model.recordResult != nil)
    }

    @Test("順位表（Game Center）へは送らない")
    func noLeaderboardSubmission() {
        @MainActor final class Spy: GameCenterService {
            var scores: [GameCenterScore] = []
            func submit(_ score: GameCenterScore) { scores.append(score) }
            func report(_ achievements: [GameCenterAchievement], completion: @escaping @MainActor (Bool) -> Void) { completion(true) }
        }
        let spy = Spy()
        let reporter = GameCenterReporter(service: spy, allowedGameIDs: ["poker"], isAvailable: { true })
        let (model, _) = PokerFixture.model(
            PokerFixture.snapshot(player: PokerFixture.flush, round: 10, totalPoints: 30),
            playLog: PokerFixture.freshPlayLog(), gameCenter: reporter
        )
        model.confirmExchange()
        model.finishExchange()
        #expect(model.isMatchOver)
        #expect(spy.scores.isEmpty)
    }

    // MARK: - もう 1 回交換（リワード広告）

    @Test("広告を見ると、1 回めの交換のあとにもう 1 回交換でき、そのあとは勝負に進む")
    func extraExchangeAfterAd() async {
        let ads = PokerStubAdService()
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk), ads: ads)
        model.confirmExchange()
        #expect(model.phase == .exchanged)
        #expect(model.canUseExtraExchange)

        let outcome = await model.extraExchangeAfterAd()
        #expect(outcome == .granted)
        #expect(ads.rewardedCount == 1)
        #expect(model.phase == .exchange, "もう一度、捨てる札を選べる")
        #expect(model.extraExchangeUsed)
        #expect(!model.canUseExtraExchange)

        model.confirmExchange()
        #expect(model.phase == .result, "2 回めの交換のあとは待たずに決着する")
    }

    @Test("1 回の勝負につき 1 回だけ。使ったあとの回は 1 回めの交換のあとそのまま決着する")
    func extraExchangeIsOncePerMatch() async {
        let ads = PokerStubAdService()
        let (model, _) = PokerFixture.model(
            PokerFixture.snapshot(player: PokerFixture.junk), ads: ads, playLog: PokerFixture.freshPlayLog()
        )
        model.confirmExchange()
        _ = await model.extraExchangeAfterAd()
        model.confirmExchange()
        #expect(model.phase == .result)

        model.nextRound()
        model.confirmExchange()
        #expect(model.phase == .result, "使用済みなら勝負に進むかの選択を挟まない")
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 1, "2 本目の広告は出さない")
    }

    @Test("視聴しなかったときは何も変えない")
    func notEarnedChangesNothing() async {
        let ads = PokerStubAdService(rewardEarned: false)
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk), ads: ads)
        model.confirmExchange()

        #expect(await model.extraExchangeAfterAd() == .notEarned)
        #expect(model.phase == .exchanged)
        #expect(!model.extraExchangeUsed, "回数は減らない")
        #expect(model.canUseExtraExchange)
    }

    @Test("交換前・決着後には広告を出さない")
    func unavailableOutsideExchanged() async {
        let ads = PokerStubAdService()
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk), ads: ads)
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        model.confirmExchange()
        model.finishExchange()
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 0)
    }

    @Test("広告のあいだに勝負へ進んだら適用しない")
    func supersededWhileWatching() async {
        let ads = PokerStubAdService()
        let (model, _) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk), ads: ads)
        model.confirmExchange()
        ads.duringAd = { model.finishExchange() }

        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(model.phase == .result)
        #expect(!model.extraExchangeUsed)
    }

    @Test("広告のあいだにハブへ戻られたら適用しない")
    func leftWhileWatching() async {
        let generation = GameScreenGeneration()
        let ads = PokerStubAdService()
        let (model, _) = PokerFixture.model(
            PokerFixture.snapshot(player: PokerFixture.junk), ads: ads, screenGeneration: generation
        )
        model.confirmExchange()
        ads.duringAd = { generation.advance() }

        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(model.phase == .exchanged)
    }

    // MARK: - 中断データ

    @Test("交換後の中断データから、広告の使用済みも含めて続きに戻れる")
    func snapshotRoundTrip() async {
        let (model, store) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.junk))
        model.confirmExchange()
        _ = await model.extraExchangeAfterAd()

        let services = GameServices(snapshots: store, ads: PokerStubAdService())
        let restored = PokerModel(services: services)
        #expect(restored.phase == .exchange)
        #expect(restored.extraExchangeUsed)
        #expect(restored.round == 1)
        restored.confirmExchange()
        #expect(restored.phase == .result)
    }

    @Test("決着済みの回の中断データは、手札から勝敗と役を数え直して戻る")
    func resultSnapshotRestoresOutcome() {
        let (model, store) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.flush, round: 2))
        model.confirmExchange()
        model.finishExchange()

        let restored = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(restored.phase == .result)
        #expect(restored.winner == .player)
        #expect(restored.playerHandRank == .flush)
        #expect(restored.lastRoundPoints == 12)
        #expect(restored.handResult?.reason.contains("12") == true)
        restored.nextRound()
        #expect(restored.round == 3)
    }

    @Test("チップ制だった頃の中断データは読み飛ばして、まっさらな開始シートに戻る")
    func legacyChipSnapshotIsIgnored() throws {
        let legacy = """
        {"playerHand":[],"cpuHand":[],"deck":[],"playerChips":100,"cpuChips":100,"pot":40,
         "phase":"betting2","currentBet":0,"playerBetInRound":0,"cpuBetInRound":0,
         "cpuFolded":false,"cpuAction":"","rules":"bonus","reviveCount":1}
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PokerSnapshot.self, from: Data(legacy.utf8))
        }

        let subdirectory = "poker-legacy-\(UUID().uuidString)"
        let store = FileSnapshotStore(subdirectory: subdirectory)
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ).appendingPathComponent(subdirectory, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("poker.json"))

        let model = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(model.phase == .idle)
        #expect(model.round == 0)
        #expect(!store.exists(for: "poker"), "読めない旧データは消える")
    }

    @Test("局を持たない（.idle）中断データは「続き」に数えない")
    func idleSnapshotIsNotResumable() {
        let (_, store) = PokerFixture.model(PokerFixture.snapshot(player: [], cpu: [], phase: .idle))
        #expect(!PokerModule().hasResumableSnapshot(in: store))
        let (_, active) = PokerFixture.model(PokerFixture.snapshot(player: PokerFixture.flush))
        #expect(PokerModule().hasResumableSnapshot(in: active))
    }

    // MARK: - 記録

    @Test("チップ制の旧記録は読み込み時に捨て、10 回勝負の記録は残る")
    func retiredChipRecordsAreDropped() {
        let defaults = UserDefaults(suiteName: "poker-retire-\(UUID().uuidString)")!
        let log = PlayLog(defaults: defaults)
        log.recordResult(gameID: "poker", outcome: .win, score: GameScore(metric: .points, points: 250))
        log.recordResult(gameID: "poker", outcome: .win, score: GameScore(metric: .points, points: 400, variant: "bonus"))
        log.recordResult(gameID: "poker", outcome: .win, score: GameScore(metric: .points, points: 42, variant: PokerMatch.recordVariant))
        #expect(log.records(gameID: "poker").count == 3)

        let reloaded = PlayLog(defaults: defaults)
        let kept = reloaded.records(gameID: "poker")
        #expect(kept.count == 1)
        #expect(kept.first?.bestPoints == 42)
        #expect(kept.first?.recordKey == "poker#round10")
    }

    @Test("記録の区分名は日本語・英語とも引ける")
    func variantLabel() {
        #expect(RecordVariantLabels.label(recordKey: "poker#round10", language: .japanese) == "10回勝負")
        #expect(RecordVariantLabels.label(recordKey: "poker#round10", language: .english) == "10 Rounds")
    }
}
