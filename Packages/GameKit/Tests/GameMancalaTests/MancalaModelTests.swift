import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
import GameKitTestSupport
@testable import GameMancala

private func board(_ south: [Int], _ southStore: Int, _ north: [Int], _ northStore: Int) -> MancalaBoard {
    MancalaBoard(slots: south + [southStore] + north + [northStore])
}

@MainActor
private func makeServices() -> (GameServices, MemorySnapshotStore) {
    let store = MemorySnapshotStore()
    return (GameServices(snapshots: store, ads: NoopAdService()), store)
}

/// CPU の手番が続くあいだ（もう一度を含む）1 手ずつ進める。
@MainActor
private func playCPUTurn(_ model: MancalaModel) async {
    var guardCount = 0
    while !model.gameOver, model.isAITurn, guardCount < 40 {
        guardCount += 1
        await model.performAIMoveIfNeeded()
    }
}

@Suite("マンカラの Model")
@MainActor
struct MancalaModelTests {
    @Test("開くと初期配置で、あなたの先手・ふつうの強さ")
    func freshStart() {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        #expect(model.board == MancalaBoard())
        #expect(!model.isAITurn && !model.gameOver)
        #expect(model.aiLevel == CPUStrength.standard.rawValue)
        #expect(model.legalPits == [0, 1, 2, 3, 4, 5])
        #expect(!model.canUndo)
    }

    @Test("穴をタップすると種をまき、相手の番になる。空の穴は何も起きない")
    func tapSows() {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        model.tap(pit: 0)
        #expect(model.board.slots == [0, 5, 5, 5, 5, 4, 0, 4, 4, 4, 4, 4, 4, 0])
        #expect(model.isAITurn)
        #expect(model.lastMove?.pitSlot == 0 && model.lastMove?.landingSlot == 4)
        let before = model.board
        model.tap(pit: 1)   // CPU の番なので打てない
        #expect(model.board == before)
    }

    @Test("空の穴をタップしても盤は変わらない")
    func tapEmptyPit() {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        model.configureForTesting(board: board([0, 4, 4, 4, 4, 4], 4, [4, 4, 4, 4, 4, 4], 0))
        let before = model.board
        model.tap(pit: 0)
        #expect(model.board == before && !model.isAITurn)
    }

    @Test("最後の種がストアに入ると、もう一度あなたの番")
    func extraTurnKeepsHuman() {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        model.tap(pit: 2)
        #expect(!model.isAITurn)
        #expect(model.lastEvent == MancalaEvent(side: .south, extraTurn: true, captured: 0))
        #expect(model.humanStore == 1)
    }

