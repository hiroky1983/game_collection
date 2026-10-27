import Testing
import Foundation
import Core
import CoreEngine
@testable import GameHearts
import CoreTestSupport

// MARK: - 組み立て

@MainActor
private func makeModel(
    seed: UInt64? = 42,
    store: SnapshotStore = MemorySnapshotStore(),
    analytics: GameAnalytics? = nil
) -> HeartsModel {
    let services = GameServices(snapshots: store, ads: NoopAdService(), analytics: analytics)
    // テストでは CPU の間合い・巡を見せる時間を取らない（待たずに最後まで進める）。
    return HeartsModel(services: services, cpuDelay: .zero, trickPause: .zero, seed: seed)
}

/// 人間の番を「出せる札のうち ID がいちばん小さい札」で自動消化しながら、決着まで進める。
@MainActor
private func playToFinish(_ model: HeartsModel, maxSteps: Int = 5_000) async -> Bool {
    var steps = 0
    while model.phase != .result, steps < maxSteps {
        steps += 1
        switch model.phase {
        case .passing:
            for card in model.playerHand.prefix(3) { model.togglePass(card) }
            model.confirmPass()
        case .playing:
            await model.runCPUTurnsIfNeeded()
            if model.isPlayerTurn, let id = model.playableCardIDs.min(),
               let card = model.playerHand.first(where: { $0.id == id }) {
                model.toggleSelection(card)
                model.playSelected()
            }
        case .handResult:
            model.nextHand()
        case .idle, .result:
            return model.phase == .result
        }
    }
    return model.phase == .result
}

/// 手札・場・片付いた札を合わせた札の ID（常に 52 枚ちょうどのはず）。
@MainActor
private func allCardIDs(_ model: HeartsModel) -> [Int] {
    model.hands.flatMap { $0.map(\.id) } + model.currentTrick.map(\.card.id) + model.playedIDs
}

// MARK: - 進行

