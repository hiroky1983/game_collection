import Foundation
import Observation
import Core

public enum MinesweeperState: Equatable, Sendable {
    case idle, playing, won, lost
}

public struct MinesweeperCell: Sendable {
    public var isRevealed      = false
    public var isFlagged       = false
    public var isMine          = false
    public var adjacentMines   = 0
    public var isContinuedMine = false  // コンティニューで確定した爆弾マス
    /// このマスが開いたときの連鎖の波（タップ地点からの距離・#203）。
    ///
    /// View が「開く演出をどれだけ遅らせるか」を決めるためだけに使う表示用の値で、
    /// ゲームの進行には影響しない。中断スナップショットにも含めない
    /// （復元したマスは最初から開いているので演出を再生する余地が無い）。
    public var revealWave      = 0
}

struct MinesweeperSnapshot: Codable {
    let rows: Int
    let cols: Int
    let totalMines: Int
    let cells: [[CellData]]
    let flagCount: Int
    let revealedCount: Int
    let elapsedSeconds: Int

    struct CellData: Codable {
        let isRevealed: Bool
        let isFlagged: Bool
        let isMine: Bool
        let adjacentMines: Int
        let isContinuedMine: Bool
    }
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
    /// 直近の終局で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private var timerTask: Task<Void, Never>?
    private let services: GameServices?
    private let gameID = "minesweeper"

    public var remainingMines: Int { totalMines - flagCount }
    public var safeCellCount: Int  { rows * cols - totalMines }
    public var gameOver: Bool      { gameState == .won || gameState == .lost }

    /// 記録を分ける区分のキー。盤の大きさと地雷数が同じものを同じ難易度として扱う。
    /// 難易度の enum を持たない（View が rows/cols/mines を直接渡す）ため、盤の構成から導く。
    private var recordVariant: String { "\(rows)x\(cols)-\(totalMines)" }

    /// 区分の表示名。新規対局シートのプリセット3種は日本語名、それ以外は盤サイズで表す。
    private var recordVariantLabel: String {
        switch (rows, cols, totalMines) {
        case (9, 9, 10):    return "初級"
        case (12, 12, 25):  return "中級"
        case (15, 15, 40):  return "上級"
        // 区分は地雷数込みで分かれるため、ラベルにも地雷数を入れて別区分だと分かるようにする。
        default:            return "\(rows)×\(cols)・地雷\(totalMines)"
        }
    }

