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

// MARK: - CPU 起動トリガー（#140: 後手を選ぶと CPU が初手を打たない）

@MainActor
@Suite("五目並べ CPU 起動トリガー")
struct GomokuAITurnKeyTests {
    /// View は `.task(id: model.aiTurnKey)` で CPU を起動する。
    /// 起動直後（0 手）に後手を選んでも手数が 0 のままなので、キーが変わらないと初手が打たれない。
    @Test func aiTurnKeyChangesWhenStartingAsGoteWithoutMoves() {
        let model = GomokuModel(services: nil)
        #expect(model.moveCount == 0)
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.moveCount == 0)      // 手数は 0 のまま
        #expect(model.aiTurnKey != before) // それでもトリガーは変化する
        #expect(model.isAITurn)
    }

    /// 後手開始 → CPU 初手 → 人間応手 → 再び CPU 番、まで通しで動くこと。
    @Test func goteStartPlaysCPUFirstMoveThenHumanReply() async {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .white)

        await model.performAIMoveIfNeeded()
        #expect(model.moveCount == 1)
        #expect(model.isAITurn == false) // 人間(白)の番
        let afterCPU = model.aiTurnKey

        // 人間(白)が空いているマスへ打つ。
        let empty = (0..<gomokuBoardSize).flatMap { r in (0..<gomokuBoardSize).map { (r, $0) } }
            .first { model.board[$0.0, $0.1] == nil }
        let (row, col) = try! #require(empty)
        model.tap(row: row, col: col)

        #expect(model.moveCount == 2)
        #expect(model.aiTurnKey != afterCPU)
        #expect(model.isAITurn) // CPU(黒)の番に戻る
    }

    /// 対局途中から新規対局を始めて後手を選んだ場合もトリガーが変化すること。
    @Test func aiTurnKeyChangesWhenRestartingMidGameAsGote() async {
        let model = GomokuModel(services: nil)
        model.tap(row: 7, col: 7)
        await model.performAIMoveIfNeeded()
        #expect(model.moveCount == 2)
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.moveCount == 0)
        #expect(model.aiTurnKey != before)
        #expect(model.isAITurn)
    }

    /// 先手を選んだ場合は従来どおり CPU は動かず、人間の手番から始まる。
    @Test func senteStartKeepsHumanTurn() async {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .black)
        #expect(model.isAITurn == false)
        await model.performAIMoveIfNeeded()
        #expect(model.moveCount == 0)
    }
}

// MARK: - 思考中の新規対局（#140 のレビュー指摘: 旧盤面で選んだ手が新盤面に着手される）

@MainActor
@Suite("五目並べ 思考中の新規対局")
struct GomokuNewGameDuringThinkingTests {
    /// CPU の思考中に後手で新規対局を始めても、旧盤面で選んだ手が新しい盤面に着手されないこと。
    /// 併せて、思考フラグが新しい対局のために解放され CPU の初手を起動できること。
    ///
    /// 思考の途中で `newGame` が入る状況を安定して作るため、CPU は深い探索（aiLevel 2）にしている。
    /// 旧タスクが先に完走した場合でも下の期待値は成立するため、この検証は結果に対して決定的。
    @Test func newGameDuringThinkingDiscardsStaleMove() async {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .black, aiLevel: 2)
        model.tap(row: 7, col: 7) // 人間(黒)が着手 → CPU(白)の番
        let thinking = Task { await model.performAIMoveIfNeeded() }
        await Task.yield()        // 思考を開始させる

        model.newGame(humanSide: .white) // 思考中に後手で新規対局
        await thinking.value             // 旧対局の計算が終わるまで待つ

        #expect(model.moveCount == 0)      // 旧盤面で選んだ手は入っていない
        #expect(model.board[7, 7] == nil)
        #expect(model.isThinking == false) // 新しい対局の CPU を起動できる
        #expect(model.isAITurn)            // 新しい対局は CPU(黒)の手番のまま
    }
}

// MARK: - 無効なタップへのフィードバック（#202）

@MainActor
@Suite("五目並べ 無効なタップ")
struct GomokuInvalidTapTests {
    /// 盤外の座標を渡しても添字の範囲外アクセスにならず、拒否として数えられること。
    /// View は `SpatialTapGesture` の座標を丸めてそのまま渡すため、負値・15 以上が来る。
    @Test func outOfBoardTapIsRejectedWithoutCrashing() {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .black)

        model.tap(row: -1, col: 7)
        #expect(model.lastRejection == .outOfBoard)
        #expect(model.rejectedTapCount == 1)

        model.tap(row: 7, col: gomokuBoardSize)
        #expect(model.lastRejection == .outOfBoard)
        #expect(model.rejectedTapCount == 2)
        #expect(model.moveCount == 0) // 盤は動かない
    }

    /// CPU の手番中のタップが「無反応」ではなく拒否として扱われること。
    /// ここを View 側の早期 return に戻すと、思考中のタップだけ再び無反応になる。
    @Test func tapDuringCPUTurnIsRejected() {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .black)
        model.tap(row: 7, col: 7)      // 人間(黒)が着手 → CPU(白)の番
        #expect(model.isAITurn)
        #expect(model.rejectedTapCount == 0)

        model.tap(row: 3, col: 3)
        #expect(model.lastRejection == .notYourTurn)
        #expect(model.rejectedTapCount == 1)
        #expect(model.moveCount == 1)  // CPU の番に人間の石は入らない
    }

    /// 石のあるマスへのタップは従来どおり拒否。理由まで区別できること。
    ///
    /// 人間の手番で埋まったマスを叩く必要があるので、後手（白）を選んで CPU に先に打たせ、
    /// その石の上を叩く。
    @Test func occupiedTapIsRejected() async {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        let cpuMove = try! #require(model.lastMove)
        #expect(model.isAITurn == false)
        #expect(model.rejectedTapCount == 0)

        model.tap(row: cpuMove.row, col: cpuMove.col)
        #expect(model.lastRejection == .occupied)
        #expect(model.rejectedTapCount == 1)
        #expect(model.moveCount == 1) // 上書きされない
    }

    /// 決着後の盤面へのタップは拒否として鳴らさない（結果表示中の雑音を避ける）。
    @Test func tapAfterGameOverIsSilent() {
        let model = GomokuModel(services: nil)
        model.newGame(humanSide: .black)
        model.resign()
        #expect(model.gameOver)

        model.tap(row: 3, col: 3)
        #expect(model.rejectedTapCount == 0)
        #expect(model.lastRejection == nil)
    }

    /// 撮影用の中盤盤面（#366）は、決着せず人間の手番で止まること。
    /// 決着したり CPU の手番で止まったりすると、撮影中に結果表示や CPU の着手で盤が動く。
    @Test func previewMidgameStopsOnHumanTurnWithoutEnding() {
        let model = GomokuModel(services: nil)
        model.applyPreviewMidgameForTesting()

        #expect(model.moveCount == 10)
        #expect(model.gameOver == false)
        #expect(model.isAITurn == false)

        // 対局が進んだあとは何もしない（撮影引数を付けたまま再起動しても盤を壊さない）。
        model.applyPreviewMidgameForTesting()
        #expect(model.moveCount == 10)
    }
}
