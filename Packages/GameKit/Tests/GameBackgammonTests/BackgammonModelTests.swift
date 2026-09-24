import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
import GameKitTestSupport
@testable import GameBackgammon

private func board(_ white: [Int: Int], _ black: [Int: Int], bar: [Int] = [0, 0], off: [Int] = [0, 0]) -> BackgammonBoard {
    var p = Array(repeating: 0, count: 24)
    for (i, n) in white { p[i] = n }
    for (i, n) in black { p[i] = -n }
    return BackgammonBoard(points: p, bar: bar, off: off)
}

@MainActor
private func makeServices() -> (GameServices, MemorySnapshotStore) {
    let store = MemorySnapshotStore()
    return (GameServices(snapshots: store, ads: NoopAdService()), store)
}

/// 人間の手番を 1 つ、合法手の先頭で消化する。
@MainActor
private func playHumanTurn(_ model: BackgammonModel) {
    var guardCount = 0
    while !model.gameOver, !model.isAITurn, guardCount < 8 {
        guardCount += 1
        if model.mustPass { model.confirmPass(); break }
        guard let move = model.legalMoves.first else { break }
        model.tap(move.from)
        model.tap(move.to)
    }
}

@MainActor
private func playCPUTurn(_ model: BackgammonModel) async {
    var guardCount = 0
    while !model.gameOver, model.isAITurn, guardCount < 8 {
        guardCount += 1
        await model.performAIMoveIfNeeded()
    }
}

