import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameDiceCombo

@MainActor
private func makeServices(
    store: MemorySnapshotStore = MemorySnapshotStore(),
    log: PlayLog? = nil,
    analytics: SpyAnalyticsService? = nil,
    feedback: SpyFeedbackService = SpyFeedbackService()
) -> GameServices {
    GameServices(
        snapshots: store, ads: NoopAdService(), feedback: feedback, playLog: log,
        analytics: analytics.map { GameAnalytics(service: $0, allowedGameIDs: [DiceComboModel.gameID]) }
    )
}

@MainActor
private func makeLog(_ name: String) -> PlayLog {
    let suite = "asobiba.dicecombo.tests.\(name)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return PlayLog(defaults: defaults)
}

/// 12 ターンを「1 回振って、空いている役の先頭に入れる」で最後まで進める。
@MainActor
private func playThrough(_ model: DiceComboModel) {
    while !model.isFinished {
        model.roll()
        let open = DiceComboCategory.allCases.first { model.canChoose($0) }!
        model.choose(open)
    }
}

@MainActor
@Suite("サイコロ役づくりの Model")
struct DiceComboModelTests {

    @Test("開いた直後は 1 ターン目で、振るまで役を選べずキープもできない")
    func initialState() {
        let model = DiceComboModel(services: makeServices(), seed: 1)
        #expect(model.turn == 1)
        #expect(model.dice.isEmpty)
        #expect(model.rollsUsed == 0)
        #expect(model.canRoll)
        #expect(!model.canHold)
        #expect(DiceComboCategory.allCases.allSatisfy { !model.canChoose($0) && model.preview($0) == nil })
        model.choose(.choice)
        #expect(model.scores.isEmpty, "振る前は記入できない")
        #expect(model.total == 0)
        #expect(!model.hasProgressToLose)
    }

    @Test("1 ターンに振れるのは 3 回まで。3 回振ったらキープは切り替えられない")
    func threeRollsPerTurn() {
        let feedback = SpyFeedbackService()
        let model = DiceComboModel(services: makeServices(feedback: feedback), seed: 2)
        model.roll()
        #expect(model.rollsUsed == 1 && model.rollsRemaining == 2)
        #expect(DiceComboLogic.isValidDice(model.dice))
        #expect(model.held == [false, false, false, false, false])
        #expect(model.canHold)
        model.roll()
        model.roll()
        #expect(model.rollsUsed == 3 && !model.canRoll && !model.canHold)
        let dice = model.dice
        model.roll()
        #expect(model.rollsUsed == 3 && model.dice == dice, "4 回目は振れない")
        #expect(feedback.notices(of: .warning) == 1)
        model.toggleHold(0)
        #expect(model.held[0] == false)
    }

    @Test("キープした目は振り直しても変わらない")
    func heldDiceStay() {
        let model = DiceComboModel(services: makeServices(), seed: 3)
        model.roll()
        model.toggleHold(1)
        model.toggleHold(4)
        let kept = (model.dice[1], model.dice[4])
        model.roll()
        #expect(model.dice[1] == kept.0 && model.dice[4] == kept.1)
        #expect(model.held == [false, true, false, false, true])
        model.toggleHold(1)
        #expect(model.held == [false, false, false, false, true], "もう一度タップで外せる")
    }

    @Test("役を選ぶとその役の点が入り、次のターンは振る前から始まる")
    func chooseScoresAndAdvances() {
        let model = DiceComboModel(services: makeServices(), seed: 4)
        model.roll()
        let expected = DiceComboLogic.score(.choice, dice: model.dice)
        #expect(model.preview(.choice) == expected)
        model.choose(.choice)
        #expect(model.scores[.choice] == expected)
        #expect(model.lastFilled == .choice)
        #expect(model.turn == 2)
        #expect(model.rollsUsed == 0 && model.dice.isEmpty && model.held.isEmpty)
        #expect(!model.canChoose(.choice), "同じ役には 2 度入れられない")
        model.roll()
        model.choose(.choice)
        #expect(model.scores[.choice] == expected && model.scores.count == 1)
        #expect(model.hasProgressToLose)
    }