@Suite("ハーツの進行")
@MainActor
struct HeartsModelTests {
    @Test("対局を始めると 13 枚ずつ配られ、渡す札を選ぶ段から始まる。配っただけの局は保存しない")
    func startMatchDeals() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        #expect(model.phase == .idle)
        model.startMatch()
        #expect(model.phase == .passing)
        #expect(model.handNumber == 1)
        #expect(model.hands.allSatisfy { $0.count == 13 })
        #expect(Set(allCardIDs(model)) == Set(0..<52))
        #expect(model.playerHand == model.playerHand.sorted { $0.sortKey < $1.sortKey }, "手札はスート → 数字の順")
        #expect(!store.exists(for: HeartsModel.gameID), "配ったばかりの局は保存しない（#240）")
    }

    @Test("渡す札は 3 枚まで。3 枚そろうまで渡せない")
    func passSelectionLimit() {
        let model = makeModel()
        model.startMatch()
        let hand = model.playerHand
        model.togglePass(hand[0])
        model.togglePass(hand[1])
        #expect(!model.canConfirmPass)
        model.confirmPass()
        #expect(model.phase == .passing, "2 枚では渡せない")
        model.togglePass(hand[2])
        model.togglePass(hand[3])
        #expect(model.passSelection == Set(hand.prefix(3).map(\.id)), "4 枚目は選べない")
        model.togglePass(hand[0])
        #expect(model.passSelection.count == 2, "同じ札をもう一度タップで外せる")
    }

    @Test("3 枚を左（CPU1）へ渡し、右（CPU3）から 3 枚受け取る。クラブの 2 を持つ人から始まり、ここで保存される")
    func confirmPassExchanges() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startMatch()
        let passed = Array(model.playerHand.prefix(3))
        for card in passed { model.togglePass(card) }
        model.confirmPass()
        #expect(model.phase == .playing)
        #expect(model.hands.allSatisfy { $0.count == 13 })
        #expect(Set(allCardIDs(model)) == Set(0..<52))
        #expect(passed.allSatisfy(model.hands[1].contains), "渡した 3 枚は CPU1 の手札にある")
        #expect(passed.allSatisfy { !model.playerHand.contains($0) })
        #expect(model.receivedIDs.count == 3)
        #expect(model.receivedIDs.isSubset(of: Set(model.playerHand.map(\.id))))
        #expect(model.hands[model.currentPlayer].contains(.twoOfClubs), "クラブの 2 を持つ人の番から")
        #expect(store.exists(for: HeartsModel.gameID))
    }

    @Test("対局を最後まで進めると、誰かが 50 点に届いた手で決着し、中断データは消える（10 局）")
    func playsToResult() async {
        for seed in UInt64(1)...10 {
            let store = MemorySnapshotStore()
            let model = makeModel(seed: seed, store: store)
            model.startMatch(aiLevel: CPUStrength.allCases[Int(seed) % 4].rawValue)
            let finished = await playToFinish(model)
            #expect(finished, "種 \(seed) で決着しなかった")
            #expect(HeartsRules.isMatchOver(totals: model.totals))
            #expect(model.totals.reduce(0, +) == HeartsRules.pointsPerHand * model.handNumber, "1 手ごとに 26 点ずつ増える")
            #expect(model.ranking == HeartsRules.ranking(totals: model.totals))
            #expect(model.playerPlace == HeartsRules.place(of: 0, totals: model.totals))
            #expect(!store.exists(for: HeartsModel.gameID), "決着したら中断データは消す")
            #expect(model.handNumber >= 2, "50 点には 1 手では届かない（1 手は 26 点）")
        }
    }

    @Test("出だしのスートがあるのに別のスートは出せない")
    func rejectsIllegalPlay() {
        let model = makeModel()
        model.configureForTesting(
            hands: [[c(.club, 9), c(.diamond, 4)], [c(.club, 3), c(.club, 7)], [c(.club, 5)], [c(.club, 4)]],
            trick: [p(2, c(.diamond, 5)), p(3, c(.diamond, 10))], heartsBroken: true, trickNumber: 11
        )
        // 手札・場・片付いた札で 52 枚がそろう構成にしてある（configureForTesting が残りを片付いた扱いにする）。
        model.toggleSelection(c(.club, 9))
        #expect(!model.canPlaySelection)
        model.playSelected()
        #expect(model.playerHand.count == 2, "出せない札は出ない")
        model.toggleSelection(c(.club, 9))   // 選択を外す
        model.toggleSelection(c(.diamond, 4))
        #expect(model.canPlaySelection)
        model.playSelected()
        #expect(model.currentTrick.count == 3)
        #expect(model.currentPlayer == 1)
    }

    @Test("最後の巡が片付くと手が締まり、点の一覧の段になる。次の手は 2 手目で、渡す前でも保存される")
    func handEndsAndNextHand() async {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.configureForTesting(
            hands: [[c(.heart, 14)], [c(.heart, 2)], [c(.spade, 12)], [c(.club, 3)]],
            heartsBroken: true, trickNumber: 12, takenPoints: [3, 2, 0, 7], totals: [10, 4, 20, 6]
        )
        model.toggleSelection(c(.heart, 14))
        model.playSelected()
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .handResult)
        // 自分のハートの A が勝ち、ハート 2 枚 + スペードの Q = 15 点を取る。
        #expect(model.takenPoints == [18, 2, 0, 7])
        #expect(model.totals == [28, 6, 20, 13])
        #expect(model.lastTrickWinner == 0)
        #expect(store.exists(for: HeartsModel.gameID), "手の合間も保存する")
        model.nextHand()
        #expect(model.phase == .passing)
        #expect(model.handNumber == 2)
        #expect(model.takenPoints == [0, 0, 0, 0])
        #expect(model.totals == [28, 6, 20, 13], "合計は持ち越す")
        #expect(store.exists(for: HeartsModel.gameID), "2 手目以降は渡す前でも保存する")
    }

    @Test("ハートが場に出たらハートを先頭に出せるようになる")
    func heartsBreak() async {
        let model = makeModel()
        model.configureForTesting(
            hands: [[c(.club, 9), c(.heart, 5), c(.diamond, 8)], [c(.heart, 3), c(.spade, 4), c(.spade, 6)],
                    [c(.diamond, 4), c(.diamond, 10)], [c(.diamond, 7), c(.diamond, 11)]],
            trick: [p(2, c(.club, 5)), p(3, c(.club, 6))], currentPlayer: 0, heartsBroken: false, trickNumber: 10
        )
        model.toggleSelection(c(.club, 9))
        model.playSelected()
        #expect(!model.heartsBroken)
        // CPU1（ふつう）はクラブが無いので、点の札（ハートの 3）を押し付ける。取るのは自分のクラブの 9。
        await model.runCPUTurnsIfNeeded()
        #expect(model.lastTrickWinner == 0)
        #expect(model.heartsBroken)
        #expect(model.takenPoints[0] == 1)
        #expect(model.isPlayerTurn)
        #expect(model.playableCardIDs == [c(.heart, 5).id, c(.diamond, 8).id], "割れたあとはハートも先頭に出せる")
    }

    @Test("合計がいちばん少なければ勝ち（同点の 1 位も勝ち）。記録は勝敗で残す")
    func outcomeAndRecord() async {
        let defaults = UserDefaults(suiteName: "HeartsModelTests-\(UUID().uuidString)")!
        let playLog = PlayLog(defaults: defaults)
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), playLog: playLog)
        let model = HeartsModel(services: services, cpuDelay: .zero, trickPause: .zero, seed: 5)
        model.configureForTesting(
            hands: [[c(.club, 2)], [c(.club, 3)], [c(.club, 4)], [c(.club, 14)]],
            heartsBroken: true, trickNumber: 12, takenPoints: [5, 13, 8, 0], totals: [20, 40, 30, 20]
        )
        model.toggleSelection(c(.club, 2))
        model.playSelected()
        await model.runCPUTurnsIfNeeded()
        #expect(model.phase == .result)
        #expect(model.totals == [25, 53, 38, 20])
        #expect(model.playerPlace == 1)
        #expect(model.reviewOutcome == .loss)
        #expect(model.recordResult != nil)

        let tie = HeartsModel(services: services, cpuDelay: .zero, trickPause: .zero, seed: 6)
        tie.configureForTesting(
            hands: [[c(.club, 2)], [c(.club, 3)], [c(.club, 4)], [c(.club, 14)]],
            heartsBroken: true, trickNumber: 12, takenPoints: [5, 13, 8, 0], totals: [15, 40, 30, 20]
        )
        tie.toggleSelection(c(.club, 2))
        tie.playSelected()
        await tie.runCPUTurnsIfNeeded()
        #expect(tie.totals == [20, 53, 38, 20])
        #expect(tie.playerPlace == 0, "同点の 1 位")
        #expect(tie.reviewOutcome == .win)
    }
}

