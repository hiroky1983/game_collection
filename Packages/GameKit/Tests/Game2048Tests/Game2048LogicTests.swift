import Testing
@testable import Game2048

@Suite("slideRowLeft 状態遷移")
struct SlideRowLeftTests {
    // (入力行, 期待行, 期待スコア) の状態遷移テーブル。決定的なので網羅できる。
    static let cases: [(input: [Int], expected: [Int], gained: Int)] = [
        ([0, 0, 0, 0], [0, 0, 0, 0], 0),
        ([2, 0, 0, 0], [2, 0, 0, 0], 0),
        ([0, 0, 0, 2], [2, 0, 0, 0], 0),
        ([2, 2, 0, 0], [4, 0, 0, 0], 4),
        ([0, 2, 0, 2], [4, 0, 0, 0], 4),
        ([2, 2, 2, 0], [4, 2, 0, 0], 4),        // 左から1組だけマージ
        ([2, 2, 2, 2], [4, 4, 0, 0], 8),        // 2組マージ
        ([4, 4, 2, 2], [8, 4, 0, 0], 12),
        ([2, 0, 2, 4], [4, 4, 0, 0], 4),
        ([8, 0, 8, 8], [16, 8, 0, 0], 16),      // 隣接優先、3連は左優先
        ([2, 4, 2, 4], [2, 4, 2, 4], 0),        // マージ不可
        ([1024, 1024, 0, 0], [2048, 0, 0, 0], 2048),
    ]

    @Test(arguments: cases)
    func slides(_ c: (input: [Int], expected: [Int], gained: Int)) {
        let result = Game2048Logic.slideRowLeft(c.input)
        #expect(result.row == c.expected)
        #expect(result.gained == c.gained)
    }
}

@Suite("盤スライド（方向）")
struct SlideDirectionTests {
    @Test func slideLeftMergesEachRow() {
        let board = [
            [2, 2, 0, 0],
            [4, 0, 4, 0],
            [0, 0, 0, 0],
            [2, 2, 2, 2],
        ]
        let r = Game2048Logic.slide(board, .left)
        #expect(r.board == [
            [4, 0, 0, 0],
            [8, 0, 0, 0],
            [0, 0, 0, 0],
            [4, 4, 0, 0],
        ])
        #expect(r.gained == 4 + 8 + 8)
        #expect(r.moved)
    }

    @Test func slideRightIsMirrorOfLeft() {
        let board = [
            [0, 0, 2, 2],
            [0, 4, 0, 4],
            [0, 0, 0, 0],
            [2, 2, 2, 2],
        ]
        let r = Game2048Logic.slide(board, .right)
        #expect(r.board == [
            [0, 0, 0, 4],
            [0, 0, 0, 8],
            [0, 0, 0, 0],
            [0, 0, 4, 4],
        ])
    }

    @Test func slideUpMergesColumns() {
        let board = [
            [2, 4, 0, 0],
            [2, 0, 0, 0],
            [0, 4, 0, 0],
            [0, 0, 0, 0],
        ]
        let r = Game2048Logic.slide(board, .up)
        #expect(r.board == [
            [4, 8, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ])
        #expect(r.gained == 4 + 8)
    }

    @Test func slideDownMergesColumns() {
        let board = [
            [2, 0, 0, 0],
            [2, 0, 0, 0],
            [4, 0, 0, 0],
            [4, 0, 0, 0],
        ]
        let r = Game2048Logic.slide(board, .down)
        #expect(r.board == [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [4, 0, 0, 0],
            [8, 0, 0, 0],
        ])
    }

    @Test func noMoveReportsNotMoved() {
        let board = [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 2],
        ]
        for d in Direction.allCases {
            #expect(Game2048Logic.slide(board, d).moved == false)
        }
    }
}

@Suite("ゲームオーバー判定")
struct GameOverTests {
    @Test func emptyCellMeansNotOver() {
        let board = [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 0],
        ]
        #expect(Game2048Logic.isGameOver(board) == false)
    }

    @Test func adjacentEqualMeansNotOver() {
        let board = [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 4], // 末尾に同値隣接
        ]
        #expect(Game2048Logic.isGameOver(board) == false)
    }

    @Test func fullWithNoMergeIsOver() {
        let board = [
            [2, 4, 2, 4],
            [4, 2, 4, 2],
            [2, 4, 2, 4],
            [4, 2, 4, 2],
        ]
        #expect(Game2048Logic.isGameOver(board))
    }
}
