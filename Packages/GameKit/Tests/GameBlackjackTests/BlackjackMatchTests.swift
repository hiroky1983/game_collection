import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

/// 10 回勝負・勝ち点制（#2552）。チップ・賭け金を外し、1 回の勝負を 10 回にした。
@Suite("ブラックジャックの 10 回勝負（#2552）")
@MainActor
struct BlackjackMatchTests {

    // MARK: - 点の数え方

    @Test("勝てば 1 点、ブラックジャックで勝てば 2 点、引き分け・負け・バストは 0 点")
    func pointsPerOutcome() {
        #expect(blackjackPoints(for: .playerBlackjack) == 2)
        #expect(blackjackPoints(for: .win) == 1)
        #expect(blackjackPoints(for: .push) == 0)
        #expect(blackjackPoints(for: .lose) == 0)
        #expect(blackjackPoints(for: .bust) == 0)
    }

    @Test("勝った回は 1 点が入り、連勝が伸びる")
    func winAddsOnePoint() {
        let model = makeBlackjackModel(blackjackSnapshot(player: [10, 9], dealer: [10, 7], deck: [],
                                                         completedRounds: 2, points: 3, streak: 1))
        model.stand()
        #expect(model.outcome == .win)
        #expect(model.roundPoints == 1)
        #expect(model.points == 4)
        #expect(model.completedRounds == 3)
        #expect(model.currentRound == 3, "結果を出しているあいだはその回を見せる")
        #expect(model.streak == 2)
        #expect(model.bestStreak == 2)
    }

    @Test("ブラックジャックで勝った回は 2 点")
    func blackjackScoresTwo() throws {
        // 配った時点で決着するので、シードを走査して「プレイヤーだけがナチュラル」の配りを探す。
        let found = (0..<5000 as Range<UInt64>).lazy.map { seed -> BlackjackModel in
            let model = BlackjackModel(seed: seed)
            model.deal()
            return model
        }.first { $0.outcome == .playerBlackjack }
        let model = try #require(found)
        #expect(model.phase == .result)
        #expect(model.points == 2)
        #expect(model.streak == 1)
    }

    @Test("引き分けは 0 点で、連勝は途切れる。やり直しの対象でもない")
    func pushScoresNothing() {
        let model = makeBlackjackModel(blackjackSnapshot(player: [10, 8], dealer: [10, 8], deck: [],
                                                         completedRounds: 1, points: 1, streak: 1))
        model.stand()
        #expect(model.outcome == .push)
        #expect(model.points == 1)
        #expect(model.streak == 0)
        #expect(model.bestStreak == 1, "最高連勝は残る")
        #expect(!model.canRetryRound)
    }

    @Test("負けた回は 0 点で、連勝は途切れる")
    func loseScoresNothing() {
        let model = makeBlackjackModel(blackjackSnapshot(player: [10, 6], dealer: [10, 8], deck: [],
                                                         completedRounds: 4, points: 3, streak: 3))
        model.stand()
        #expect(model.outcome == .lose)
        #expect(model.points == 3)
        #expect(model.streak == 0)
        #expect(model.bestStreak == 3)
    }

    // MARK: - 10 回で終わる

    @Test("1 回目は「配る」で始まり、2 回目以降は「次の回へ」でそのまま配られる")
    func roundsAdvance() {
        let model = BlackjackModel(seed: 7)
        #expect(model.phase == .ready)
        #expect(model.currentRound == 1)

        model.deal()
        standUntilResolved(model)
        #expect(model.phase == .result)
        #expect(model.completedRounds == 1)

        model.nextRound()
        #expect(model.phase != .ready, "2 回目は押した時点で配られている")
        #expect(model.currentRound == 2)
        model.deal()
        #expect(model.currentRound == 2, "途中の回では「配る」は効かない")
    }

    @Test("10 回で勝負が終わり、記録は 1 回だけ・合計点で付く")
    func matchEndsAfterTenRounds() {
        let (log, defaults, name) = makeBlackjackPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = MemorySnapshotStore()
        let model = BlackjackModel(services: GameServices(snapshots: store, ads: BlackjackStubAds(), playLog: log), seed: 20261020)

        playWholeMatch(model)

        #expect(model.matchOver)
        #expect(model.completedRounds == BlackjackModel.roundsPerMatch)
        #expect(model.currentRound == 10)
        let record = log.record(gameID: "blackjack", variant: BlackjackModel.recordVariant)
        #expect(record?.plays == 1, "10 回で 1 回の決着")
        #expect(record?.metric == .points)
        #expect(record?.bestPoints == model.points)
        #expect(model.recordResult != nil)
        #expect(model.matchOutcome != nil)
        #expect(!store.exists(for: "blackjack"), "締めた勝負の中断データは残さない")

        // 終わった勝負では、次の回にも配りにも進めない。
        let before = model.dealerHand
        model.nextRound()
        model.deal()
        #expect(model.dealerHand == before)
        #expect(model.completedRounds == 10)
    }

    @Test("9 回目まで終えた勝負は、10 回目に勝てば合計に 1 点足して締まる")
    func lastRoundWinFinishesTheMatch() {
        let (log, defaults, name) = makeBlackjackPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = makeBlackjackModel(
            blackjackSnapshot(player: [10, 9], dealer: [10, 7], deck: [],
                              completedRounds: 9, points: 6, streak: 2, handsWon: 6, handsLost: 3),
            playLog: log
        )
        model.stand()

        #expect(model.matchOver)
        #expect(model.points == 7)
        #expect(model.matchOutcome == .win, "勝った手 7・負けた手 3 で勝ち越し")
        #expect(log.record(gameID: "blackjack", variant: BlackjackModel.recordVariant)?.bestPoints == 7)
    }

