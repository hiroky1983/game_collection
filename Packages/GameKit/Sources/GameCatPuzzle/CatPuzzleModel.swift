import Core
import CoreEngine
import Observation

/// おじさんの飼い猫パズル（#2250）のゲーム状態。問題・置いた印・ミス・ヒント・経過秒を持ち、
/// 中断スナップショットを書く。生成・判定の純粋ロジックは `CatPuzzleLogic` に委譲し、
/// ここは操作の受け付け・計時・永続化・決着の記録だけを担う。
///
/// 操作: マスをタップすると ×（いない）→ 猫 → 空 の順に変わる。答え（唯一解）でないマスに猫を置こうとしたら
/// 猫は置かず、そのマスに**赤い × を固定**で置いてミスを 1 数える（会長 QA 2026-10-21・build 42。答えとの一致を見せる）。
/// 固定の赤 × はタップ・戻す・やり直しで消えず、中断データにも残る。盤に残る猫は必ず答えのマスなので、
/// 決まり違反（同じ部屋・行・列に 2 匹、隣り合う）は起きない。猫が部屋の数だけ置けたらクリア。
/// 赤い ×（ミス）が `maxMistakes`（3）回目になったら終局（負け）にする（会長 QA 2026-10-21・build 43）。
///
/// 計時は盤が出た時点（画面の表示・新しい問題が出た瞬間）から動かす（最初のタップからではない。
/// 眺めて考えてから押せばタイムが縮む抜け道を塞ぐ・会長 QA 2026-10-21・build 43）。止めるのは画面側
/// （`gameTimerLifecycle`: 開始シート・確認・遊び方・広告・背面）。
@MainActor
@Observable
public final class CatPuzzleModel {
    /// 解析・記録・中断データの ID。`CatPuzzleModule.id` と同じ。
    public nonisolated static let gameID = "catpuzzle"
    /// 1 問につき無料で使えるヒントの回数。使い切ったあとの「広告を見て +1」は差し込み口だけ
    /// （試作の段階では広告を呼ばない・`CatPuzzleView`）。
    public static let freeHints = 3
    /// 赤い ×（ミス）の上限。この回数目で終局（負け）。
    public nonisolated static let maxMistakes = 3
    /// 計時中に保存し直す間隔（秒）。他の計時のあるゲームと同じ幅。
    static let persistInterval = 10
    /// 最後の猫を置いてからクリアのダイアログを出すまでの間（仮 0.8 秒・会長 QA 2026-10-21・build 42）。
    /// 最後の猫が「ぽん」と出る演出を見せてからダイアログを重ねる。
    public static let clearCardDelay: Duration = .milliseconds(800)

    /// マスの印。
    public enum Mark: Int, Codable, Sendable {
        case empty = 0
        case cross = 1
        case cat = 2
    }

    public private(set) var size: CatPuzzleSize
    public private(set) var puzzle: CatPuzzle
    public private(set) var marks: [Mark]
    /// 答えでないマスに猫を置こうとした回数。
    public private(set) var mistakes = 0
    /// 答えでないマスに猫を置こうとして付いた、固定の赤い ×（タップ・戻す・やり直しで消えない。中断データに保存）。
    public private(set) var wrongCrosses: Set<Int> = []
    /// 直近に赤い × が付いたマス（揺れ・赤の点滅の演出用）。次の操作で消える。保存しない。
    public private(set) var lastWrongCell: Int?
    public private(set) var hintsUsed = 0
    /// ヒントで置いた猫のマス（印付き・タップでも「戻す」「やり直し」でも消えない。会長の決まり 2026-10-21）。
    public private(set) var hintCells: Set<Int> = []
    /// ヒントで置いた × のマス（印付き・猫と同じく消えない。推理の 1 歩で確定した「いない」マス）。
    public private(set) var hintCrosses: Set<Int> = []
    /// 直近のヒントの中身（盤の下の理由の文と、光らせる行・列・部屋、置いた・× にしたマスの枠に使う）。次の操作で消える。保存しない。
    public private(set) var lastHint: CatPuzzleHint?
    /// 最初の 1 手からの経過秒。開いて眺めているだけの時間は数えない。
    public private(set) var elapsedSeconds = 0
    public private(set) var isSolved = false
    /// ミスが `maxMistakes` 回になって終局した（負け）。
    public private(set) var isFailed = false
    /// クリアのダイアログを出すか。最後の猫を置いてから `clearCardDelay` おいて真になる（`revealClearCardIfDue`）。
    public private(set) var showsClearCard = false
    /// クリアした時刻（ダイアログまでの間を測る）。
    private var solvedAt: ContinuousClock.Instant?
    /// 直近の決着で確定した自己ベスト。クリアのカードに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// タップした回数（手数）。
    public private(set) var moves = 0

