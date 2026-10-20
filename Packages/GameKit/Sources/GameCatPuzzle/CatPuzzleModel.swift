import Core
import CoreEngine
import Observation

/// おじさんの飼い猫パズル（#2250）のゲーム状態。問題・置いた印・ミス・ヒント・経過秒を持ち、
/// 中断スナップショットを書く。生成・判定の純粋ロジックは `CatPuzzleLogic` に委譲し、
/// ここは操作の受け付け・計時・永続化・決着の記録だけを担う。
///
/// 操作: マスをタップすると ×（いない）→ 猫 → 空 の順に変わる。猫を置いた瞬間に矛盾
/// （同じ部屋・行・列に 2 匹、隣り合う）があればミスを 1 数え、該当の猫に印を付ける。
/// 猫が部屋の数だけ置けて矛盾が無ければクリア（答えは 1 つしか無いので、それが答え）。
@MainActor
@Observable
public final class CatPuzzleModel {
    /// 解析・記録・中断データの ID。`CatPuzzleModule.id` と同じ。
    public nonisolated static let gameID = "catpuzzle"
    /// 1 問につき無料で使えるヒントの回数。使い切ったあとの「広告を見て +1」は差し込み口だけ
    /// （試作の段階では広告を呼ばない・`CatPuzzleView`）。
    public static let freeHints = 3
    /// 計時中に保存し直す間隔（秒）。他の計時のあるゲームと同じ幅。
    static let persistInterval = 10

    /// マスの印。
    public enum Mark: Int, Codable, Sendable {
        case empty = 0
        case cross = 1
        case cat = 2
    }

    public private(set) var size: CatPuzzleSize
    public private(set) var puzzle: CatPuzzle
    public private(set) var marks: [Mark]
    /// いま置いてある猫どうしの矛盾（印の表示用）。
    public private(set) var violations = CatPuzzleViolations()
    /// 猫を置いた瞬間に矛盾があった回数。
    public private(set) var mistakes = 0
    public private(set) var hintsUsed = 0
    /// 出しているヒントのマス（答えの猫のマス）。そこに猫を置くと消える。
    public private(set) var hintCell: Int?
    /// 最初の 1 手からの経過秒。開いて眺めているだけの時間は数えない。
    public private(set) var elapsedSeconds = 0
    public private(set) var isSolved = false
    /// 直近の決着で確定した自己ベスト。クリアのカードに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// タップした回数（手数）。
    public private(set) var moves = 0

    private let services: GameServices?
    private var generator: SplitMix64?
    /// 「戻す」用の履歴（印と、出していたヒント。保存しない）。
    private var history: [(marks: [Mark], hintCell: Int?)] = []
    private let stopwatch = GameStopwatch(persistInterval: CatPuzzleModel.persistInterval)
    /// 現在時刻の取り出し口（テストが時間を進めるために差し替える）。
    var clockNow: ElapsedClock.Now {
        get { stopwatch.now }
        set { stopwatch.now = newValue }
    }

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    /// `seed` を渡すと問題を種から決める（テスト・日替わり用。省略時はシステム乱数）。
    public init(services: GameServices? = nil, size: CatPuzzleSize = .normal, seed: UInt64? = nil) {
        self.services = services
        var seeded = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(CatPuzzleSnapshot.self, for: Self.gameID),
           CatPuzzleSnapshot.isResumable(snap), let restoredSize = CatPuzzleSize(rawValue: snap.size) {
            self.size = restoredSize
            puzzle = snap.puzzle
            marks = snap.marks.compactMap(Mark.init(rawValue:))
            elapsedSeconds = snap.elapsedSeconds
            mistakes = snap.mistakes
            hintsUsed = snap.hintsUsed
            hintCell = snap.hintCell
            violations = CatPuzzleLogic.violations(puzzle: snap.puzzle, cats: Self.cats(in: marks))
        } else {
            self.size = size
            let made = Self.makePuzzle(size: size, generator: &seeded)
            puzzle = made
            marks = Array(repeating: .empty, count: made.cellCount)
            // 壊れた・手つかずの保存が残っていれば捨てる（印の無い盤は保存しない）。
            services?.snapshots.clear(for: Self.gameID)
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            services?.gameDidStart(gameID: Self.gameID, level: size.analyticsLevel)
        }
        generator = seeded
    }

