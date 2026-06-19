import Foundation
import Observation
import Core

struct SudokuSnapshot: Codable {
    let board: [Int]
    let given: [Bool]
    let solution: [Int]
    let notes: [[Bool]]
    let elapsedSeconds: Int
    let hintsUsed: Int
    let difficulty: Int
    let hintedCells: [Int]
}

@MainActor
@Observable
public final class SudokuModel {
    public static let maxHints = 3

    public private(set) var board: [Int]
    public private(set) var given: [Bool]
    public private(set) var solution: [Int]
    public private(set) var notes: [[Bool]]       // 81 × 9
    public private(set) var selected: Int?
    public private(set) var isComplete: Bool = false
    public private(set) var isGenerating: Bool = false
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var hintsUsed: Int = 0
    public private(set) var noteMode: Bool = false
    public private(set) var difficulty: Int = 1
    public private(set) var hintedCells: Set<Int> = []

    private let services: GameServices?
    private let gameID = "sudoku"
    private var timerTask: Task<Void, Never>?

    public var hasGame: Bool       { given.contains(true) }
    public var remainingHints: Int { Self.maxHints - hintsUsed }
    public var canHint: Bool {
        !isComplete && !isGenerating && hintsUsed < Self.maxHints
        && selected.map { board[$0] != solution[$0] } ?? false
    }

    public var errorCells: Set<Int> {
        Set((0..<81).filter { !given[$0] && board[$0] != 0 && board[$0] != solution[$0] })
    }

    public var highlightedCells: Set<Int> {
        guard let sel = selected else { return [] }
        let r = sel / 9, c = sel % 9
        let br = (r / 3) * 3, bc = (c / 3) * 3
        var result = Set<Int>()
        for i in 0..<9 { result.insert(r * 9 + i); result.insert(i * 9 + c) }
        for dr in 0..<3 { for dc in 0..<3 { result.insert((br + dr) * 9 + bc + dc) } }
        result.remove(sel)
        return result
    }

    public var sameDigitCells: Set<Int> {
        guard let sel = selected, board[sel] != 0 else { return [] }
        let d = board[sel]
        return Set((0..<81).filter { board[$0] == d })
    }

    public init(services: GameServices? = nil) {
        self.services = services
        board    = [Int](repeating: 0, count: 81)
        given    = [Bool](repeating: false, count: 81)
        solution = [Int](repeating: 0, count: 81)
        notes    = [[Bool]](repeating: [Bool](repeating: false, count: 9), count: 81)

        if let snap = services?.snapshots.load(SudokuSnapshot.self, for: "sudoku") {
            board          = snap.board
            given          = snap.given
            solution       = snap.solution
            notes          = snap.notes
            elapsedSeconds = snap.elapsedSeconds
            hintsUsed      = snap.hintsUsed
            difficulty     = snap.difficulty
            hintedCells    = Set(snap.hintedCells)
        }
    }

    // MARK: - Game lifecycle

    public func newGame(difficulty: Int) async {
        isGenerating = true
        timerTask?.cancel()
        timerTask      = nil
        elapsedSeconds = 0
        selected       = nil

        let diff = difficulty
        let result = await Task.detached(priority: .userInitiated) {
            SudokuEngine.generate(difficulty: diff)
        }.value

        board           = result.board
        given           = result.board.map { $0 != 0 }
        solution        = result.solution
        notes           = [[Bool]](repeating: [Bool](repeating: false, count: 9), count: 81)
        isComplete      = false
        hintsUsed       = 0
        noteMode        = false
        hintedCells     = []
        self.difficulty = difficulty
        isGenerating    = false

        persist()
        startTimer()
    }

    // MARK: - Actions

    public func select(index: Int) {
        guard !isComplete, !isGenerating else { return }
        selected = (selected == index) ? nil : index
    }

    public func enter(digit: Int) {
        guard let sel = selected, !given[sel], !isComplete, !isGenerating else { return }
        if noteMode && digit != 0 {
            notes[sel][digit - 1].toggle()
        } else {
            board[sel] = digit
            if digit != 0 {
                notes[sel] = [Bool](repeating: false, count: 9)
                if board[sel] == solution[sel] { clearPeerNotes(for: sel, digit: digit) }
            }
            checkCompletion()
        }
        persist()
    }

    public func requestHint() async {
        guard canHint, let sel = selected, board[sel] != solution[sel] else { return }
        await services?.ads.showInterstitial()
        board[sel]    = solution[sel]
        notes[sel]    = [Bool](repeating: false, count: 9)
        hintsUsed    += 1
        hintedCells.insert(sel)
        clearPeerNotes(for: sel, digit: solution[sel])
        checkCompletion()
        persist()
    }

    public func toggleNoteMode() { noteMode.toggle() }

    public func resumeTimerIfNeeded() {
        guard !isComplete, !isGenerating, hasGame, timerTask == nil else { return }
        startTimer()
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - Private helpers

    private func clearPeerNotes(for index: Int, digit: Int) {
        let r = index / 9, c = index % 9
        let br = (r / 3) * 3, bc = (c / 3) * 3
        var peers = Set<Int>()
        for i in 0..<9 { peers.insert(r * 9 + i); peers.insert(i * 9 + c) }
        for dr in 0..<3 { for dc in 0..<3 { peers.insert((br + dr) * 9 + bc + dc) } }
        peers.remove(index)
        for p in peers { notes[p][digit - 1] = false }
    }

    private func checkCompletion() {
        guard (0..<81).allSatisfy({ board[$0] == solution[$0] }) else { return }
        isComplete = true
        timerTask?.cancel()
        timerTask  = nil
        services?.snapshots.clear(for: gameID)
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

    private func persist() {
        guard !isComplete, !isGenerating else { return }
        let snap = SudokuSnapshot(
            board: board,
            given: given,
            solution: solution,
            notes: notes,
            elapsedSeconds: elapsedSeconds,
            hintsUsed: hintsUsed,
            difficulty: difficulty,
            hintedCells: Array(hintedCells)
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
