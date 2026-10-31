import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameOldMaid

// MARK: - 組み立て

private func card(_ suit: OldMaidSuit, _ rank: Int) -> OldMaidCard {
    OldMaidCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
}

@MainActor
private func makeLog(_ name: String) -> PlayLog {
    let suite = "asobiba.oldmaid.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlayLog(defaults: defaults)
}

@MainActor
private func makeModel(
    seed: UInt64? = 42,
    store: SnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil,
    feedback: SpyFeedbackService = SpyFeedbackService()
) -> OldMaidModel {
    let services = GameServices(
        snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [OldMaidModel.gameID]) }
    )
    // テストでは CPU の間合いを取らない（待たずに最後まで進める）。
    return OldMaidModel(services: services, cpuDelay: .zero, seed: seed)
}

/// あなたの番は先頭の札を選んで引き、決着まで進める。
@MainActor
private func playToFinish(_ model: OldMaidModel, maxTurns: Int = 3_000) async -> Bool {
    var turns = 0
    while model.phase == .playing, turns < maxTurns {
        turns += 1
        await model.runCPUTurnsIfNeeded()
        guard model.phase == .playing, model.isPlayerTurn, let target = model.humanTarget else { continue }
        model.toggleSelection(model.hands[target][0].id)
        model.drawSelected()
    }
    return model.phase == .result
}

/// 53 枚の整合を取った局面（手札に出さない札はペアで捨て札に入れる。手札の各数字は 2 枚ずつ）。
private func scenario(_ hands: [[OldMaidCard]], currentPlayer: Int = 0, level: CPUStrength = .normal,
                      watched: Bool = false, tellSeed: UInt64 = 1) -> OldMaidGame {
    let used = Set(hands.flatMap { $0 })
    let rest = OldMaidCard.makeDeck().filter { !used.contains($0) && !$0.isJoker }
    let pairs = (1...13).flatMap { rank -> [[OldMaidCard]] in
        let same = rest.filter { $0.rank == rank }
        return stride(from: 0, to: same.count - 1, by: 2).map { [same[$0], same[$0 + 1]] }
    }
    return OldMaidGame(hands: hands, discardedPairs: pairs, currentPlayer: currentPlayer,
                       aiLevel: level.rawValue, tellSeed: tellSeed, humanJokerWatched: watched)
}

// MARK: - 開始と進行

@Suite("ババ抜きの進行")
@MainActor
struct OldMaidModelFlowTests {
    @Test("開いた直後は配っていない。配ると 53 枚・ペア無しで、1 ゲーム目はあなたから引く")
    func startsDealt() {
        let model = makeModel()
        #expect(model.phase == .idle)
        #expect(model.game == nil)
        model.startGame()
        #expect(model.phase == .playing)
        #expect(model.gameNumber == 1)
        #expect(model.game?.totalCardCount == 53)
        #expect(model.game?.isConsistent == true)
        #expect(model.currentPlayer == 0 || model.playerHand.isEmpty)
        #expect(model.aiLevel == CPUStrength.standard.rawValue)
    }

    @Test("どの強さでも決着まで進み、負けは 1 人・ジョーカー 1 枚だけが残る")
    func playsToResult() async {
        for level in CPUStrength.allCases {
            for seed in UInt64(1)...15 {
                let model = makeModel(seed: seed)
                model.startGame(aiLevel: level.rawValue)
                #expect(await playToFinish(model), "\(level) seed \(seed)")
                let loser = model.loser
                #expect(loser != nil)
                #expect(loser.map { model.hands[$0] } == [OldMaidCard.joker])
                #expect(model.game?.ranking.count == 4)
                #expect(model.reviewOutcome == (loser == 0 ? .loss : .win))
            }
        }
    }