    /// 問題を直接与えて開始する。狙った局面から検証するためのテスト用の経路。
    public init(services: GameServices? = nil, puzzle: CatPuzzle, size: CatPuzzleSize = .normal) {
        self.services = services
        self.size = size
        self.puzzle = puzzle
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        services?.snapshots.clear(for: Self.gameID)
        services?.gameDidStart(gameID: Self.gameID, level: size.analyticsLevel)
    }

    // MARK: - 読み取り

    /// 猫を置いたマス。
    public var catCells: [Int] { Self.cats(in: marks) }

    /// まだ置いていない猫の数（部屋の数 − 置いた猫）。
    public var remainingCats: Int { max(0, puzzle.side - catCells.count) }

    /// いま使えるヒントの回数（無料ぶんの残り）。
    public var hintsRemaining: Int { max(0, Self.freeHints - hintsUsed) }

    /// 次のヒントで教えるマス。答えの猫のうちまだ猫を置いていないマスで、部屋の空きが少ない
    /// （絞り込みやすい）部屋から選ぶ。全部置けていれば nil。
    public var hintTarget: Int? {
        var best: (cell: Int, open: Int)?
        for cell in puzzle.solutionCells where marks[cell] != .cat {
            let open = puzzle.cells(inRoom: puzzle.rooms[cell]).filter { marks[$0] != .cross }.count
            if best == nil || open < best!.open { best = (cell, open) }
        }
        return best?.cell
    }

    public var canHint: Bool { !isSolved && hintsRemaining > 0 && hintCell == nil && hintTarget != nil }
    public var canUndo: Bool { !history.isEmpty && !isSolved }

    /// 「新規ゲーム」・大きさの切り替え・やり直しで失われる進行があるか。印の無い盤と解き終えた盤は捨ててよい。
    public var hasProgressToLose: Bool { marks.contains { $0 != .empty } && !isSolved }

    // MARK: - 操作

    /// マスをタップする。×（いない）→ 猫 → 空 の順に変わる。
    public func tap(cell: Int) {
        guard !isSolved, marks.indices.contains(cell) else { return }
        history.append((marks, hintCell))
        let next: Mark
        switch marks[cell] {
        case .empty: next = .cross
        case .cross: next = .cat
        case .cat: next = .empty
        }
        marks[cell] = next
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        // 印を付けた = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: Self.gameID)
        refreshViolations()
        if next == .cat {
            if hintCell == cell { hintCell = nil }
            if violations.cells.contains(cell) {
                mistakes += 1
                services?.feedback.notify(.warning)
            } else {
                services?.feedback.impact(.medium)
            }
        } else {
            services?.feedback.impact(.light)
        }
        if CatPuzzleLogic.isSolved(puzzle: puzzle, cats: catCells) {
            finish()
        } else {
            persist()
        }
    }

