import Foundation
import Observation
import Core

/// 中断データ。盤は手順（列の並び）から作り直す。あとから足す鍵は optional にする（規約「1局=1RuleSet」の 2 と同じ理由）。
struct YonmokuSnapshot: Codable {
    /// 先手から交互に入れた列（0〜6）。
    let moves: [Int]
    let humanSide: Int
    let aiLevel: Int
    let startedAt: Date
    let undoUsed: Bool?
}

/// 四目並べ（CPU 対戦・#1738・企画倉庫）。黒が先手で、あなたは開始シートで黒（先手）か白（後手）を選ぶ。
///
/// CPU の手番は五目並べ・オセロと同じ `withAITurnGuard` の定石で 1 手ずつ進める（#531）。
/// 「待った」（無料 1 回、以後は広告）は自分の直前の 1 手を CPU の応手ごと戻す（`BoardUndoModel`）。
@MainActor
@Observable
public final class YonmokuModel: AITurnGuarded, BoardUndoModel {
    /// `GameModule.id` と同じ値。`YonmokuModuleTests` が一致を確かめる。
    public static let gameID = "yonmoku"

    public private(set) var board = YonmokuBoard()
    /// 次に打つ側（黒が先手）。
    public private(set) var currentDisc: YonmokuDisc = .black
    public private(set) var humanSide: YonmokuDisc
    public private(set) var aiLevel: Int
    public private(set) var winner: YonmokuDisc?
    public private(set) var isDraw = false
    public private(set) var isThinking = false
    /// 直前の手が入ったマス。
    public private(set) var lastMove: YonmokuPoint?
    /// 決着した 4 つ（以上）の並び。着手で決まったときだけ入り、投了・引き分けでは nil。
    public private(set) var winningLine: [YonmokuPoint]?
    /// CPU が着手した直後の `aiTurnKey`（#2280）。View はこれと一致する鍵の変化だけを読み上げる。
    public private(set) var lastCPUMoveKey: AITurnKey?
    public private(set) var undoUsed = false
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial = 0
    /// 直近の決着で確定した自己ベスト（#115）。
    public private(set) var recordResult: RecordResult?
    /// 打てないタップの通し番号（#202）。View は盤の揺れのトリガーにする。
    public private(set) var rejectedTapCount = 0
    public private(set) var resigned = false

    private let services: GameServices?
    public let gameID: String = YonmokuModel.gameID
    /// CPU が 1 手打つまでの最短の間合い（すぐ打つと何が起きたか見えない）。テストは `.zero`。
    private let cpuDelay: Duration
    /// CPU の乱数の種（テスト用。nil なら毎回変わる）。
    private let engineSeed: UInt64?
    private var startedAt = Date()
    /// 打たれた列（先手から交互）。
    private var moves: [Int] = []
    /// 開始シートを出す局の `game_start` は、最初の操作かシートを閉じた時点まで遅らせる（#1372。五目並べと同じ）。
    @ObservationIgnored private var pendingInitialStart = false
    /// 思考タスクの待ち合わせ点（テスト専用）。
    @ObservationIgnored var thinkingGate: (@MainActor () async -> Void)?