    private let services: GameServices?
    private var generator: SplitMix64?
    /// 「戻す」用の履歴（印。保存しない。ヒントは履歴に積まず、戻してもヒントの猫は残す）。
    private var history: [[Mark]] = []
    private let stopwatch = GameStopwatch(persistInterval: CatPuzzleModel.persistInterval)
    /// 現在時刻の取り出し口（テストが時間を進めるために差し替える）。
    var clockNow: ElapsedClock.Now {
        get { stopwatch.now }
        set { stopwatch.now = newValue }
    }

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    /// `seed` を渡すと問題を種から決める（テスト・日替わり用。省略時はシステム乱数）。
    /// `defersStart` が真なら、新規開始の `game_start` を最初の操作か `startPlayIfPending()` まで遅らせる
    /// （開始シートを出す画面用。シートで始めると `newGame` が数えるので、ここで先に数えると 1 局が 2 回になる・
    /// 囲碁・チェスと同じ #1372）。
    public init(services: GameServices? = nil, size: CatPuzzleSize = .normal, seed: UInt64? = nil, defersStart: Bool = false) {
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
            hintCells = Set(snap.hintCells ?? [])
            hintCrosses = Set(snap.hintCrosses ?? [])
            wrongCrosses = Set(snap.wrongCrosses ?? [])
            // 赤い × の決まりより前（build 42 まで）の中断データには答えでない猫が残りうる。固定の赤 × に置き換える
            // （そのときのミスは数え済みなので足さない）。
            let solution = Set(snap.puzzle.solutionCells)
            for cell in marks.indices where marks[cell] == .cat && !solution.contains(cell) {
                marks[cell] = .cross
                wrongCrosses.insert(cell)
            }
        } else {
            self.size = size
            let made = Self.makePuzzle(size: size, generator: &seeded)
            puzzle = made
            marks = Array(repeating: .empty, count: made.cellCount)
            // 壊れた・手つかずの保存が残っていれば捨てる（印の無い盤は保存しない）。
            services?.snapshots.clear(for: Self.gameID)
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            if defersStart {
                pendingInitialStart = true
            } else {
                services?.gameDidStart(gameID: Self.gameID, level: size.analyticsLevel)
            }
        }
        generator = seeded
    }

    /// 遅らせている新規開始の `game_start`（`defersStart`）。冪等で、2 回目以降は何もしない。
    @ObservationIgnored private var pendingInitialStart = false

    /// 開始シートを閉じた（このまま今の盤で遊ぶ）・最初の操作をしたときに、遅らせていた `game_start` を数える。
    public func startPlayIfPending() {
        guard pendingInitialStart else { return }
        pendingInitialStart = false
        services?.gameDidStart(gameID: Self.gameID, level: size.analyticsLevel)
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

    /// 次のヒントの中身（推理の 1 歩。選び方は `CatPuzzleLogic.hint`）。解けていれば nil。
    public var nextHint: CatPuzzleHint? { CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) }

    /// 終局したか（クリア・ミス上限の負けのどちらでも）。
    public var isOver: Bool { isSolved || isFailed }

    /// あと何回まちがえられるか（上限で終局）。
    public var mistakesRemaining: Int { max(0, Self.maxMistakes - mistakes) }

    /// ヒントを押せるか。終局した・無料ぶんを使い切った・盤を進める手が無いときは押せない（回数は減らない）。
    public var canHint: Bool { !isOver && hintsRemaining > 0 && nextHint != nil }
    public var canUndo: Bool { !history.isEmpty && !isOver }

    /// 決まった印（ヒントの猫・×、赤い ×）のマスか。タップしても変わらない。
    public func isFixed(cell: Int) -> Bool {
        hintCells.contains(cell) || hintCrosses.contains(cell) || wrongCrosses.contains(cell)
    }

    /// 「新規ゲーム」・大きさの切り替え・やり直しで失われる進行があるか。印の無い盤と終局した盤は捨ててよい。
    public var hasProgressToLose: Bool { marks.contains { $0 != .empty } && !isOver }

    // MARK: - 操作

    /// マスをタップする。×（いない）→ 猫 → 空 の順に変わる。ヒントで置いた猫・×、赤い × のマスは変わらない。
    /// 答えでないマスに猫を置こうとしたら、猫は置かず赤い × を固定で置き、ミスを 1 数える。
    public func tap(cell: Int) {
        guard !isOver, marks.indices.contains(cell), !isFixed(cell: cell) else { return }
        startPlayIfPending()
        lastHint = nil
        lastWrongCell = nil
        let next: Mark
        switch marks[cell] {
        case .empty: next = .cross
        case .cross: next = .cat
        case .cat: next = .empty
        }
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        // 印を付けた = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: Self.gameID)
        if next == .cat, !puzzle.solutionCells.contains(cell) {
            // 戻せない印なので履歴には積まない（「戻す」で取り消せる操作ではない）。
            marks[cell] = .cross
            wrongCrosses.insert(cell)
            lastWrongCell = cell
            mistakes += 1
            if mistakes >= Self.maxMistakes {
                fail()
            } else {
                services?.feedback.notify(.warning)
                persist()
            }
            return
        }
        history.append(marks)
        marks[cell] = next
        services?.feedback.impact(next == .cat ? .medium : .light)
        if CatPuzzleLogic.isSolved(puzzle: puzzle, cats: catCells) {
            finish()
        } else {
            persist()
        }
    }

    /// 直前のタップを取り消す。ヒントで置いた猫・× は戻しても残る。
    public func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        marks = previous
        keepFixedMarks()
        lastHint = nil
        lastWrongCell = nil
        moves += 1
        services?.feedback.impact(.light)
        persist()
    }

    /// 印を全部消して同じ問題を最初から。ミス・ヒント・経過秒は引き継ぎ、ヒントで置いた猫・×、赤い × も残る。
    public func reset() {
        guard !isOver else { return }
        history.removeAll()
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        keepFixedMarks()
        lastHint = nil
        lastWrongCell = nil
        services?.feedback.impact(.light)
        // 印の無い盤は保存しない（開いただけの盤を「続き」にしない）。ヒント・赤い × の印があれば保存する。
        persist()
    }

    /// ヒントを 1 回使う。推理の 1 歩（`CatPuzzleLogic.hint`）を盤に反映する: 確定した × を置き、猫が確定する
    /// ときだけ猫を置く。答えでない位置の猫があれば先にそれを × に変える。ヒントで置いた猫・× は印付きで消せない。
    /// 回数は必ず 1 だけ減り、盤は必ず 1 歩進む。置いた結果で盤が完成すればそのままクリア。
    public func useHint() {
        guard canHint, let hint = nextHint else { return }
        startPlayIfPending()
        for cell in hint.removed + hint.crossed {
            marks[cell] = .cross
            hintCrosses.insert(cell)
        }
        if let placed = hint.placed {
            marks[placed] = .cat
            hintCells.insert(placed)
        }
        lastHint = hint
        lastWrongCell = nil
        hintsUsed += 1
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        services?.gameDidUseHint(gameID: Self.gameID)
        services?.gameDidProgress(gameID: Self.gameID)
        services?.feedback.impact(.medium)
        if CatPuzzleLogic.isSolved(puzzle: puzzle, cats: catCells) {
            finish()
        } else {
            persist()
        }
    }

    /// ヒントで置いた猫・×、赤い × を盤に戻す（「戻す」「やり直し」で消えないように）。
    private func keepFixedMarks() {
        for cell in hintCells where marks.indices.contains(cell) { marks[cell] = .cat }
        for cell in hintCrosses.union(wrongCrosses) where marks.indices.contains(cell) { marks[cell] = .cross }
    }

    /// 新規ゲーム。`size` を渡すと盤の大きさを変える。
    public func newGame(size newSize: CatPuzzleSize? = nil) {
        if let newSize { size = newSize }
        stopwatch.stop()
        puzzle = Self.makePuzzle(size: size, generator: &generator)
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        history.removeAll()
        mistakes = 0
        hintsUsed = 0
        hintCells = []
        hintCrosses = []
        wrongCrosses = []
        lastWrongCell = nil
        lastHint = nil
        elapsedSeconds = 0
        moves = 0
        isSolved = false
        isFailed = false
        // 開始シートで始めた局は `gameDidRestart` だけで数える（遅らせていた開始は捨てる）。
        pendingInitialStart = false
        showsClearCard = false
        solvedAt = nil
        recordResult = nil
        services?.snapshots.clear(for: Self.gameID)
        services?.gameDidRestart(gameID: Self.gameID, level: size.analyticsLevel)
        // 新しい問題が出た瞬間から計時する（止めるのは画面側のシート・背面など）。
        startTimer()
    }

    // MARK: - 計時

    /// 盤が出たとき・画面に戻ったときの開始／再開。1 手目より前でも数える（盤が見えていれば考えている時間）。
    /// 終局した後は数えない。
    public func resumeTimerIfNeeded() {
        guard !isOver, !stopwatch.isRunning else { return }
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
        solvedAt = stopwatch.now()
        showsClearCard = false
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

    /// ミスが上限に達した終局（負け）。記録・解析は負け（`game_end` result=loss）。中断データは消す。
    private func fail() {
        syncElapsed()
        stopwatch.stop()
        isFailed = true
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .loss,
            score: GameScore(
                metric: .shortestTime, seconds: elapsedSeconds,
                variant: size.recordVariant, variantLabel: size.recordVariantLabel
            )
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    /// クリアのダイアログまでの残り時間（解けていなければ nil、出してよければ 0）。画面はこの分だけ待って
    /// `revealClearCardIfDue` を呼ぶ。
    public var clearCardWait: Duration? {
        guard isSolved, let solvedAt else { return nil }
        guard !showsClearCard else { return .zero }
        return max(.zero, Self.clearCardDelay - (stopwatch.now() - solvedAt))
    }

    /// クリアから `clearCardDelay` 経っていれば、クリアのダイアログを出す。
    public func revealClearCardIfDue() {
        guard let wait = clearCardWait, wait == .zero else { return }
        showsClearCard = true
    }

    private func persist() {
        // 印の無い盤と解き終えた盤は保存しない（印を全部消したら、残っていた保存も捨てる）。
        guard hasProgressToLose else {
            services?.snapshots.clear(for: Self.gameID)
            return
        }
        let snapshot = CatPuzzleSnapshot(
            size: size.rawValue, puzzle: puzzle, marks: marks.map(\.rawValue),
            elapsedSeconds: elapsedSeconds, mistakes: mistakes, hintsUsed: hintsUsed, hintCells: hintCells.sorted(),
            hintCrosses: hintCrosses.sorted(), wrongCrosses: wrongCrosses.sorted()
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
