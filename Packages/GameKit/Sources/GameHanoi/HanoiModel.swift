import Core
import Observation

/// ハノイの塔のゲーム状態（#2003・企画倉庫）。盤・手数・経過秒を持ち、中断スナップショットを書く。
/// 純粋ロジックは `HanoiLogic` に委譲し、ここは操作の受け付け・計時・永続化・決着の記録だけを担う。
///
/// 操作は「柱をタップして取る → 別の柱をタップして置く」。取った柱をもう一度タップすると取り消し。
@MainActor
@Observable
public final class HanoiModel {
    nonisolated public static let gameID = "hanoi"
    /// 計時中に保存し直す間隔（秒）。他の計時のあるゲームと同じ幅。
    static let persistInterval = 10

    public private(set) var disks: Int
    /// 柱 3 本。各柱は下から上へ円盤の大きさ（1 が最小）。
    public private(set) var pegs: [[Int]]
    public private(set) var moves = 0
    /// 1 手目を動かしてからの経過秒。開いて眺めているだけの時間は数えない。
    public private(set) var elapsedSeconds = 0
    public private(set) var isSolved = false
    /// 取っている円盤の柱。nil なら何も取っていない。
    public private(set) var selectedPeg: Int?
    /// 直前の操作を断った理由。次に動かせたら消える。
    public private(set) var rejection: HanoiLogic.Rejection?
    /// 断った回数。同じ理由が続いても読み上げを毎回出すため、View はこの値の変化で通知する。
    public private(set) var rejectionCount = 0
    /// 直近の決着で確定した自己ベスト。クリアのカードに 1 行出す。
    public private(set) var recordResult: RecordResult?

    private let services: GameServices?
    private let stopwatch = GameStopwatch(persistInterval: HanoiModel.persistInterval)
    /// 現在時刻の取り出し口（テストが時間を進めるために差し替える）。
    var clockNow: ElapsedClock.Now {
        get { stopwatch.now }
        set { stopwatch.now = newValue }
    }

    /// services を渡すと、中断スナップショットがあれば復元、無ければ `disks` 枚で新規開始する。
    public init(services: GameServices? = nil, disks: Int = HanoiLogic.defaultDisks) {
        self.services = services
        if let snap = services?.snapshots.load(HanoiSnapshot.self, for: Self.gameID),
           HanoiSnapshot.isResumable(snap) {
            self.disks = snap.disks
            pegs = snap.pegs
            moves = snap.moves
            elapsedSeconds = max(0, snap.elapsedSeconds)
        } else {
            let count = HanoiLogic.diskRange.contains(disks) ? disks : HanoiLogic.defaultDisks
            self.disks = count
            pegs = HanoiLogic.initial(disks: count)
            // 壊れた・手つかずの保存が残っていれば捨てる（手つかずの盤は保存しない・#1847）。
            services?.snapshots.clear(for: Self.gameID)
            // 中断からの復元は「新しいプレイ」ではないので開始は数えない。
            services?.gameDidStart(gameID: Self.gameID, level: Self.analyticsLevel(disks: count))
        }
    }

    /// 最少手数（2ⁿ−1 手）。
    public var minimumMoves: Int { HanoiLogic.minimumMoves(disks: disks) }

    /// 「新規ゲーム」・枚数の切り替えで失われる進行があるか。1 手も動かしていない盤と解き終えた盤は捨ててよい。
    public var hasProgressToLose: Bool { moves > 0 && !isSolved }

    /// 柱をタップする。何も取っていなければ取り、取っていればそこへ置く（同じ柱なら取り消し）。
    public func tap(peg: Int) {
        guard !isSolved, pegs.indices.contains(peg) else { return }
        guard let from = selectedPeg else {
            if pegs[peg].isEmpty {
                reject(.emptySource)
            } else {
                selectedPeg = peg
                rejection = nil
                services?.feedback.impact(.light)
            }
            return
        }
        if from == peg {
            selectedPeg = nil
            return
        }
        guard let next = HanoiLogic.moving(pegs, from: from, to: peg) else {
            // 置けなければ取ったまま（別の柱を選び直せる）。
            reject(HanoiLogic.rejection(pegs, from: from, to: peg) ?? .largerOnSmaller)
            return
        }
        pegs = next
        moves += 1
        selectedPeg = nil
        rejection = nil
        // 1 手目で計時を始める。
        if moves == 1 { startTimer() }
        // 盤が動いた = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: Self.gameID)
        if HanoiLogic.isSolved(pegs, disks: disks) {
            finish()
        } else {
            services?.feedback.impact(.light)
            persist()
        }
    }

    /// 新規ゲーム。`disks` を渡すとその枚数で始める（枚数の切り替え）。
    public func newGame(disks newDisks: Int? = nil) {
        if let newDisks, HanoiLogic.diskRange.contains(newDisks) { disks = newDisks }
        stopwatch.stop()
        pegs = HanoiLogic.initial(disks: disks)
        moves = 0
        elapsedSeconds = 0
        isSolved = false
        selectedPeg = nil
        rejection = nil
        recordResult = nil
        services?.snapshots.clear(for: Self.gameID)
        services?.gameDidRestart(gameID: Self.gameID, level: Self.analyticsLevel(disks: disks))
    }

    // MARK: - 計時

    /// 画面に戻ったときの再開。1 手目より前・解き終えた後は数えない。
    public func resumeTimerIfNeeded() {
        guard moves > 0, !isSolved, !stopwatch.isRunning else { return }
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
        services?.feedback.notify(.success)
        // 決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。記録は枚数ごとに分ける（3 枚と 7 枚は比べない）。
        let variant = Self.recordVariant(disks: disks)
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .win,
            score: GameScore(
                metric: .fewestMoves, seconds: elapsedSeconds, moves: moves,
                variant: variant,
                variantLabel: RecordVariantLabels.stored(gameID: Self.gameID, variant: variant)
            )
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    private func reject(_ reason: HanoiLogic.Rejection) {
        rejection = reason
        rejectionCount += 1
        services?.feedback.notify(.warning)
    }

    private func persist() {
        // 1 手も動かしていない盤と解き終えた盤は保存しない。
        guard moves > 0, !isSolved else { return }
        let snapshot = HanoiSnapshot(disks: disks, pegs: pegs, moves: moves, elapsedSeconds: elapsedSeconds)
        try? services?.snapshots.save(snapshot, for: Self.gameID)
    }

    // MARK: - 区分

    /// 記録の区分キー（`RecordVariantLabels` の `hanoi` と同じ形・例: `5disks`）。
    static func recordVariant(disks: Int) -> String { "\(disks)disks" }

    /// `game_start` の `level`。枚数 3〜7 を 5 段階に当てる。
    static func analyticsLevel(disks: Int) -> AnalyticsLevel {
        switch disks {
        case ...3: .novice
        case 4: .beginner
        case 5: .normal
        case 6: .hard
        default: .expert
        }
    }
}