    @Test("引けるのは自分の番に、引く相手の札だけ。選ばずには引けない")
    func drawingRules() {
        let feedback = SpyFeedbackService()
        let model = makeModel(feedback: feedback)
        model.configureForTesting(scenario([
            [card(.spades, 2), card(.hearts, 5)],
            [card(.hearts, 2), OldMaidCard.joker],
            [card(.clubs, 5), card(.spades, 7)],
            [card(.hearts, 7)],
        ]))
        #expect(model.isPlayerTurn)
        #expect(model.humanTarget == 1)
        #expect(!model.canDraw, "選ぶまでは引けない")
        model.drawSelected()
        #expect(feedback.notices(of: .warning) == 1)
        model.toggleSelection(card(.clubs, 5).id)
        #expect(model.selectedID == nil, "引く相手ではない人の札は選べない")
        model.toggleSelection(card(.hearts, 2).id)
        #expect(model.selectedID == card(.hearts, 2).id)
        model.toggleSelection(card(.hearts, 2).id)
        #expect(model.selectedID == nil, "もう一度タップで指を離す")
        model.toggleSelection(card(.hearts, 2).id)
        #expect(model.canDraw)
        model.drawSelected()
        #expect(model.playerHand == [card(.hearts, 5)], "2 のペアを捨てた")
        #expect(model.game?.lastActions[0] == .drewPair(rank: 2))
        #expect(model.currentPlayer == 1)
        #expect(!model.isPlayerTurn)
        #expect(model.selectedID == nil)
    }

    @Test("CPU の番はあなたの番になるまで進み、CPU は合法な札だけを引く")
    func cpuTurnsRunUntilHuman() async {
        let model = makeModel()
        model.configureForTesting(scenario([
            [card(.spades, 2), card(.hearts, 5), card(.clubs, 9)],
            [card(.hearts, 2), OldMaidCard.joker, card(.spades, 9)],
            [card(.clubs, 5), card(.spades, 7)],
            [card(.hearts, 7)],
        ], currentPlayer: 1))
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .result || model.isPlayerTurn)
        #expect(model.game?.isConsistent == true)
    }

    @Test("あなたが抜けたら残りの CPU だけでその場で決着し、あなたの勝ちとして記録する")
    func humanOutSettlesImmediately() {
        let log = makeLog("humanOut")
        let model = makeModel(log: log)
        model.configureForTesting(scenario([
            [card(.spades, 4)],
            [card(.hearts, 4)],
            [card(.clubs, 6), card(.clubs, 8)],
            [card(.spades, 6), card(.spades, 8), OldMaidCard.joker],
        ]))
        model.toggleSelection(card(.hearts, 4).id)
        model.drawSelected()
        #expect(model.phase == .result)
        #expect(model.playerPlace == 0 || model.playerPlace == 1)
        #expect(model.loser != 0)
        #expect(model.reviewOutcome == .win)
        let record = log.record(gameID: OldMaidModel.gameID)
        #expect(record?.wins == 1)
        #expect(record?.plays == 1)
        #expect(model.recordResult != nil)
    }

    @Test("ジョーカーを持って残ったら負けとして記録する")
    func humanLoses() {
        let log = makeLog("humanLoses")
        let model = makeModel(log: log)
        model.configureForTesting(scenario([
            [OldMaidCard.joker, card(.spades, 3)],
            [card(.hearts, 3)],
            [],
            [],
        ]))
        model.toggleSelection(card(.hearts, 3).id)
        model.drawSelected()
        #expect(model.phase == .result)
        #expect(model.loser == 0)
        #expect(model.reviewOutcome == .loss)
        #expect(log.record(gameID: OldMaidModel.gameID)?.losses == 1)
    }

    @Test("次のゲームは最初に引く人が 1 人ずつ回り、強さは引き継ぐ")
    func nextGameRotatesFirstPlayer() {
        let model = makeModel()
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        model.startGame()
        #expect(model.gameNumber == 2)
        #expect(model.aiLevel == CPUStrength.hard.rawValue)
        #expect(model.game?.aiLevel == CPUStrength.hard.rawValue)
        let first = model.game?.currentPlayer
        #expect(first == 1 || model.hands[1].isEmpty)
    }
}

