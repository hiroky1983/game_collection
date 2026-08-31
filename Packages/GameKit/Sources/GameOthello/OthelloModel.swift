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
    let undoUsed: Bool?
}

private struct TurnState {
    let cells: [OthelloStone?]
    let currentStone: OthelloStone
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
    public private(set) var undoUsed: Bool
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial: Int = 0
    /// 直前の着手で裏返った石の位置（`行 * 8 + 列`）。反転演出の対象（#204）。
    public private(set) var flippedCells: Set<Int> = []
    /// 石を置いた回数。反転演出の進捗を補間するための通し番号（永続化しない）。
    ///
    /// `turnID` はパス・待ったでも増えるため、これらで反転演出が空振りしないよう別に持つ。
    public private(set) var placementCount: Int = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    /// 思考タスクの待ち合わせ点（テスト専用。本番では nil のまま）。
    /// `isThinking = true` と盤面の取り込みが済んだ直後・探索の開始前に await する。
    /// テストはここで思考を止めることで、「探索の完了待ちで停止中」という状態を
    /// 探索の所要時間に依存せず決定論的に作れる（#172）。
    @ObservationIgnored var thinkingGate: (@MainActor () async -> Void)?
    private let gameID = "othello"
    /// CPU が着手する前に、直前の反転演出へ最低限あける間合い（#204）。
    /// **読みと並行に測るので、読みが長い局面（強レベル）ではここによる追加の待ちは発生しない**。
    /// テストは `.zero` を渡して実時間の待ちを消す（大富豪・麻雀の `cpuDelay` と同じ運用）。
    private let flipSettleDelay: Duration
    private var startedAt: Date
    private var undoHistory: [TurnState] = []

    public var gameOver: Bool { winner != nil || isDraw }
    public var isAITurn: Bool { !gameOver && currentStone != humanSide }
    /// 決着の種類（評価リクエスト #53 の判定用。リザルト表示時に参照する）。
    public var reviewOutcome: GameOutcome {
        if isDraw { return .draw }
        return winner == humanSide ? .win : .loss
    }
    public var blackCount: Int { board.count(for: .black) }
    public var whiteCount: Int { board.count(for: .white) }
    public var canUndo: Bool {
        !gameOver && !isAITurn && !isThinking && !mustPass && !undoHistory.isEmpty
    }

