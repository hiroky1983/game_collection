import Core
import Observation

/// 明かり消しパズルのゲーム状態（#1883）。盤・手数・計時を持ち、永続化サービスへ中断スナップショットを書く。
/// 盤の規則と問題の生成は `AkariKeshiLogic` に委譲し、ここは乱数・計時・永続化・決着の管理だけを担う。
@MainActor
@Observable
public final class AkariKeshiModel {
    public enum State: Equatable, Sendable {
        /// 盤がまだ無い（開始シートを閉じた直後など）。
        case idle
        case playing
        case cleared
    }

    public static let gameID = "akarikeshi"
    /// 同じモジュールの View も参照する。
    let gameID = AkariKeshiModel.gameID
    /// 計時中に保存し直す間隔（秒）。マインスイーパー等と同じ考え方（#513）。
    static let persistInterval = 10

    public private(set) var board: [Bool]
    public private(set) var difficulty: AkariKeshiDifficulty
    /// 押した回数。
    public private(set) var moves: Int
    /// この盤の最短の手数（生成で押した数・最短の押し方はただ 1 つ）。
    public private(set) var par: Int
    public private(set) var elapsedSeconds: Int
    public private(set) var state: State
    /// 直近の決着で確定した自己ベスト。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 局の番号。始め直すたびに進む。
    public private(set) var gameSerial = 0

    private let services: GameServices?
    private var generator: SplitMix64?
    private let stopwatch = GameStopwatch(persistInterval: AkariKeshiModel.persistInterval)

    /// 現在時刻の取り出し口（テストが時間を進めるために差し替える）。
    var clockNow: ElapsedClock.Now {
        get { stopwatch.now }
        set { stopwatch.now = newValue }
    }

    /// services を渡すと、中断スナップショットがあれば復元する。無ければ盤の無い状態で待つ
    /// （難易度を開始シートで選んでから `newGame(difficulty:)` で始める）。
    /// `seed` を渡すと問題を種から決める（テスト用。省略時はシステム乱数）。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services
        generator = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(AkariKeshiSnapshot.self, for: AkariKeshiModel.gameID),
           Self.isRestorable(snap) {
            board = snap.board
            moves = snap.moves
            difficulty = snap.difficulty
            par = snap.par
            elapsedSeconds = snap.elapsedSeconds
            state = .playing
        } else {
            board = AkariKeshiLogic.cleared
            moves = 0
            difficulty = .easy
            par = 0
            elapsedSeconds = 0
            state = .idle
        }
    }

    /// 盤面を直接与えて開始する。狙った局面（あと 1 手で消える盤など）から検証するためのテスト用の経路。
    public init(services: GameServices? = nil, board: [Bool], difficulty: AkariKeshiDifficulty = .easy,
                par: Int, moves: Int = 0) {
        self.services = services
        self.board = board
        self.difficulty = difficulty
        self.par = par
        self.moves = moves
        elapsedSeconds = 0
        state = AkariKeshiLogic.isCleared(board) ? .cleared : .playing
    }

    /// 盤があるか（開始シートを閉じただけの状態でないか）。
    public var hasPuzzle: Bool { state != .idle }

    /// 「新規ゲーム」で失われる進行があるか（#1011）。1 回も押していない盤と消し終えた盤は捨てて構わない。
    public var hasProgressToLose: Bool { state == .playing && moves > 0 }

    /// 点灯しているマスの数。
    public var litCount: Int { board.filter { $0 }.count }

    /// 新しい問題で始める。開いただけの盤は保存しない（1 回押した時点で初めて保存する・#1847）。
    public func newGame(difficulty: AkariKeshiDifficulty) {
        stopwatch.stop()
        let puzzle = makePuzzle(presses: difficulty.presses)
        board = puzzle.board
        par = puzzle.solution.count
        self.difficulty = difficulty
        moves = 0
        elapsedSeconds = 0
        recordResult = nil
        state = .playing
        gameSerial += 1
        // 前の局の中断データ（押しかけの盤）は捨てる。新しい盤は 1 回押すまで保存しない。
        services?.snapshots.clear(for: gameID)
        startTimer()
        // 盤が出来て計時が始まるここが 1 プレイの開始（#158）。
        services?.gameDidRestart(gameID: gameID, level: difficulty.analyticsLevel)
    }

    /// `index` のマスを押す。決着後・盤の外は何もしない。
    public func press(at index: Int) {
        guard state == .playing, (0..<AkariKeshiLogic.cellCount).contains(index) else { return }
        board = AkariKeshiLogic.press(board, at: index)
        moves += 1
        // 盤が動いた = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: gameID)
        if AkariKeshiLogic.isCleared(board) {
            if let advanced = stopwatch.advance(from: elapsedSeconds) { elapsedSeconds = advanced.seconds }
            stopwatch.stop()
            state = .cleared
            services?.feedback.notify(.success)
            // 決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。記録は手数を見出しにし、タイムも残す。
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: .win,
                score: GameScore(
                    metric: .fewestMoves, seconds: elapsedSeconds, moves: moves,
                    variant: difficulty.rawValue, variantLabel: difficulty.recordVariantLabel
                )
            )
            services?.snapshots.clear(for: gameID)
        } else {
            services?.feedback.impact(.light)
            persist()
        }
    }

    // MARK: - 計時

    /// 画面に戻ったときに計時を再開する（`.task` / 前面復帰から呼ぶ）。
    public func resumeTimerIfNeeded() {
        guard state == .playing, !stopwatch.isRunning else { return }
        startTimer()
    }

    /// 画面を離れる・背面に回るときに計時を止める。止める前に端数を取り込んで保存し直す。
    public func pauseTimer() {
        if let advanced = stopwatch.advance(from: elapsedSeconds) { elapsedSeconds = advanced.seconds }
        if stopwatch.isRunning { persist() }
        stopwatch.stop()
    }

    var isTimerRunning: Bool { stopwatch.isRunning }

    private func startTimer() {
        stopwatch.start(base: elapsedSeconds) { [weak self] in self?.syncElapsed() }
    }

    /// タイマーのループが秒の境目ごとに呼ぶ。経過秒を実経過時間に合わせ、保存間隔の境目を跨いだら保存する。
    func syncElapsed() {
        guard let advanced = stopwatch.advance(from: elapsedSeconds) else { return }
        elapsedSeconds = advanced.seconds
        if advanced.crossedPersistBoundary { persist() }
    }

    // MARK: - 内部

    private func makePuzzle(presses: Int) -> (board: [Bool], solution: Set<Int>) {
        if var seeded = generator {
            defer { generator = seeded }
            return AkariKeshiLogic.generate(presses: presses, using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return AkariKeshiLogic.generate(presses: presses, using: &system)
    }

    /// 遊んでいる途中で、1 回以上押した盤だけを保存する。
    private func persist() {
        guard state == .playing, moves > 0 else { return }
        try? services?.snapshots.save(
            AkariKeshiSnapshot(board: board, moves: moves, difficulty: difficulty, par: par, elapsedSeconds: elapsedSeconds),
            for: gameID
        )
    }

    /// 復元してよい中断データか。形が正しく、まだ消し切っておらず、解ける盤で、数値が値域にあること。
    static func isRestorable(_ snap: AkariKeshiSnapshot) -> Bool {
        AkariKeshiLogic.isValid(snap.board)
            && !AkariKeshiLogic.isCleared(snap.board)
            && AkariKeshiLogic.isSolvable(snap.board)
            && snap.moves > 0
            && (1...AkariKeshiLogic.maxPresses).contains(snap.par)
            && snap.elapsedSeconds >= 0
    }
}
