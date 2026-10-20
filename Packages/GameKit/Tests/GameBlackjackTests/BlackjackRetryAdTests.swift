import Testing
import Foundation
import Core
@testable import GameBlackjack
import CoreTestSupport
import GameKitTestSupport

/// 「あなた 16 対 ディーラー 18」でスタンド直前の回。スタンドすれば必ず負ける。
@MainActor
private func losingRound(
    completedRounds: Int = 2,
    points: Int = 2,
    streak: Int = 2,
    hasUsedRetry: Bool = false,
    ads: BlackjackStubAds = BlackjackStubAds(),
    store: MemorySnapshotStore = MemorySnapshotStore(),
    playLog: PlayLog? = nil,
    screenGeneration: GameScreenGeneration = GameScreenGeneration()
) -> BlackjackModel {
    let model = makeBlackjackModel(
        blackjackSnapshot(player: [10, 6], dealer: [10, 8], deck: [],
                          completedRounds: completedRounds, points: points, streak: streak,
                          hasUsedRetry: hasUsedRetry, handsWon: points, handsLost: 0),
        store: store, ads: ads, playLog: playLog, screenGeneration: screenGeneration
    )
    model.stand()
    #expect(model.outcome == .lose)
    return model
}

@Suite("負けた回のやり直し（リワード広告・#2552）")
@MainActor
struct BlackjackRetryAdTests {

    @Test("負けた回だけ、1 回の勝負につき 1 回やり直せる")
    func offeredOnlyAfterALoss() {
        #expect(losingRound().canRetryRound)
        #expect(!losingRound(hasUsedRetry: true).canRetryRound, "使い切った勝負では出さない")

        let won = makeBlackjackModel(blackjackSnapshot(player: [10, 9], dealer: [10, 7], deck: []))
        won.stand()
        #expect(!won.canRetryRound, "勝った回は対象外")
    }

    @Test("視聴完了でその回は無かったことになり、配り直される。点は動かず連勝は元に戻る")
    func retryUndoesTheLostRound() async {
        let ads = BlackjackStubAds()
        let model = losingRound(completedRounds: 2, points: 2, streak: 2, ads: ads)
        #expect(model.completedRounds == 3)
        #expect(model.streak == 0)

        let result = await model.retryRoundAfterAd()

        #expect(result == .granted)
        #expect(ads.rewardedCount == 1)
        #expect(model.hasUsedRetry)
        #expect(model.completedRounds == 2 || model.phase == .result,
                "配り直した回が進行中（ナチュラルで即決着したときだけ 3 回目の結果になる）")
        #expect(model.currentRound == 3, "同じ 3 回目をもう一度遊ぶ")
        #expect(model.points >= 2, "負けた回は 0 点なので合計は減らない")
        if model.phase == .playerTurn {
            #expect(model.streak == 2, "負けで途切れた連勝が戻る")
            #expect(model.hands.count == 1)
            #expect(model.hands[0].outcome == nil, "新しく配られている")
        }
        #expect(!model.canRetryRound, "やり直しは 1 回まで")
    }

    @Test("やり直した回でまた負けても、2 回目のやり直しは出ない")
    func onlyOncePerMatch() async throws {
        // 配り直しの札を決め打ちできないので、やり直し済みの勝負の中断データから負けを作る。
        let model = losingRound(hasUsedRetry: true)
        #expect(!model.canRetryRound)
        #expect(await model.retryRoundAfterAd() == .unavailable)
    }

    @Test("見なかった・読み込めなかったときは何も変えない")
    func notEarnedChangesNothing() async {
        let ads = BlackjackStubAds(rewardEarned: false)
        let model = losingRound(ads: ads)
        let round = model.completedRounds

        let result = await model.retryRoundAfterAd()

        #expect(result == .notEarned)
        #expect(model.phase == .result)
        #expect(model.completedRounds == round)
        #expect(!model.hasUsedRetry, "使っていないので権利は残る")
        #expect(model.canRetryRound)
    }

    @Test("広告のあいだに次の回へ進んでいたら、やり直しを乗せない（#727）")
    func movedOnDuringTheAd() async {
        let ads = BlackjackStubAds()
        let model = losingRound(ads: ads)
        ads.duringAd = { model.nextRound() }

        let result = await model.retryRoundAfterAd()

        #expect(result == .unavailable)
        #expect(!model.hasUsedRetry, "適用しなかったので権利は残る")
        #expect(model.completedRounds == 3, "進んだ先の回はそのまま")
    }

    @Test("広告のあいだにハブへ戻られていたら、捨てられたモデルに適用しない（#653）")
    func leftTheScreenDuringTheAd() async {
        let ads = BlackjackStubAds()
        let generation = GameScreenGeneration()
        let model = losingRound(ads: ads, screenGeneration: generation)
        ads.duringAd = { generation.advance() }

        #expect(await model.retryRoundAfterAd() == .unavailable)
        #expect(!model.hasUsedRetry)
        #expect(model.phase == .result)
    }

    @Test("負けた 10 回目は、選ぶまで勝負を締めない。やり直せば 10 回目をもう一度遊べる")
    func finalRoundWaitsForTheChoice() async {
        let (log, defaults, name) = makeBlackjackPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = losingRound(completedRounds: 9, points: 5, playLog: log)

        #expect(model.isFinalRoundResult)
        #expect(!model.matchOver, "やり直しが残っているあいだは締めない")
        #expect(log.record(gameID: "blackjack", variant: BlackjackModel.recordVariant) == nil, "記録もまだ付かない")

        #expect(await model.retryRoundAfterAd() == .granted)
        #expect(model.currentRound == 10)

        standUntilResolved(model)
        if !model.matchOver { model.nextRound() }
        #expect(model.matchOver)
        #expect(log.record(gameID: "blackjack", variant: BlackjackModel.recordVariant)?.plays == 1, "記録は 1 回だけ")
    }

    @Test("負けた 10 回目で「結果を見る」を選べば、そのまま締まる")
    func finalRoundFinishesOnNext() {
        let (log, defaults, name) = makeBlackjackPlayLog()
        defer { defaults.removePersistentDomain(forName: name) }
        let model = losingRound(completedRounds: 9, points: 5, playLog: log)

        model.nextRound()

        #expect(model.matchOver)
        #expect(model.points == 5)
        #expect(log.record(gameID: "blackjack", variant: BlackjackModel.recordVariant)?.bestPoints == 5)
        #expect(!model.canRetryRound)
    }

    @Test("やり直しを使ったことは中断を挟んでも残る")
    func usedRetrySurvivesResume() async {
        let store = MemorySnapshotStore()
        let model = losingRound(store: store)
        #expect(await model.retryRoundAfterAd() == .granted)
        standUntilResolved(model)

        let reopened = BlackjackModel(services: GameServices(snapshots: store, ads: BlackjackStubAds()))
        #expect(reopened.hasUsedRetry)
    }

    @Test("広告の目的は既存の「戻す・待った」と同じ undo で数える")
    func usesTheUndoPurpose() throws {
        let model = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackModel.swift")
        #expect(model.contains("showRewardedAd(gameID: gameID, purpose: .undo)"))
        let view = try SourceScan.packageSource("Sources/GameBlackjack/BlackjackView.swift")
        #expect(view.contains(".rewardOffer(retryRescue, for: .undo, isPresented: model.canRetryRound"))
    }
}
