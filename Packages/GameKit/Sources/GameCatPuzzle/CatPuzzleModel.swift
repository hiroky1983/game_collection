import Foundation
import Core
import CoreEngine
import Observation

/// おじさんちのねこさがし（#2250）のゲーム状態。問題・置いた印・ミス・ヒント・経過秒を持ち、
/// 中断スナップショットを書く。生成・判定の純粋ロジックは `CatPuzzleLogic` に委譲し、
/// ここは操作の受け付け・計時・永続化・決着の記録だけを担う。
///
/// 操作: マスをタップすると ×（いない）を付け外しし、ダブルタップでそのマスに猫を見つける（会長 QA 2026-10-22・build 45。
/// 「一回バツ印つけるとキャンセルできない」への対応。× の付け外しはミスにならない）。答え（唯一解）でないマスで
/// 猫を見つけようとしたら猫は置かず、そのマスに**赤い × を固定**で置いてミスを 1 数える（会長 QA 2026-10-21・build 42。答えとの一致を見せる）。
/// 固定の赤 × はタップ・戻す・やり直しで消えず、中断データにも残る。盤に残る猫は必ず答えのマスなので、
/// 決まり違反（同じ部屋・行・列に 2 匹、隣り合う）は起きない。猫が部屋の数だけ置けたらクリア。
/// 赤い ×（ミス）が `maxMistakes`（3）回目になったら終局（負け）にする（会長 QA 2026-10-21・build 43）。
/// 3 回目のミスで終局する前に、1 局 1 回だけ「広告を見て続ける」を提案する（`isOfferingContinue`・#2780。画面は負けの
/// 結果カード 1 枚の中に「広告を見てコンティニュー」「あきらめて正解を見る」を並べる・#2904）。続けるとミスが 1 回ぶん戻り（赤い × は盤に残る）、断ったら負けを確定して
/// まだ見つけていない猫の場所（`unfoundCats`）を盤に見せる。答えを見せたあとはコンティニューできない。
///
/// 計時は盤が出た時点（画面の表示・新しい問題が出た瞬間）から動かす（最初のタップからではない。
/// 眺めて考えてから押せばタイムが縮む抜け道を塞ぐ・会長 QA 2026-10-21・build 43）。止めるのは画面側
/// （`gameTimerLifecycle`: 開始シート・確認・遊び方・広告・背面）。
@MainActor
@Observable
public final class CatPuzzleModel {
    /// 解析・記録・中断データの ID。`CatPuzzleModule.id` と同じ。
    public nonisolated static let gameID = "catpuzzle"
    /// 1 問につき無料で使えるヒントの回数。使い切ったあとはリワード広告 1 本ごとに 1 回足せる（上限 `adHints`・`CatPuzzleView`）。
    /// 1 局 1 回（会長決裁 2026-10-28・#3048。3 回だと広告の追加と合わせてヒントだけで解き切れてしまうため）。
    public static let freeHints = 1
    /// 無料を使い切ったあと、広告で足せるヒントの上限（1 局で合計 `freeHints + adHints` = 4 回・会長決裁 2026-10-28・#3048）。
    /// いちばん小さい 6×6（猫 6 匹）でも、ヒントだけでは全部見つからないようにする。
    public static let adHints = 3
    /// 赤い ×（ミス）の上限。この回数目で終局（負け）。
    public nonisolated static let maxMistakes = 3
    /// 計時中に保存し直す間隔（秒）。他の計時のあるゲームと同じ幅。
    static let persistInterval = 10
    /// 最後の猫を置いてからクリアのダイアログを出すまでの間（仮 0.8 秒・会長 QA 2026-10-21・build 42）。
    /// 最後の猫が「ぽん」と出る演出を見せてからダイアログを重ねる。
    public static let clearCardDelay: Duration = .milliseconds(800)
    /// 同じマスへの 2 回目のタップをダブルタップとみなす間隔（会長 QA 2026-10-22・build 45）。
    /// 1 回目はすぐ × を付け外しし（単タップを遅らせない）、この間に同じマスへ 2 回目が来たら 1 回目を取り消して猫を見つける。
    public static let doubleTapInterval: Duration = .milliseconds(300)

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
    /// この局のヒントの回数（無料 `freeHints` 回 + 広告で最大 `adHints` 回）。勘定は Core の `BoardHintBudget`。
    public private(set) var hints = BoardHintBudget(freeLimit: CatPuzzleModel.freeHints, adLimit: CatPuzzleModel.adHints)
    /// この局で使ったヒントの回数（無料・広告の合計。中断データに保存する）。
    public var hintsUsed: Int { hints.used }
    /// 局の通し番号。広告を出す前に控え、視聴中に新しい局へ入れ替わっていたら報酬を乗せない（#815）。
    public private(set) var gameSerial = 0
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
    /// 3 回目のミスの直後で、広告を見て続けるかを選ばせている間。計時は止まり、盤は操作できない。
    /// 断る（`declineContinue`）か広告を見る（`continueAfterAd`）まで終局にしない。
    public private(set) var isOfferingContinue = false
    /// この局でコンティニューを使った。使ったら 2 回目の提案はせず、次の 3 回目のミスでそのまま負け。
    public private(set) var continueUsed = false
    /// クリアのダイアログを出すか。最後の猫を置いてから `clearCardDelay` おいて真になる（`revealClearCardIfDue`）。
    public private(set) var showsClearCard = false
    /// クリアした時刻（ダイアログまでの間を測る）。
    private var solvedAt: ContinuousClock.Instant?
    /// 直近の決着で確定した自己ベスト。クリアのカードに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// タップした回数（手数）。
    public private(set) var moves = 0
    /// ステージモードの面の番号（#3048）。自由に遊ぶ盤なら nil。
    public private(set) var stage: Int?
    /// ステージの問題を裏で作っている間（`startStage`）。盤は操作できず、計時もしない。
    public private(set) var isPreparingStage = false
    /// ステージの進み具合（次に遊ぶ面の番号）の保存先。テストは専用の `UserDefaults` を渡す。
    @ObservationIgnored private let stageDefaults: UserDefaults
    /// ステージの問題の作成を頼んだ回数。作っている間に別の局へ切り替わったら、出来上がった問題は捨てる。
    @ObservationIgnored private var stageRequest = 0
    /// 次の面を先に作っておく（遊んでいる間に裏で作り、「次のステージへ」で待たせない）。
    @ObservationIgnored private var prefetched: (number: Int, task: Task<CatPuzzle, Never>)?
    /// 作っている最中のステージの問題を盤に出すまでの段取り（テストが待つ）。
    @ObservationIgnored private(set) var stagePreparation: Task<Void, Never>?
    /// いま作っている面の番号と、その問題を作っている計算（取り消すときに止める）。
    @ObservationIgnored private var preparingStage: Int?
    @ObservationIgnored private var stageGeneration: Task<CatPuzzle, Never>?

