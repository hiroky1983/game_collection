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

@Suite("コンティニューの復活処理（#122）")
struct ReviveTests {
    /// 実プレイで到達しうる終局盤面。最小値は 2 が 1 個、次に 4 が 4 個。
    static let deadBoard = [
        [2, 4, 8, 4],
        [16, 8, 32, 16],
        [4, 64, 128, 32],
        [16, 8, 4, 8],
    ]

    @Test("空きマスがちょうど4になり、消えるのは最小値のタイルだけ")
    func removesSmallestTilesDeterministically() {
        let revived = Game2048Logic.revive(Self.deadBoard)

        #expect(Game2048Logic.emptyCells(revived).count == 4)
        // 値の昇順 → 行・列の昇順で 2(0,0) → 4(0,1) → 4(0,3) → 4(2,0) の 4 個が消える。
        #expect(revived == [
            [0, 0, 8, 0],
            [16, 8, 32, 16],
            [0, 64, 128, 32],
            [16, 8, 4, 8],
        ])
    }

    @Test("何度呼んでも結果が同じ（乱数に依存しない）")
    func isDeterministic() {
        let first = Game2048Logic.revive(Self.deadBoard)
        for _ in 0..<50 {
            #expect(Game2048Logic.revive(Self.deadBoard) == first)
        }
    }

    @Test("最大タイルは取り除かない")
    func keepsHighestTile() {
        let revived = Game2048Logic.revive(Self.deadBoard)
        #expect(revived.flatMap { $0 }.max() == 128)
        #expect(revived[2][2] == 128)
    }

    @Test("復活後の盤面は終局ではない")
    func revivedBoardIsPlayable() {
        let revived = Game2048Logic.revive(Self.deadBoard)
        #expect(Game2048Logic.isGameOver(revived) == false)
        #expect(Direction.allCases.contains { Game2048Logic.slide(revived, $0).moved })
    }

    @Test("既に空きマスが足りている盤面には手を加えない")
    func noOpWhenAlreadyEnoughSpace() {
        let board = [
            [2, 4, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
        ]
        #expect(Game2048Logic.revive(board) == board)
    }

    /// 「最小値のタイルを 4 個消す」という仕様が、実プレイ由来ではない終局盤面でも
    /// 成り立つことを機械的に確かめる。市松模様に敷いた最大タイルは保護対象。
    @Test("最大タイルが8個ある最悪ケースでも空きマス4を確保できる")
    func worksWhenHighestTileFillsCheckerboard() {
        // 128 を市松の 8 マスに敷き、残りをマージ不可の 2/4/8/16 で埋めた終局盤面。
        let board = [
            [128, 2, 128, 4],
            [8, 128, 16, 128],
            [128, 4, 128, 2],
            [16, 128, 8, 128],
        ]
        #expect(Game2048Logic.isGameOver(board))

        let revived = Game2048Logic.revive(board)
        #expect(Game2048Logic.emptyCells(revived).count == 4)
        #expect(revived.flatMap { $0 }.filter { $0 == 128 }.count == 8, "最大タイルは1個も消えない")
        #expect(Game2048Logic.isGameOver(revived) == false)
    }
}
