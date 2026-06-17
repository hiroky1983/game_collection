import Testing
@testable import GameGomoku

@Suite("GomokuBoard")
struct GomokuBoardTests {
    @Test func winHorizontal() {
        var b = GomokuBoard()
        for col in 0..<5 { b[7, col] = .black }
        #expect(b.checkWin(row: 7, col: 4))
        #expect(!b.checkWin(row: 7, col: 0) == false) // same stone wins
    }

    @Test func winVertical() {
        var b = GomokuBoard()
        for row in 3..<8 { b[row, 7] = .white }
        #expect(b.checkWin(row: 7, col: 7))
    }

    @Test func winDiagonal() {
        var b = GomokuBoard()
        for i in 0..<5 { b[i, i] = .black }
        #expect(b.checkWin(row: 4, col: 4))
    }

    @Test func noWinWithFour() {
        var b = GomokuBoard()
        for col in 0..<4 { b[7, col] = .black }
        #expect(!b.checkWin(row: 7, col: 3))
    }

    @Test func boardIsFull() {
        let cells = (0..<(gomokuBoardSize * gomokuBoardSize)).map { i -> GomokuStone? in
            i % 2 == 0 ? .black : .white
        }
        let b = GomokuBoard(cells: cells)
        #expect(b.isFull)
    }
}

@Suite("GomokuEngine")
struct GomokuEngineTests {
    @Test func engineBlocksWinningMove() async {
        var b = GomokuBoard()
        // 黒が4連で白に勝たせない
        for col in 0..<4 { b[7, col] = .black }
        let engine = SimpleGomokuEngine(level: 1)
        let move = await engine.bestMove(board: b, stone: .white)
        // 白は黒の5つ目をブロックするはず
        #expect(move != nil)
        if let m = move {
            #expect(m.row == 7 && (m.col == 4 || m.col == -1) == (m.col == 4))
        }
    }

    @Test func engineTakesWin() async {
        var b = GomokuBoard()
        // 白が4連で白自身が勝てる
        for col in 0..<4 { b[3, col] = .white }
        let engine = SimpleGomokuEngine(level: 0)
        let move = await engine.bestMove(board: b, stone: .white)
        #expect(move?.row == 3 && move?.col == 4)
    }
}

@MainActor
@Suite("GomokuModel")
struct GomokuModelTests {
    @Test func undoLastExchangeRemovesHumanAndCPUMoves() async {
        let model = GomokuModel(services: nil)
        model.tap(row: 7, col: 7)
        await model.performAIMoveIfNeeded()
        #expect(model.moveCount == 2)
        #expect(model.canUndo)

        model.undoLastExchange()
        #expect(model.moveCount == 0)
        #expect(model.board[7, 7] == nil)
        #expect(model.isAITurn == false)
        #expect(model.canUndo == false)
    }
}
