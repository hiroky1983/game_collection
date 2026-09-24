import Foundation
import Observation
import Core

/// 中断データ。`undo*` と `turnStart*` は旧データに無いので optional（規約「1局=1RuleSet」の 2 と同じ理由）。
struct BackgammonSnapshot: Codable {
    let points: [Int]
    let bar: [Int]
    let off: [Int]
    let currentSide: Int
    let aiLevel: Int
    let dice: [Int]
    let remainingDice: [Int]
    let turnID: Int
    let startedAt: Date
    let undoUsed: Bool?
    let mustPass: Bool?
    let hasProgressed: Bool?
    let openingHuman: Int?
    let openingCPU: Int?
    /// 「待った」で戻る先（人間の直前の手番の開始時点）。
    let undoPoints: [Int]?
    let undoBar: [Int]?
    let undoOff: [Int]?
    let undoDice: [Int]?
    /// 「やり直し」で戻る先（いまの手番の開始時点）。
    let turnStartPoints: [Int]?
    let turnStartBar: [Int]?
    let turnStartOff: [Int]?
}

/// 巻き戻しの単位（盤 + 振った目）。手番の持ち主は常に人間。
struct BackgammonTurnState: Equatable {
    let board: BackgammonBoard
    let dice: [Int]
}

/// バックギャモン（CPU 対戦・#1322・企画倉庫）。人間は白で、CPU（黒）の手番は
/// オセロと同じ `withAITurnGuard` の定石で 1 手ずつ進める（#531）。
///
/// サイコロは**手番が回ってきた瞬間に自動で振る**（振るボタンは置かない）。目を使い切るか
/// 動かせる駒が無くなった時点で手番が移る。手番の途中は「やり直し」（無料）で振った直後へ戻せ、
/// 手番が移った後は「待った」（無料 1 回、以後は広告）で CPU の応手ごと戻せる（`BoardUndoModel`）。
@MainActor
@Observable
public final class BackgammonModel: AITurnGuarded, BoardUndoModel {
    /// `GameModule.id` と同じ値。`ModuleTests` が一致を確かめる。
    public static let gameID = "backgammon"
    /// 人間は常に白。
    public static let human = BackgammonSide.white

    public private(set) var board: BackgammonBoard
    public private(set) var currentSide: BackgammonSide
    public private(set) var aiLevel: Int
    /// この手番で振った目（表示用。ゾロ目は 4 個）。
    public private(set) var dice: [Int]
    /// まだ使っていない目。
    public private(set) var remainingDice: [Int]
    public private(set) var winner: BackgammonSide?
    public private(set) var winKind: BackgammonWinKind?
    public private(set) var isThinking = false
    public private(set) var mustPass: Bool
    public private(set) var turnID: Int
    public private(set) var undoUsed: Bool
    /// 新規対局のたびに増える通し番号（CPU 起動トリガー用。永続化しない）。
    public private(set) var gameSerial = 0
    /// 選択中の移動元（盤の添字か `BackgammonBoard.bar`）。
    public private(set) var selectedPoint: Int?
    /// 直前に動いた駒（演出・読み上げ用）。
    public private(set) var lastMove: BackgammonMove?
    /// オープニングロール（人間の目, CPU の目）。開始直後の案内に使う。
    public private(set) var openingRoll: (human: Int, cpu: Int)?
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    public let gameID: String = BackgammonModel.gameID
    public var humanSide: BackgammonSide { Self.human }
    /// CPU が 1 手動かすまでの間合い。テストは `.zero`。
    private let cpuDelay: Duration
    private var rng: SplitMix64
    private var startedAt: Date
    /// この局で 1 手でも動いたか（`gameDidProgress` の冪等化と「配っただけ」の判定）。
    private var hasProgressed: Bool
    private var undoHistory: [BackgammonTurnState] = []
    /// いまの手番の開始時点（「やり直し」の戻り先）。人間の手番でだけ持つ。
    private var turnStart: BackgammonBoard?
    /// 思考タスクの待ち合わせ点（テスト専用）。
    @ObservationIgnored var thinkingGate: (@MainActor () async -> Void)?
    #if DEBUG
    private var isPreviewCapture = false
    #endif