    @Test("条件に合わない役にも 0 点で入れられる")
    func zeroScoreIsAllowed() {
        let model = DiceComboModel(services: makeServices(), seed: 5)
        model.roll()
        // 5 個とも同じでなければ 0 点、同じなら 50 点。どちらでも記入はできる。
        let expected = Set(model.dice).count == 1 ? 50 : 0
        model.choose(.fiveDice)
        #expect(model.scores[.fiveDice] == expected)
    }

    @Test("12 役を埋めると決着し、合計点が自己ベストに記録され、中断データは消える")
    func finishRecordsPoints() {
        let store = MemorySnapshotStore()
        let log = makeLog("finish")
        let feedback = SpyFeedbackService()
        let model = DiceComboModel(services: makeServices(store: store, log: log, feedback: feedback), seed: 6)
        playThrough(model)
        #expect(model.isFinished)
        #expect(model.scores.count == 12)
        #expect(model.total == DiceComboLogic.total(model.scores))
        #expect(model.total <= DiceComboLogic.maxTotal)
        #expect(!model.canRoll)
        #expect(!model.hasProgressToLose)
        #expect(model.recordResult?.record.bestPoints == model.total)
        #expect(model.recordResult?.record.metric == .points)
        #expect(log.record(gameID: DiceComboModel.gameID)?.plays == 1)
        #expect(!store.exists(for: DiceComboModel.gameID))
        #expect(feedback.notices(of: .success) == 1)
        model.roll()
        #expect(model.dice.isEmpty, "決着後は振れない")
    }

    @Test("新しいゲームで得点表が空に戻り、また 12 ターン遊べる")
    func newGameResets() {
        let model = DiceComboModel(services: makeServices(), seed: 7)
        playThrough(model)
        model.newGame()
        #expect(!model.isFinished && model.scores.isEmpty && model.turn == 1)
        #expect(model.recordResult == nil)
        playThrough(model)
        #expect(model.isFinished)
    }

    @Test("中断データから出目・キープ・振った回数・得点表を復元する")
    func resumesFromSnapshot() {
        let store = MemorySnapshotStore()
        let first = DiceComboModel(services: makeServices(store: store), seed: 8)
        first.roll()
        first.choose(.sixes)
        first.roll()
        first.toggleHold(2)
        first.roll()
        let second = DiceComboModel(services: makeServices(store: store), seed: 99)
        #expect(second.dice == first.dice)
        #expect(second.held == first.held)
        #expect(second.rollsUsed == 2)
        #expect(second.scores == first.scores)
        #expect(second.turn == 2)
    }

    @Test("壊れた中断データ・終わった局の中断データは捨てて新しく始める")
    func rejectsBrokenSnapshots() throws {
        let broken: [DiceComboSnapshot] = [
            DiceComboSnapshot(dice: [1, 2, 3], held: [false, false, false], rollsUsed: 1, scores: [:]),
            DiceComboSnapshot(dice: [1, 2, 3, 4, 9], held: Array(repeating: false, count: 5), rollsUsed: 1, scores: [:]),
            DiceComboSnapshot(dice: [], held: [], rollsUsed: 4, scores: [:]),
            DiceComboSnapshot(dice: [1, 1, 1, 1, 1], held: [], rollsUsed: 0, scores: [:]),
            DiceComboSnapshot(dice: [], held: [], rollsUsed: 0, scores: ["yacht": 50]),
            DiceComboSnapshot(dice: [], held: [], rollsUsed: 0, scores: ["threes": 13]),
            DiceComboSnapshot(dice: [], held: [], rollsUsed: 0, scores: Dictionary(
                uniqueKeysWithValues: DiceComboCategory.allCases.map { ($0.rawValue, 0) })),
        ]
        for snap in broken {
            let store = MemorySnapshotStore()
            try store.save(snap, for: DiceComboModel.gameID)
            let spy = SpyAnalyticsService()
            let model = DiceComboModel(services: makeServices(store: store, analytics: spy), seed: 1)
            #expect(model.scores.isEmpty && model.rollsUsed == 0, "\(snap) を復元してしまった")
            #expect(spy.starts == [DiceComboModel.gameID], "捨てたら新しいプレイとして数える")
        }
    }

