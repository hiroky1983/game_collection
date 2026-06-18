import Foundation
import Observation
import Core

public enum MinesweeperState: Equatable, Sendable {
    case idle, playing, won, lost
}

public struct MinesweeperCell: Sendable {
    public var isRevealed    = false
    public var isFlagged     = false
    public var isMine        = false
    public var adjacentMines = 0
}

@MainActor
@Observable
public final class MinesweeperModel {
    public private(set) var cells: [[MinesweeperCell]]
    public private(set) var gameState: MinesweeperState = .idle
    public private(set) var rows: Int
    public private(set) var cols: Int
    public private(set) var totalMines: Int
    public private(set) var flagCount: Int = 0
    public private(set) var revealedCount: Int = 0
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var hitMine: (row: Int, col: Int)?

    private var timerTask: Task<Void, Never>?

    public var remainingMines: Int { totalMines - flagCount }
    public var safeCellCount: Int  { rows * cols - totalMines }
    public var gameOver: Bool      { gameState == .won || gameState == .lost }

    public init(rows: Int = 9, cols: Int = 9, mines: Int = 10) {
        self.rows       = rows
        self.cols       = cols
        self.totalMines = mines
        self.cells      = Self.emptyBoard(rows: rows, cols: cols)
    }

    // MARK: - New game

    public func newGame(rows: Int, cols: Int, mines: Int) {
        timerTask?.cancel()
        timerTask      = nil
        self.rows       = rows
        self.cols       = cols
        self.totalMines = mines
        self.cells      = Self.emptyBoard(rows: rows, cols: cols)
        self.gameState  = .idle
        self.flagCount  = 0
        self.revealedCount = 0
        self.elapsedSeconds = 0
        self.hitMine    = nil
    }

    // MARK: - Actions

    public func tap(row: Int, col: Int) {
        guard !gameOver,
              !cells[row][col].isRevealed,
              !cells[row][col].isFlagged else { return }

        if gameState == .idle {
            placeMines(avoiding: row, col: col)
            gameState = .playing
            startTimer()
        }

        if cells[row][col].isMine {
            hitMine = (row, col)
            revealAllMines()
            gameState = .lost
            timerTask?.cancel()
            timerTask = nil
            return
        }

        floodReveal(row: row, col: col)

        if revealedCount == safeCellCount {
            flagAllMines()
            gameState = .won
            timerTask?.cancel()
            timerTask = nil
        }
    }

    public func toggleFlag(row: Int, col: Int) {
        guard !gameOver, !cells[row][col].isRevealed else { return }
        if cells[row][col].isFlagged {
            cells[row][col].isFlagged = false
            flagCount -= 1
        } else {
            cells[row][col].isFlagged = true
            flagCount += 1
        }
    }

    // MARK: - Private helpers

    private func floodReveal(row: Int, col: Int) {
        var queue = [(row, col)]
        var i = 0
        while i < queue.count {
            let (r, c) = queue[i]; i += 1
            guard r >= 0, r < rows, c >= 0, c < cols,
                  !cells[r][c].isRevealed,
                  !cells[r][c].isFlagged,
                  !cells[r][c].isMine else { continue }
            cells[r][c].isRevealed = true
            revealedCount += 1
            if cells[r][c].adjacentMines == 0 {
                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        queue.append((r + dr, c + dc))
                    }
                }
            }
        }
    }

    private func revealAllMines() {
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isMine && !cells[r][c].isFlagged {
                cells[r][c].isRevealed = true
            }
        }
    }

    private func flagAllMines() {
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isMine && !cells[r][c].isFlagged {
                cells[r][c].isFlagged = true
                flagCount += 1
            }
        }
    }

    private func placeMines(avoiding safeRow: Int, col safeCol: Int) {
        var excluded = Set<Int>()
        for dr in -1...1 {
            for dc in -1...1 {
                let r = safeRow + dr, c = safeCol + dc
                if r >= 0, r < rows, c >= 0, c < cols {
                    excluded.insert(r * cols + c)
                }
            }
        }
        var candidates = (0..<rows * cols).filter { !excluded.contains($0) }.shuffled()
        if candidates.count < totalMines {
            candidates = (0..<rows * cols).filter { $0 != safeRow * cols + safeCol }.shuffled()
        }
        for i in 0..<min(totalMines, candidates.count) {
            cells[candidates[i] / cols][candidates[i] % cols].isMine = true
        }
        for r in 0..<rows {
            for c in 0..<cols {
                guard !cells[r][c].isMine else { continue }
                var count = 0
                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        let nr = r + dr, nc = c + dc
                        if nr >= 0, nr < rows, nc >= 0, nc < cols, cells[nr][nc].isMine {
                            count += 1
                        }
                    }
                }
                cells[r][c].adjacentMines = count
            }
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                elapsedSeconds += 1
            }
        }
    }

    private static func emptyBoard(rows: Int, cols: Int) -> [[MinesweeperCell]] {
        Array(repeating: Array(repeating: MinesweeperCell(), count: cols), count: rows)
    }
}
