import Foundation
import Observation
import Core

/// 中断データ。あとから足す鍵は optional にする（規約「1局=1RuleSet」の 2 と同じ理由）。
struct MancalaSnapshot: Codable {
    let slots: [Int]
    let currentSide: Int
    let humanFirst: Bool
    let aiLevel: Int
    let turnID: Int
    let startedAt: Date
    let undoUsed: Bool?
    /// 「待った」で戻る先（人間の直前の 1 手を打つ前の盤）。
    let undoSlots: [Int]?
    /// 直前に動いた側の手（穴の添字と、最後の種が入った置き場）。無ければ印なし。
    let lastPitSlot: Int?
    let lastLandingSlot: Int?
}

/// マンカラ（CPU 対戦・#1626・企画倉庫）。人間は常に手前（南）で、CPU（北）の手番は
/// オセロと同じ `withAITurnGuard` の定石で 1 手ずつ進める（#531）。
///
/// 最後の種が自分のストアに入ると同じ側がもう一度打つので、CPU は手番の鍵（`aiTurnKey`）が
/// 進むたびに View の `.task(id:)` から 1 手ずつ起こされる。パスは無い（片側の穴が空になった時点で終局）。
/// 「待った」（無料 1 回、以後は広告）は人間の直前の 1 手を、続いた CPU の手ごと戻す（`BoardUndoModel`）。
@MainActor
@Observable
public final class MancalaModel: AITurnGuarded, BoardUndoModel {
    /// `GameModule.id` と同じ値。`MancalaModuleTests` が一致を確かめる。
    public static let gameID = "mancala"
    /// 人間は常に手前（南）。
    public static let human = MancalaSide.south

    public private(set) var board: MancalaBoard
    public private(set) var currentSide: MancalaSide
    /// 人間が先手か（開始シートで選ぶ）。
    public private(set) var humanFirst: Bool
    public private(set) var aiLevel: Int
    public private(set) var isThinking = false
    /// 決着したか（`winner` が nil でも引き分けで終わっていれば true）。
    public private(set) var isFinished = false
    public private(set) var winner: MancalaSide?
    public private(set) var turnID: Int
    public private(set) var undoUsed: Bool
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial = 0
    /// 直前の手（まいた穴の添字・最後の種が入った置き場の添字）。盤の印と読み上げに使う。
    public private(set) var lastMove: (pitSlot: Int, landingSlot: Int)?
    /// 直前の手で起きたこと（状況の 1 行に出す）。永続化しない。
    public private(set) var lastEvent: MancalaEvent?
    /// CPU が着手した直後の `aiTurnKey`。View はこれと一致するときだけ着手を読み上げる（#3062）。永続化しない。
    public private(set) var lastCPUMoveKey: AITurnKey?
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    public let gameID: String = MancalaModel.gameID
    public var humanSide: MancalaSide { Self.human }
    /// CPU が 1 手まくまでの間合い。テストは `.zero`。
    private let cpuDelay: Duration
    /// 入門の無作為選択の種（テスト用。nil なら毎回変わる）。
    private let engineSeed: UInt64?
    private var startedAt: Date
    /// 「待った」の戻り先（人間が 1 手打つ直前の盤）。続けて打った手ぶん積まれる。
    private var undoHistory: [MancalaBoard] = []
    /// 思考タスクの待ち合わせ点（テスト専用）。
    @ObservationIgnored var thinkingGate: (@MainActor () async -> Void)?
    #if DEBUG
    private var isPreviewCapture = false
    #endif

