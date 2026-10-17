import Testing
import Foundation
import Core
import CoreEngine
import CoreTestSupport
import GameKitTestSupport
@testable import GameYonmoku

@MainActor
private func makeServices() -> (GameServices, MemorySnapshotStore) {
    let store = MemorySnapshotStore()
    return (GameServices(snapshots: store, ads: NoopAdService()), store)
}

@Suite("四目並べの Model")
@MainActor
struct YonmokuModelTests {
    @Test("開くと空の盤で、あなたは黒（先手）・ふつうの強さ")
    func freshStart() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        #expect(model.board == YonmokuBoard())
        #expect(model.humanSide == .black && !model.isAITurn && !model.gameOver)
        #expect(model.aiLevel == CPUStrength.standard.rawValue)
        #expect(model.playableColumns == Array(0..<7))
        #expect(!model.canUndo)
    }

    @Test("列をタップすると一番下に入り、CPU の番になる。CPU の番のタップは盤が揺れるだけ")
    func tapDrops() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.tap(column: 3)
        #expect(model.board[3, 0] == .black)
        #expect(model.lastMove == YonmokuPoint(col: 3, row: 0))
        #expect(model.isAITurn && model.moveCount == 1)
        let before = model.board
        model.tap(column: 2)
        #expect(model.board == before)
        #expect(model.rejectedTapCount == 1)
    }

    @Test("満杯の列のタップは盤を変えず、揺れで知らせる")
    func tapFullColumn() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.configureForTesting(moves: [0, 0, 0, 0, 0, 0])
        let before = model.board
        model.tap(column: 0)
        #expect(model.board == before && !model.isAITurn)
        #expect(model.rejectedTapCount == 1)
    }

    @Test("CPU は入る列に 1 手打ち、あなたの番に戻る")
    func cpuMoves() async {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 3)
        model.newGame(humanSide: .black, aiLevel: 0)
        model.tap(column: 3)
        await model.performAIMoveIfNeeded()
        #expect(model.moveCount == 2)
        #expect(!model.isAITurn)
        #expect(model.lastCPUMoveKey == model.aiTurnKey)
    }

    @Test("後手（白）を選ぶと CPU の黒から始まる")
    func humanSecond() async {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 3)
        model.newGame(humanSide: .white, aiLevel: -1)
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moveCount == 1 && !model.isAITurn)
        #expect(model.board.discCount == 1)
    }

    @Test("CPU の思考中に新規対局を始めても旧局面の手は入らない")
    func newGameDuringThinking() async throws {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 3)
        model.newGame(humanSide: .black, aiLevel: 0)
        model.tap(column: 3)
        let gate = TaskGate()
        model.thinkingGate = { await gate.wait() }
        let task = Task { await model.performAIMoveIfNeeded() }
        await gate.waitUntilArrived()
        model.thinkingGate = nil
        try #require(model.isThinking)
        model.newGame(humanSide: .black, aiLevel: 0)
        #expect(!model.isThinking, "新しい対局の CPU を起動できる")
        gate.release()
        await task.value
        #expect(model.board == YonmokuBoard() && model.moveCount == 0, "旧タスクは新しい盤を書き換えていない")
    }

    @Test("4 つ並べると勝ち。勝ち筋が残り、決着後は打てない")
    func humanWins() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.configureForTesting(moves: [0, 0, 1, 1, 2, 2])
        model.tap(column: 3)
        #expect(model.gameOver && model.winner == .black && model.reviewOutcome == .win)
        #expect(model.winningLine == (0...3).map { YonmokuPoint(col: $0, row: 0) })
        let before = model.board
        model.tap(column: 4)
        #expect(model.board == before && model.rejectedTapCount == 0, "決着後のタップは黙って無視")
    }

    @Test("CPU が 4 つ並べると負け")
    func cpuWins() async {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .black, aiLevel: 2)
        // 白（CPU）が 0 列にたてに 3 つ。あなた（黒）が 4 列に入れて止めないと、CPU が 0 列で勝つ。
        model.configureForTesting(moves: [6, 0, 6, 0, 5, 0])
        #expect(!model.isAITurn)
        model.tap(column: 4)
        await model.performAIMoveIfNeeded()
        #expect(model.gameOver && model.winner == .white && model.reviewOutcome == .loss)
    }

    @Test("42 マス埋まって 4 つが無ければ引き分け")
    func draw() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        let moves = YonmokuRulesTests.drawMoves
        model.configureForTesting(moves: Array(moves.dropLast()), humanSide: .white)
        #expect(!model.isAITurn, "最後の 42 手目は白（あなた）")
        model.tap(column: moves.last!)
        #expect(model.gameOver && model.isDraw && model.winner == nil && model.reviewOutcome == .draw)
    }

    @Test("投了は CPU の勝ち")
    func resign() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.tap(column: 3)
        model.resign()
        #expect(model.gameOver && model.winner == .white && model.reviewOutcome == .loss)
        #expect(model.winningLine == nil)
    }

    @Test("待った: 自分の直前の 1 手を CPU の応手ごと戻す")
    func undo() async {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 5)
        model.newGame(humanSide: .black, aiLevel: 0)
        model.tap(column: 3)
        await model.performAIMoveIfNeeded()
        model.tap(column: 2)
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo)
        let key = model.aiTurnKey
        model.undoLastExchange()
        #expect(model.moveCount == 2 && model.board.discCount == 2)
        #expect(model.board[2, 0] == nil || model.board[2, 0] == .white, "あなたの 2 手目は消えた")
        #expect(!model.isAITurn && model.undoUsed)
        #expect(model.aiTurnKey != key)
    }

    @Test("後手のとき: 待ったは自分の手と CPU の応手を戻し、CPU の初手は残る")
    func undoAsSecond() async {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 5)
        model.newGame(humanSide: .white, aiLevel: 0)
        await model.performAIMoveIfNeeded()
        #expect(!model.canUndo, "まだ自分は打っていない")
        model.tap(column: 0)
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo)
        model.undoLastExchange()
        #expect(model.moveCount == 1 && !model.isAITurn)
    }

    @Test("広告の待ったは控えた局面のときだけ効く（#729）")
    func rewardedUndoGuard() async {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 5)
        model.newGame(humanSide: .black, aiLevel: 0)
        model.tap(column: 3)
        await model.performAIMoveIfNeeded()
        let stale = model.aiTurnKey
        model.tap(column: 3)
        await model.performAIMoveIfNeeded()
        #expect(!model.undoLastExchange(forTurn: stale))
        #expect(model.moveCount == 4)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey))
        #expect(model.moveCount == 2)
    }

    @Test("1 手打つまでは保存せず、打ったら保存し、新規対局・決着で消える")
    func snapshotLifecycle() {
        let (services, store) = makeServices()
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        #expect(!store.exists(for: "yonmoku"), "開いただけの局は保存しない（#240）")
        model.tap(column: 3)
        #expect(store.exists(for: "yonmoku"))
        model.newGame()
        #expect(!store.exists(for: "yonmoku"))
        model.tap(column: 2)
        model.resign()
        #expect(!store.exists(for: "yonmoku"))
    }

    @Test("中断データから盤・手番・石の色・強さ・待ったの使用・直前の手を復元する")
    func restore() async {
        let (services, _) = makeServices()
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 5)
        model.newGame(humanSide: .white, aiLevel: -1)
        await model.performAIMoveIfNeeded()
        model.tap(column: 0)
        await model.performAIMoveIfNeeded()
        model.undoLastExchange()
        model.tap(column: 6)
        let restored = YonmokuModel(services: services, cpuDelay: .zero, seed: 5)
        #expect(restored.board == model.board)
        #expect(restored.currentDisc == model.currentDisc)
        #expect(restored.humanSide == .white)
        #expect(restored.aiLevel == -1)
        #expect(restored.undoUsed)
        #expect(restored.moveCount == model.moveCount)
        #expect(restored.lastMove == model.lastMove)
        #expect(restored.isAITurn)
        await restored.performAIMoveIfNeeded()
        #expect(restored.canUndo, "手順ごと戻るので、復元後も待ったが効く")
    }

    @Test("壊れた中断データ（入らない列・決着後の手・知らない色）は捨てて新規にする",
          arguments: [[0, 0, 0, 0, 0, 0, 0], [9], [0, 0, 1, 1, 2, 2, 3, 4]])
    func corruptedSnapshot(moves: [Int]) throws {
        let (services, store) = makeServices()
        try store.save(YonmokuSnapshot(moves: moves, humanSide: 0, aiLevel: 1, startedAt: Date(), undoUsed: nil),
                       for: "yonmoku")
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        #expect(model.board == YonmokuBoard() && model.moveCount == 0)
        #expect(!store.exists(for: "yonmoku"))
    }

    @Test("知らない石の色の中断データも捨てる")
    func unknownSide() throws {
        let (services, store) = makeServices()
        try store.save(YonmokuSnapshot(moves: [3], humanSide: 5, aiLevel: 1, startedAt: Date(), undoUsed: nil),
                       for: "yonmoku")
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        #expect(model.moveCount == 0 && !store.exists(for: "yonmoku"))
    }

    @Test("決着まで打ち切ると石は 42 個以下で、必ず勝ち・負け・引き分けのどれか", arguments: [-1, 0, 1])
    func fullGame(level: Int) async {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 11)
        model.newGame(humanSide: level == 0 ? .white : .black, aiLevel: level)
        var guardCount = 0
        while !model.gameOver, guardCount < 60 {
            guardCount += 1
            if model.isAITurn {
                await model.performAIMoveIfNeeded()
            } else if let col = model.playableColumns.first {
                model.tap(column: col)
            }
        }
        #expect(model.gameOver)
        #expect(model.board.discCount <= 42)
        #expect(model.winner != nil || model.isDraw)
    }
}