    /// View の `.task(id:)` に渡す CPU 起動トリガー。
    /// `turnID` だけだと「0 手のまま後手で新規対局を始めた」ときに値が変わらず、
    /// CPU の初手が起動しない（#140。将棋 #82 と同じ原因）。対局の通し番号と組にする。
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: turnID) }

    public init(
        services: GameServices? = nil,
        flipSettleDelay: Duration = .milliseconds(Int(OthelloFlip.duration * 1000))
    ) {
        self.services = services
        self.flipSettleDelay = flipSettleDelay
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = false

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
            undoUsed     = snap.undoUsed ?? false
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
            undoUsed     = false
            isFreshStart = true
        }
        isThinking = false
        lastMove   = nil
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshStart { services?.gameDidStart(gameID: gameID) }
    }

    public func tap(row: Int, col: Int) {
        guard !gameOver, !isAITurn, !mustPass else { return }
        guard board.isValid(row: row, col: col, stone: currentStone) else {
            services?.feedback.notify(.warning) // 石を返せないマスへの着手
            return
        }
        saveUndoState()
        place(row: row, col: col)
    }

    public func confirmPass() {
        guard mustPass, !gameOver else { return }
        saveUndoState()
        mustPass     = false
        currentStone = currentStone.opponent
        turnID      += 1
        checkTermination()
        notifyTermination()
        persist()
    }

    public func undoLastExchange() {
        guard canUndo, let prev = undoHistory.popLast() else { return }
        board        = OthelloBoard(cells: prev.cells)
        currentStone = prev.currentStone
        lastMove     = nil
        // 戻した盤に「直前に返った石」は無い。残すと巻き戻した石が反転中の姿で描かれる。
        flippedCells = []
        mustPass     = false
        winner       = nil
        isDraw       = false
        undoUsed     = true
        turnID      += 1
        persist()
    }

    public func resign() {
        guard !gameOver else { return }
        winner = humanSide.opponent
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: GameScore(metric: .winLoss))
        persist()
    }

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking, !gameOver else { return }
        // 待ちの最中に新規対局が始まると、旧盤面での判断（パス・着手）が新しい盤面に
        // 適用されてしまう。開始時のトリガー（対局の通し番号 × turnID）を控え、
        // 完了時に一致する場合だけ進める。
        let key = aiTurnKey
        let serial = gameSerial

        if mustPass {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard aiTurnKey == key, isAITurn, mustPass else { return }
            confirmPass()
            return
        }

        isThinking = true
        // 別対局が始まっていたら、思考フラグの持ち主は新しい対局のタスクなので触らない。
        defer { if gameSerial == serial { isThinking = false } }

        let b = board, s = currentStone, lvl = aiLevel
        // 直前の着手の反転演出を見せてから打つための締切（#204）。読みを始める前に取り、
        // 読みが終わったあとに「残り」だけ待つので、読みが長ければ待ちはゼロになる。
        let settleDeadline = ContinuousClock.now + flipSettleDelay
        await thinkingGate?()
        let move = await Task.detached(priority: .userInitiated) {
            await OthelloEngine(level: lvl).bestMove(board: b, stone: s)
        }.value
        try? await Task.sleep(until: settleDeadline, clock: .continuous)

        guard aiTurnKey == key, isAITurn, !gameOver else { return }
        // 旧盤面で選んだ手を新しい盤面に打つと石が返らず盤面が壊れるため、合法手であることも再確認する。
        if let (r, c) = move, board.isValid(row: r, col: c, stone: currentStone) {
            place(row: r, col: c)
        }
    }

    public func newGame(humanSide: OthelloStone = .black, aiLevel: Int = 1) {
        board          = OthelloBoard()
        currentStone   = .black
        self.humanSide = humanSide
        self.aiLevel   = aiLevel
        winner         = nil
        isDraw         = false
        lastMove       = nil
        flippedCells   = []
        mustPass       = false
        turnID         = 0
        undoUsed       = false
        undoHistory    = []
        recordResult   = nil
        startedAt      = Date()
        gameSerial    += 1
        // 前対局の思考が走っていても、新しい対局の CPU を起動できるようにする。
        // 旧タスクは gameSerial が変わったことを見て着手もフラグ操作も行わない。
        isThinking     = false
        persist()
        services?.gameDidRestart(gameID: gameID)
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    private func saveUndoState() {
        undoHistory.append(TurnState(cells: board.cells, currentStone: currentStone))
    }

    private func place(row: Int, col: Int) {
        let mover = currentStone
        // 反転演出の対象は盤を書き換える前にしか取れない（#204）。
        flippedCells = Set(board.flippable(row: row, col: col, stone: currentStone)
            .map { $0.0 * othelloBoardSize + $0.1 })
        placementCount += 1
        board.place(row: row, col: col, stone: currentStone)
        lastMove     = (row, col)
        currentStone = currentStone.opponent
        turnID      += 1
        checkTermination()
        // 着手の手応えは自分が指したときだけ。CPU の着手では鳴らさない。
        if !notifyTermination(), mover == humanSide {
            services?.feedback.impact(.medium)
        }
        persist()
    }

    /// 決着していれば結果を触覚で伝える。決着していなければ false（呼び出し側が着手音を出す）。
    @discardableResult
    private func notifyTermination() -> Bool {
        guard gameOver else { return false }
        if isDraw {
            services?.feedback.notify(.warning)
        } else {
            services?.feedback.notify(winner == humanSide ? .success : .error)
        }
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: GameScore(metric: .winLoss))
        return true
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
        guard !gameOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = OthelloSnapshot(
            cells: board.cells.map { $0?.rawValue },
            currentStone: currentStone.rawValue,
            humanSide: humanSide.rawValue,
            aiLevel: aiLevel,
            startedAt: startedAt,
            winner: winner?.rawValue,
            isDraw: isDraw,
            mustPass: mustPass ? true : nil,
            turnID: turnID,
            undoUsed: undoUsed ? true : nil
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