    private let services: GameServices?
    private var generator: SplitMix64?
    /// 「戻す」用の履歴（印。保存しない。ヒントは履歴に積まず、戻してもヒントの猫は残す）。
    private var history: [[Mark]] = []
    /// 直前の 1 回目のタップ（ダブルタップの 2 回目が来たら、その × の付け外しを取り消すための控え）。保存しない。
    private struct PendingTap {
        let cell: Int
        let at: ContinuousClock.Instant
        /// 1 回目で × を付け外ししたか（猫・決まった印のマスでは何も変わらない）。
        let toggled: Bool
        let marksBefore: [Mark]
        let historyCount: Int
        let movesBefore: Int
    }
    @ObservationIgnored private var pendingTap: PendingTap?
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
    public init(services: GameServices? = nil, size: CatPuzzleSize = .normal, seed: UInt64? = nil, defersStart: Bool = false,
                stageDefaults: UserDefaults = .standard) {
        self.services = services
        self.stageDefaults = stageDefaults
        var seeded = seed.map { SplitMix64(seed: $0) }
        if let snap = services?.snapshots.load(CatPuzzleSnapshot.self, for: Self.gameID),
           CatPuzzleSnapshot.isResumable(snap), let restoredSize = CatPuzzleSize(rawValue: snap.size) {
            self.size = restoredSize
            puzzle = snap.puzzle
            marks = snap.marks.compactMap(Mark.init(rawValue:))
            elapsedSeconds = snap.elapsedSeconds
            mistakes = snap.mistakes
            continueUsed = snap.continueUsed ?? false
            stage = snap.stage
            // ミスが上限のまま保存されている = コンティニューの提案の最中に離れた局。提案から続ける。
            isOfferingContinue = snap.mistakes >= Self.maxMistakes
            hints = BoardHintBudget(used: snap.hintsUsed, freeLimit: Self.freeHints, adLimit: Self.adHints)
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
                services?.gameDidStart(gameID: Self.gameID, level: analyticsLevel)
            }
        }
        generator = seeded
        // 続きのステージを遊んでいる間に、次の面を裏で作っておく。
        if let stage { prefetchStage(stage + 1) }
    }

    /// 遅らせている新規開始の `game_start`（`defersStart`）。冪等で、2 回目以降は何もしない。
    @ObservationIgnored private var pendingInitialStart = false

    /// 開始シートを閉じた（このまま今の盤で遊ぶ）・最初の操作をしたときに、遅らせていた `game_start` を数える。
    public func startPlayIfPending() {
        guard pendingInitialStart else { return }
        pendingInitialStart = false
        services?.gameDidStart(gameID: Self.gameID, level: analyticsLevel)
    }

    /// 問題を直接与えて開始する。狙った局面から検証するためのテスト用の経路。
    public init(services: GameServices? = nil, puzzle: CatPuzzle, size: CatPuzzleSize = .normal, stage: Int? = nil,
                stageDefaults: UserDefaults = .standard) {
        self.services = services
        self.stageDefaults = stageDefaults
        self.stage = stage
        self.size = size
        self.puzzle = puzzle
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        services?.snapshots.clear(for: Self.gameID)
        services?.gameDidStart(gameID: Self.gameID, level: analyticsLevel)
    }

    // MARK: - 読み取り

    /// 猫を置いたマス。
    public var catCells: [Int] { Self.cats(in: marks) }

    /// まだ置いていない猫の数（部屋の数 − 置いた猫）。
    public var remainingCats: Int { max(0, puzzle.side - catCells.count) }

    /// いま使えるヒントの回数（無料ぶんの残り）。ボタンの「あと n 回」はこの数で、広告で足せる分は含めない（#1897）。
    public var hintsRemaining: Int { hints.freeRemaining }

    /// 無料ぶんを使い切っていて、次の 1 回に広告が要るか（広告の追加まで使い切ったら false）。
    public var needsAdForHint: Bool { !hints.hasFreeRemaining && !hints.isExhausted }

    /// 次のヒントの中身（推理の 1 歩。選び方は `CatPuzzleLogic.hint`）。解けていれば nil。
    public var nextHint: CatPuzzleHint? { CatPuzzleLogic.hint(puzzle: puzzle, marks: marks) }

    /// 終局したか（クリア・ミス上限の負けのどちらでも）。
    public var isOver: Bool { isSolved || isFailed }

    /// 盤を操作できない間（終局、またはコンティニューの提案中）。
    private var isFrozen: Bool { isOver || isOfferingContinue || isPreparingStage }

    /// 負けたあとに見せる、まだ見つけていない猫の場所（正解のうち猫の印が無いマス。行→列の順）。負けていなければ空。
    public var unfoundCats: [Int] {
        guard isFailed else { return [] }
        return puzzle.solutionCells.filter { marks.indices.contains($0) && marks[$0] != .cat }.sorted()
    }

    /// 範囲内ならそのマスの部屋番号と印、範囲外なら `nil`（#3141）。View は `nil` のとき空のマスを返す。
    /// 盤が小さくなる新規（9×9→5×5 等）の差分更新で、旧盤面の添字のまま残った子が評価されても落ちないようにする（#489・#3084 と同じ型）。
    public func cellState(at cell: Int) -> (room: Int, mark: Mark)? {
        guard puzzle.rooms.indices.contains(cell), marks.indices.contains(cell) else { return nil }
        return (puzzle.rooms[cell], marks[cell])
    }

    /// 負けたあとの正解の場所か（読み上げ用）。
    public func isUnfoundCat(cell: Int) -> Bool { unfoundCats.contains(cell) }

    /// あと何回まちがえられるか（上限で終局）。
    public var mistakesRemaining: Int { max(0, Self.maxMistakes - mistakes) }

    /// ヒントを押せるか。終局した・広告の追加まで使い切った・盤を進める手が無いときは押せない（回数は減らない）。
    /// 無料ぶんを使い切っていても広告で足せるうちは押せる（押すと広告・`needsAdForHint`）。
    public var canHint: Bool { !isFrozen && !hints.isExhausted && nextHint != nil }
    public var canUndo: Bool { !history.isEmpty && !isFrozen }

    /// 決まった印（ヒントの猫・×、赤い ×）のマスか。タップしても変わらない。
    public func isFixed(cell: Int) -> Bool {
        hintCells.contains(cell) || hintCrosses.contains(cell) || wrongCrosses.contains(cell)
    }

    /// 「新規ゲーム」・大きさの切り替え・やり直しで失われる進行があるか。印の無い盤と終局した盤は捨ててよい。
    public var hasProgressToLose: Bool { marks.contains { $0 != .empty } && !isOver }

    // MARK: - 操作

    /// 画面のタップの入口（1 回のタップごとに呼ぶ）。1 回目はすぐ `toggleCross` で × を付け外しする（単タップを遅らせない）。
    /// 同じマスへの 2 回目が `doubleTapInterval` 以内に来たらダブルタップとみなし、1 回目の付け外しを取り消して
    /// （印・「戻す」の履歴・手数を 1 回目の前に戻して）から `findCat` する。3 回目は新しい 1 回目として扱う。
    /// 時刻は `clockNow`（タップを受けた時点）で測る。
    public func tap(cell: Int) {
        let now = stopwatch.now()
        if let first = pendingTap, first.cell == cell, now - first.at <= Self.doubleTapInterval {
            pendingTap = nil
            if first.toggled, !isFrozen {
                marks = first.marksBefore
                history.removeSubrange(min(first.historyCount, history.count)...)
                moves = first.movesBefore
            }
            findCat(cell: cell)
            return
        }
        let before = (marks: marks, history: history.count, moves: moves)
        let toggled = toggleCross(cell: cell)
        pendingTap = PendingTap(cell: cell, at: now, toggled: toggled, marksBefore: before.marks,
                                historyCount: before.history, movesBefore: before.moves)
    }

    /// シングルタップ: 空のマスに × を付け、× のマスなら外す（空に戻す）。ミスにはならない。
    /// 猫のいるマス・ヒントで置いた猫・×、赤い × のマスは変わらない。付け外ししたら真を返す。
    @discardableResult
    public func toggleCross(cell: Int) -> Bool {
        // 直接の呼び出し（VoiceOver のアクションなど）は、手前の 1 回目のタップの控えを捨てる（`tap` は呼んだ後で控え直す）。
        pendingTap = nil
        guard !isFrozen, marks.indices.contains(cell), !isFixed(cell: cell), marks[cell] != .cat else { return false }
        startPlayIfPending()
        lastHint = nil
        lastWrongCell = nil
        let next: Mark = marks[cell] == .cross ? .empty : .cross
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        // 印を付けた = 捨てたら途中離脱として数える盤面。
        services?.gameDidProgress(gameID: Self.gameID)
        history.append(marks)
        marks[cell] = next
        services?.feedback.impact(.light)
        persist()
        return true
    }

    // MARK: - スライドで続けて ×（#3116）

    /// 指の動きがマスの一辺のこの割合に届くまではタップとして扱う（届いたらスライド）。
    public static let slideThreshold: Double = 0.4

    /// 盤の座標（盤の左上が原点）から、いま指があるマスの番号。盤の外（余白・枠の外）は nil。
    public static func cell(at point: CGPoint, side: Int, cellSide: CGFloat, inset: CGFloat) -> Int? {
        let col = Int(((point.x - inset) / cellSide).rounded(.down))
        let row = Int(((point.y - inset) / cellSide).rounded(.down))
        guard (0..<side).contains(col), (0..<side).contains(row) else { return nil }
        return row * side + col
    }

    /// `from` から `to` までに通ったマス（両端を含む。マスの中心どうしを結ぶ線）。速いスライドで飛んだマスを埋める。
    public static func cellsOnLine(from: Int, to: Int, side: Int) -> [Int] {
        var (col, row) = (from % side, from / side)
        let (endCol, endRow) = (to % side, to / side)
        let dx = abs(endCol - col), dy = abs(endRow - row)
        let (stepX, stepY) = (col < endCol ? 1 : -1, row < endRow ? 1 : -1)
        var error = dx - dy
        var cells = [row * side + col]
        while col != endCol || row != endRow {
            let doubled = error * 2
            if doubled > -dy { error -= dy; col += stepX }
            if doubled < dx { error += dx; row += stepY }
            cells.append(row * side + col)
        }
        return cells
    }

    /// スライド 1 回ぶんの状態。向きは最初に触れたマスで決まる（空なら付ける・× なら外す）。
    private struct CrossDrag {
        let adds: Bool
        var changed: Set<Int> = []
        var last: Int?
        var hasChangedAny = false
    }
    @ObservationIgnored private var crossDrag: CrossDrag?

    /// スライドの開始（指が `slideThreshold` 以上動いて、スライドと決まったとき）。最初のマスの印で向きを決め、
    /// そのマスにも適用する。ダブルタップの控え（`pendingTap`）は捨てる。
    public func beginCrossDrag(cell: Int) {
        pendingTap = nil
        guard !isFrozen, marks.indices.contains(cell) else { return }
        crossDrag = CrossDrag(adds: marks[cell] != .cross)
        dragCross(to: cell)
    }

    /// 指が `cell` に来た（盤の外に出ているときは nil）。前のマスとの間も通ったものとして、向きに合うマスだけ変える。
    /// 同じマスは 1 回のスライドで 1 回しか変えない。猫・決まった印のマスは変えない。
    public func dragCross(to cell: Int?) {
        guard var drag = crossDrag, !isFrozen else { return }
        defer { crossDrag = drag }
        guard let cell, marks.indices.contains(cell) else {
            drag.last = nil
            return
        }
        let path = drag.last.map { Self.cellsOnLine(from: $0, to: cell, side: puzzle.side) } ?? [cell]
        drag.last = cell
        for passed in path where !drag.changed.contains(passed) {
            guard !isFixed(cell: passed), marks[passed] != .cat,
                  marks[passed] == (drag.adds ? .empty : .cross) else { continue }
            if !drag.hasChangedAny {
                // 最初に変わるときに 1 回だけ履歴を積む（スライド全体が「戻す」1 回ぶん・手数も 1）。
                drag.hasChangedAny = true
                startPlayIfPending()
                lastHint = nil
                lastWrongCell = nil
                moves += 1
                if !stopwatch.isRunning { startTimer() }
                services?.gameDidProgress(gameID: Self.gameID)
                history.append(marks)
            }
            drag.changed.insert(passed)
            marks[passed] = drag.adds ? .cross : .empty
            services?.feedback.impact(.light)
        }
    }

    /// 指を離した（スライドの確定）。変わったマスがあれば保存する。
    public func endCrossDrag() {
        guard let drag = crossDrag else { return }
        crossDrag = nil
        if drag.hasChangedAny { persist() }
    }

    /// ダブルタップ: そのマスで猫を見つける（空でも × でも同じ）。答えのマスなら猫を置き、答えでなければ猫は置かず
    /// 赤い × を固定で置いてミスを 1 数える。猫のいるマス・ヒントで置いた猫・×、赤い × のマスでは何もしない。
    public func findCat(cell: Int) {
        pendingTap = nil
        guard !isFrozen, marks.indices.contains(cell), !isFixed(cell: cell), marks[cell] != .cat else { return }
        startPlayIfPending()
        lastHint = nil
        lastWrongCell = nil
        moves += 1
        if !stopwatch.isRunning { startTimer() }
        services?.gameDidProgress(gameID: Self.gameID)
        if !puzzle.solutionCells.contains(cell) {
            // 戻せない印なので履歴には積まない（「戻す」で取り消せる操作ではない）。
            marks[cell] = .cross
            wrongCrosses.insert(cell)
            lastWrongCell = cell
            mistakes += 1
            if mistakes >= Self.maxMistakes {
                if continueUsed {
                    fail()
                } else {
                    offerContinue()
                }
            } else {
                services?.feedback.notify(.warning)
                persist()
            }
            return
        }
        history.append(marks)
        marks[cell] = .cat
        services?.feedback.impact(.medium)
        if CatPuzzleLogic.isSolved(puzzle: puzzle, cats: catCells) {
            finish()
        } else {
            persist()
        }
    }

    /// 直前の × の付け外し・見つけた猫を取り消す。ヒントで置いた猫・×、赤い × は戻しても残る。
    public func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
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
        guard !isFrozen else { return }
        history.removeAll()
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
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
    /// 無料ぶんだけを使う。使い切っていたら何もしない（広告の 1 回は `grantAdHint(forGame:)`）。
    public func useHint() {
        guard canHint, !needsAdForHint, let hint = nextHint, hints.consume() else { return }
        apply(hint)
    }

    /// 広告を最後まで見たあとの 1 回。`game` は広告を出す前に控えた `gameSerial`。
    /// 局が入れ替わっていた・終局した・無料ぶんが残っている・盤を進める手が無いときは適用せず false（回数も減らさない）。
    @discardableResult
    public func grantAdHint(forGame game: Int) -> Bool {
        guard game == gameSerial, canHint, needsAdForHint, let hint = nextHint, hints.consumeAd() else { return false }
        apply(hint)
        return true
    }

    /// ヒントの中身を盤に反映する（回数の消費は呼び出し側が済ませている）。
    private func apply(_ hint: CatPuzzleHint) {
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
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

    /// 新規ゲーム（自由に遊ぶ）。`size` を渡すと盤の大きさを変える。ステージの途中からでも自由に遊ぶへ切り替わる。
    public func newGame(size newSize: CatPuzzleSize? = nil) {
        if let newSize { size = newSize }
        cancelStagePreparation()
        begin(puzzle: Self.makePuzzle(size: size, generator: &generator), size: size, stage: nil)
    }

    // MARK: - ステージ（#3048）

    /// ステージの進み具合（次に遊ぶ面の番号）の保存キー。進み具合はこの番号だけを持つ（面ごとの記録は持たない）。
    public static let stageProgressKey = "catPuzzleStage"

    /// 次に遊ぶ面の番号（1 始まり）。クリアするたびに 1 つ進み、負けても戻らない。
    public var savedStage: Int { max(1, stageDefaults.integer(forKey: Self.stageProgressKey)) }

    /// ステージの面を始める。`number` を省くと次に遊ぶ面（`savedStage`）。問題はステージ番号から決めた種で作る
    /// （`CatPuzzleStage`・9×9 は数秒かかることがあるので裏で作る）。作っている間は `isPreparingStage` が真で、
    /// 盤は前のまま操作できない。先に作っておいた次の面（`prefetchStage`）があればそれを使う。
    public func startStage(_ number: Int? = nil) {
        let n = max(1, number ?? savedStage)
        // 同じ面を作っている最中の 2 回目（「次のステージへ」の連打）は何もしない（同じ問題を二重に作らない）。
        if isPreparingStage, preparingStage == n { return }
        cancelStagePreparation()
        let request = stageRequest
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        stopwatch.stop()
        isPreparingStage = true
        preparingStage = n
        let task: Task<CatPuzzle, Never>
        if let prefetched, prefetched.number == n {
            task = prefetched.task
        } else {
            // 別の面を先に作っていたら止める（使わない計算を残さない）。
            prefetched?.task.cancel()
            prefetched = nil
            task = Self.makeStagePuzzle(n)
        }
        stageGeneration = task
        stagePreparation = Task { [weak self] in
            let made = await task.value
            guard let self, self.stageRequest == request else { return }
            self.isPreparingStage = false
            self.preparingStage = nil
            self.stageGeneration = nil
            self.begin(puzzle: made, size: CatPuzzleStage(n).size, stage: n)
            self.prefetchStage(n + 1)
        }
    }

    /// 次の面を裏で作っておく（作り終えた問題は `startStage` が使う）。
    private func prefetchStage(_ number: Int) {
        guard prefetched?.number != number else { return }
        prefetched?.task.cancel()
        prefetched = (number, Self.makeStagePuzzle(number))
    }

    /// 作っている最中のステージの問題を捨てる（出来上がっても盤に出さない）。作っている計算も止める
    /// （`CatPuzzleStage.makePuzzle` は取り消されたら途中で抜ける）。止めた計算が先読みのものなら、先読みの記録も消す。
    private func cancelStagePreparation() {
        stageRequest += 1
        if let generation = stageGeneration {
            generation.cancel()
            if prefetched?.task == generation { prefetched = nil }
        }
        stageGeneration = nil
        stagePreparation = nil
        isPreparingStage = false
        preparingStage = nil
    }

    /// ステージの問題をメインスレッドの外で作る。
    nonisolated private static func makeStagePuzzle(_ number: Int) -> Task<CatPuzzle, Never> {
        Task.detached(priority: .userInitiated) { CatPuzzleStage(number).makePuzzle() }
    }

    /// `game_start` の `level`。ステージは面の番号（チャリンコおじさんと同じ `stage-N`）、自由に遊ぶは盤の大きさ。
    var analyticsLevel: AnalyticsLevel {
        stage.map { .stage($0) } ?? size.analyticsLevel
    }

    /// 新しい問題で局を始める（自由に遊ぶ・ステージ共通）。
    private func begin(puzzle newPuzzle: CatPuzzle, size newSize: CatPuzzleSize, stage newStage: Int?) {
        size = newSize
        stage = newStage
        pendingTap = nil
        crossDrag = nil  // 進行中のスライドは捨てる（盤が変わるため）
        stopwatch.stop()
        puzzle = newPuzzle
        marks = Array(repeating: .empty, count: puzzle.cellCount)
        history.removeAll()
        mistakes = 0
        continueUsed = false
        isOfferingContinue = false
        hints.reset()
        gameSerial += 1
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
        services?.gameDidRestart(gameID: Self.gameID, level: analyticsLevel)
        // 新しい問題が出た瞬間から計時する（止めるのは画面側のシート・背面など）。
        startTimer()
    }

    // MARK: - 計時

    /// 盤が出たとき・画面に戻ったときの開始／再開。1 手目より前でも数える（盤が見えていれば考えている時間）。
    /// 終局した後は数えない。
    public func resumeTimerIfNeeded() {
        guard !isFrozen, !stopwatch.isRunning else { return }
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

    /// 記録の区分。ステージは面ごとに難しさが違うので、自由に遊ぶの大きさ別ベストに混ぜず `stage` に分ける（#3145）。
    private var recordVariant: String { stage == nil ? size.recordVariant : Self.stageRecordVariant }

    private var recordVariantLabel: String {
        stage == nil ? size.recordVariantLabel : RecordVariantLabels.stored(gameID: Self.gameID, variant: Self.stageRecordVariant)
    }

    static let stageRecordVariant = "stage"

    private func finish() {
        syncElapsed()
        stopwatch.stop()
        isSolved = true
        solvedAt = stopwatch.now()
        // ステージは決着の時点で次の面へ進める（クリアのカードを閉じずにアプリを落としても進み具合は残る）。
        if let stage, stage + 1 > savedStage { stageDefaults.set(stage + 1, forKey: Self.stageProgressKey) }
        showsClearCard = false
        services?.feedback.notify(.success)
        // 決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。記録は大きさごとに分ける。
        recordResult = services?.gameDidFinish(
            gameID: Self.gameID,
            outcome: .win,
            score: GameScore(
                metric: .shortestTime, seconds: elapsedSeconds,
                variant: recordVariant, variantLabel: recordVariantLabel
            )
        )
        services?.snapshots.clear(for: Self.gameID)
    }

    /// 3 回目のミス。負けにする前に、広告を見て続けるかを選ばせる。計時は止め、提案の最中に離れても同じ提案から
    /// 続けられるよう、ミスが上限のまま保存する（保存しないと、アプリを閉じて開き直すだけで 3 回目のミスが無かったことになる）。
    private func offerContinue() {
        syncElapsed()
        stopwatch.stop()
        isOfferingContinue = true
        services?.feedback.notify(.error)
        persist()
    }

    /// 広告を見終えたら、ミスを 1 回ぶん戻して続きから再開する。**視聴が済んでから** View が呼ぶ。
    /// 最後の赤い × は盤に残す（どこで間違えたかが分かるように）。1 局 1 回。
    @discardableResult
    public func continueAfterAd() -> Bool {
        guard isOfferingContinue, !isFailed, !continueUsed else { return false }
        continueUsed = true
        isOfferingContinue = false
        mistakes = Self.maxMistakes - 1
        startTimer()
        services?.feedback.notify(.success)
        persist()
        return true
    }

    /// 広告を出す前に控えた `gameSerial` の局にだけコンティニューを適用する（#729）。
    /// - Returns: 適用できたか。false のとき View は「コンティニューできなかった」と知らせる。
    @discardableResult
    public func continueAfterAd(forGame serial: Int) -> Bool {
        guard serial == gameSerial else { return false }
        return continueAfterAd()
    }

    /// コンティニューを断る（または使えない）。負けを確定し、まだ見つけていない猫を盤に見せる（`unfoundCats`）。
    /// 見せたあとは続けられない。
    public func declineContinue() {
        guard isOfferingContinue, !isFailed else { return }
        isOfferingContinue = false
        fail()
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
                variant: recordVariant, variantLabel: recordVariantLabel
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
            hintCrosses: hintCrosses.sorted(), wrongCrosses: wrongCrosses.sorted(),
            continueUsed: continueUsed, stage: stage
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
    /// `game_start` の `level`（#500）。6×6 をやさしい、7×7 をふつう、8×8 を上級、9×9 を最上級として送る。
    var analyticsLevel: AnalyticsLevel {
        switch self {
        case .easy: .beginner
        case .normal: .normal
        case .hard: .hard
        case .expert: .expert
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
        case .expert: tr("とことん")
        }
    }

    /// 「6×6」。数字と記号だけなので言語で変わらない。
    public var sizeLabel: String { "\(side)×\(side)" }
}
