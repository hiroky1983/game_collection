import Foundation
import Observation
import Core

struct GomokuMoveRecord: Codable {
    let row: Int
    let col: Int
    let stone: Int
}

struct GomokuSnapshot: Codable {
    let cells: [Int?]
    let currentStone: Int
    let humanSide: Int
    let aiLevel: Int
    let startedAt: Date
    let moveHistory: [GomokuMoveRecord]?
    let undoUsed: Bool?
    let resigned: Bool?
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
    public private(set) var undoUsed: Bool
    private var resigned: Bool

    private let services: GameServices?
    private let gameID = "gomoku"
    private var startedAt: Date
    private var moves: [(row: Int, col: Int, stone: GomokuStone)]

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
        let moves: [(row: Int, col: Int, stone: GomokuStone)]
        let lastMove: (row: Int, col: Int)?
        let undoUsed: Bool
        let resigned: Bool

        if let snap = services?.snapshots.load(GomokuSnapshot.self, for: "gomoku") {
            humanSide = GomokuStone(rawValue: snap.humanSide) ?? .black
            aiLevel   = snap.aiLevel
            startedAt = snap.startedAt
            if let history = snap.moveHistory {
                let parsed = history.compactMap { rec -> (Int, Int, GomokuStone)? in
                    guard let stone = GomokuStone(rawValue: rec.stone) else { return nil }
                    return (rec.row, rec.col, stone)
                }
                moves     = parsed
                board     = Self.board(from: parsed)
                moveCount = parsed.count
                if let last = parsed.last {
                    lastMove      = (last.0, last.1)
                    currentStone  = last.2.opponent
                } else {
                    lastMove     = nil
                    currentStone = .black
                }
            } else {
                let cells = snap.cells.map { $0.flatMap { GomokuStone(rawValue: $0) } }
                board        = GomokuBoard(cells: cells)
                currentStone = GomokuStone(rawValue: snap.currentStone) ?? .black
                moveCount    = cells.compactMap { $0 }.count
                moves        = []
                lastMove     = nil
            }
            undoUsed = snap.undoUsed ?? false
            resigned = snap.resigned ?? false
        } else {
            board        = GomokuBoard()
            currentStone = .black
            humanSide    = .black
            aiLevel      = 1
            startedAt    = Date()
            moveCount    = 0
            moves        = []
            lastMove     = nil
            undoUsed     = false
            resigned     = false
        }

        self.board        = board
        self.currentStone = currentStone
        self.humanSide    = humanSide
        self.aiLevel      = aiLevel
        self.startedAt    = startedAt
        self.moveCount    = moveCount
        self.moves        = moves
        self.winner       = resigned ? humanSide.opponent : nil
        self.isDraw       = false
        self.isThinking   = false
        self.lastMove     = lastMove
        self.undoUsed     = undoUsed
        self.resigned     = resigned
    }

    public func tap(row: Int, col: Int) {
        guard !gameOver, !isAITurn, board[row, col] == nil else { return }
        place(row: row, col: col)
    }

    private func place(row: Int, col: Int) {
        board[row, col] = currentStone
        moves.append((row, col, currentStone))
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
        board          = GomokuBoard()
        currentStone   = .black
        self.humanSide = humanSide
        self.aiLevel   = aiLevel
        winner         = nil
        isDraw         = false
        lastMove       = nil
        moveCount      = 0
        moves          = []
        undoUsed       = false
        resigned       = false
        startedAt      = Date()
        persist()
    }

    // MARK: - 投了

    public func resign() {
        guard !gameOver else { return }
        resigned = true
        winner = humanSide.opponent
        persist()
    }

    // MARK: - 待った（自分の直前手＋CPU 応手の 2 手を戻す）

    private func mover(at index: Int) -> GomokuStone {
        index % 2 == 0 ? .black : .white
    }

    /// 人間の手番で、直前の自分の手と CPU 応手をまとめて戻せるか。
    public var canUndo: Bool {
        guard !gameOver, !isAITurn, !isThinking else { return false }
        let n = moves.count
        guard n >= 2 else { return false }
        return mover(at: n - 1) == humanSide.opponent && mover(at: n - 2) == humanSide
    }

    /// 待った: 直前 2 手（人間→CPU）を巻き戻し、人間が指し直せる状態にする。
    public func undoLastExchange() {
        guard canUndo else { return }
        moves.removeLast(2)
        board        = Self.board(from: moves)
        moveCount    = moves.count
        winner       = nil
        isDraw       = false
        undoUsed     = true
        if let last = moves.last {
            lastMove     = (last.row, last.col)
            currentStone = last.stone.opponent
        } else {
            lastMove     = nil
            currentStone = .black
        }
        persist()
    }

    private static func board(from moves: [(row: Int, col: Int, stone: GomokuStone)]) -> GomokuBoard {
        var board = GomokuBoard()
        for move in moves {
            board[move.row, move.col] = move.stone
        }
        return board
    }

    private func persist() {
        let snap = GomokuSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: currentStone.rawValue,
            humanSide: humanSide.rawValue,
            aiLevel: aiLevel,
            startedAt: startedAt,
            moveHistory: moves.map { GomokuMoveRecord(row: $0.row, col: $0.col, stone: $0.stone.rawValue) },
            undoUsed: undoUsed,
            resigned: resigned ? true : nil
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }
}
