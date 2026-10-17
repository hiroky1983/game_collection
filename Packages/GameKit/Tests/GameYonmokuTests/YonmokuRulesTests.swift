import Testing
@testable import GameYonmoku

@Suite("四目並べのルール（落下・勝ち・引き分け）")
struct YonmokuRulesTests {
    @Test("石は列の一番下の空きに入り、積み重なる")
    func dropFallsToBottom() {
        var board = YonmokuBoard()
        #expect(board.drop(.black, in: 3) == YonmokuPoint(col: 3, row: 0))
        #expect(board.drop(.white, in: 3) == YonmokuPoint(col: 3, row: 1))
        #expect(board.drop(.black, in: 0) == YonmokuPoint(col: 0, row: 0))
        #expect(board[3, 0] == .black && board[3, 1] == .white && board[3, 2] == nil)
        #expect(board.height(of: 3) == 2)
        #expect(board.discCount == 3)
    }

    @Test("6 段埋まった列と盤の外の列には入らない（盤は変わらない）")
    func fullColumnRejects() {
        var board = YonmokuBoard()
        for i in 0..<YonmokuBoard.rows { board.drop(i % 2 == 0 ? .black : .white, in: 2) }
        let before = board
        #expect(!board.canDrop(in: 2))
        #expect(board.drop(.black, in: 2) == nil)
        #expect(board.drop(.black, in: -1) == nil)
        #expect(board.drop(.black, in: 7) == nil)
        #expect(board == before)
        #expect(board.playableColumns == [0, 1, 3, 4, 5, 6])
    }

    @Test("よこ・たて・ななめ 2 方向の 4 つで勝ち、3 つでは勝ちでない")
    func winningLines() throws {
        // よこ: 黒 0,1,2,3（白は上に積む）
        let horizontal = try #require(YonmokuBoard.replay([0, 0, 1, 1, 2, 2, 3]))
        let h = try #require(horizontal.winningLine(through: YonmokuPoint(col: 3, row: 0)))
        #expect(h == (0...3).map { YonmokuPoint(col: $0, row: 0) })
        #expect(YonmokuBoard.replay([0, 0, 1, 1, 2]).flatMap { $0.winningLine(through: YonmokuPoint(col: 2, row: 0)) } == nil)

        // たて: 黒が 0 列に 4 つ
        let vertical = try #require(YonmokuBoard.replay([0, 1, 0, 1, 0, 1, 0]))
        #expect(vertical.winningLine(through: YonmokuPoint(col: 0, row: 3))?.count == 4)

        // ななめ（右上がり）: 黒 (0,0) (1,1) (2,2) (3,3)
        let rising = try #require(YonmokuBoard.replay([0, 1, 1, 2, 2, 3, 2, 3, 3, 6, 3]))
        #expect(rising[3, 3] == .black)
        #expect(rising.winningLine(through: YonmokuPoint(col: 3, row: 3))
                == [YonmokuPoint(col: 0, row: 0), YonmokuPoint(col: 1, row: 1),
                    YonmokuPoint(col: 2, row: 2), YonmokuPoint(col: 3, row: 3)])

        // ななめ（右下がり）: 黒 (3,0) (2,1) (1,2) (0,3)
        let falling = try #require(YonmokuBoard.replay([3, 2, 2, 1, 1, 0, 1, 0, 0, 6, 0]))
        #expect(falling[0, 3] == .black)
        #expect(falling.winningLine(through: YonmokuPoint(col: 0, row: 3))?.count == 4)
    }

    @Test("5 つ並んでも勝ち（並んだ全部を返す）")
    func fiveInARow() throws {
        // 黒 0,1,3,4 → 最後に 2 で 5 つ
        var board = YonmokuBoard()
        for col in [0, 1, 3, 4] { board.drop(.black, in: col) }
        let dropped = board.drop(.black, in: 2)
        let p = try #require(dropped)
        #expect(board.winningLine(through: p)?.count == 5)
    }

    @Test("42 マス埋まって 4 つが無ければ満杯（引き分けの盤）")
    func fullBoardDraw() throws {
        let moves = Self.drawMoves
        #expect(moves.count == 42)
        let board = try #require(YonmokuBoard.replay(moves))
        #expect(board.isFull)
        #expect(board.playableColumns.isEmpty)
        for col in 0..<YonmokuBoard.columns {
            for row in 0..<YonmokuBoard.rows {
                #expect(board.winningLine(through: YonmokuPoint(col: col, row: row)) == nil)
            }
        }
    }

    @Test("手順の復元: 入らない列・決着後の手は nil、最後の手での決着は読める")
    func replayValidation() {
        #expect(YonmokuBoard.replay([]) == YonmokuBoard())
        #expect(YonmokuBoard.replay([9]) == nil)
        #expect(YonmokuBoard.replay(Array(repeating: 0, count: 7)) == nil, "7 個目は入らない")
        #expect(YonmokuBoard.replay([0, 0, 1, 1, 2, 2, 3]) != nil)
        #expect(YonmokuBoard.replay([0, 0, 1, 1, 2, 2, 3, 4]) == nil, "決着後の手")
    }

    /// 引き分けで埋まる手順（列 0〜6 の段ごとの色が 4 つ並ばない並び）。
    ///
    /// 段の色は列ごとに「黒白黒白黒白」を、2 列ずつ「白黒…」に反転させた配置
    /// （列 0,1: 黒始まり / 列 2,3: 白始まり / 列 4,5: 黒始まり / 列 6: 白始まり）。
    /// 先手・後手が交互になるように列を選ぶ。
    static var drawMoves: [Int] {
        // 目標の配置: target[col][row]
        let starts: [YonmokuDisc] = [.black, .black, .white, .white, .black, .black, .white]
        let target: [[YonmokuDisc]] = starts.map { s in (0..<6).map { $0 % 2 == 0 ? s : s.opponent } }
        // 手番の色が次に入る列を選んでいく（行き詰まったら戻る）。
        var heights = Array(repeating: 0, count: 7)
        var moves: [Int] = []
        func search(_ disc: YonmokuDisc) -> Bool {
            if moves.count == 42 { return true }
            for col in 0..<7 where heights[col] < 6 && target[col][heights[col]] == disc {
                moves.append(col); heights[col] += 1
                if search(disc.opponent) { return true }
                moves.removeLast(); heights[col] -= 1
            }
            return false
        }
        _ = search(.black)
        return moves
    }
}
