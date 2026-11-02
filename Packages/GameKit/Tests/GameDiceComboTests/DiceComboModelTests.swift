import Testing
import Foundation
import Core
import CoreTestSupport
import GameKitTestSupport
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
/// 0 点の役が残るとコンティニューの提案で止まる（#3257）ので、断って決着を確定させる。
@MainActor
private func playThrough(_ model: DiceComboModel) {
    while !model.isFinished {
        model.roll()
        let open = DiceComboCategory.allCases.first { model.canChoose($0) }!
        model.choose(open)
    }
    model.declineContinue()
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

    @Test("1 ターンに振れるのは 3 回まで。3 回振り切ったあとも、広告で振れるあいだはキープできる")
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
        #expect(model.rollsUsed == 3 && !model.canRoll && model.canHold, "広告の振り直しが残るあいだはキープできる")
        let dice = model.dice
        model.roll()
        #expect(model.rollsUsed == 3 && model.dice == dice, "4 回目は振れない")
        #expect(feedback.notices(of: .warning) == 1)
        model.toggleHold(0)
        #expect(model.held[0] == true)
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

    // MARK: - 広告で振り直す（#3257）

    private func rollThrice(_ model: DiceComboModel) {
        for _ in 0..<DiceComboLogic.maxRolls {
            model.roll()
            model.settleRoll()
        }
    }

    @Test("広告の振り直しは通常の 3 回を振り切ったあとにだけ出る。1 ターン最大 3 回で、6 回振れる")
    func adRerollOnlyAfterRegularRolls() {
        let model = DiceComboModel(services: makeServices(), seed: 21)
        let game = model.gameSerial, turn = model.turnSerial
        #expect(!model.canAdReroll)
        #expect(!model.grantReroll(forGame: game, turn: turn), "1 回も振っていない")
        model.roll()
        model.settleRoll()
        #expect(!model.canAdReroll && !model.grantReroll(forGame: game, turn: turn), "通常の回数が残っている")
        model.roll(); model.settleRoll(); model.roll(); model.settleRoll()
        #expect(model.rollsUsed == DiceComboLogic.maxRolls && !model.canRoll)
        #expect(model.canAdReroll && model.adRerollsRemaining == DiceComboModel.maxAdRerolls)
        for n in 1...DiceComboModel.maxAdRerolls {
            #expect(model.grantReroll(forGame: game, turn: turn))
            model.settleRoll()
            #expect(model.adRollsUsed == n && model.rollsUsed == DiceComboLogic.maxRolls)
        }
        #expect(!model.canAdReroll && model.adRerollsRemaining == 0)
        #expect(!model.grantReroll(forGame: game, turn: turn), "4 回目は振れない")
        #expect(model.canChoose(.choice), "振り終えたら役を選べる")
    }

    @Test("広告の振り直しでもキープが効く。最後の 1 回を振ったあとはキープを切り替えられない")
    func adRerollHonorsHold() {
        let model = DiceComboModel(services: makeServices(), seed: 22)
        rollThrice(model)
        #expect(model.canHold, "広告で振れるうちはキープできる")
        model.toggleHold(0); model.toggleHold(2)
        let keep = [model.dice[0], model.dice[2]]
        #expect(model.grantReroll(forGame: model.gameSerial, turn: model.turnSerial))
        model.settleRoll()
        #expect([model.dice[0], model.dice[2]] == keep)
        for _ in 1..<DiceComboModel.maxAdRerolls {
            #expect(model.grantReroll(forGame: model.gameSerial, turn: model.turnSerial))
            model.settleRoll()
        }
        #expect(!model.canHold)
    }

    @Test("役を選ぶと広告の振り直しは 3 に戻る。広告のロード中にターンや局が変わったら乗せない")
    func adRerollResetsPerTurnAndIgnoresStale() {
        let model = DiceComboModel(services: makeServices(), seed: 23)
        let game = model.gameSerial, turn = model.turnSerial
        rollThrice(model)
        #expect(model.grantReroll(forGame: game, turn: turn))
        model.settleRoll()
        #expect(model.adRollsUsed == 1)
        model.choose(.choice)
        #expect(model.adRollsUsed == 0 && model.turnSerial != turn)
        rollThrice(model)
        #expect(model.adRerollsRemaining == DiceComboModel.maxAdRerolls)
        #expect(!model.grantReroll(forGame: game, turn: turn), "前のターンの広告は乗せない")
        let turn2 = model.turnSerial
        model.newGame()
        rollThrice(model)
        #expect(!model.grantReroll(forGame: game, turn: turn2), "前の局の広告は乗せない")
    }

    @Test("広告で振った回数は中断から復元される。旧データ（戻す用の鍵つき）は読み捨てて読める")
    func adRollsSurviveResumeAndOldKeysAreDropped() throws {
        let store = MemorySnapshotStore()
        let model = DiceComboModel(services: makeServices(store: store), seed: 24)
        rollThrice(model)
        _ = model.grantReroll(forGame: model.gameSerial, turn: model.turnSerial)
        model.settleRoll()
        let resumed = DiceComboModel(services: makeServices(store: store), seed: 24)
        #expect(resumed.adRollsUsed == 1 && resumed.adRerollsRemaining == 2)
        #expect(resumed.dice == model.dice)

        let json = #"{"dice":[],"held":[],"rollsUsed":0,"scores":{"choice":20},"undosRemaining":2,"lastChoice":{"category":"ones","dice":[1,2,3,4,5],"held":[false,false,false,false,false],"rollsUsed":1}}"#
        let snap = try JSONDecoder().decode(DiceComboSnapshot.self, from: Data(json.utf8))
        let restored = DiceComboModel.restore(snap)
        #expect(restored?.scores == [.choice: 20] && restored?.adRollsUsed == 0 && restored?.continueUsed == false)

        let corrupt = #"{"dice":[],"held":[],"rollsUsed":0,"scores":{"choice":20},"adRollsUsed":"x","continueUsed":3}"#
        let snap2 = try JSONDecoder().decode(DiceComboSnapshot.self, from: Data(corrupt.utf8))
        #expect(snap2.adRollsUsed == nil && snap2.continueUsed == nil)
        let outOfRange = DiceComboSnapshot(dice: [1, 2, 3, 4, 5], held: Array(repeating: false, count: 5),
                                           rollsUsed: 3, scores: [:], adRollsUsed: 99)
        #expect(DiceComboModel.restore(outOfRange)?.adRollsUsed == DiceComboModel.maxAdRerolls)
        let early = DiceComboSnapshot(dice: [1, 2, 3, 4, 5], held: Array(repeating: false, count: 5),
                                      rollsUsed: 1, scores: [:], adRollsUsed: 2)
        #expect(DiceComboModel.restore(early)?.adRollsUsed == 0, "通常の回数が残っているなら広告の回数は無い")
    }

    @Test("役選びを戻す機能は無い")
    func noUndoSurface() throws {
        let code = try SourceScan.moduleSources("GameDiceCombo")
        #expect(!code.contains("undoChoice") && !code.contains("grantUndos") && !code.contains("DiceComboUndoBudget"))
    }

    // MARK: - コンティニュー（#3257）

    /// 0 点でない、入りうる点（上段は目 1 個ぶん）。
    private static func nonZero(_ category: DiceComboCategory) -> Int {
        switch category {
        case .choice, .fourDice, .fullHouse: return 20
        case .smallStraight: return 15
        case .bigStraight: return 30
        case .fiveDice: return 50
        default: return category.face ?? 1
        }
    }

    /// 11 役が埋まっていて、`open` だけが空いた局。`zero` の役は 0 点で埋めてある。
    private func nearlyDoneStore(open: DiceComboCategory, zero: [DiceComboCategory]) -> MemorySnapshotStore {
        var scores: [String: Int] = [:]
        for category in DiceComboCategory.allCases where category != open {
            scores[category.rawValue] = zero.contains(category) ? 0 : Self.nonZero(category)
        }
        let store = MemorySnapshotStore()
        try? store.save(DiceComboSnapshot(dice: [], held: [], rollsUsed: 0, scores: scores), for: DiceComboModel.gameID)
        return store
    }

    private func finishLastTurn(_ model: DiceComboModel, _ category: DiceComboCategory) {
        model.roll()
        model.settleRoll()
        model.choose(category)
    }

    @Test("0 点の役があって 12 役が埋まったら、記録を確定せずコンティニューを提案する")
    func finishWithZeroOffersContinue() {
        let log = makeLog("offer")
        let spy = SpyAnalyticsService()
        let model = DiceComboModel(services: makeServices(store: nearlyDoneStore(open: .choice, zero: [.fourDice, .fiveDice]),
                                                          log: log, analytics: spy), seed: 31)
        finishLastTurn(model, .choice)
        #expect(model.isFinished && model.isOfferingContinue)
        #expect(model.continueCandidates == [.fourDice, .fiveDice])
        #expect(model.recordResult == nil)
        #expect(log.record(gameID: DiceComboModel.gameID) == nil, "提案中は記録しない")
        #expect(!spy.events.contains { $0.name == "game_end" })
        #expect(!model.canRoll && !model.canAdReroll)
    }

    @Test("断ると、その場で記録を 1 回だけ確定する")
    func declineCommitsOnce() {
        let log = makeLog("decline")
        let store = nearlyDoneStore(open: .choice, zero: [.fourDice])
        let model = DiceComboModel(services: makeServices(store: store, log: log), seed: 32)
        finishLastTurn(model, .choice)
        model.declineContinue()
        #expect(!model.isOfferingContinue && model.isFinished && model.recordResult != nil)
        #expect(log.record(gameID: DiceComboModel.gameID)?.plays == 1)
        model.declineContinue()
        #expect(log.record(gameID: DiceComboModel.gameID)?.plays == 1, "二重に数えない")
        #expect(store.load(DiceComboSnapshot.self, for: DiceComboModel.gameID) == nil)
    }

    @Test("0 点の役が無ければ提案せず、そのまま確定する")
    func noZeroNoOffer() {
        let log = makeLog("nozero")
        let model = DiceComboModel(services: makeServices(store: nearlyDoneStore(open: .choice, zero: []), log: log), seed: 33)
        finishLastTurn(model, .choice)
        #expect(model.isFinished && !model.isOfferingContinue && model.recordResult != nil)
        #expect(log.record(gameID: DiceComboModel.gameID)?.plays == 1)
    }

    @Test("やり直すと、その役だけが開いた 3 回振れる番に戻り、合計を出し直す。広告の振り直しも使え、2 回目の提案は無い")
    func continueRedoesOneCategory() {
        let log = makeLog("redo")
        let model = DiceComboModel(services: makeServices(store: nearlyDoneStore(open: .choice, zero: [.fourDice, .fiveDice]), log: log),
                                   seed: 34)
        let game = model.gameSerial
        finishLastTurn(model, .choice)
        let before = model.total
        #expect(!model.grantContinue(forGame: game, category: .ones), "0 点でない役はやり直せない")
        #expect(!model.grantContinue(forGame: game + 1, category: .fourDice), "前の局の広告は乗せない")
        #expect(model.grantContinue(forGame: game, category: .fourDice))
        #expect(!model.isFinished && !model.isOfferingContinue && model.continueUsed)
        #expect(model.scores[.fourDice] == nil && model.scores[.fiveDice] == 0)
        #expect(model.rollsUsed == 0 && model.adRollsUsed == 0 && model.total <= before)
        rollThrice(model)
        #expect(model.grantReroll(forGame: game, turn: model.turnSerial), "やり直しの番でも広告の振り直しは使える")
        model.settleRoll()
        #expect(model.canChoose(.fourDice) && !model.canChoose(.fiveDice) && !model.canChoose(.ones))
        model.choose(.fourDice)
        #expect(model.isFinished && !model.isOfferingContinue, "1 局 1 回まで。fiveDice が 0 でも再提案しない")
        #expect(model.recordResult != nil)
        #expect(log.record(gameID: DiceComboModel.gameID)?.plays == 1)
        #expect(!model.grantContinue(forGame: game, category: .fiveDice))
    }

    @Test("提案中に新しいゲームを始めると、断ったのと同じに確定してから始まる。使用済みは新しい局で戻る")
    func newGameDuringOfferCommits() {
        let log = makeLog("newgame")
        let model = DiceComboModel(services: makeServices(store: nearlyDoneStore(open: .choice, zero: [.fourDice]), log: log), seed: 35)
        let game = model.gameSerial
        finishLastTurn(model, .choice)
        model.newGame()
        #expect(log.record(gameID: DiceComboModel.gameID)?.plays == 1)
        #expect(!model.isFinished && !model.isOfferingContinue && !model.continueUsed && model.scores.isEmpty)
        #expect(!model.grantContinue(forGame: game, category: .fourDice))
    }

    @Test("提案中に中断しても、再開すると提案から続く。やり直しの番も使用済みのまま復元される")
    func offerAndRedoSurviveResume() {
        let store = nearlyDoneStore(open: .choice, zero: [.fourDice])
        let model = DiceComboModel(services: makeServices(store: store), seed: 36)
        finishLastTurn(model, .choice)
        let resumed = DiceComboModel(services: makeServices(store: store), seed: 36)
        #expect(resumed.isFinished && resumed.isOfferingContinue && resumed.continueCandidates == [.fourDice])
        #expect(resumed.grantContinue(forGame: resumed.gameSerial, category: .fourDice))
        let again = DiceComboModel(services: makeServices(store: store), seed: 36)
        #expect(!again.isFinished && again.continueUsed && again.scores[.fourDice] == nil)
    }

    @Test("埋まりきった中断データは、提案できる局（0 点あり・未使用）以外は読まない")
    func completeSnapshotRestoreRules() {
        var scores: [String: Int] = [:]
        for category in DiceComboCategory.allCases { scores[category.rawValue] = Self.nonZero(category) }
        #expect(DiceComboModel.restore(DiceComboSnapshot(dice: [], held: [], rollsUsed: 0, scores: scores)) == nil, "0 点が無い")
        scores["fourDice"] = 0
        #expect(DiceComboModel.restore(DiceComboSnapshot(dice: [], held: [], rollsUsed: 0, scores: scores)) != nil, "0 点あり・未使用")
        #expect(DiceComboModel.restore(DiceComboSnapshot(dice: [], held: [], rollsUsed: 0, scores: scores, continueUsed: true)) == nil)
    }
}