    @Test("もう一度遊ぶと 1 回目・0 点・連勝 0 に戻る")
    func restartResetsTheMatch() {
        let model = BlackjackModel(seed: 3)
        playWholeMatch(model)
        #expect(model.matchOver)

        model.restartMatch()

        #expect(model.phase == .ready)
        #expect(!model.matchOver)
        #expect(model.completedRounds == 0)
        #expect(model.points == 0)
        #expect(model.streak == 0)
        #expect(model.bestStreak == 0)
        #expect(!model.hasUsedRetry)
        #expect(model.recordResult == nil)
    }

    // MARK: - 中断と再開

    @Test("勝負の途中の結果で離れても、同じ回・同じ点から戻る")
    func resumesMidMatch() {
        let store = MemorySnapshotStore()
        let model = makeBlackjackModel(blackjackSnapshot(player: [10, 9], dealer: [10, 7], deck: [],
                                                         completedRounds: 3, points: 2, streak: 1),
                                       store: store)
        model.stand()
        #expect(BlackjackModule().hasResumableSnapshot(in: store), "勝負の途中は続きとして数える")

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: BlackjackStubAds()))
        #expect(reopened.phase == .result)
        #expect(reopened.completedRounds == 4)
        #expect(reopened.points == 3)
        #expect(reopened.streak == 2)
        #expect(reopened.outcome == .win)
    }

    // MARK: - 古い保存データ

    @Test("#2552 より前の中断データは読み飛ばし、落ちずに 1 回目から始まる")
    func legacySnapshotIsSkipped() throws {
        // 以前の形式（チップの残高・賭け金・ダブルダウンの印を持ち、回数を持たない）をそのまま流し込む。
        let legacy = """
        {"playerHand":[{"id":0,"suit":0,"rank":10},{"id":1,"suit":1,"rank":6}],
         "dealerHand":[{"id":2,"suit":2,"rank":10},{"id":3,"suit":3,"rank":7}],
         "deck":[{"id":4,"suit":0,"rank":2}],
         "chips":1500,"bet":100,"phase":"playerTurn",
         "hands":[{"id":0,"cards":[{"id":0,"suit":0,"rank":10},{"id":1,"suit":1,"rank":6}],
                   "bet":100,"isFromSplit":false,"isDoubled":false,"isDone":false}],
         "activeHandIndex":0,"hasRevivedThisSession":true,"reviveCount":2}
        """
        let store = MemorySnapshotStore()
        store.inject(Data(legacy.utf8), for: "blackjack")

        #expect(!BlackjackModule().hasResumableSnapshot(in: store), "旧形式は続きに数えない")
        let model = BlackjackModel(services: GameServices(snapshots: store, ads: BlackjackStubAds()))

        #expect(model.phase == .ready)
        #expect(model.completedRounds == 0)
        #expect(model.points == 0)
        #expect(model.hands.isEmpty)
        #expect(!store.exists(for: "blackjack"), "読めない中断データは消す")

        model.deal()
        #expect(model.phase != .ready, "そのまま遊べる")
    }

    @Test("賭け待ちだけの旧データ（残高と復活の回数）も読み飛ばす")
    func legacyBetWaitingSnapshotIsSkipped() {
        let legacy = """
        {"playerHand":[],"dealerHand":[],"deck":[],"chips":2000,"bet":0,"phase":"betting",
         "hands":[],"activeHandIndex":0,"hasRevivedThisSession":true,"reviveCount":1}
        """
        let store = MemorySnapshotStore()
        store.inject(Data(legacy.utf8), for: "blackjack")
        let model = BlackjackModel(services: GameServices(snapshots: store, ads: BlackjackStubAds()))
        #expect(model.phase == .ready)
        #expect(!store.exists(for: "blackjack"))
    }

    @Test("以前の記録（区分なしのキー）は読み込み時に捨て、勝ち点は別のキーに付く")
    func legacyRecordIsDropped() throws {
        let (_, defaults, name) = makeBlackjackPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy: [String: PlayRecord] = [
            "blackjack": PlayRecord(metric: .points, plays: 40, wins: 20, losses: 20, bestPoints: 5200),
            "poker": PlayRecord(metric: .points, plays: 3, bestPoints: 1200),
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: PlayLog.recordsKey)

        let log = PlayLog(defaults: defaults)
        #expect(log.record(gameID: "blackjack") == nil, "以前の記録は残さない")
        #expect(log.record(gameID: "poker")?.bestPoints == 1200, "他のゲームの記録には触れない")

        let model = BlackjackModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: BlackjackStubAds(), playLog: log), seed: 11)
        playWholeMatch(model)
        #expect(log.records(gameID: "blackjack").count == 1)
        #expect(log.record(gameID: "blackjack", variant: BlackjackModel.recordVariant)?.bestPoints == model.points)
        #expect(log.summaryLine(gameID: "blackjack") == "ベスト \(model.points)", "ハブの 1 行は勝ち点の記録から出る")
    }

    // MARK: - Game Center

    @Test("Game Center の順位表（blackjackChips）へは送らない")
    func doesNotSubmitToGameCenter() {
        #expect(GameCenterLeaderboard.score(
            gameID: "blackjack", outcome: .win,
            score: GameScore(metric: .points, points: 8, variant: BlackjackModel.recordVariant)
        ) == nil)
        #expect(GameCenterLeaderboard.score(
            gameID: "blackjack", outcome: .win, score: GameScore(metric: .points, points: 8)
        ) == nil)
        #expect(!GameCenterLeaderboard.allIDs.contains(GameCenterLeaderboard.blackjackChips))
    }
}