    public var moveCount: Int { moves.count }
    public var gameOver: Bool { winner != nil || isDraw }
    public var isAITurn: Bool { !gameOver && currentDisc != humanSide }
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: moves.count) }
    public var reviewOutcome: GameOutcome {
        guard let winner else { return .draw }
        return winner == humanSide ? .win : .loss
    }
    /// 人間がいま入れられる列。CPU の手番・決着後は空。
    public var playableColumns: [Int] {
        guard !gameOver, !isAITurn else { return [] }
        return board.playableColumns
    }
    /// 「新規対局」で失われる進行があるか（1 手でも打った未決着の局）。
    public var hasProgressToLose: Bool { !gameOver && !moves.isEmpty }

    public init(services: GameServices? = nil, cpuDelay: Duration = .milliseconds(450), seed: UInt64? = nil) {
        self.services = services
        self.cpuDelay = cpuDelay
        engineSeed = seed
        if let snap = services?.snapshots.load(YonmokuSnapshot.self, for: Self.gameID),
           let side = YonmokuDisc(rawValue: snap.humanSide),
           let restored = YonmokuBoard.replay(snap.moves),
           !snap.moves.isEmpty {
            humanSide = side
            aiLevel = snap.aiLevel
            startedAt = snap.startedAt
            undoUsed = snap.undoUsed ?? false
            moves = snap.moves
            board = restored
            currentDisc = moves.count % 2 == 0 ? .black : .white
            lastMove = Self.lastPoint(of: moves, on: restored)
            if let last = lastMove, let line = restored.winningLine(through: last) {
                // 決着した局は保存しないが、念のため決着として読む（同じ盤で詰まらないように）。
                winningLine = line
                winner = restored[last.col, last.row]
            } else if restored.isFull {
                isDraw = true
            }
            if gameOver { services?.snapshots.clear(for: Self.gameID) }
        } else {
            // 壊れた中断データ（入らない列・決着後の手）は読まずに捨てる（開くたびに同じ盤で詰まらないように）。
            services?.snapshots.clear(for: Self.gameID)
            humanSide = .black
            aiLevel = CPUStrength.standard.rawValue
            // 開いた直後は開始シートが出る。`game_start` はシートで選ぶまで待つ（五目並べと同じ・PR #572）。
            pendingInitialStart = true
        }
    }

    /// シートを閉じてそのまま遊ぶ局・最初の操作で `game_start` を数える（冪等）。
    public func startPlayIfPending() {
        guard pendingInitialStart else { return }
        pendingInitialStart = false
        services?.gameDidStart(gameID: gameID)
    }

    // MARK: - 操作

    /// 列をタップした。入らない列・CPU の手番は盤を揺らして知らせる。決着後は黙って無視する。
    public func tap(column: Int) {
        guard !gameOver else { return }
        guard !isAITurn, board.canDrop(in: column) else {
            rejectedTapCount += 1
            services?.feedback.notify(.warning)
            return
        }
        play(column: column)
    }

    public func resign() {
        guard !gameOver else { return }
        resigned = true
        winner = humanSide.opponent
        winningLine = nil
        services?.feedback.notify(.error)
        startPlayIfPending()
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: GameScore(metric: .winLoss))
        persist()
    }

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking else { return }
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isThinking) {
            let b = board, disc = currentDisc, level = aiLevel
            let seed = engineSeed.map { $0 &+ UInt64(moves.count) }
            let deadline = ContinuousClock.now + cpuDelay
            await thinkingGate?()
            let col = await Task.detached(priority: .userInitiated) {
                YonmokuEngine(level: level, seed: seed).bestMove(board: b, disc: disc)
            }.value
            try? await Task.sleep(until: deadline, clock: .continuous)
            return col
        } commit: { col in
            // 旧局面で選んだ手をそのまま打たない。いまの盤で入る列のときだけ進める。
            guard isAITurn, let col, board.canDrop(in: col) else { return }
            play(column: col)
            lastCPUMoveKey = aiTurnKey
        }
    }

    public func newGame(humanSide: YonmokuDisc = .black, aiLevel: Int = CPUStrength.standard.rawValue) {
        self.humanSide = humanSide
        self.aiLevel = aiLevel
        board = YonmokuBoard()
        currentDisc = .black
        moves = []
        winner = nil
        isDraw = false
        resigned = false
        lastMove = nil
        winningLine = nil
        lastCPUMoveKey = nil
        undoUsed = false
        recordResult = nil
        startedAt = Date()
        gameSerial += 1
        // 前の対局の思考が走っていても、新しい対局の CPU を起動できるようにする（旧タスクは鍵の違いで何もしない）。
        isThinking = false
        // まだ 1 手も打っていない局は保存しないので、前の対局の中断データはここで消す（#240）。
        services?.snapshots.clear(for: gameID)
        pendingInitialStart = false
        services?.gameDidRestart(gameID: gameID, level: CPUStrength.analyticsLevel(forLevel: aiLevel))
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 待った（自分の直前手＋CPU の応手の 2 手を戻す）

    public var canUndo: Bool {
        guard !gameOver, !isAITurn, !isThinking, moves.count >= 2 else { return false }
        // 最後が CPU の手、その前が自分の手（黒が偶数番目）。
        let lastMover: YonmokuDisc = (moves.count - 1) % 2 == 0 ? .black : .white
        return lastMover == humanSide.opponent
    }

    public func undoLastExchange() {
        guard canUndo else { return }
        moves.removeLast(2)
        board = YonmokuBoard.replay(moves) ?? YonmokuBoard()
        currentDisc = moves.count % 2 == 0 ? .black : .white
        lastMove = Self.lastPoint(of: moves, on: board)
        winningLine = nil
        undoUsed = true
        persist()
    }

    @discardableResult
    public func undoLastExchange(forTurn turn: AITurnKey) -> Bool {
        guard turn == aiTurnKey, canUndo else { return false }
        undoLastExchange()
        return true
    }

    // MARK: - 進行

    private func play(column: Int) {
        let mover = currentDisc
        guard let point = board.drop(mover, in: column) else { return }
        moves.append(column)
        lastMove = point
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。冪等。
        startPlayIfPending()
        services?.gameDidProgress(gameID: gameID)
        if let line = board.winningLine(through: point) {
            winningLine = line
            winner = mover
            services?.feedback.notify(mover == humanSide ? .success : .error)
            recordResult = services?.gameDidFinish(
                gameID: gameID, outcome: mover == humanSide ? .win : .loss,
                score: GameScore(metric: .winLoss),
                // 評価リクエストの見せ場は「ふつう」以上の CPU に勝ったとき（#1471）。
                isReviewHighlight: CPUStrength.isReviewWorthy(level: aiLevel)
            )
        } else if board.isFull {
            isDraw = true
            services?.feedback.notify(.warning)
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .draw, score: GameScore(metric: .winLoss))
        } else {
            currentDisc = mover.opponent
            if mover == humanSide { services?.feedback.impact(.medium) }
        }
        persist()
    }

    private static func lastPoint(of moves: [Int], on board: YonmokuBoard) -> YonmokuPoint? {
        guard let col = moves.last else { return nil }
        return YonmokuPoint(col: col, row: board.height(of: col) - 1)
    }

    private func persist() {
        guard !gameOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        // 開いただけ（1 手も打っていない）の局は保存しない（#240）。
        guard !moves.isEmpty else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = YonmokuSnapshot(moves: moves, humanSide: humanSide.rawValue, aiLevel: aiLevel,
                                   startedAt: startedAt, undoUsed: undoUsed ? true : nil)
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - テスト・撮影用

    #if DEBUG
    /// 手順から局面を作る（テスト・撮影用）。中断データ・解析・記録には流さない（保存対局を壊さない・PR #367 の指摘と同じ）。
    /// 決着していない手順だけを渡す。
    public func configureForTesting(moves: [Int], humanSide: YonmokuDisc = .black) {
        guard let built = YonmokuBoard.replay(moves) else { preconditionFailure("入らない手順: \(moves)") }
        self.humanSide = humanSide
        self.moves = moves
        board = built
        currentDisc = moves.count % 2 == 0 ? .black : .white
        lastMove = Self.lastPoint(of: moves, on: built)
        precondition(lastMove.flatMap { built.winningLine(through: $0) } == nil, "決着した手順は渡さない")
        winner = nil
        isDraw = false
        resigned = false
        winningLine = nil
        recordResult = nil
        gameSerial += 1
        isThinking = false
    }

    /// 撮影用（`-yonmokuScenario <名前>`）: 見せたい局面へ差し替える。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "midgame":
            // 中盤。あなた（黒）の番で、CPU は動き出さない。
            configureForTesting(moves: [3, 3, 2, 4, 4, 2, 3, 5])
        case "threat":
            // 黒が横に 3 つ並べ、どちらの端に入れても 4 つになる局面（あなた＝黒の番）。
            configureForTesting(moves: [2, 2, 3, 3, 1, 1])
        default:
            break
        }
    }
    #endif
}