// MARK: - 顔と見張り

@Suite("ババ抜きの顔とシャッフル")
@MainActor
struct OldMaidModelFaceTests {
    @Test("顔に出るのは、あなたが指をかけている相手だけ")
    func faceOnlyOnTarget() {
        let model = makeModel()
        model.configureForTesting(scenario([
            [card(.spades, 2), card(.hearts, 5)],
            [card(.hearts, 2), OldMaidCard.joker],
            [card(.clubs, 5), card(.spades, 7)],
            [card(.hearts, 7)],
        ], level: .novice, tellSeed: 11))
        #expect(model.face(of: 1) == .neutral, "指をかける前はふつうの顔")
        model.toggleSelection(OldMaidCard.jokerID)
        let expected = model.game!.face(of: 1, touching: OldMaidCard.jokerID)
        #expect(model.face(of: 1) == expected)
        #expect(model.face(of: 2) == .neutral)
        #expect(model.face(of: 3) == .neutral)
    }

    @Test("ジョーカーを引くと見張られ、シャッフルで外れる。シャッフルしても札は変わらない")
    func shuffleClearsWatch() {
        let model = makeModel()
        model.configureForTesting(scenario([
            [card(.spades, 2), card(.hearts, 5), card(.clubs, 9)],
            [OldMaidCard.joker, card(.spades, 5)],
            [card(.hearts, 2), card(.spades, 9), card(.hearts, 11)],
            [card(.clubs, 11)],
        ]))
        model.toggleSelection(OldMaidCard.jokerID)
        model.drawSelected()
        #expect(model.playerHand.last == .joker)
        #expect(model.lastDrawnCardID == OldMaidCard.jokerID)
        #expect(model.isJokerWatched)
        let before = Set(model.playerHand)
        model.shuffleHand()
        #expect(!model.isJokerWatched)
        #expect(Set(model.playerHand) == before)
    }

    @Test("あなたから引くのは、あなたの前の手札が残っている人")
    func humanDrawer() {
        let model = makeModel()
        model.configureForTesting(scenario([
            [card(.spades, 2)],
            [card(.hearts, 2), OldMaidCard.joker],
            [card(.clubs, 5)],
            [],
        ], currentPlayer: 1))
        #expect(model.humanDrawer == 2, "CPU3 が抜けているので CPU2 があなたから引く")
    }
}

// MARK: - 中断データと計測

@Suite("ババ抜きの中断データと計測")
@MainActor
struct OldMaidPersistenceTests {
    @Test("配ったばかりの局は保存しない。1 枚動いたら保存し、開き直すと同じ局面から続く")
    func resumes() {
        let store = MemorySnapshotStore()
        let module = OldMaidModule()
        let model = makeModel(store: store)
        model.startGame(aiLevel: CPUStrength.easy.rawValue)
        #expect(!module.hasResumableSnapshot(in: store), "配ったばかりの局は保存しない（#240）")
        if model.isPlayerTurn, let target = model.humanTarget {
            model.toggleSelection(model.hands[target][0].id)
            model.drawSelected()
        }
        guard model.phase == .playing else { return }
        #expect(module.hasResumableSnapshot(in: store))
        let restored = makeModel(store: store)
        #expect(restored.phase == .playing)
        #expect(restored.game == model.game)
        #expect(restored.aiLevel == CPUStrength.easy.rawValue)
        #expect(restored.gameNumber == model.gameNumber)
    }

    @Test("決着したら中断データを消す")
    func clearsOnFinish() async {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startGame()
        #expect(await playToFinish(model))
        #expect(!OldMaidModule().hasResumableSnapshot(in: store))
    }

