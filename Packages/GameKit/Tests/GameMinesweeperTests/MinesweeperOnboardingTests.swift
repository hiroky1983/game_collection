import Testing
import Core
@testable import GameMinesweeper
import CoreTestSupport

/// 図で見る「はじめての遊び方」（#2826）の中身が、実装のルールと食い違っていないこと。
///
/// 地雷の配置は乱数なので、図の盤は中断スナップショットを自作して注入する（`MinesweeperChordTests` と同じ手口）。
@MainActor
@Suite("マインスイーパー: はじめての遊び方")
struct MinesweeperOnboardingTests {
    private static func makeModel(
        rows: Int,
        cols: Int,
        mines: [(row: Int, col: Int)],
        revealed: [(row: Int, col: Int)] = [],
        flagged: [(row: Int, col: Int)] = []
    ) -> MinesweeperModel {
        let mineSet = Set(mines.map { $0.row * cols + $0.col })
        let revealedSet = Set(revealed.map { $0.row * cols + $0.col })
        let flaggedSet = Set(flagged.map { $0.row * cols + $0.col })
        let cells = (0..<rows).map { r in
            (0..<cols).map { c -> MinesweeperSnapshot.CellData in
                var adjacent = 0
                for dr in -1...1 {
                    for dc in -1...1 where !(dr == 0 && dc == 0) {
                        let nr = r + dr, nc = c + dc
                        if nr >= 0, nr < rows, nc >= 0, nc < cols, mineSet.contains(nr * cols + nc) { adjacent += 1 }
                    }
                }
                return MinesweeperSnapshot.CellData(
                    isRevealed: revealedSet.contains(r * cols + c),
                    isFlagged: flaggedSet.contains(r * cols + c),
                    isMine: mineSet.contains(r * cols + c),
                    adjacentMines: adjacent,
                    isContinuedMine: false
                )
            }
        }
        let snapshot = MinesweeperSnapshot(
            rows: rows, cols: cols, totalMines: mines.count, cells: cells,
            flagCount: flaggedSet.count, revealedCount: revealedSet.count, elapsedSeconds: 0
        )
        let store = MemorySnapshotStore()
        try? store.save(snapshot, for: "minesweeper")
        return MinesweeperModel(services: GameServices(snapshots: store, ads: NoopAdService()))
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(MinesweeperOnboarding.guide.isWellFormed)
        #expect(MinesweeperOnboarding.guide.gameID == MinesweeperModel(services: nil).gameID)
    }

    @Test("目的の図: 角をタップすると、図のとおりにまとめて開く")
    func goalFigureOpensAsDrawn() {
        let opened = MinesweeperOnboarding.goalOpened
        let model = Self.makeModel(rows: opened.count, cols: opened[0].count, mines: MinesweeperOnboarding.goalMines)
        model.tap(row: MinesweeperOnboarding.goalTap.row, col: MinesweeperOnboarding.goalTap.col)
        #expect(model.gameState == .playing)
        for (r, line) in opened.enumerated() {
            for (c, ch) in line.enumerated() {
                let cell = model.cells[r][c]
                if let n = ch.wholeNumberValue {
                    #expect(cell.isRevealed && cell.adjacentMines == n, "(\(r), \(c)) が図と違う")
                } else {
                    #expect(!cell.isRevealed, "(\(r), \(c)) は開かないはず")
                }
            }
        }
    }

    @Test("最初にタップしたマスは地雷ではない（どの難易度でも）")
    func firstTapIsSafe() {
        for difficulty in MinesweeperDifficulty.allCases {
            for trial in 0..<20 {
                let model = MinesweeperModel(services: nil, rows: difficulty.rows, cols: difficulty.cols, mines: difficulty.mines)
                let row = trial % difficulty.rows, col = (trial * 7) % difficulty.cols
                model.tap(row: row, col: col)
                #expect(model.gameState != .lost, "\(difficulty) の最初のタップで地雷を踏んだ")
                #expect(model.cells[row][col].isRevealed && !model.cells[row][col].isMine)
            }
        }
    }

    @Test("数字はまわり 8 マスにある地雷の数")
    func numberCountsNeighbours() {
        let model = Self.makeModel(rows: 3, cols: 3, mines: [(0, 2)])
        model.tap(row: 1, col: 1)
        #expect(model.cells[1][1].isRevealed)
        #expect(model.cells[1][1].adjacentMines == 1)
    }

    @Test("旗を立てたマスはタップしても開かない")
    func flaggedCellDoesNotOpen() {
        let model = Self.makeModel(rows: 3, cols: 3, mines: [(0, 0)], revealed: [(1, 1)])
        model.toggleFlag(row: 2, col: 2)
        #expect(model.cells[2][2].isFlagged)
        model.tap(row: 2, col: 2)
        #expect(!model.cells[2][2].isRevealed)
    }

    @Test("まとめて開く: 旗が数字と同じ数なら数字のタップでまわりが開き、旗が違えば地雷を踏む")
    func chord() {
        let right = Self.makeModel(rows: 3, cols: 3, mines: [(0, 0)], revealed: [(1, 1)], flagged: [(0, 0)])
        #expect(right.canChord(row: 1, col: 1))
        right.tap(row: 1, col: 1)
        // 遊び方の図（ChordFigure）の「後」と同じ: 旗のとなりは 1、残りは 0。
        #expect(right.cells[0][1].isRevealed && right.cells[0][1].adjacentMines == 1)
        #expect(right.cells[1][0].isRevealed && right.cells[1][0].adjacentMines == 1)
        #expect(right.cells[2][2].isRevealed && right.cells[2][2].adjacentMines == 0)

        let wrong = Self.makeModel(rows: 3, cols: 3, mines: [(0, 0)], revealed: [(1, 1)], flagged: [(0, 1)])
        wrong.tap(row: 1, col: 1)
        #expect(wrong.gameState == .lost)
    }

    @Test("地雷以外を全部開けたらクリア、地雷を踏むと負け。コンティニューは 1 局に 1 回")
    func winAndLose() {
        let win = Self.makeModel(rows: 2, cols: 2, mines: [(0, 1)], revealed: [(0, 0), (1, 0)])
        win.tap(row: 1, col: 1)
        #expect(win.gameState == .won)

        let lose = Self.makeModel(rows: 3, cols: 3, mines: [(0, 0), (2, 2)], revealed: [(1, 1)])
        lose.tap(row: 0, col: 0)
        #expect(lose.gameState == .lost)
        #expect(lose.canContinue)
        #expect(lose.continueAfterAd())
        #expect(lose.gameState == .playing)
        lose.tap(row: 2, col: 2)
        #expect(lose.gameState == .lost)
        #expect(!lose.canContinue)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in MinesweeperOnboarding.guide.texts + ["角をタップ", "まとめて開いた", "クリア！", "ゲームオーバー"] {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
