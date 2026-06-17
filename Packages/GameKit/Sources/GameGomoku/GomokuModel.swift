import Foundation
import Observation
import Core

struct GomokuSnapshot: Codable {
    let cells: [Int?]
    let currentStone: Int
    let humanSide: Int
    let aiLevel: Int
    let startedAt: Date
}

@MainActor
@Observable
public final class GomokuModel {
    public private(set) var board: GomokuBoard
    public private(set) var currentStone: GomokuStone
    public private(set) var humanSide: GomokuStone
    public private(set) var aiLevel: Int
    public private(set) var winner: GomokuStone?
    public private(set) var isDraw: Bool
    public private(set) var isThinking: Bool
    public private(set) var lastMove: (row: Int, col: Int)?
    public private(set) var moveCount: Int

    private let services: GameServices?
    private let gameID = "gomoku"
    private var startedAt: Date

    public var gameOver: Bool { winner != nil || isDraw }
    public var isAITurn: Bool { !gameOver && currentStone != humanSide }

    public init(services: GameServices? = nil) {
        self.services = services

        let board: GomokuBoard
        let currentStone: GomokuStone
        let humanSide: GomokuStone
        let aiLevel: Int
        let startedAt: Date
        let moveCount: Int

        if let snap = services?.snapshots.load(GomokuSnapshot.self, for: "gomoku") {
            let cells = snap.cells.map { $0.flatMap { GomokuStone(rawValue: $0) } }
            board        = GomokuBoard(cells: cells)
            currentStone = GomokuStone(rawValue: snap.currentStone) ?? .black
            humanSide    = GomokuStone(rawValue: snap.humanSide)    ?? .black
            aiLevel      = snap.aiLevel
            startedAt    = snap.startedAt
            moveCount    = cells.compactMap { $0 }.count
        } else {
            board        = GomokuBoard()
            currentStone = .black
            humanSide    = .black
            aiLevel      = 1
            startedAt    = Date()
            moveCount    = 0
        }

        self.board        = board
        self.currentStone = currentStone
        self.humanSide    = humanSide
        self.aiLevel      = aiLevel
        self.startedAt    = startedAt
        self.moveCount    = moveCount
        self.winner       = nil
        self.isDraw       = false
        self.isThinking   = false
        self.lastMove     = nil
    }

    public func tap(row: Int, col: Int) {
        guard !gameOver, !isAITurn, board[row, col] == nil else { return }
        place(row: row, col: col)
    }

    private func place(row: Int, col: Int) {
        board[row, col] = currentStone
        lastMove = (row, col)
        moveCount += 1
        if board.checkWin(row: row, col: col) {
            winner = currentStone
        } else if board.isFull {
            isDraw = true
        } else {
            currentStone = currentStone.opponent
        }
        persist()
    }

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        isThinking = true
        defer { isThinking = false }

        let b = board
        let s = currentStone
        let level = aiLevel

        let move = await Task.detached(priority: .userInitiated) {
            await SimpleGomokuEngine(level: level).bestMove(board: b, stone: s)
        }.value

        guard isAITurn, let (r, c) = move else { return }
        place(row: r, col: c)
    }

    public func newGame(humanSide: GomokuStone = .black, aiLevel: Int = 1) {
        board         = GomokuBoard()
        currentStone  = .black
        self.humanSide = humanSide
        self.aiLevel  = aiLevel
        winner        = nil
        isDraw        = false
        lastMove      = nil
        moveCount     = 0
        startedAt     = Date()
        persist()
    }

    private func persist() {
        let snap = GomokuSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: currentStone.rawValue,
            humanSide: humanSide.rawValue,
            aiLevel: aiLevel,
            startedAt: startedAt
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }
}