    public var gameOver: Bool { isFinished }
    public var isAITurn: Bool { !gameOver && currentSide != humanSide }
    public var reviewOutcome: GameOutcome {
        guard let winner else { return .draw }
        return winner == humanSide ? .win : .loss
    }
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: turnID) }
    /// 人間がいま打てる穴（0〜5）。CPU の手番・決着後は空。
    public var legalPits: [Int] {
        guard !gameOver, !isAITurn else { return [] }
        return MancalaRules.legalMoves(board: board, side: humanSide)
    }
    public var canUndo: Bool {
        !gameOver && !isAITurn && !isThinking && !undoHistory.isEmpty
    }
    /// 「新規対局」で失われる進行があるか（1 手でも打った未決着の局）。
    public var hasProgressToLose: Bool { !gameOver && turnID > 0 }
    public var humanStore: Int { board.store(humanSide) }
    public var cpuStore: Int { board.store(humanSide.opponent) }

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(650),
        seed: UInt64? = nil
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        engineSeed = seed
        if let snap = services?.snapshots.load(MancalaSnapshot.self, for: Self.gameID),
           let side = MancalaSide(rawValue: snap.currentSide),
           MancalaRules.isConsistent(MancalaBoard(slots: snap.slots)),
           !MancalaRules.isGameOver(MancalaBoard(slots: snap.slots)) {
            board      = MancalaBoard(slots: snap.slots)
            currentSide = side
            humanFirst = snap.humanFirst
            aiLevel    = snap.aiLevel
            turnID     = snap.turnID
            startedAt  = snap.startedAt
            undoUsed   = snap.undoUsed ?? false
            if let u = snap.undoSlots, MancalaRules.isConsistent(MancalaBoard(slots: u)) {
                undoHistory = [MancalaBoard(slots: u)]
            }
            if let p = snap.lastPitSlot, let l = snap.lastLandingSlot,
               (0..<MancalaBoard.slotCount).contains(p), (0..<MancalaBoard.slotCount).contains(l) {
                lastMove = (p, l)
            }
        } else {
            // 壊れた・終局済みの中断データは読まずに捨てる（開くたびに同じ盤で詰まらないように）。
            services?.snapshots.clear(for: Self.gameID)
            board       = MancalaBoard()
            currentSide = Self.human
            humanFirst  = true
            aiLevel     = CPUStrength.standard.rawValue
            turnID      = 0
            startedAt   = Date()
            undoUsed    = false
            // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
            // 開始シートは通らないので `level` は載せない（オセロと同じ）。
            services?.gameDidStart(gameID: gameID)
        }
    }

    // MARK: - 操作

    /// 手前の `pit` 番目（0〜5・左から）の穴をタップした。
    public func tap(pit: Int) {
        guard !gameOver, !isAITurn else { return }
        guard MancalaRules.isLegal(pit: pit, board: board, side: humanSide) else {
            services?.feedback.notify(.warning) // 空の穴
            return
        }
        undoHistory.append(board)
        play(pit: pit)
    }

    public func undoLastExchange() {
        guard canUndo, let prev = undoHistory.popLast() else { return }
        board = prev
        currentSide = humanSide
        lastMove = nil
        lastEvent = nil
        lastCPUMoveKey = nil
        undoUsed = true
        turnID += 1
        persist()
    }

    @discardableResult
    public func undoLastExchange(forTurn turn: AITurnKey) -> Bool {
        guard turn == aiTurnKey, canUndo else { return false }
        undoLastExchange()
        return true
    }

    public func resign() {
        guard !gameOver else { return }
        finish(winner: humanSide.opponent)
    }

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking, !gameOver else { return }
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isThinking) {
            let b = board, s = currentSide, lvl = aiLevel, seed = engineSeed.map { $0 &+ UInt64(turnID) }
            let deadline = ContinuousClock.now + cpuDelay
            await thinkingGate?()
            let pit = await Task.detached(priority: .userInitiated) {
                MancalaEngine(level: lvl, seed: seed).bestMove(board: b, side: s)
            }.value
            try? await Task.sleep(until: deadline, clock: .continuous)
            return pit
        } commit: { pit in
            guard isAITurn, !gameOver, let pit else { return }
            // 旧局面で選んだ手をそのまま打たない。いまの盤で打てる穴のときだけ進める。
            guard MancalaRules.isLegal(pit: pit, board: board, side: currentSide) else { return }
            play(pit: pit)
        }
    }

    public func newGame(humanFirst: Bool = true, aiLevel: Int = CPUStrength.standard.rawValue) {
        self.humanFirst = humanFirst
        self.aiLevel = aiLevel
        board = MancalaBoard()
        currentSide = humanFirst ? humanSide : humanSide.opponent
        isFinished = false
        winner = nil
        lastMove = nil
        lastEvent = nil
        lastCPUMoveKey = nil
        undoUsed = false
        undoHistory = []
        recordResult = nil
        startedAt = Date()
        turnID = 0
        gameSerial += 1
        isThinking = false
        // まだ 1 手も打っていない局は `persist()` が保存しないので、前の対局の中断データはここで消す
        // （残すと、新規対局を始めて 1 手も打たずに離れたとき「続きから」が前の対局を復元する）。
        services?.snapshots.clear(for: gameID)
        services?.gameDidRestart(gameID: gameID, level: CPUStrength.analyticsLevel(forLevel: aiLevel))
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 進行

    private func play(pit: Int) {
        let mover = currentSide
        let result = MancalaRules.apply(pit: pit, side: mover, to: board)
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。冪等。
        // 人間が後手のとき CPU の初手だけでは数えない（#2934）。
        if mover == humanSide { services?.gameDidProgress(gameID: gameID) }
        board = result.board
        lastMove = (MancalaBoard.slotIndex(mover, pit: pit), result.lastSlot)
        lastEvent = MancalaEvent(side: mover, extraTurn: result.extraTurn, captured: result.captured)
        turnID += 1
        lastCPUMoveKey = mover == humanSide ? nil : aiTurnKey
        if result.gameEnded {
            finish(winner: MancalaRules.winner(of: board))
            return
        }
        if mover == humanSide {
            services?.feedback.impact(result.captured > 0 || result.extraTurn ? .rigid : .medium)
        }
        if !result.extraTurn { currentSide = mover.opponent }
        persist()
    }

    private func finish(winner side: MancalaSide?) {
        isFinished = true
        winner = side
        switch reviewOutcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: GameScore(metric: .winLoss))
        persist()
    }

    private func persist() {
        #if DEBUG
        if isPreviewCapture { return }
        #endif
        guard !gameOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        // 開いただけ（1 手も打っていない）の局は保存しない（#240）。
        guard turnID > 0 else { return }
        let snap = MancalaSnapshot(
            slots: board.slots, currentSide: currentSide.rawValue, humanFirst: humanFirst,
            aiLevel: aiLevel, turnID: turnID, startedAt: startedAt,
            undoUsed: undoUsed ? true : nil, undoSlots: undoHistory.last?.slots,
            lastPitSlot: lastMove?.pitSlot, lastLandingSlot: lastMove?.landingSlot
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - テスト・撮影用

    #if DEBUG
    /// 任意の局面を作る（テスト・撮影用）。中断データには流さない（保存対局を壊さない・PR #367 の指摘と同じ）。
    public func configureForTesting(board: MancalaBoard, side: MancalaSide = MancalaModel.human) {
        isPreviewCapture = true
        defer { isPreviewCapture = false }
        precondition(MancalaRules.isConsistent(board), "種の数が 48 個になっていない")
        self.board = board
        currentSide = side
        isFinished = false
        winner = nil
        lastMove = nil
        lastEvent = nil
        lastCPUMoveKey = nil
        undoHistory = []
        recordResult = nil
        gameSerial += 1
        isThinking = false
    }

    /// 撮影用（`-mancalaScenario <名前>`）: 見せたい局面へ差し替える。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "capture":
            // 左端の 1 個をまくと空の穴に入り、向かいの 6 個を取れる局面。
            configureForTesting(board: MancalaBoard(slots: [1, 0, 3, 4, 5, 2, 9, 4, 3, 2, 0, 6, 1, 8]))
        case "endgame":
            configureForTesting(board: MancalaBoard(slots: [0, 0, 0, 1, 0, 2, 22, 0, 1, 0, 0, 0, 0, 22]))
        default:
            break
        }
    }
    #endif
}

/// 直前の手で起きたこと（状況の 1 行に出す）。
public struct MancalaEvent: Equatable, Sendable {
    public let side: MancalaSide
    public let extraTurn: Bool
    public let captured: Int
}
