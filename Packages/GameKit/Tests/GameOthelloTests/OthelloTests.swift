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
