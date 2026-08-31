import Foundation
import Observation
import Core

struct GomokuMoveRecord: Codable {
    let row: Int
    let col: Int
    let stone: Int
}

/// 着手が拒否された理由（#202）。
///
/// 判定は Model 側に集約する（`FeedbackService` の規約どおり。View のタップハンドラで
/// 早期 return すると、その分岐だけフィードバックを付け忘れる）。View はこれを見て
/// 震え演出のトリガーにするだけで、判定そのものは持たない。
/// 決着後のタップは含まない。結果表示と「もう一度」が出ている状態で盤を触るのは
/// 誤操作ではないため、拒否として鳴らすと雑音になる。
public enum GomokuTapRejection: Equatable, Sendable {
    /// CPU の手番・思考中のタップ。
    case notYourTurn
    /// 盤の外（格子の範囲外）へのタップ。
    case outOfBoard
    /// 既に石が置かれている交点へのタップ。
    case occupied
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
    let winner: Int?
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
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial: Int = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?
    /// 拒否されたタップの通し番号（#202）。View はこの値の変化を震え演出のトリガーにする。
    /// 同じ理由で連続して拒否されても毎回震えるよう、理由ではなく回数を見せる。
    public private(set) var rejectedTapCount: Int = 0
    /// 直近の拒否理由（#202）。フィードバックの内訳をテストから確かめるために公開する。
    public private(set) var lastRejection: GomokuTapRejection?
    private var resigned: Bool

    private let services: GameServices?
    private let gameID = "gomoku"
    private var startedAt: Date
    private var moves: [(row: Int, col: Int, stone: GomokuStone)]

    public var gameOver: Bool { winner != nil || isDraw }
    public var isAITurn: Bool { !gameOver && currentStone != humanSide }

    /// View の `.task(id:)` に渡す CPU 起動トリガー。
    /// 手数だけだと「0 手のまま後手で新規対局を始めた」ときに値が変わらず、
    /// CPU の初手が起動しない（#140。将棋 #82 と同じ原因）。対局の通し番号と組にする。
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: moveCount) }

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
        let savedWinner: GomokuStone?
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = false

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
            undoUsed    = snap.undoUsed ?? false
            resigned    = snap.resigned ?? false
            savedWinner = snap.winner.flatMap { GomokuStone(rawValue: $0) }
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
            savedWinner  = nil
            isFreshStart = true
        }

        self.board        = board
        self.currentStone = currentStone
        self.humanSide    = humanSide
        self.aiLevel      = aiLevel
        self.startedAt    = startedAt
        self.moveCount    = moveCount
        self.moves        = moves
        // savedWinner が最優先。なければ resign フラグで補完（旧スナップショット互換）
        self.winner       = savedWinner ?? (resigned ? humanSide.opponent : nil)
        self.isDraw       = (savedWinner == nil && !resigned && board.isFull)
        self.isThinking   = false
        self.lastMove     = lastMove
        self.undoUsed     = undoUsed
        self.resigned     = resigned
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshStart { services?.gameDidStart(gameID: gameID) }
    }

    /// 盤面へのタップ。**盤外の座標を渡してよい**（範囲判定もここで行う）。
    ///
    /// 打てない理由はすべて `reject(_:)` を通す。View 側で早期 return させると、
    /// 「タップしたのに何も起きない = アプリが固まったように見える」状態が残る（#202）。
    public func tap(row: Int, col: Int) {
        // 決着後は結果表示が出ているので、拒否として鳴らさず黙って無視する。
        guard !gameOver else { return }
        guard !isAITurn else { return reject(.notYourTurn) }
        guard row >= 0, row < gomokuBoardSize,
              col >= 0, col < gomokuBoardSize else { return reject(.outOfBoard) }
        guard board[row, col] == nil else { return reject(.occupied) }
        place(row: row, col: col)
    }

    /// 打てないタップを記録し、触覚・効果音で拒否を伝える（#202）。
    private func reject(_ reason: GomokuTapRejection) {
        lastRejection = reason
        rejectedTapCount += 1
        services?.feedback.notify(.warning)
    }

    private func place(row: Int, col: Int) {
        let mover = currentStone
        board[row, col] = currentStone
        moves.append((row, col, currentStone))
        lastMove = (row, col)
        moveCount += 1
        if board.checkWin(row: row, col: col) {
            winner = currentStone
            services?.feedback.notify(mover == humanSide ? .success : .error)
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: mover == humanSide ? .win : .loss,
                score: GameScore(metric: .winLoss)
            )
        } else if board.isFull {
            isDraw = true
            services?.feedback.notify(.warning)
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .draw, score: GameScore(metric: .winLoss))
        } else {
            currentStone = currentStone.opponent
            // 着手の手応えは自分が指したときだけ。CPU の着手では鳴らさない。
            if mover == humanSide { services?.feedback.impact(.medium) }
        }
        persist()
    }

    #if DEBUG
    /// 撮影用（#366）: 中盤風の盤面を作る（`-gomokuMidgame` 起動引数）。
    /// 五連にならない固定手順で、人間（黒）の手番で止まるため CPU は動き出さない。
    public func applyPreviewMidgameForTesting() {
        guard moveCount == 0, !gameOver else { return }
        let preset: [(Int, Int)] = [(7, 7), (7, 8), (8, 8), (8, 7), (6, 8),
                                    (6, 7), (8, 6), (7, 6), (9, 7), (9, 9)]
        for (row, col) in preset where board[row, col] == nil && !gameOver {
            place(row: row, col: col)
        }
    }
    #endif

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        // 計算中に新規対局が始まると、旧盤面で選んだ手が新しい盤面に着手されてしまう。
        // 計算開始時のトリガー（対局の通し番号 × 手数）を控え、完了時に一致する場合だけ着手する。
        let key = aiTurnKey
        let serial = gameSerial
        isThinking = true
        // 別対局が始まっていたら、思考フラグの持ち主は新しい対局のタスクなので触らない。
        defer { if gameSerial == serial { isThinking = false } }

        let b = board
        let s = currentStone
        let level = aiLevel

        let move = await Task.detached(priority: .userInitiated) {
            await SimpleGomokuEngine(level: level).bestMove(board: b, stone: s)
        }.value

        guard aiTurnKey == key, isAITurn, let (r, c) = move, board[r, c] == nil else { return }
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
        recordResult   = nil
        startedAt      = Date()
        gameSerial    += 1
        // 前対局の思考が走っていても、新しい対局の CPU を起動できるようにする。
        // 旧タスクは gameSerial が変わったことを見て着手もフラグ操作も行わない。
        isThinking     = false
        persist()
        services?.gameDidRestart(gameID: gameID)
    }

    // MARK: - 投了

    public func resign() {
        guard !gameOver else { return }
        resigned = true
        winner = humanSide.opponent
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: GameScore(metric: .winLoss))
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
        guard !gameOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = GomokuSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: currentStone.rawValue,
            humanSide: humanSide.rawValue,
            aiLevel: aiLevel,
            startedAt: startedAt,
            moveHistory: moves.map { GomokuMoveRecord(row: $0.row, col: $0.col, stone: $0.stone.rawValue) },
            undoUsed: undoUsed,
            resigned: resigned ? true : nil,
            winner: winner?.rawValue
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    public func clearSnapshot() {
        services?.snapshots.clear(for: gameID)
    }
}