// MARK: - 中断データ

@Suite("ハーツの中断データ")
@MainActor
struct HeartsSnapshotTests {
    @Test("途中の局を保存し、作り直したモデルが同じ局面から再開できる")
    func restoresMidHand() async {
        let store = MemorySnapshotStore()
        let model = makeModel(seed: 9, store: store)
        model.startMatch(aiLevel: CPUStrength.hard.rawValue)
        for card in model.playerHand.prefix(3) { model.togglePass(card) }
        model.confirmPass()
        await model.runCPUTurnsIfNeeded()
        if let id = model.playableCardIDs.min(), let card = model.playerHand.first(where: { $0.id == id }) {
            model.toggleSelection(card)
            model.playSelected()
        }
        let restored = makeModel(seed: 1, store: store)
        #expect(restored.phase == model.phase)
        #expect(restored.hands == model.hands)
        #expect(restored.currentTrick == model.currentTrick)
        #expect(restored.currentPlayer == model.currentPlayer)
        #expect(restored.totals == model.totals)
        #expect(restored.takenPoints == model.takenPoints)
        #expect(restored.playedIDs == model.playedIDs)
        #expect(restored.aiLevel == CPUStrength.hard.rawValue)
        #expect(restored.receivedIDs == model.receivedIDs)
        // 復元した局は最後まで進められる。
        #expect(await playToFinish(restored))
    }

    @Test("札の枚数が合わない壊れた中断データは読まない")
    func rejectsBrokenSnapshot() throws {
        let store = MemorySnapshotStore()
        let broken = HeartsSnapshot(
            phase: .playing, hands: [[c(.club, 2)], [], [], []], currentTrick: [], currentPlayer: 0,
            heartsBroken: false, trickNumber: 0, takenPoints: [0, 0, 0, 0], totals: [0, 0, 0, 0], handNumber: 1,
            playedIDs: [], lastTrick: [], lastTrickWinner: nil, receivedIDs: [], aiLevel: 1, turnSerial: 0, hintsUsed: nil
        )
        try store.save(broken, for: HeartsModel.gameID)
        let model = makeModel(store: store)
        #expect(model.phase == .idle)
        #expect(!HeartsModel.isConsistent(broken))
    }

    @Test("新しい対局を始めると前の対局の中断データは消える")
    func newMatchClearsSnapshot() {
        let store = MemorySnapshotStore()
        let model = makeModel(store: store)
        model.startMatch()
        for card in model.playerHand.prefix(3) { model.togglePass(card) }
        model.confirmPass()
        #expect(store.exists(for: HeartsModel.gameID))
        model.startMatch()
        #expect(!store.exists(for: HeartsModel.gameID))
    }
}

// MARK: - 解析

