import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameBlackjack
import GameKitTestSupport

/// 単発戦（#2860）。10 回勝負とは別に、1 回だけで終わる勝負を選べる。
@Suite("ブラックジャックの単発戦（#2860）")
@MainActor
struct BlackjackSingleRoundTests {

    @Test("単発戦は 1 回で勝負が締まり、game_start / game_end は 1 回ずつ（mode は single_round）")
    func finishesAfterOneRound() {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: BlackjackStubAds(), playLog: makeBlackjackPlayLog().0,
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["blackjack"])
        )
        let model = BlackjackModel(services: services, seed: 7)
        model.deal(format: .single)
        #expect(model.format == .single)
        #expect(model.isFinalRound)
        #expect(!model.showsFinalRoundMark)
        standUntilResolved(model)
        if model.canRetryRound { model.nextRound() }  // 負けならやり直しを使わず先へ（結果を見る）
        #expect(model.phase == .result)
        if !model.matchOver { model.nextRound() }
        #expect(model.matchOver)
        #expect(model.recordResult != nil)
        #expect(spy.starts == ["blackjack"])
        #expect(spy.ends.count == 1)
        let modes = spy.events.compactMap { event -> AnalyticsMode?? in
            switch event {
            case let .gameStart(_, _, mode, _, _): return .some(mode)
            case let .gameEnd(_, _, _, mode, _, _, _, _, _): return .some(mode)
            default: return nil
            }
        }
        #expect(modes == [.some(.singleRound), .some(.singleRound)])
    }

    @Test("10 回勝負は従来どおり mode を送らず、10 回目まで締まらない")
    func tenRoundsUnchanged() {
        let spy = SpyAnalyticsService()
        let services = GameServices(
            snapshots: MemorySnapshotStore(), ads: BlackjackStubAds(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["blackjack"])
        )
        let model = BlackjackModel(services: services, seed: 7)
        model.deal()
        #expect(model.format == .tenRounds)
        standUntilResolved(model)
        if model.canRetryRound { /* やり直しは使わない */ }
        #expect(!model.matchOver, "1 回目では締まらない")
        let modes = spy.events.compactMap { event -> AnalyticsMode?? in
            if case let .gameStart(_, _, mode, _, _) = event { return .some(mode) }
            return nil
        }
        #expect(modes == [.none])
    }

    @Test("単発戦の勝ちは 10 回勝負と別の記録（blackjack#single）に残る")
    func recordsSeparately() {
        let (log, _, _) = makeBlackjackPlayLog()
        let model = makeBlackjackModel(
            blackjackSnapshot(player: [10, 9], dealer: [10, 7], deck: [], format: .single), playLog: log)
        model.stand()
        #expect(model.outcome == .win)
        #expect(model.matchOver, "勝った 1 回目で勝負が締まる（やり直しの対象ではない）")
        #expect(model.matchOutcome == .win)
        let single = log.record(gameID: "blackjack", variant: "single")
        #expect(single?.plays == 1)
        #expect(single?.bestPoints == 1)
        #expect(single?.variantLabel == "単発戦")
        #expect(log.record(gameID: "blackjack", variant: BlackjackModel.recordVariant) == nil)
    }

    @Test("単発戦で負けた回は、広告でやり直せる（1 回まで）。見送れば締まる")
    func lossCanRetryOnce() async {
        let model = makeBlackjackModel(
            blackjackSnapshot(player: [10, 6], dealer: [10, 9], deck: [], format: .single))
        model.stand()
        #expect(model.outcome == .lose)
        #expect(!model.matchOver, "やり直しが残っているあいだは締めない")
        #expect(model.canRetryRound)
        let result = await model.retryRoundAfterAd()
        #expect(result == .granted)
        #expect(model.completedRounds == 0)
        #expect(model.format == .single)
    }

    @Test("単発戦の途中の中断データから戻っても形が保たれる。形の無い旧い中断データは 10 回勝負")
    func formatSurvivesResume() {
        let single = makeBlackjackModel(
            blackjackSnapshot(player: [10, 6], dealer: [10, 9], deck: [], format: .single))
        #expect(single.format == .single)
        let legacy = makeBlackjackModel(
            blackjackSnapshot(player: [10, 6], dealer: [10, 9], deck: [], completedRounds: 3))
        #expect(legacy.format == .tenRounds)
        #expect(!legacy.isFinalRound)
    }

    @Test("単発戦の中断データに completedRounds が 1 を超える値があれば読まない")
    func invalidSingleSnapshotIsDropped() {
        let store = MemorySnapshotStore()
        let model = makeBlackjackModel(
            blackjackSnapshot(player: [10, 6], dealer: [10, 9], deck: [], completedRounds: 3, format: .single),
            store: store)
        #expect(model.phase == .ready)
        #expect(store.isEmpty)
    }

    @Test("もう一度・遊び方を選び直しても、選んだ形で 1 回目から始まる")
    func restartWithFormat() {
        let model = BlackjackModel(services: nil, seed: 3)
        model.deal(format: .single)
        standUntilResolved(model)
        model.restartMatch()
        #expect(model.phase == .ready)
        model.deal(format: .tenRounds)
        #expect(model.format == .tenRounds)
        #expect(model.currentRound == 1)
        #expect(!model.isFinalRound)
    }

    @Test("記録の区分・回数・解析の mode・表示名")
    func formatProperties() {
        #expect(BlackjackMatchFormat.tenRounds.rounds == 10)
        #expect(BlackjackMatchFormat.single.rounds == 1)
        #expect(BlackjackMatchFormat.tenRounds.recordVariant == "match10")
        #expect(BlackjackMatchFormat.single.recordVariant == "single")
        #expect(BlackjackMatchFormat.tenRounds.analyticsMode == nil)
        #expect(BlackjackMatchFormat.single.analyticsMode == .singleRound)
        #expect(RecordVariantLabels.label(recordKey: "blackjack#match10", language: .japanese) == "10回勝負")
        #expect(RecordVariantLabels.label(recordKey: "blackjack#single", language: .english) == "Single Round")
    }

    @Test("単発戦でスプリットして一勝一敗でも、点が入れば勝負全体は勝ち（回の結果と揃える）")
    func splitWinLossIsWin() {
        let model = makeBlackjackModel(
            blackjackSnapshot(player: [], dealer: [10, 7], deck: [], hands: { table in
                [BlackjackHand(id: 0, cards: table.cards([10, 9]), isFromSplit: true, isDone: true),
                 BlackjackHand(id: 1, cards: table.cards([10, 5]), isFromSplit: true)]
            }, activeHandIndex: 1, format: .single))
        model.stand()
        #expect(model.outcome == .win)
        #expect(model.matchOutcome == .win)
    }
}
