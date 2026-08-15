import Testing
@testable import GameOthello

@Suite("OthelloBoard")
struct OthelloBoardTests {

    @Test("初期配置は石4個") func initialCount() {
        let board = OthelloBoard()
        #expect(board.count(for: .black) == 2)
        #expect(board.count(for: .white) == 2)
    }

    @Test("初手は4マスどれか") func initialMoves() {
        let board = OthelloBoard()
        let moves = board.validMoves(for: .black)
        #expect(moves.count == 4)
    }

    @Test("石を置くとひっくり返る") func flipOnPlace() {
        var board = OthelloBoard()
        // 黒の初手 (2,3) → (3,3) の白がひっくり返る
        board.place(row: 2, col: 3, stone: .black)
        #expect(board[2, 3] == .black)
        #expect(board[3, 3] == .black)
    }

    @Test("盤面満杯判定") func fullBoard() {
        var board = OthelloBoard()
        for r in 0..<othelloBoardSize {
            for c in 0..<othelloBoardSize {
                if board[r, c] == nil { board[r, c] = .black }
            }
        }
        #expect(board.isFull)
    }
}

// MARK: - CPU 起動トリガー（#140: 後手を選ぶと CPU が初手を打たない）

@MainActor
@Suite("オセロ CPU 起動トリガー")
struct OthelloAITurnKeyTests {
    /// View は `.task(id: model.aiTurnKey)` で CPU を起動する。
    /// 起動直後（turnID = 0）に後手を選んでも turnID が 0 のままなので、
    /// キーが変わらないと初手が打たれない。
    @Test func aiTurnKeyChangesWhenStartingAsGoteWithoutMoves() {
        let model = OthelloModel(services: nil)
        #expect(model.turnID == 0)
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.turnID == 0)         // turnID は 0 のまま
        #expect(model.aiTurnKey != before) // それでもトリガーは変化する
        #expect(model.isAITurn)
    }

    /// 後手開始 → CPU 初手 → 人間応手 → 再び CPU 番、まで通しで動くこと。
    @Test func goteStartPlaysCPUFirstMoveThenHumanReply() async {
        let model = OthelloModel(services: nil)
        model.newGame(humanSide: .white)

        await model.performAIMoveIfNeeded()
        #expect(model.turnID == 1)
        #expect(model.isAITurn == false) // 人間(白)の番
        let afterCPU = model.aiTurnKey

        let move = try! #require(model.board.validMoves(for: .white).first)
        model.tap(row: move.0, col: move.1)

        #expect(model.turnID == 2)
        #expect(model.aiTurnKey != afterCPU)
        #expect(model.isAITurn) // CPU(黒)の番に戻る
    }

    /// 対局途中から新規対局を始めて後手を選んだ場合もトリガーが変化すること。
    @Test func aiTurnKeyChangesWhenRestartingMidGameAsGote() async {
        let model = OthelloModel(services: nil)
        let first = try! #require(model.board.validMoves(for: .black).first)
        model.tap(row: first.0, col: first.1)
        await model.performAIMoveIfNeeded()
        let before = model.aiTurnKey

        model.newGame(humanSide: .white)
        #expect(model.turnID == 0)
        #expect(model.aiTurnKey != before)
        #expect(model.isAITurn)
    }

    /// 先手を選んだ場合は従来どおり CPU は動かず、人間の手番から始まる。
    @Test func senteStartKeepsHumanTurn() async {
        let model = OthelloModel(services: nil)
        model.newGame(humanSide: .black)
        #expect(model.isAITurn == false)
        await model.performAIMoveIfNeeded()
        #expect(model.turnID == 0)
    }
}

// MARK: - 思考中の新規対局（#140 のレビュー指摘: 旧盤面で選んだ手が新盤面に着手される）

@MainActor
@Suite("オセロ 思考中の新規対局")
struct OthelloNewGameDuringThinkingTests {
    /// CPU の思考中に後手で新規対局を始めても、旧盤面で選んだ手が新しい盤面に着手されないこと。
    /// オセロは着手で石が返るため、旧盤面の手をそのまま打つと盤面が壊れる。
    @Test func newGameDuringThinkingDiscardsStaleMove() async {
        let model = OthelloModel(services: nil)
        model.newGame(humanSide: .black, aiLevel: 2)
        let first = try! #require(model.board.validMoves(for: .black).first)
        model.tap(row: first.0, col: first.1) // 人間(黒)が着手 → CPU(白)の番
        let thinking = Task { await model.performAIMoveIfNeeded() }
        await Task.yield()

        model.newGame(humanSide: .white)
        await thinking.value

        #expect(model.turnID == 0)         // 旧盤面で選んだ手は入っていない
        #expect(model.blackCount == 2)     // 初期配置のまま（石が返っていない）
        #expect(model.whiteCount == 2)
        #expect(model.isThinking == false)
        #expect(model.isAITurn)            // 新しい対局は CPU(黒)の手番のまま
    }
}
