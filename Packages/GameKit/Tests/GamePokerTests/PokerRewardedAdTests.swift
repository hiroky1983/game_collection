import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GamePoker

/// 広告の「もう 1 回交換」（#2551。チップ補充の広告の置き換え）。
@Suite("ポーカー: 広告でもう 1 回交換")
@MainActor
struct PokerRewardedAdTests {

    @Test("見終えたら、交換の段へ戻ってもう 1 回交換できる")
    func grantedReturnsToExchange() async {
        let ads = PokerStubAdService(rewardEarned: true)
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.straight), ads: ads)
        #expect(model.canUseExtraExchange)

        #expect(await model.extraExchangeAfterAd() == .granted)
        #expect(ads.rewardedCount == 1)
        #expect(model.phase == .exchange)
        #expect(model.extraExchangeUsed)

        let before = model.playerHand
        model.toggleCardSelection(before[0])
        model.confirmExchange()
        #expect(model.playerHand[0].id != before[0].id, "選んだ札が引き直されている")
        #expect(model.phase == .result, "2 回目の交換のあとはそのまま勝負になる")
    }

    @Test("1 回の勝負（10 回）につき 1 回まで。次の回では広告を出さない")
    func oncePerSession() async {
        let ads = PokerStubAdService(rewardEarned: true)
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.straight), ads: ads)
        #expect(await model.extraExchangeAfterAd() == .granted)
        model.confirmExchange()
        model.nextRound()
        model.confirmExchange()
        #expect(model.phase == .result, "使い切った勝負では選ぶ段を通らない")
        #expect(!model.canUseExtraExchange)
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 1, "使い切ったあとは広告を出さない")

        // 新しい 10 回勝負では、また 1 回使える。
        playPokerToEnd(model)
        model.startGame()
        model.confirmExchange()
        #expect(model.phase == .drawn)
        #expect(model.canUseExtraExchange)
    }

    @Test("使った印は中断を挟んでも戻らない")
    func usedFlagSurvivesResume() async {
        let store = MemorySnapshotStore()
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.straight), store: store)
        #expect(await model.extraExchangeAfterAd() == .granted)
        let reopened = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        #expect(reopened.phase == .exchange)
        #expect(reopened.extraExchangeUsed)
    }

    @Test("見なかったときは何も変えない")
    func notEarnedChangesNothing() async {
        let ads = PokerStubAdService(rewardEarned: false)
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.straight), ads: ads)
        let hand = model.playerHand
        #expect(await model.extraExchangeAfterAd() == .notEarned)
        #expect(model.phase == .drawn)
        #expect(!model.extraExchangeUsed)
        #expect(model.playerHand == hand)
    }

    @Test("交換の段（.drawn）以外では広告を出さない")
    func onlyWhileDrawn() async {
        let ads = PokerStubAdService(rewardEarned: true)
        let model = makePokerModel(pokerSnapshot(phase: .exchange, player: PokerHands.highCard, cpu: PokerHands.straight), ads: ads)
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        model.confirmExchange()
        model.showdown()
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(ads.rewardedCount == 0)
    }

    @Test("広告のあいだに勝負へ進んだら適用しない（#728）")
    func supersededByShowdown() async {
        let ads = PokerStubAdService(rewardEarned: true)
        let model = makePokerModel(pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.straight), ads: ads)
        ads.duringAd = { model.showdown() }
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(model.phase == .result)
        #expect(!model.extraExchangeUsed, "回数は減らない")
    }

    @Test("広告のあいだにハブへ戻ったら適用しない（#653）")
    func supersededByLeavingTheScreen() async {
        let ads = PokerStubAdService(rewardEarned: true)
        let generation = GameScreenGeneration()
        let model = makePokerModel(
            pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.straight),
            ads: ads, screenGeneration: generation
        )
        ads.duringAd = { generation.advance() }
        #expect(await model.extraExchangeAfterAd() == .unavailable)
        #expect(model.phase == .drawn)
        #expect(!model.extraExchangeUsed)
    }

    @Test("広告は「やり直し」系の目的（undo）で計測する")
    func purposeIsUndo() async {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["poker"])
        let model = makePokerModel(
            pokerSnapshot(player: PokerHands.highCard, cpu: PokerHands.straight), analytics: analytics
        )
        #expect(await model.extraExchangeAfterAd() == .granted)
        let source = try? SourceScan.packageSource("Sources/GamePoker/PokerModel.swift")
        #expect(source?.contains("showRewardedAd(gameID: gameID, purpose: .undo)") == true)
        #expect(source?.contains("purpose: .revival") == false, "チップ補充（復活）の広告は無くなった")
    }
}
