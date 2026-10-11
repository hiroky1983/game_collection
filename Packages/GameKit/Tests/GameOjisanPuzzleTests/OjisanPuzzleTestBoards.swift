@testable import GameOjisanPuzzle

/// テストで「盤の重さがちょうど◯」の盤を作る道具（腰痛ゲージは盤の重さで決まる・#2069）。
enum OjisanPuzzleTestBoards {
    /// `start` の空きマスに、重さの合計がちょうど `weight` になるまで荷物を敷く。
    /// 下の段から左→右へ、重い荷物（4・5）を市松に置くので 4 つつながらず消えない。端数は軽い荷物 1〜3 で埋める。
    /// 重さがすでに `weight` を超えている・敷く場所が足りないときは失敗として止める。
    static func filled(
        weight target: Int, columns: Range<Int> = 0..<OjisanPuzzleBoard.columns,
        topRow: Int = 3, from start: [[Int]] = OjisanPuzzleBoard.emptyBoard()
    ) -> [[Int]] {
        var board = start
        var remaining = target - OjisanPuzzlePain.boardWeight(start)
        precondition(remaining >= 0, "すでに目標の重さを超えている")
        var cells: [(row: Int, col: Int)] = []
        for row in stride(from: OjisanPuzzleBoard.rows - 1, through: topRow, by: -1) {
            for col in columns where start[row][col] == 0 { cells.append((row, col)) }
        }
        var index = 0
        func place(_ kind: Int) {
            precondition(index < cells.count, "敷く場所が足りない")
            board[cells[index].row][cells[index].col] = kind
            index += 1
        }
        while remaining >= 5 {
            let cell = cells[index]
            let kind = (cell.row + cell.col) % 2 == 0 ? 5 : 4
            place(kind)
            remaining -= kind
        }
        if remaining == 4 {
            place(1)
            place(3)
        } else if remaining > 0 {
            place(remaining)
        }
        precondition(OjisanPuzzlePain.boardWeight(board) == target)
        return board
    }

    /// ゲージがちょうど `gauge`（切り捨て）になる盤。
    static func board(gauge: Int) -> [[Int]] {
        filled(weight: (gauge * OjisanPuzzlePain.hospitalWeight + 99) / 100)
    }
}