    /// 直前のタップを取り消す（ヒントのマスに置いた猫を戻せば、ヒントの枠も戻る）。
    public func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        marks = previous.marks
        hintCell = previous.hintCell
        moves += 1
        refreshViolations()
        services?.feedback.impact(.light)
        persist()
    }

    /// 印を全部消して同じ問題を最初から。ミス・ヒント・経過秒は引き継ぐ。
    public func reset() {
        guard !isSolved else { return }
        history.removeAll()
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        hintCell = nil
        violations = CatPuzzleViolations()
        services?.feedback.impact(.light)
        // 印の無い盤は保存しない（開いただけの盤を「続き」にしない）。
        services?.snapshots.clear(for: Self.gameID)
    }

    /// ヒントを 1 回使う。答えの猫のマスを 1 つ示す（猫を置くのは自分）。
    public func useHint() {
        guard canHint, let target = hintTarget else { return }
        hintCell = target
        hintsUsed += 1
        if !stopwatch.isRunning { startTimer() }
        services?.gameDidUseHint(gameID: Self.gameID)
        services?.feedback.impact(.light)
        persist()
    }

    /// 新規ゲーム。`size` を渡すと盤の大きさを変える。
    public func newGame(size newSize: CatPuzzleSize? = nil) {
        if let newSize { size = newSize }
        stopwatch.stop()
        puzzle = Self.makePuzzle(size: size, generator: &generator)
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        history.removeAll()
        violations = CatPuzzleViolations()
        mistakes = 0
        hintsUsed = 0
        hintCell = nil
        elapsedSeconds = 0
        moves = 0
        isSolved = false
        recordResult = nil
        services?.snapshots.clear(for: Self.gameID)
        services?.gameDidRestart(gameID: Self.gameID, level: size.analyticsLevel)
    }

    // MARK: - 計時

    /// 画面に戻ったときの再開。1 手目より前・解き終えた後は数えない。
    public func resumeTimerIfNeeded() {
        guard hasProgressToLose || hintsUsed > 0, !isSolved, !stopwatch.isRunning else { return }
        startTimer()
    }

    /// 画面を離れる・背面に回るときの停止。止める前に端数を取り込み、保存し直す。
    public func pauseTimer() {
        syncElapsed()
        persist()
        stopwatch.stop()
    }

    /// 計時中か。
    public var isCounting: Bool { stopwatch.isRunning }

    /// タイマーのループが秒の境目ごとに呼ぶ。経過秒を実経過時間に合わせ、保存間隔の境目を跨いだら保存する。
    func syncElapsed() {
        guard let advanced = stopwatch.advance(from: elapsedSeconds) else { return }
        elapsedSeconds = advanced.seconds
        if advanced.crossedPersistBoundary { persist() }
    }

    private func startTimer() {
        stopwatch.start(base: elapsedSeconds) { [weak self] in self?.syncElapsed() }
    }

    // MARK: - 決着・保存

    private func finish() {
        syncElapsed()
        stopwatch.stop()
        isSolved = true
        hintCell = nil
        services?.feedback.notify(.success)
        // 決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。記録は大きさごとに分ける。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .win,
            score: GameScore(
                metric: .shortestTime, seconds: elapsedSeconds,
                variant: size.recordVariant, variantLabel: size.recordVariantLabel
            )
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    private func refreshViolations() {
        violations = CatPuzzleLogic.violations(puzzle: puzzle, cats: catCells)
    }

    private func persist() {
        // 印の無い盤と解き終えた盤は保存しない（印を全部消したら、残っていた保存も捨てる）。
        guard hasProgressToLose else {
            services?.snapshots.clear(for: Self.gameID)
            return
        }
        let snapshot = CatPuzzleSnapshot(
            size: size.rawValue, puzzle: puzzle, marks: marks.map(\.rawValue),
            elapsedSeconds: elapsedSeconds, mistakes: mistakes, hintsUsed: hintsUsed, hintCell: hintCell
        )
        try? services?.snapshots.save(snapshot, for: Self.gameID)
    }

    private static func cats(in marks: [Mark]) -> [Int] {
        marks.indices.filter { marks[$0] == .cat }
    }

    private static func makePuzzle(size: CatPuzzleSize, generator: inout SplitMix64?) -> CatPuzzle {
        if var seeded = generator {
            defer { generator = seeded }
            return CatPuzzleLogic.generate(size: size, using: &seeded)
        }
        var system = SystemRandomNumberGenerator()
        return CatPuzzleLogic.generate(size: size, using: &system)
    }
}

extension CatPuzzleSize {
    /// `game_start` の `level`（#500）。6×6 をやさしい、7×7 をふつう、8×8 を上級として送る。
    var analyticsLevel: AnalyticsLevel {
        switch self {
        case .easy: .beginner
        case .normal: .normal
        case .hard: .hard
        }
    }

    /// 記録の区分キー。大きさごとに自己ベストを分ける。
    var recordVariant: String { rawValue }

    /// 記録に保存する区分名（日本語の控え・`RecordVariantLabels` が表示言語で引き直す）。
    var recordVariantLabel: String { RecordVariantLabels.stored(gameID: CatPuzzleModel.gameID, variant: rawValue) }

    /// 画面に出す名前（「かんたん」など）。
    public var label: String {
        switch self {
        case .easy: tr("かんたん")
        case .normal: tr("ふつう")
        case .hard: tr("むずかしい")
        }
    }

    /// 「6×6」。数字と記号だけなので言語で変わらない。
    public var sizeLabel: String { "\(side)×\(side)" }
}