    @Test("鍵が増えても読める（未知の鍵は無視し、旧データを壊さない）")
    func snapshotIgnoresUnknownKeys() throws {
        let json = #"{"dice":[2,2,5,5,5],"held":[true,true,false,false,false],"rollsUsed":1,"scores":{"choice":20},"future":1}"#
        let store = MemorySnapshotStore()
        store.inject(Data(json.utf8), for: DiceComboModel.gameID)
        let model = DiceComboModel(services: makeServices(store: store), seed: 1)
        #expect(model.dice == [2, 2, 5, 5, 5])
        #expect(model.scores == [.choice: 20])
        #expect(model.preview(.fullHouse) == 19)
    }

    @Test("ハブの「続きから」は 1 回でも振った局だけ（開いただけの局は手つかず）")
    func resumableOnlyAfterRolling() {
        let store = MemorySnapshotStore()
        let module = DiceComboModule()
        let model = DiceComboModel(services: makeServices(store: store), seed: 9)
        #expect(store.exists(for: DiceComboModel.gameID))
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(module.hasUntouchedSnapshot(in: store))
        model.roll()
        #expect(module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("解析: 開いて 1 プレイ、振ったら進行、12 役で 1 回だけ決着、新しいゲームで次のプレイ")
    func analyticsPerGame() {
        let spy = SpyAnalyticsService()
        let model = DiceComboModel(services: makeServices(analytics: spy), seed: 10)
        #expect(spy.starts == [DiceComboModel.gameID])
        #expect(spy.startLevels == [nil], "難易度を持たないので level は送らない")
        playThrough(model)
        #expect(spy.outcomes == [.win])
        model.newGame()
        #expect(spy.starts.count == 2)
        #expect(spy.ends.count == 1)
    }

    @Test("解析: 振ってから離れたら途中離脱ではなく休憩（中断データから戻れる）")
    func leavingAfterRollIsResumable() {
        let spy = SpyAnalyticsService()
        let services = makeServices(analytics: spy)
        let model = DiceComboModel(services: services, seed: 11)
        model.roll()
        services.gameDidLeave(gameID: DiceComboModel.gameID)
        #expect(spy.quits.isEmpty)
    }

    @Test("種が同じなら同じ出目になる（テストの再現性）")
    func seededIsDeterministic() {
        let a = DiceComboModel(services: makeServices(), seed: 123)
        let b = DiceComboModel(services: makeServices(), seed: 123)
        for _ in 0..<3 {
            a.roll()
            b.roll()
            #expect(a.dice == b.dice)
        }
    }

    @Test("25 点以上の役を入れたときだけ強い触覚（milestone）、それ未満は軽い触覚のまま（#2804）")
    func bigScoreCelebratesOnlyAtThreshold() {
        var big = false, small = false
        for seed in UInt64(1)...300 where !(big && small) {
            let feedback = SpyFeedbackService()
            let model = DiceComboModel(services: makeServices(feedback: feedback), seed: seed)
            model.roll()
            let points = model.preview(.choice) ?? 0
            feedback.reset()
            model.choose(.choice)
            if points >= DiceComboModel.bigScoreThreshold {
                big = true
                #expect(feedback.notices(of: .milestone) == 1)
                #expect(feedback.impacts.isEmpty)
            } else {
                small = true
                #expect(feedback.notices(of: .milestone) == 0)
                #expect(feedback.impacts == [.light])
            }
        }
        #expect(big && small, "両方の出目が探索範囲に出る")
    }
}