@Suite("ハーツの解析イベント")
@MainActor
struct HeartsAnalyticsTests {
    @Test("1 対局で game_start と game_end が 1 組。game_start に CPU の強さが載る")
    func onePairPerMatch() async {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: [HeartsModel.gameID])
        let model = makeModel(seed: 3, analytics: analytics)
        #expect(spy.events.isEmpty, "画面を開いただけでは数えない")
        model.startMatch(aiLevel: CPUStrength.hard.rawValue)
        #expect(await playToFinish(model))
        #expect(spy.starts == [HeartsModel.gameID])
        #expect(spy.startLevels == [CPUStrength.hard.analyticsLevel])
        #expect(spy.ends.count == 1)
        #expect(spy.ends.first?.gameID == HeartsModel.gameID)
    }

    @Test("記録は「ふつう」だけ区分なし、ほかの強さは強さ別の区分に分かれる（#2716）")
    func recordVariantPerStrength() {
        let model = makeModel()
        model.startMatch()
        #expect(model.recordScore.variant == nil)
        for strength in CPUStrength.allCases where strength != .standard {
            model.startMatch(aiLevel: strength.rawValue)
            #expect(model.recordScore.variant == strength.recordVariantKey)
            #expect(model.recordScore.variantLabel != nil)
            #expect(model.recordScore.variantLabel == RecordVariantLabels.label(
                recordKey: "hearts#\(strength.recordVariantKey)", language: .japanese))
        }
    }
}

// MARK: - CPU 進行のキャンセル

@Suite("ハーツの CPU 進行のキャンセル")
@MainActor
struct HeartsCancelTests {
    /// CPU1 の番から始まる 1 巡（自分はまだ出していない）。
    /// キャンセルの検証では間合いを 1 時間にする。CI では並列のテストで MainActor が数十秒ふさがることがあり、
    /// 60 秒だとキャンセルより先に sleep が明けて CPU が正当に指してしまう（PR #2266 の初回 CI）。
    private func cpuTurnModel(cpuDelay: Duration) -> HeartsModel {
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService())
        let model = HeartsModel(services: services, cpuDelay: cpuDelay, trickPause: cpuDelay, seed: 42)
        model.configureForTesting(
            hands: [[c(.club, 9), c(.heart, 5)], [c(.club, 3), c(.spade, 4)], [c(.club, 2), c(.diamond, 4)], [c(.club, 10), c(.diamond, 7)]],
            currentPlayer: 1, heartsBroken: true, trickNumber: 11
        )
        return model
    }

    /// `HeartsView` は `.task { await model.runCPUTurnsIfNeeded() }` で CPU を回しており、画面を離れると
    /// キャンセルされる。ループが `Task.isCancelled` を見ていないと残りの手番が遅延ゼロで走り抜ける（#287・#1621）。
    @Test("キャンセルされたら遅延を飛ばして打ち続けない")
    func cancelledLoopDoesNotFastForward() async {
        let model = cpuTurnModel(cpuDelay: .seconds(3_600))
        let handsBefore = model.hands
        let task = Task { await model.runCPUTurnsIfNeeded() }
        task.cancel()
        await task.value
        #expect(model.currentPlayer == 1, "キャンセル済みのタスクが cpuDelay を無視して手番を進めた")
        #expect(model.hands == handsBefore)
        #expect(model.currentTrick.isEmpty)
    }

    /// sleep に入ってからキャンセルされた場合も、sleep の直後の判定で止まる（#817 の変異で赤くなる側）。
    @Test("sleep に入った後にキャンセルされても手番を進めない")
    func cancelledDuringSleepDoesNotAdvance() async {
        let model = cpuTurnModel(cpuDelay: .seconds(3_600))
        let task = Task { await model.runCPUTurnsIfNeeded() }
        var gate = 0
        while !model.isRunningCPUTurns, gate < 1_000 {
            gate += 1
            await Task.yield()
        }
        try? #require(model.isRunningCPUTurns, "先行タスクが開始しなかった")
        // 本体を sleep まで走らせてからキャンセルする。
        await Task { @MainActor in }.value
        task.cancel()
        await task.value
        #expect(model.currentPlayer == 1, "sleep 後のキャンセル判定を通らずに手番を進めた")
        #expect(model.currentTrick.isEmpty)
    }

    /// 先行タスクが走者を握ったまま suspend している間に新タスクが走ると、走者不在で手番が止まる（#311 と同じレース）。
    @Test("差し替え後の新タスクが先行タスクの終了を待って引き継ぐ（走者不在で止まらない）")
    func replacementTaskTakesOver() async {
        let model = cpuTurnModel(cpuDelay: .milliseconds(20))
        let taskA = Task { await model.runCPUTurnsIfNeeded() }
        var gate = 0
        while !model.isRunningCPUTurns, gate < 1_000 {
            gate += 1
            await Task.yield()
        }
        let taskB = Task { await model.runCPUTurnsIfNeeded() }
        taskA.cancel()
        await taskA.value
        await taskB.value
        #expect(model.isPlayerTurn || model.phase != .playing, "走者不在で CPU の手番が止まった")
    }
}