    /// 今の対局の成績。クリアタイムは勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    private var currentScore: GameScore {
        GameScore(
            metric: .shortestTime,
            seconds: elapsedSeconds,
            variant: recordVariant,
            variantLabel: recordVariantLabel
        )
    }

    public init(services: GameServices? = nil, rows: Int = 9, cols: Int = 9, mines: Int = 10) {
        self.services = services

        if let snap = services?.snapshots.load(MinesweeperSnapshot.self, for: "minesweeper") {
            self.rows          = snap.rows
            self.cols          = snap.cols
            self.totalMines    = snap.totalMines
            self.flagCount     = snap.flagCount
            self.revealedCount = snap.revealedCount
            self.elapsedSeconds = snap.elapsedSeconds
            self.gameState     = .playing
            self.cells = snap.cells.map { row in
                row.map { data in
                    var cell = MinesweeperCell()
                    cell.isRevealed    = data.isRevealed
                    cell.isFlagged     = data.isFlagged
                    cell.isMine        = data.isMine
                    cell.adjacentMines = data.adjacentMines
                    cell.isContinuedMine = data.isContinuedMine
                    return cell
                }
            }
        } else {
            self.rows       = rows
            self.cols       = cols
            self.totalMines = mines
            self.cells      = Self.emptyBoard(rows: rows, cols: cols)
        }
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
        self.recordResult = nil
        persist()
    }

    // MARK: - Timer resume (call from onAppear when restoring saved game)

    public func resumeTimerIfNeeded() {
        guard gameState == .playing, timerTask == nil else { return }
        startTimer()
    }

    // MARK: - Actions

    /// このマスを開けるか。VoiceOver に「いま何ができるか」を伝えるためにも使うので、
    /// 判定を `tap` の中に埋めずここに出しておく（二重管理で食い違わせないため・#188）。
    public func canReveal(row: Int, col: Int) -> Bool {
        !gameOver && !cells[row][col].isRevealed && !cells[row][col].isFlagged
    }

    /// このマスの旗を立て下ろしできるか。開き済み・確定爆弾マスには置けない。
    public func canToggleFlag(row: Int, col: Int) -> Bool {
        !gameOver && !cells[row][col].isRevealed && !cells[row][col].isContinuedMine
    }

    public func tap(row: Int, col: Int) {
        guard !gameOver else { return }
        guard canReveal(row: row, col: col) else {
            services?.feedback.notify(.warning) // 開き済み・旗付きマスは開けない
            return
        }

        if gameState == .idle {
            placeMines(avoiding: row, col: col)
            gameState = .playing
            startTimer()
            // 地雷を置いて計時が始まるここが 1 プレイの開始（#158）。
            // 盤を用意しただけの `.idle` や、中断からの復元（`.playing` で始まる）では数えない。
            services?.gameDidRestart(gameID: gameID)
        }

        if cells[row][col].isMine {
            hitMine = (row, col)
            revealAllMines()
            gameState = .lost
            timerTask?.cancel()
            timerTask = nil
            services?.feedback.notify(.error)
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        } else {
            floodReveal(row: row, col: col)

            if revealedCount == safeCellCount {
                flagAllMines()
                gameState = .won
                timerTask?.cancel()
                timerTask = nil
                services?.feedback.notify(.success)
                recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
            } else {
                services?.feedback.impact(.light)
            }
        }

        persist()
    }

    // MARK: - Continue

    public func continueAfterAd() {
        guard gameState == .lost, let hit = hitMine else { return }
        // 同じ盤面の続きなので、直前に記録した「負け」は無かったことにする
        // （そのままだと1回のプレイが2回分として数えられる）。
        services?.playLog?.cancelLoss(gameID: gameID, variant: recordVariant)
        recordResult = nil

        // ゲームオーバーで露出した地雷を再び隠す
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isMine && !cells[r][c].isFlagged {
                cells[r][c].isRevealed = false
                // 隠し直したマスは次に開くときの起点になるので、古い波を残さない（#203）。
                cells[r][c].revealWave = 0
            }
        }

        // 踏んだ地雷は専用マークで確定爆弾として残す
        cells[hit.row][hit.col].isFlagged       = true
        cells[hit.row][hit.col].isContinuedMine = true
        flagCount += 1
        hitMine = nil
        gameState = .playing
        startTimer()
        // `game_end` はもう送信済みなので、続きは次の1プレイとして数える（#158）。
        services?.gameDidRestart(gameID: gameID)

        // すでに全安全マスを開けていた場合（まずないが念のため）
        if revealedCount == safeCellCount {
            flagAllMines()
            gameState = .won
            timerTask?.cancel()
            timerTask = nil
            services?.feedback.notify(.success)
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
        }

        persist()
    }

    public func toggleFlag(row: Int, col: Int) {
        guard !gameOver else { return }
        guard canToggleFlag(row: row, col: col) else {
            services?.feedback.notify(.warning) // 開き済み・確定爆弾マスには旗を置けない
            return
        }
        if cells[row][col].isFlagged {
            cells[row][col].isFlagged = false
            flagCount -= 1
        } else {
            cells[row][col].isFlagged = true
            flagCount += 1
        }
        services?.feedback.impact(.rigid)
        persist()
    }

    public func giveUp() {
        guard gameState == .playing else { return }
        revealAllMines()
        gameState = .lost
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        timerTask?.cancel()
        timerTask = nil
        services?.snapshots.clear(for: gameID)
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - Private helpers

    private func persist() {
        guard gameState == .playing else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = MinesweeperSnapshot(
            rows: rows,
            cols: cols,
            totalMines: totalMines,
            cells: cells.map { row in
                row.map { cell in
                    MinesweeperSnapshot.CellData(
                        isRevealed: cell.isRevealed,
                        isFlagged: cell.isFlagged,
                        isMine: cell.isMine,
                        adjacentMines: cell.adjacentMines,
                        isContinuedMine: cell.isContinuedMine
                    )
                }
            },
            flagCount: flagCount,
            revealedCount: revealedCount,
            elapsedSeconds: elapsedSeconds
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    /// タップ地点から幅優先で開いていく。**探索の深さを `revealWave` として各マスに残す**（#203）。
    ///
    /// FIFO で処理するので波は必ず非減少に並び、同じ波のマスは同じ遅延で一斉に開く。
    /// 深さを持たせるだけなので探索そのものの計算量は従来と変わらない。
    private func floodReveal(row: Int, col: Int) {
        var queue = [(row: row, col: col, wave: 0)]
        var i = 0
        while i < queue.count {
            let (r, c, wave) = queue[i]; i += 1
            guard r >= 0, r < rows, c >= 0, c < cols,
                  !cells[r][c].isRevealed,
                  !cells[r][c].isFlagged,
                  !cells[r][c].isMine else { continue }
            cells[r][c].isRevealed = true
            cells[r][c].revealWave = wave
            revealedCount += 1
            if cells[r][c].adjacentMines == 0 {
                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        queue.append((r + dr, c + dc, wave + 1))
                    }
                }
            }
        }
    }

    private func revealAllMines() {
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isMine && !cells[r][c].isFlagged {
                cells[r][c].isRevealed = true
                // 決着時の一斉公開は連鎖ではないので波を持たせない（全マス同時に出す・#203）。
                cells[r][c].revealWave = 0
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