    public var gameOver: Bool { winner != nil }
    public var isAITurn: Bool { !gameOver && currentSide != humanSide }
    public var reviewOutcome: GameOutcome { winner == humanSide ? .win : .loss }
    public var aiTurnKey: AITurnKey { AITurnKey(gameSerial: gameSerial, ply: turnID) }
    /// 人間がいま打てる 1 手。CPU の手番・決着後は空。
    public var legalMoves: [BackgammonMove] {
        guard !gameOver, !isAITurn, !mustPass else { return [] }
        return BackgammonRules.legalMoves(board: board, side: humanSide, dice: remainingDice)
    }
    /// 動かせる駒のある場所（選択のヒント）。
    public var movableSources: Set<Int> { Set(legalMoves.map(\.from)) }
    /// 選択中の駒の移動先。
    public var destinations: [BackgammonMove] {
        guard let from = selectedPoint else { return [] }
        return legalMoves.filter { $0.from == from }
    }
    /// 手番の途中（目を 1 つでも使った）で、振った直後へ戻せるか。
    public var canRestartTurn: Bool {
        !gameOver && !isAITurn && !mustPass && turnStart != nil && remainingDice.count < dice.count
    }
    /// 「待った」が押せるのは**自分の手番の頭（まだ目を使っていない）**だけ。手番の途中は「やり直し」の領分で、
    /// ここでも押せると無料枠や広告を「やり直し」と同じ結果に使わせてしまう（verifier 指摘・PR #1344）。
    public var canUndo: Bool {
        !gameOver && !isAITurn && !isThinking && !mustPass && !undoHistory.isEmpty
            && remainingDice.count == dice.count
    }
    public var humanPips: Int { board.pipCount(humanSide) }
    public var cpuPips: Int { board.pipCount(humanSide.opponent) }

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(550),
        seed: UInt64? = nil
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        rng = SplitMix64(seed: seed ?? UInt64.random(in: 0...UInt64.max))
        var isFreshStart = false
        if let snap = services?.snapshots.load(BackgammonSnapshot.self, for: Self.gameID),
           let side = BackgammonSide(rawValue: snap.currentSide),
           BackgammonRules.isConsistent(BackgammonBoard(points: snap.points, bar: snap.bar, off: snap.off)) {
            board         = BackgammonBoard(points: snap.points, bar: snap.bar, off: snap.off)
            currentSide   = side
            aiLevel       = snap.aiLevel
            dice          = snap.dice
            remainingDice = snap.remainingDice
            turnID        = snap.turnID
            startedAt     = snap.startedAt
            undoUsed      = snap.undoUsed ?? false
            mustPass      = snap.mustPass ?? false
            hasProgressed = snap.hasProgressed ?? true
            if let h = snap.openingHuman, let c = snap.openingCPU { openingRoll = (h, c) }
            if let p = snap.undoPoints, let b = snap.undoBar, let o = snap.undoOff, let d = snap.undoDice,
               BackgammonRules.isConsistent(BackgammonBoard(points: p, bar: b, off: o)) {
                undoHistory = [BackgammonTurnState(board: BackgammonBoard(points: p, bar: b, off: o), dice: d)]
            }
            if let p = snap.turnStartPoints, let b = snap.turnStartBar, let o = snap.turnStartOff,
               BackgammonRules.isConsistent(BackgammonBoard(points: p, bar: b, off: o)) {
                turnStart = BackgammonBoard(points: p, bar: b, off: o)
            }
        } else {
            board         = BackgammonBoard()
            currentSide   = .white
            aiLevel       = CPUStrength.standard.rawValue
            dice          = []
            remainingDice = []
            turnID        = 0
            startedAt     = Date()
            undoUsed      = false
            mustPass      = false
            hasProgressed = false
            isFreshStart  = true
        }
        if isFreshStart {
            // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
            // 開始シートは通らないので `level` は載せない（オセロと同じ）。
            services?.gameDidStart(gameID: gameID)
            openNewGame()
        }
    }

    // MARK: - 操作

    /// ポイント（0〜23）・バー（`BackgammonBoard.bar`）・あがり（`BackgammonBoard.off`）をタップした。
    public func tap(_ point: Int) {
        guard !gameOver, !isAITurn, !mustPass else { return }
        if let from = selectedPoint {
            if let move = destinations.first(where: { $0.to == point }) {
                selectedPoint = nil
                play(move)
                return
            }
            if point == from {
                selectedPoint = nil
                return
            }
        }
        if movableSources.contains(point) {
            selectedPoint = point
            services?.feedback.impact(.light)
        } else {
            services?.feedback.notify(.warning) // 動かせない駒・行けない場所
        }
    }

    /// この手番で動かした駒を振った直後へ戻す（無料・何度でも）。
    public func restartTurn() {
        guard canRestartTurn, let start = turnStart else { return }
        board = start
        remainingDice = dice
        selectedPoint = nil
        lastMove = nil
        // この手番の最初の 1 手で積んだ「待った」の戻り先も取り下げる。残すと次の 1 手でもう 1 本積まれ、
        // 同じ盤面のエントリが 2 本並んで広告の待ったが空振りする（verifier 指摘・PR #1344）。
        if undoHistory.last?.board == start { undoHistory.removeLast() }
        turnID += 1
        persist()
    }

    public func confirmPass() {
        guard mustPass, !gameOver else { return }
        mustPass = false
        selectedPoint = nil
        turnID += 1
        beginTurn(for: currentSide.opponent)
    }

    public func undoLastExchange() {
        guard canUndo, let prev = undoHistory.popLast() else { return }
        board = prev.board
        dice = prev.dice
        remainingDice = prev.dice
        turnStart = prev.board
        currentSide = humanSide
        selectedPoint = nil
        lastMove = nil
        mustPass = false
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
        finish(winner: humanSide.opponent, kind: .single)
    }

    public func performAIMoveIfNeeded() async {
        guard isAITurn, !isThinking, !gameOver else { return }
        if mustPass {
            await withAITurnGuard(key: \.aiTurnKey) {
                try? await Task.sleep(for: cpuDelay * 2)
            } commit: { _ in
                guard isAITurn, mustPass else { return }
                confirmPass()
            }
            return
        }
        await withAITurnGuard(key: \.aiTurnKey, thinking: \.isThinking) {
            let b = board, s = currentSide, d = remainingDice, lvl = aiLevel
            let deadline = ContinuousClock.now + cpuDelay
            await thinkingGate?()
            let seq = await Task.detached(priority: .userInitiated) {
                BackgammonEngine(level: lvl).bestSequence(board: b, side: s, dice: d)
            }.value
            try? await Task.sleep(until: deadline, clock: .continuous)
            return seq.first
        } commit: { move in
            guard isAITurn, !gameOver, let move else { return }
            // 旧局面で選んだ手をそのまま打たない。いまの合法手に含まれるときだけ進める。
            guard BackgammonRules.legalMoves(board: board, side: currentSide, dice: remainingDice).contains(move) else { return }
            play(move)
        }
    }

    public func newGame(aiLevel: Int = CPUStrength.standard.rawValue) {
        self.aiLevel = aiLevel
        board = BackgammonBoard()
        winner = nil
        winKind = nil
        selectedPoint = nil
        lastMove = nil
        mustPass = false
        undoUsed = false
        undoHistory = []
        turnStart = nil
        recordResult = nil
        hasProgressed = false
        startedAt = Date()
        turnID = 0
        gameSerial += 1
        isThinking = false
        // まだ 1 手も動いていない局は `persist()` が保存しないので、前の対局の中断データはここで消す
        // （残すと、新規対局を始めて 1 手も指さずに離れたとき「続きから」が前の対局を復元する）。
        services?.snapshots.clear(for: gameID)
        openNewGame()
        services?.gameDidRestart(gameID: gameID, level: CPUStrength.analyticsLevel(forLevel: aiLevel))
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 進行

    /// オープニングロール（同じ目なら振り直し）。大きい目を出した側が、その 2 個の目で先手を取る。
    private func openNewGame() {
        var h = rollDie(), c = rollDie()
        while h == c { h = rollDie(); c = rollDie() }
        openingRoll = (h, c)
        let starter: BackgammonSide = h > c ? humanSide : humanSide.opponent
        beginTurn(for: starter, roll: (h, c))
    }

    private func rollDie() -> Int { Int(rng.next() % 6) + 1 }

    /// 手番を回し、目を振る。動かせる手が無ければ `mustPass` を立てる。
    private func beginTurn(for side: BackgammonSide, roll: (Int, Int)? = nil) {
        currentSide = side
        let r = roll ?? (rollDie(), rollDie())
        dice = BackgammonRules.dice(for: r)
        remainingDice = dice
        selectedPoint = nil
        turnStart = side == humanSide ? board : nil
        mustPass = BackgammonRules.legalMoves(board: board, side: side, dice: dice).isEmpty
        // 自分がパスする手番では「直前の自分の 1 手」がパスそのものになるので、古い戻り先は捨てる。
        // 残すと、パスの次の手番で押した「待った」が 2 往復以上前まで戻る（verifier 指摘・PR #1344）。
        if side == humanSide, mustPass { undoHistory = [] }
        turnID += 1
        persist()
    }

    private func play(_ move: BackgammonMove) {
        let mover = currentSide
        if mover == humanSide, remainingDice.count == dice.count {
            // 「待った」の戻り先は、この手番で最初の駒を動かす直前（= 振った直後）。
            undoHistory.append(BackgammonTurnState(board: board, dice: dice))
        }
        if !hasProgressed {
            hasProgressed = true
        }
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。冪等。
        services?.gameDidProgress(gameID: gameID)
        board = BackgammonRules.apply(move, to: board, side: mover)
        if let i = remainingDice.firstIndex(of: move.die) { remainingDice.remove(at: i) }
        lastMove = move
        turnID += 1
        if board.hasWon(mover) {
            finish(winner: mover, kind: board.winKind(winner: mover))
            return
        }
        if mover == humanSide {
            services?.feedback.impact(move.hits ? .rigid : .medium)
        }
        if remainingDice.isEmpty
            || BackgammonRules.legalMoves(board: board, side: mover, dice: remainingDice).isEmpty {
            beginTurn(for: mover.opponent)
        } else {
            persist()
        }
    }

    private func finish(winner side: BackgammonSide, kind: BackgammonWinKind) {
        winner = side
        winKind = kind
        selectedPoint = nil
        mustPass = false
        turnStart = nil
        services?.feedback.notify(side == humanSide ? .success : .error)
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
        // 開いただけ（オープニングロールを振っただけ）の局は保存しない（#240）。ハブに「続きから」を
        // 出す意味が無く、次に開いたときに振り直しても失うものが無い。
        guard hasProgressed else { return }
        let snap = BackgammonSnapshot(
            points: board.points, bar: board.bar, off: board.off,
            currentSide: currentSide.rawValue, aiLevel: aiLevel,
            dice: dice, remainingDice: remainingDice, turnID: turnID, startedAt: startedAt,
            undoUsed: undoUsed ? true : nil, mustPass: mustPass ? true : nil, hasProgressed: hasProgressed,
            openingHuman: openingRoll?.human, openingCPU: openingRoll?.cpu,
            undoPoints: undoHistory.last?.board.points, undoBar: undoHistory.last?.board.bar,
            undoOff: undoHistory.last?.board.off, undoDice: undoHistory.last?.dice,
            turnStartPoints: turnStart?.points, turnStartBar: turnStart?.bar, turnStartOff: turnStart?.off
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - テスト・撮影用

    #if DEBUG
    /// 任意の局面を作る（テスト・撮影用）。人間の手番で、`roll` の目を振った直後の状態にする。
    /// 中断データには流さない（保存対局を壊さない・PR #367 の指摘と同じ）。
    public func configureForTesting(board: BackgammonBoard, side: BackgammonSide = BackgammonModel.human, roll: (Int, Int)) {
        isPreviewCapture = true
        defer { isPreviewCapture = false }
        precondition(BackgammonRules.isConsistent(board), "駒の数が 15 個ずつになっていない")
        self.board = board
        winner = nil
        winKind = nil
        undoHistory = []
        recordResult = nil
        gameSerial += 1
        isThinking = false
        beginTurn(for: side, roll: roll)
    }

    /// 撮影用（`-backgammonScenario <名前>`）: 見せたい局面へ差し替える。
    /// 中断データから復元した局面も差し替える（前回の撮影が残っていても狙った局面になるように）。
    public func applyDebugScenario(_ name: String) {
        switch name {
        case "hit":
            // 白が 8 ポイントから 5・3 で黒のブロットを叩ける局面。
            var b = BackgammonBoard()
            b.points[4] = -1; b.points[0] = -1          // 黒: 1 ポイントの 1 個を 5 ポイントへ出したブロット
            configureForTesting(board: b, roll: (5, 3))
        case "bar":
            // 白がバーから入る局面（黒が自陣を 3 ポイント閉じている）。
            var b = BackgammonBoard()
            b.points[23] = 1; b.bar[0] = 1
            b.points[18] = -3; b.points[19] = -2        // 黒: 19 に 5 → 3 個 + 20 に 2 個
            configureForTesting(board: b, roll: (6, 2))
        case "bearoff":
            // 双方がベアオフに入った終盤。
            var p = Array(repeating: 0, count: 24)
            p[0] = 2; p[1] = 3; p[2] = 3; p[3] = 2; p[4] = 2; p[5] = 1     // 白 13 個 + あがり 2
            p[23] = -2; p[22] = -3; p[21] = -3; p[20] = -3; p[19] = -2      // 黒 13 個 + あがり 2
            configureForTesting(board: BackgammonBoard(points: p, bar: [0, 0], off: [2, 2]), roll: (6, 4))
        case "result":
            var p = Array(repeating: 0, count: 24)
            p[0] = 1
            p[23] = -2; p[22] = -3; p[21] = -3; p[20] = -3; p[19] = -2; p[5] = -2
            configureForTesting(board: BackgammonBoard(points: p, bar: [0, 0], off: [14, 0]), roll: (1, 2))
            tap(0); tap(BackgammonBoard.off)
        default:
            break
        }
    }
    #endif
}
