import Foundation
import Observation
import Core

struct OthelloSnapshot: Codable {
    let cells: [Int?]
    let currentStone: Int
    let humanSide: Int
    let aiLevel: Int
    let startedAt: Date
    let winner: Int?
    let isDraw: Bool
    let mustPass: Bool?
    let turnID: Int?
}

@MainActor
@Observable
public final class OthelloModel {
    public private(set) var board: OthelloBoard
    public private(set) var currentStone: OthelloStone
    public private(set) var humanSide: OthelloStone
    public private(set) var aiLevel: Int
    public private(set) var winner: OthelloStone?
    public private(set) var isDraw: Bool
    public private(set) var isThinking: Bool
    public private(set) var lastMove: (row: Int, col: Int)?
    public private(set) var mustPass: Bool
    public private(set) var turnID: Int

    private let services: GameServices?
    private let gameID = "othello"
    private var startedAt: Date

    public var gameOver: Bool { winner != nil || isDraw }
    public var isAITurn: Bool { !gameOver && currentStone != humanSide }
    public var blackCount: Int { board.count(for: .black) }
    public var whiteCount: Int { board.count(for: .white) }

    public init(services: GameServices? = nil) {
        self.services = services

        if let snap = services?.snapshots.load(OthelloSnapshot.self, for: "othello") {
            let cells = snap.cells.map { $0.flatMap { OthelloStone(rawValue: $0) } }
            board        = OthelloBoard(cells: cells)
            currentStone = OthelloStone(rawValue: snap.currentStone) ?? .black
            humanSide    = OthelloStone(rawValue: snap.humanSide) ?? .black
            aiLevel      = snap.aiLevel
            startedAt    = snap.startedAt
            winner       = snap.winner.flatMap { OthelloStone(rawValue: $0) }
            isDraw       = snap.isDraw
            mustPass     = snap.mustPass ?? false
            turnID       = snap.turnID ?? 0
        } else {
            board        = OthelloBoard()
            currentStone = .black
            humanSide    = .black
            aiLevel      = 1
            startedAt    = Date()
            winner       = nil
            isDraw       = false
            mustPass     = false
            turnID       = 0
        }
        isThinking = false
        lastMove   = nil
    }

    public func tap(row: Int, col: Int) {
        guard !gameOver, !isAITurn, !mustPass else { return }
        guard board.isValid(row: row, col: col, stone: currentStone) else { return }
        place(row: row, col: col)
    }

    public func confirmPass() {
        guard mustPass, !gameOver else { return }
        mustPass     = false
        currentStone = currentStone.opponent
        turnID      += 1
        checkTermination()
        persist()
    }

    public func resign() {
        guard !gameOver else { return }
        winner = humanSide.opponent
        persist()
    }

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking, !gameOver else { return }

        if mustPass {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard isAITurn else { return }
            confirmPass()
            return
        }

        isThinking = true
        defer { isThinking = false }

        let b = board, s = currentStone, lvl = aiLevel
        let move = await Task.detached(priority: .userInitiated) {
            await OthelloEngine(level: lvl).bestMove(board: b, stone: s)
        }.value

        guard isAITurn, !gameOver else { return }
        if let (r, c) = move { place(row: r, col: c) }
    }

    public func newGame(humanSide: OthelloStone = .black, aiLevel: Int = 1) {
        board          = OthelloBoard()
        currentStone   = .black
        self.humanSide = humanSide
        self.aiLevel   = aiLevel
        winner         = nil
        isDraw         = false
        lastMove       = nil
        mustPass       = false
        turnID         = 0
        startedAt      = Date()
        persist()
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    private func place(row: Int, col: Int) {
        board.place(row: row, col: col, stone: currentStone)
        lastMove     = (row, col)
        currentStone = currentStone.opponent
        turnID      += 1
        checkTermination()
        persist()
    }

    private func checkTermination() {
        if board.isFull { resolveWinner(); return }
        if board.validMoves(for: currentStone).isEmpty {
            if board.validMoves(for: currentStone.opponent).isEmpty {
                resolveWinner()
            } else {
                mustPass = true
            }
        }
    }

    private func resolveWinner() {
        let b = blackCount, w = whiteCount
        if b > w { winner = .black } else if w > b { winner = .white } else { isDraw = true }
    }

    private func persist() {
        let snap = OthelloSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: currentStone.rawValue,
            humanSide: humanSide.rawValue,
            aiLevel: aiLevel,
            startedAt: startedAt,
            winner: winner?.rawValue,
            isDraw: isDraw,
            mustPass: mustPass ? true : nil,
            turnID: turnID
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