    @Test("壊れた中断データからは復元しない（落ちずに開始前へ）")
    func brokenSnapshot() throws {
        let store = MemorySnapshotStore()
        var broken = OldMaidCard.makeDeck()
        broken.removeLast()
        let game = OldMaidGame(hands: [broken, [], [], []])
        try store.save(OldMaidSnapshot(game: game, gameNumber: 3), for: OldMaidModel.gameID)
        let model = makeModel(store: store)
        #expect(model.phase == .idle)
        #expect(model.game == nil)
    }

    @Test("game_start は配るたびに 1 回（強さを載せる）、game_end は決着で 1 回")
    func analytics() async {
        let spy = SpyAnalyticsService()
        let model = makeModel(analytics: spy)
        #expect(spy.events.isEmpty, "画面を開いただけでは配られない")
        model.startGame(aiLevel: CPUStrength.hard.rawValue)
        #expect(spy.starts == [OldMaidModel.gameID])
        #expect(spy.startLevels == [.hard])
        #expect(await playToFinish(model))
        #expect(spy.starts(of: OldMaidModel.gameID) == 1)
        #expect(spy.ends(of: OldMaidModel.gameID) == 1)
        model.startGame()
        #expect(spy.starts(of: OldMaidModel.gameID) == 2, "2 ゲーム目は gameDidRestart で数える")
    }

    @Test("記録は「ふつう」だけ区分なし、ほかの強さは強さ別の区分に分かれる（#2716）")
    func recordVariantPerStrength() {
        let model = makeModel()
        model.startGame()
        #expect(model.recordScore.variant == nil)
        for strength in CPUStrength.allCases where strength != .standard {
            model.startGame(aiLevel: strength.rawValue)
            #expect(model.recordScore.variant == strength.recordVariantKey)
            #expect(model.recordScore.variantLabel == RecordVariantLabels.label(
                recordKey: "oldmaid#\(strength.recordVariantKey)", language: .japanese))
            #expect(model.recordScore.variantLabel != nil)
        }
    }
}

// MARK: - CPU 手番キー（#3146）

@MainActor
struct OldMaidCPUTurnKeyTests {
    /// `OldMaidView` は `.task(id: model.cpuTurnKey)` 1 か所で CPU を起こす。キーが変わらない操作があると、
    /// その操作の後に CPU 番のまま止まる。
    @Test("引く・CPU の着手・新しいゲームのどれでも手番キーが変わる")
    func keyChangesAfterEveryTurnAdvancingOperation() async {
        let model = makeModel()
        var seen: Set<AITurnKey> = []
        func expectFreshKey(_ what: String) {
            #expect(seen.insert(model.cpuTurnKey).inserted, "\(what)の後に手番キーが変わらない")
        }
        model.startGame()
        expectFreshKey("新しいゲーム")
        var humanDraws = 0
        var steps = 0
        while model.phase == .playing, steps < 3_000, humanDraws < 3 {
            steps += 1
            let before = model.cpuTurnKey
            await model.runCPUTurnsIfNeeded()
            if model.cpuTurnKey != before { expectFreshKey("CPU の着手") }
            guard model.phase == .playing, model.isPlayerTurn, let target = model.humanTarget else { continue }
            model.toggleSelection(model.hands[target][0].id)
            model.drawSelected()
            humanDraws += 1
            expectFreshKey("札を引く")
        }
        #expect(humanDraws > 0)
        model.startGame()
        expectFreshKey("対局の作り直し")
    }

    @Test("CPU の手番は手番キーの .task(id:) 1 か所で起こし、操作側から手で起こさない")
    func viewDrivesCPUFromSingleTask() throws {
        let code = SourceScan.strippingComments(try SourceScan.packageSource("Sources/GameOldMaid/OldMaidView.swift"))
        #expect(code.contains(".task(id: CPUDriveKey(turn: model.cpuTurnKey"))
        #expect(code.components(separatedBy: "runCPUTurnsIfNeeded()").count - 1 == 1)
        #expect(!code.contains("cpuTask") && !code.contains("runCPU()"))
    }
}