@Suite("バックギャモンの Model")
@MainActor
struct BackgammonModelTests {
    @Test("開くとオープニングロールが済み、大きい目の側から始まる")
    func openingRoll() {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 1)
        let roll = try! #require(model.openingRoll)
        #expect(roll.human != roll.cpu)
        #expect(model.isAITurn == (roll.cpu > roll.human))
        #expect(Set(model.dice) == Set([roll.human, roll.cpu]))
        #expect(model.remainingDice == model.dice)
        #expect(model.turnID == 1)
    }

    @Test("駒 → 行き先の順にタップすると動き、目が減る")
    func tapMoves() {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 1)
        model.configureForTesting(board: BackgammonBoard(), roll: (3, 1))
        #expect(!model.isAITurn)
        #expect(model.movableSources.contains(7))
        model.tap(7)
        #expect(model.selectedPoint == 7)
        #expect(model.destinations.map(\.to).contains(4))
        model.tap(4)
        #expect(model.selectedPoint == nil)
        #expect(model.board.points[4] == 1 && model.board.points[7] == 2)
        #expect(model.remainingDice == [1])
        #expect(!model.isAITurn, "まだ 1 が残っている")
        model.tap(5); model.tap(4)
        #expect(model.board.points[4] == 2)
        #expect(model.isAITurn, "目を使い切ったら CPU の番")
        #expect(!model.dice.isEmpty, "CPU の目は自動で振られている")
    }

    @Test("動かせない駒・行けない場所をタップしても何も起きない。同じ駒をもう一度タップすると選び直せる")
    func invalidTaps() {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 1)
        model.configureForTesting(board: BackgammonBoard(), roll: (3, 1))
        let before = model.board
        model.tap(0)   // 黒の駒
        #expect(model.selectedPoint == nil && model.board == before)
        model.tap(7)
        model.tap(0)   // 黒 2 個で止まれない
        #expect(model.selectedPoint == 7 && model.board == before)
        model.tap(7)
        #expect(model.selectedPoint == nil)
    }

    @Test("やり直しは振った直後へ戻し、目を使う前は押せない")
    func restartTurn() {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 1)
        model.configureForTesting(board: BackgammonBoard(), roll: (3, 1))
        #expect(!model.canRestartTurn)
        model.tap(7); model.tap(4)
        #expect(model.canRestartTurn)
        model.restartTurn()
        #expect(model.board == BackgammonBoard())
        #expect(model.remainingDice == [3, 1])
        #expect(!model.canRestartTurn)
    }

    @Test("動かせる手が無ければ mustPass になり、確認で相手の番へ")
    func passWhenBlocked() {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 1)
        // 白 1 個がバー。黒が 19〜24 を閉じている。
        let b = board([12: 4, 7: 3, 5: 5, 4: 2], [18: 3, 19: 3, 20: 3, 21: 2, 22: 2, 23: 2], bar: [1, 0])
        model.configureForTesting(board: b, roll: (6, 1))
        #expect(model.mustPass)
        #expect(model.legalMoves.isEmpty)
        model.confirmPass()
        #expect(!model.mustPass && model.isAITurn)
    }

    @Test("CPU は withAITurnGuard で 1 手ずつ進め、目を使い切ると人間の番に戻る")
    func cpuTurn() async {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 3)
        model.configureForTesting(board: BackgammonBoard(), side: .black, roll: (6, 5))
        #expect(model.isAITurn)
        let before = model.board
        await model.performAIMoveIfNeeded()
        #expect(model.board != before)
        #expect(model.remainingDice.count == 1)
        await model.performAIMoveIfNeeded()
        #expect(!model.isAITurn, "2 個の目を使い切って人間の番")
        #expect(BackgammonRules.isConsistent(model.board))
        #expect(model.board.pipCount(.black) == 167 - 11)
    }

    @Test("CPU の思考中に新規対局を始めても旧局面の手は入らない")
    func newGameDuringThinking() async throws {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 3)
        model.configureForTesting(board: BackgammonBoard(), side: .black, roll: (6, 5))
        let gate = TaskGate()
        model.thinkingGate = { await gate.wait() }
        let task = Task { await model.performAIMoveIfNeeded() }
        await gate.waitUntilArrived()
        model.thinkingGate = nil
        try #require(model.isThinking)
        model.newGame(aiLevel: 0)
        #expect(!model.isThinking, "新しい対局の CPU を起動できる")
        let serial = model.gameSerial
        let boardAfterNewGame = model.board
        let turnAfterNewGame = model.turnID
        gate.release()
        await task.value
        #expect(model.gameSerial == serial)
        // 旧タスクは何も書き換えていない（新規対局の初期盤面・手数のまま）。
        #expect(model.board == boardAfterNewGame && model.turnID == turnAfterNewGame)
    }

    @Test("待った: 自分の直前の手番を CPU の応手ごと戻し、同じ目が戻る。無料は 1 回")
    func undoExchange() async {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 5)
        model.configureForTesting(board: BackgammonBoard(), roll: (3, 1))
        #expect(!model.canUndo, "まだ動かしていない")
        playHumanTurn(model)
        await playCPUTurn(model)
        #expect(!model.isAITurn && model.canUndo)
        let key = model.aiTurnKey
        model.undoLastExchange()
        #expect(model.board == BackgammonBoard())
        #expect(model.dice == [3, 1] && model.remainingDice == [3, 1])
        #expect(!model.isAITurn && model.undoUsed)
        #expect(!model.canUndo, "履歴は 1 段だけ")
        #expect(model.aiTurnKey != key)
    }

    @Test("広告の待ったは控えた局面のときだけ効く（#729）")
    func rewardedUndoGuard() async {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 5)
        model.configureForTesting(board: BackgammonBoard(), roll: (3, 1))
        playHumanTurn(model)
        await playCPUTurn(model)
        let stale = model.aiTurnKey
        playHumanTurn(model)
        await playCPUTurn(model)
        guard model.canUndo else { return }   // ごく稀に mustPass で終わる並びは対象外
        let board = model.board
        #expect(!model.undoLastExchange(forTurn: stale))
        #expect(model.board == board)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey))
        #expect(model.board != board)
    }

    @Test("あがりで決着し、種類（ギャモン）が付く。投了は CPU の勝ち")
    func finishAndResign() {
        let (services, store) = makeServices()
        let model = BackgammonModel(services: services, cpuDelay: .zero, seed: 1)
        model.configureForTesting(board: board([0: 1], [18: 15], off: [14, 0]), roll: (1, 2))
        model.tap(0); model.tap(BackgammonBoard.off)
        #expect(model.gameOver && model.winner == .white)
        #expect(model.winKind == .gammon)
        #expect(model.reviewOutcome == .win)
        #expect(!store.exists(for: "backgammon"), "決着した局は中断データを残さない")

        let other = BackgammonModel(services: nil, cpuDelay: .zero, seed: 1)
        other.resign()
        #expect(other.gameOver && other.winner == .black && other.winKind == .single)
        #expect(other.reviewOutcome == .loss)
        #expect(!other.canUndo && !other.canRestartTurn)
    }

    @Test("中断データから盤・目・手番・やり直し先・待った先を復元する")
    func snapshotRoundTrip() async {
        let (services, store) = makeServices()
        let model = BackgammonModel(services: services, cpuDelay: .zero, seed: 5)
        #expect(!store.exists(for: "backgammon"), "開いただけでは保存しない")
        // 人間の番になるまで進める。
        if model.isAITurn { await playCPUTurn(model) }
        let move = model.legalMoves.first!
        model.tap(move.from); model.tap(move.to)
        #expect(store.exists(for: "backgammon"))
        let restored = BackgammonModel(services: services, cpuDelay: .zero, seed: 99)
        #expect(restored.board == model.board)
        #expect(restored.dice == model.dice && restored.remainingDice == model.remainingDice)
        #expect(restored.currentSide == model.currentSide)
        #expect(restored.turnID == model.turnID)
        #expect(restored.canRestartTurn == model.canRestartTurn)
        #expect(restored.canUndo == model.canUndo)
        #expect(restored.openingRoll?.human == model.openingRoll?.human)
    }

    @Test("壊れた中断データ（駒が 15 個ずつでない）は捨てて新規対局にする")
    func corruptSnapshotIsIgnored() throws {
        let (services, store) = makeServices()
        var points = Array(repeating: 0, count: 24)
        points[0] = 3
        let snap = BackgammonSnapshot(
            points: points, bar: [0, 0], off: [0, 0], currentSide: 0, aiLevel: 1, dice: [3, 1], remainingDice: [3, 1],
            turnID: 4, startedAt: Date(), undoUsed: nil, mustPass: nil, hasProgressed: true, openingHuman: nil, openingCPU: nil,
            undoPoints: nil, undoBar: nil, undoOff: nil, undoDice: nil, turnStartPoints: nil, turnStartBar: nil, turnStartOff: nil
        )
        try store.save(snap, for: "backgammon")
        let model = BackgammonModel(services: services, cpuDelay: .zero, seed: 1)
        #expect(BackgammonRules.isConsistent(model.board))
        #expect(model.turnID == 1)
    }

    @Test("新規対局は通し番号を進め、強さを持ち替える")
    func newGame() {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 1)
        let key = model.aiTurnKey
        model.newGame(aiLevel: CPUStrength.hard.rawValue)
        #expect(model.aiLevel == CPUStrength.hard.rawValue)
        #expect(model.aiTurnKey.gameSerial == key.gameSerial + 1)
        #expect(model.board == BackgammonBoard())
        #expect(!model.undoUsed && !model.canUndo)
    }

    @Test("1 局を通しで遊ぶと必ず決着し、駒の数が常に 15 個ずつ保たれる")
    func fullGame() async {
        let model = BackgammonModel(services: nil, cpuDelay: .zero, seed: 11)
        model.newGame(aiLevel: 0)
        var plies = 0
        while !model.gameOver && plies < 4_000 {
            plies += 1
            if model.isAITurn {
                await model.performAIMoveIfNeeded()
            } else if model.mustPass {
                model.confirmPass()
            } else if let move = model.legalMoves.first {
                model.tap(move.from); model.tap(move.to)
            } else {
                break
            }
            #expect(BackgammonRules.isConsistent(model.board), "ply \(plies)")
        }
        #expect(model.gameOver, "\(plies) 手で決着していない")
        #expect(model.winner != nil && model.winKind != nil)
    }
}