    @Test("CPU は合法な穴だけを 1 手ずつまき、もう一度の間は CPU の番が続く")
    func cpuTurn() async {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 3)
        model.tap(pit: 0)
        #expect(model.isAITurn)
        await playCPUTurn(model)
        #expect(!model.isAITurn || model.gameOver)
        #expect(MancalaRules.isConsistent(model.board))
        #expect(model.cpuStore >= 0)
    }

    @Test("CPU の思考中に新規対局を始めても旧局面の手は入らない")
    func newGameDuringThinking() async throws {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 3)
        model.tap(pit: 0)
        let gate = TaskGate()
        model.thinkingGate = { await gate.wait() }
        let task = Task { await model.performAIMoveIfNeeded() }
        await gate.waitUntilArrived()
        model.thinkingGate = nil
        try #require(model.isThinking)
        model.newGame(humanFirst: true, aiLevel: 0)
        #expect(!model.isThinking, "新しい対局の CPU を起動できる")
        let serial = model.gameSerial
        gate.release()
        await task.value
        #expect(model.gameSerial == serial)
        #expect(model.board == MancalaBoard() && model.turnID == 0, "旧タスクは新しい盤を書き換えていない")
    }

    @Test("後手を選ぶと CPU から始まる")
    func cpuFirst() async {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 3)
        model.newGame(humanFirst: false, aiLevel: -1)
        #expect(model.isAITurn)
        await playCPUTurn(model)
        #expect(model.board != MancalaBoard())
        #expect(!model.isAITurn || model.gameOver)
    }

    @Test("待った: 自分の直前の 1 手を CPU の応手ごと戻す。無料は 1 回の印が立つ")
    func undoExchange() async {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 5)
        #expect(!model.canUndo, "まだ打っていない")
        model.tap(pit: 0)
        await playCPUTurn(model)
        #expect(!model.isAITurn && model.canUndo)
        let key = model.aiTurnKey
        model.undoLastExchange()
        #expect(model.board == MancalaBoard())
        #expect(!model.isAITurn && model.undoUsed)
        #expect(!model.canUndo)
        #expect(model.aiTurnKey != key)
    }

    @Test("広告の待ったは控えた局面のときだけ効く（#729）")
    func rewardedUndoGuard() async {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 5)
        model.tap(pit: 0)
        await playCPUTurn(model)
        let stale = model.aiTurnKey
        guard let pit = model.legalPits.first else { return }
        model.tap(pit: pit)
        await playCPUTurn(model)
        guard model.canUndo else { return }
        let b = model.board
        #expect(!model.undoLastExchange(forTurn: stale))
        #expect(model.board == b)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey))
        #expect(model.board != b)
    }

    @Test("片側が空になると決着し、勝ち・負け・引き分けが付く。投了は CPU の勝ち")
    func finishing() {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        // 最後の 1 個をストアへ入れると南の穴が空になり、北の残り 2 個は北のストアへ。
        model.configureForTesting(board: board([0, 0, 0, 0, 0, 1], 25, [1, 1, 0, 0, 0, 0], 20))
        model.tap(pit: 5)
        #expect(model.gameOver && model.winner == .south)
        #expect(model.reviewOutcome == .win)
        #expect(model.humanStore == 26 && model.cpuStore == 22)

        model.configureForTesting(board: board([0, 0, 0, 0, 0, 1], 23, [1, 1, 0, 0, 0, 0], 22))
        model.tap(pit: 5)
        #expect(model.gameOver && model.winner == nil && model.reviewOutcome == .draw)

        model.newGame()
        model.resign()
        #expect(model.gameOver && model.winner == .north && model.reviewOutcome == .loss)
        model.tap(pit: 0)
        #expect(model.board == MancalaBoard(), "決着後は打てない")
    }

    @Test("1 手打つまでは保存せず、打ったら保存し、決着で消える")
    func snapshotLifecycle() {
        let (services, store) = makeServices()
        let model = MancalaModel(services: services, cpuDelay: .zero, seed: 1)
        #expect(!store.exists(for: "mancala"), "開いただけの局は保存しない（#240）")
        model.tap(pit: 0)
        #expect(store.exists(for: "mancala"))
        model.newGame()
        #expect(!store.exists(for: "mancala"), "新規対局を始めた時点で前の対局の中断データは消える")
        model.tap(pit: 1)
        model.resign()
        #expect(!store.exists(for: "mancala"))
    }

    @Test("中断データから盤・手番・強さ・待った先・直前の手を復元する")
    func restore() async {
        let (services, _) = makeServices()
        let model = MancalaModel(services: services, cpuDelay: .zero, seed: 5)
        model.newGame(humanFirst: true, aiLevel: 2)
        model.tap(pit: 0)
        await playCPUTurn(model)
        let restored = MancalaModel(services: services, cpuDelay: .zero, seed: 5)
        #expect(restored.board == model.board)
        #expect(restored.currentSide == model.currentSide)
        #expect(restored.aiLevel == 2)
        #expect(restored.turnID == model.turnID)
        #expect(restored.canUndo == model.canUndo)
        #expect(restored.lastMove?.pitSlot == model.lastMove?.pitSlot)
        restored.undoLastExchange()
        #expect(restored.board == MancalaBoard())
    }

    @Test("壊れた中断データ（種が 48 個でない）は捨てて新規対局にする")
    func corruptedSnapshot() throws {
        let (services, store) = makeServices()
        let snap = MancalaSnapshot(slots: [9, 9, 9, 9, 9, 9, 0, 4, 4, 4, 4, 4, 4, 0], currentSide: 0,
                                   humanFirst: true, aiLevel: 1, turnID: 3, startedAt: Date(),
                                   undoUsed: nil, undoSlots: nil, lastPitSlot: nil, lastLandingSlot: nil)
        try store.save(snap, for: "mancala")
        let model = MancalaModel(services: services, cpuDelay: .zero, seed: 1)
        #expect(model.board == MancalaBoard() && model.turnID == 0)
        #expect(!store.exists(for: "mancala"))
    }

    @Test("新規対局は通し番号を進め、強さと手番を持ち替える")
    func newGameSettings() {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 1)
        let serial = model.gameSerial
        model.newGame(humanFirst: false, aiLevel: -1)
        #expect(model.gameSerial == serial + 1)
        #expect(model.aiLevel == -1 && !model.humanFirst && model.isAITurn)
    }

    @Test("CPU 同士の代わりに人間側も先頭の穴で打ち続けると、必ず決着し種は 48 個のまま", arguments: [-1, 0, 1])
    func fullGame(level: Int) async {
        let model = MancalaModel(services: nil, cpuDelay: .zero, seed: 11)
        model.newGame(humanFirst: level != 0, aiLevel: level)
        var guardCount = 0
        while !model.gameOver, guardCount < 400 {
            guardCount += 1
            if model.isAITurn {
                await model.performAIMoveIfNeeded()
            } else if let pit = model.legalPits.last {
                model.tap(pit: pit)
            }
            #expect(MancalaRules.isConsistent(model.board))
        }
        #expect(model.gameOver)
        #expect(model.humanStore + model.cpuStore == MancalaBoard.totalSeeds)
    }
}
