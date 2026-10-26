import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GamePoker

/// 単発戦（#2860）。10 回勝負とは別に、1 回だけで終わる勝負を選べる。
@Suite("ポーカーの単発戦（#2860）")
@MainActor
struct PokerSingleRoundTests {

    private func makeServices(
        store: MemorySnapshotStore = MemorySnapshotStore(), log: PlayLog? = nil, spy: SpyAnalyticsService? = nil
    ) -> GameServices {
        GameServices(
            snapshots: store, ads: PokerStubAdService(), playLog: log,
            analytics: spy.map { GameAnalytics(service: $0, allowedGameIDs: ["poker"]) }
        )
    }

    @Test("単発戦は 1 回で決着し、game_start / game_end は 1 回ずつ（mode は single_round）")
    func finishesAfterOneRound() {
        let spy = SpyAnalyticsService()
        let model = PokerModel(services: makeServices(log: makePokerPlayLog(), spy: spy))
        model.startGame(format: .single)
        #expect(model.format == .single)
        #expect(model.round == 1)
        #expect(model.isFinalRound)
        #expect(!model.showsFinalRoundMark, "最初から最後の回なので最終回の印は出さない")
        model.confirmExchange()
        if model.phase == .drawn { model.showdown() }
        #expect(model.phase == .result)
        #expect(model.sessionOver)
        #expect(model.recordResult != nil)
        model.nextRound()
        #expect(model.round == 1, "決着のあとは次の回へ進まない")

        #expect(spy.starts == ["poker"])
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

    @Test("10 回勝負の解析は従来どおり mode を送らない")
    func tenRoundsHasNoMode() {
        let spy = SpyAnalyticsService()
        let model = PokerModel(services: makeServices(spy: spy))
        model.startGame()
        #expect(model.format == .tenRounds)
        #expect(model.showsFinalRoundMark == false)
        let modes = spy.events.compactMap { event -> AnalyticsMode?? in
            if case let .gameStart(_, _, mode, _, _) = event { return .some(mode) }
            return nil
        }
        #expect(modes == [.none])
    }

    @Test("単発戦の勝ちは 10 回勝負と別の記録（poker#single）に残る")
    func recordsSeparately() {
        let log = makePokerPlayLog()
        let win = makePokerModel(
            pokerSnapshot(round: 1, player: PokerHands.fullHouse, cpu: PokerHands.straight, sessionFormat: .single),
            playLog: log
        )
        win.showdown()
        #expect(win.sessionOver)
        #expect(win.sessionWinner == .player)
        #expect(win.reviewOutcome == .win)
        #expect(win.recordResult?.record.bestPoints == 18)
        let single = log.record(gameID: "poker", variant: "single")
        #expect(single?.plays == 1)
        #expect(single?.bestPoints == 18)
        #expect(single?.variantLabel == "単発戦")
        #expect(log.record(gameID: "poker", variant: PokerModel.recordVariant) == nil, "10 回勝負の記録には触れない")
    }

    @Test("単発戦の負け・引き分けは勝負全体の負け・引き分け")
    func lossAndTie() {
        let lose = makePokerModel(
            pokerSnapshot(round: 1, player: PokerHands.highCard, cpu: PokerHands.flush, sessionFormat: .single))
        lose.showdown()
        #expect(lose.sessionWinner == .cpu)
        #expect(lose.reviewOutcome == .loss)
        let tie = makePokerModel(
            pokerSnapshot(round: 1, player: PokerHands.straight, cpu: PokerHands.sameStraight, sessionFormat: .single))
        tie.showdown()
        #expect(tie.sessionWinner == .tie)
        #expect(tie.reviewOutcome == .draw)
    }

    @Test("単発戦の途中の中断データから戻っても形が保たれる。形の無い旧い中断データは 10 回勝負")
    func formatSurvivesResume() {
        let single = makePokerModel(
            pokerSnapshot(phase: .exchange, round: 1, player: PokerHands.fullHouse, cpu: PokerHands.straight,
                          sessionFormat: .single))
        #expect(single.format == .single)
        let legacy = makePokerModel(
            pokerSnapshot(phase: .exchange, round: 3, player: PokerHands.fullHouse, cpu: PokerHands.straight))
        #expect(legacy.format == .tenRounds)
        #expect(!legacy.isFinalRound)
    }

    @Test("配ったあとの中断データに形が載る")
    func persistsFormat() throws {
        let store = MemorySnapshotStore()
        let model = PokerModel(services: makeServices(store: store))
        model.startGame(format: .single)
        let snap = try #require(store.load(PokerSnapshot.self, for: "poker"))
        #expect(snap.sessionFormat == .single)
    }

    @Test("記録の区分・回数・解析の mode")
    func formatProperties() {
        #expect(PokerSessionFormat.tenRounds.rounds == 10)
        #expect(PokerSessionFormat.single.rounds == 1)
        #expect(PokerSessionFormat.tenRounds.recordVariant == "round10")
        #expect(PokerSessionFormat.single.recordVariant == "single")
        #expect(PokerSessionFormat.tenRounds.analyticsMode == nil)
        #expect(PokerSessionFormat.single.analyticsMode == .singleRound)
        #expect(RecordVariantLabels.label(recordKey: "poker#single", language: .japanese) == "単発戦")
        #expect(RecordVariantLabels.label(recordKey: "poker#single", language: .english) == "Single Round")
    }

    @Test("勝負をやり直す（もう一度）と、選んだ形のまま 1 回目から始まる")
    func restartKeepsFormat() {
        let model = PokerModel(services: makeServices())
        model.startGame(format: .single)
        playPokerToEnd(model)
        #expect(model.sessionOver)
        model.startGame(format: model.format)
        #expect(!model.sessionOver)
        #expect(model.format == .single)
        #expect(model.round == 1)
        model.startGame(format: .single)
        model.restartSession()
        model.startGame(format: .tenRounds)
        #expect(model.format == .tenRounds)
    }

    @Test("読み上げの帯: 単発戦は「n回目」を言わない")
    func scoreboardLabelForSingle() {
        let label = PokerAccessibility.scoreboardLabel(round: 1, playerPoints: 3, cpuPoints: 0, format: .single)
        #expect(label.hasPrefix("単発戦"))
        #expect(!label.contains("1回目"))
    }
}
