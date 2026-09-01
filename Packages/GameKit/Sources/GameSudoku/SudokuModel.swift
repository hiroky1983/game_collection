import Foundation
import Observation
import Core

/// 数独の進行状態。
public enum SudokuState: Equatable, Sendable {
    /// まだ出題が無い（新規ゲームシートで難易度を選ぶ前）。
    case idle
    /// 生成中（`hard` は唯一解チェックのぶん一瞬かかる）。
    case generating
    /// プレイ中。
    case playing
    /// 完成した。
    case cleared
    /// ミスが上限（`SudokuModel.maxMistakes`）に達した。広告のコンティニューで `playing` に戻れる。
    case failed
    /// 諦めて答えを見た。
    case givenUp
}

/// 中断スナップショット（#115 の「続きから」）。
///
/// 盤 81 + 正解 81 + メモ 81（1 マス 9 ビットの整数 1 個）+ 既出フラグ 81 の**固定長**で、
/// プレイを重ねても項目は増えない。`SnapshotStore` は `gameID` ごとに 1 ファイルを
/// 常に上書きするため、積み上がることもない。
struct SudokuSnapshot: Codable {
    let board: [Int]
    let given: [Bool]
    let solution: [Int]
    /// 1 マスぶんのメモをビットマスクで持つ（bit0 が 1、bit8 が 9）。
    let notes: [Int]
    let elapsedSeconds: Int
    let hintsUsed: Int
    let difficulty: SudokuDifficulty
    let hintedCells: [Int]
    /// ミス回数。**古い中断データを読めなくしないため任意**にする（麻雀の `melds` と同じ判断）。
    let mistakes: Int?
}

@MainActor
@Observable
public final class SudokuModel {
    /// 1 局で使えるヒントの上限。
    public static let maxHints = 3
    /// 許されるミス（誤答の確定入力）の回数。上限に達すると `failed` になり、
    /// 広告のコンティニュー（`continueAfterAd`）で続けられる（2048 と同じ型・会長指示 2026-08-30）。
    public static let maxMistakes = 3

    public private(set) var board: [Int]
    public private(set) var given: [Bool]
    public private(set) var solution: [Int]
    /// 1 マスぶんのメモをビットマスクで持つ（bit0 が 1、bit8 が 9）。
    public private(set) var notes: [Int]
    public private(set) var selected: Int?
    public private(set) var state: SudokuState = .idle
    public private(set) var difficulty: SudokuDifficulty = .normal
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var hintsUsed: Int = 0
    /// 誤答の確定入力の回数。`maxMistakes` で `failed`。
    public private(set) var mistakes: Int = 0
    public private(set) var noteMode: Bool = false
    /// ヒントで埋まったマス。プレイヤーが自力で入れたマスと見分けて色を変える。
    public private(set) var hintedCells: Set<Int> = []
    /// 直近の終局で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?

    /// 直前の1手（数字の入力・消去・メモの付け外し）の取り消し情報（#353）。
    ///
    /// **深さは1**（直前の1手だけ）。誤タップの救済が目的で、履歴を深くすると
    /// 「間違えては戻す」の総当たりでミス上限（#322・会長指示の仕様）が形骸化するため。
    /// ヒントで埋めた手は記録しない（広告の対価を undo で取り消させない）。
    private struct UndoStep {
        let index: Int
        let previousBoard: Int
        let previousNotes: Int
        /// 正解入力の巻き添えで消えた同行・列・ブロックのメモ（マス → 消える前のビットマスク）。
        let changedPeerNotes: [Int: Int]
        /// 消したマスがヒントで埋めたものだったか（`erase` は `hintedCells` からも外すため）。
        let wasHinted: Bool
    }
    private var lastUndoStep: UndoStep?

    /// 「元に戻す」を押せるか。中断・再開をまたぐと履歴は持ち越さない（`lastUndoStep` は
    /// 保存しない）ため false になる。`failed`（ミス上限）からは戻せない（下の `fail()` 参照）。
    public var canUndo: Bool { state == .playing && lastUndoStep != nil }

    private let services: GameServices?
    private let gameID = "sudoku"
    private var timerTask: Task<Void, Never>?
    /// テスト用の固定種。nil ならシステムの乱数を使う。
    private var seed: UInt64?

    public var isGenerating: Bool { state == .generating }
    public var hasPuzzle: Bool { state != .idle && state != .generating }
    public var isFinished: Bool { state == .cleared || state == .givenUp }
    public var remainingHints: Int { max(0, Self.maxHints - hintsUsed) }
    public var remainingMistakes: Int { max(0, Self.maxMistakes - mistakes) }

    /// まだ埋まっていないマスの数。ステータスバーに出す。
    public var remainingCount: Int { board.filter { $0 == 0 }.count }

    /// 選択マスを編集できるか。VoiceOver のヒントと数字パッドの活性で同じ判定を使う（#188）。
    public var canEditSelection: Bool {
        guard state == .playing, let index = selected else { return false }
        return !given[index]
    }

    /// ヒントを要求できるか。**選択マスがまだ正解になっていないこと**まで含めて判定する
    /// （既に正解のマスへヒントを使わせると、広告だけ見せて何も起きない）。
    public var canHint: Bool { selected.map { canHint(at: $0) } ?? false }

    /// `index` のマスにヒントを入れられるか。広告を要求した時点と入れる時点で
    /// **同じマスについて**判定できるよう、選択とは切り離して公開する。
    public func canHint(at index: Int) -> Bool {
        guard state == .playing, hintsUsed < Self.maxHints,
              (0..<SudokuEngine.cellCount).contains(index) else { return false }
        return !given[index] && board[index] != solution[index]
    }

    /// 間違って入っている数字のマス。
    public var errorCells: Set<Int> {
        Set((0..<SudokuEngine.cellCount).filter {
            !given[$0] && board[$0] != 0 && board[$0] != solution[$0]
        })
    }

    /// 選択マスと同じ行・列・ブロックのマス（薄く敷く）。
    public var highlightedCells: Set<Int> {
        selected.map { SudokuEngine.peers(of: $0) } ?? []
    }

    /// 選択マスと同じ数字が入っているマス（濃く敷く）。
    public var sameDigitCells: Set<Int> {
        guard let index = selected, board[index] != 0 else { return [] }
        let digit = board[index]
        return Set((0..<SudokuEngine.cellCount).filter { board[$0] == digit })
    }

    /// その数字がもう 9 個すべて盤に入っているか（数字パッドを薄く落とす判定）。
    public func isDigitExhausted(_ digit: Int) -> Bool {
        board.filter { $0 == digit }.count >= SudokuEngine.size
    }

    /// `index` のマスに `digit` のメモが付いているか。
    public func hasNote(_ digit: Int, at index: Int) -> Bool {
        notes[index] & (1 << (digit - 1)) != 0
    }

    /// 今の対局の成績。クリアタイムは勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    private var currentScore: GameScore {
        GameScore(
            metric: .shortestTime,
            seconds: elapsedSeconds,
            variant: difficulty.rawValue,
            variantLabel: difficulty.label
        )
    }

    /// - Parameter seed: テスト用の固定種。nil ならシステムの乱数を使う。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services
        self.seed = seed
        board    = [Int](repeating: 0, count: SudokuEngine.cellCount)
        given    = [Bool](repeating: false, count: SudokuEngine.cellCount)
        solution = [Int](repeating: 0, count: SudokuEngine.cellCount)
        notes    = [Int](repeating: 0, count: SudokuEngine.cellCount)

        // 中断からの復元は「新しいプレイ」ではないので `game_start` を送らない（#158）。
        // 壊れたスナップショットは捨てて `.idle`（新規ゲームシート）から始める。
        if let snapshot = services?.snapshots.load(SudokuSnapshot.self, for: gameID) {
            if Self.isValid(snapshot) {
                board          = snapshot.board
                given          = snapshot.given
                solution       = snapshot.solution
                notes          = snapshot.notes
                elapsedSeconds = snapshot.elapsedSeconds
                hintsUsed      = snapshot.hintsUsed
                difficulty     = snapshot.difficulty
                hintedCells    = Set(snapshot.hintedCells.filter { (0..<SudokuEngine.cellCount).contains($0) })
                mistakes       = snapshot.mistakes ?? 0
                // ミス上限のまま閉じていたら `failed` に戻す（コンティニューの選択からやり直せる）。
                state          = mistakes >= Self.maxMistakes ? .failed : .playing
            } else {
                services?.snapshots.clear(for: gameID)
            }
        }
    }

    // MARK: - Game lifecycle

    /// 新しいパズルを生成して始める。
    ///
    /// 生成（バックトラッキング + 唯一解チェック）はメインスレッドを止めないよう別スレッドで走らせる。
    public func newGame(difficulty: SudokuDifficulty) async {
        // 生成中の再入を弾く。View 側でもボタンを止めているが、シートの連打や
        // 「+」の二度押しで 2 本目の生成が走ると、`gameDidRestart`（= `game_start`）が
        // 2 回飛んで「1 プレイ 1 組」の不変条件（#158）が崩れる。
        guard state != .generating else { return }
        timerTask?.cancel()
        timerTask      = nil
        state          = .generating
        selected       = nil
        elapsedSeconds = 0
        recordResult   = nil

        let currentSeed = seed
        let puzzle = await Task.detached(priority: .userInitiated) {
            if var rng = currentSeed.map(SudokuSeededGenerator.init(seed:)) {
                return SudokuEngine.generate(difficulty: difficulty, using: &rng)
            }
            var rng = SystemRandomNumberGenerator()
            return SudokuEngine.generate(difficulty: difficulty, using: &rng)
        }.value
        // 種を渡している（テスト）ときは、続けて新規ゲームを始めても同じ盤にならないよう進める。
        if let currentSeed { seed = currentSeed &+ 1 }

        board           = puzzle.board
        given           = puzzle.board.map { $0 != 0 }
        solution        = puzzle.solution
        notes           = [Int](repeating: 0, count: SudokuEngine.cellCount)
        hintsUsed       = 0
        hintedCells     = []
        mistakes        = 0
        noteMode        = false
        lastUndoStep    = nil
        self.difficulty = difficulty
        state           = .playing

        persist()
        startTimer()
        // 盤が出来て計時が始まるここが 1 プレイの開始（#158）。
        services?.gameDidRestart(gameID: gameID)
    }

    /// 中断から復帰したときに計時を再開する（`onAppear` / `task` から呼ぶ）。
    public func resumeTimerIfNeeded() {
        guard state == .playing, timerTask == nil else { return }
        startTimer()
    }

    /// 画面を離れるときに計時を止める（`onDisappear` から呼ぶ）。
    ///
    /// 計時の `Task` は `self` を強く握るので、止めないと**モデルが解放されず**、
    /// 画面を離れたあとも 1 秒ごとに `elapsedSeconds` が進み続ける（#375）。
    /// 画面に戻れば `resumeTimerIfNeeded()` が計時を再開するので、経過時間は失われない。
    public func pauseTimer() { stopTimer() }

    /// 計時が動いているか。`@testable` から計時の開始・停止を実時間に依存せず確かめるために持つ。
    var isTimerRunning: Bool { timerTask != nil }

    // MARK: - Actions

    /// マスを選ぶ。同じマスをもう一度タップすると選択解除。
    public func select(index: Int) {
        guard state == .playing, (0..<SudokuEngine.cellCount).contains(index) else { return }
        selected = (selected == index) ? nil : index
        services?.feedback.impact(.light)
    }

    /// 数字を入れる（メモモードならメモの付け外し）。
    public func enter(digit: Int) {
        guard (1...SudokuEngine.size).contains(digit) else { return }
        guard state == .playing, let index = selected, !given[index] else {
            services?.feedback.notify(.warning)  // 出題のマスは書き換えられない
            return
        }

        if noteMode {
            lastUndoStep = UndoStep(
                index: index, previousBoard: board[index], previousNotes: notes[index],
                changedPeerNotes: [:], wasHinted: false
            )
            notes[index] ^= (1 << (digit - 1))
            services?.feedback.impact(.rigid)
        } else {
            // 同じ数字の入れ直し（無操作）をミスに数えないよう、変化があったときだけ判定する。
            let isNewWrongEntry = digit != solution[index] && board[index] != digit
            // 正解入力は同じ行・列・ブロックのメモも消す（下）ので、undo 用に消える前の値を控える。
            let peerNotesBefore: [Int: Int] = digit == solution[index]
                ? Dictionary(
                    uniqueKeysWithValues: SudokuEngine.peers(of: index)
                        .filter { notes[$0] & (1 << (digit - 1)) != 0 }
                        .map { ($0, notes[$0]) }
                )
                : [:]
            lastUndoStep = UndoStep(
                index: index, previousBoard: board[index], previousNotes: notes[index],
                changedPeerNotes: peerNotesBefore, wasHinted: false
            )
            board[index] = digit
            notes[index] = 0
            // 正解のときだけ、同じ行・列・ブロックの同じ数字のメモを消してやる。
            // 間違いのときに消すと、正しかったメモまで巻き添えで失われる。
            if digit == solution[index] { clearPeerNotes(for: index, digit: digit) }
            services?.feedback.impact(.medium)
            if isNewWrongEntry {
                mistakes += 1
                if mistakes >= Self.maxMistakes {
                    fail()
                    return   // fail() が persist まで済ませる
                }
            }
            checkCompletion()
        }
        persist()
    }

    /// 直前の1手を取り消す（#353）。盤・メモ・巻き添えで消えたメモが戻る。
    ///
    /// **ミス回数は戻さない**（#375 の会長決裁 A）。以前は `previousMistakes` まで復元していたため、
    /// 深さ 1 でも「誤答 → 戻す → 別の数字を試す」を繰り返すだけでミス上限（#322）が形骸化し、
    /// 広告コンティニューの導線ごと骨抜きになっていた。盤面は戻すがミスは戻さないのが業界標準で、
    /// 誤タップの救済という undo 本来の目的（#353）はそのまま果たせる。
    public func undo() {
        guard state == .playing, let step = lastUndoStep else { return }
        lastUndoStep = nil
        board[step.index] = step.previousBoard
        notes[step.index] = step.previousNotes
        for (peer, mask) in step.changedPeerNotes { notes[peer] = mask }
        if step.wasHinted { hintedCells.insert(step.index) }
        selected = step.index
        services?.feedback.impact(.rigid)
        persist()
    }

    /// 選択マスの数字とメモを消す。
    public func erase() {
        guard state == .playing, let index = selected, !given[index] else {
            services?.feedback.notify(.warning)
            return
        }
        guard board[index] != 0 || notes[index] != 0 else { return }
        lastUndoStep = UndoStep(
            index: index, previousBoard: board[index], previousNotes: notes[index],
            changedPeerNotes: [:],
            wasHinted: hintedCells.contains(index)
        )
        board[index] = 0
        notes[index] = 0
        hintedCells.remove(index)
        services?.feedback.impact(.rigid)
        persist()
    }

    public func toggleNoteMode() {
        noteMode.toggle()
        services?.feedback.impact(.rigid)
    }

    /// 指定のマスに正解を 1 つ入れる。**広告の視聴が済んでから** View が呼ぶ（#262）。
    ///
    /// 対象を引数で受けるのは、広告の読み込み〜視聴のあいだに選択が動いても
    /// **ユーザーが広告と引き換えに指定したマス**に入れるため。
    /// - Returns: 実際に入れられたか。false のとき View は「入れられなかった」と伝える
    ///   （黙って何も起きないと、広告だけ見せて対価が無い状態になる）。
    @discardableResult
    public func applyHint(at index: Int) -> Bool {
        guard canHint(at: index) else { return false }
        selected = index
        board[index] = solution[index]
        notes[index] = 0
        hintsUsed += 1
        hintedCells.insert(index)
        clearPeerNotes(for: index, digit: solution[index])
        // ヒント自体は `UndoStep` を作らないが、**手前の履歴も捨てる**（#383）。
        // 残しておくと、その `changedPeerNotes` が「ヒントを使う前のメモ」を持っているため、
        // 直後に「元に戻す」を押すとヒントが消したメモが復活し、広告の対価が一部巻き戻る。
        // `fail()` が同じ理由で履歴を捨てているのと同じ扱い。
        lastUndoStep = nil
        services?.feedback.impact(.medium)
        checkCompletion()
        persist()
        return true
    }

    /// ミスが上限に達した。負けの記録はまだ付けない（コンティニューで続けられるため）。
    /// スナップショットは**消さずに**残す: ここでアプリを閉じても、次に開いたとき
    /// `failed` のまま復元され、コンティニューか諦めるかを選び直せる。
    private func fail() {
        state = .failed
        selected = nil
        // 3回目のミスは undo で取り消せない（#353）。取り消せると「広告を見てコンティニュー」
        // （#322・会長指示の仕様）を素通りできてしまう。
        lastUndoStep = nil
        stopTimer()
        services?.feedback.notify(.error)
        persist()
    }

    /// 広告を見終えたらミスを 0 に戻して続きから再開する。**視聴が済んでから** View が呼ぶ
    /// （2048 の `continueAfterAd` と同じ契約）。2048 と違い 1 局 1 回の制限は設けない:
    /// 数独は解が一意で「粘れば必ず解ける」ため、続けたい人を止める理由が無い。
    public func continueAfterAd() {
        guard state == .failed else { return }
        mistakes = 0
        state = .playing
        startTimer()
        services?.feedback.notify(.success)
        persist()
    }

    /// 諦めて答えを見る。マインスイーパーの「諦める」と同じく 1 敗として記録する。
    /// ミス上限（`failed`）からも諦められる（コンティニューしない選択）。
    public func giveUp() {
        guard state == .playing || state == .failed else { return }
        board = solution
        notes = [Int](repeating: 0, count: SudokuEngine.cellCount)
        selected = nil
        state = .givenUp
        stopTimer()
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        services?.snapshots.clear(for: gameID)
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - Private helpers

    private func checkCompletion() {
        guard board == solution else { return }
        state = .cleared
        selected = nil
        stopTimer()
        services?.feedback.notify(.success)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
        services?.snapshots.clear(for: gameID)
    }

    private func clearPeerNotes(for index: Int, digit: Int) {
        for peer in SudokuEngine.peers(of: index) {
            notes[peer] &= ~(1 << (digit - 1))
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                elapsedSeconds += 1
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func persist() {
        // `failed` も保存対象: コンティニューするか選ぶ前に閉じても状態が戻せるように。
        guard state == .playing || state == .failed else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snapshot = SudokuSnapshot(
            board: board,
            given: given,
            solution: solution,
            notes: notes,
            elapsedSeconds: elapsedSeconds,
            hintsUsed: hintsUsed,
            difficulty: difficulty,
            hintedCells: Array(hintedCells),
            mistakes: mistakes
        )
        try? services?.snapshots.save(snapshot, for: gameID)
    }

    /// 復元して安全に使えるスナップショットか。**長さと値域まで見る**
    /// （盤の添字は View から直接引かれるので、短い配列を信じると即クラッシュする）。
    private static func isValid(_ snapshot: SudokuSnapshot) -> Bool {
        let n = SudokuEngine.cellCount
        guard snapshot.board.count == n,
              snapshot.given.count == n,
              snapshot.solution.count == n,
              snapshot.notes.count == n else { return false }
        guard snapshot.board.allSatisfy({ (0...SudokuEngine.size).contains($0) }),
              snapshot.solution.allSatisfy({ (1...SudokuEngine.size).contains($0) }),
              snapshot.notes.allSatisfy({ $0 >= 0 && $0 < (1 << SudokuEngine.size) }) else { return false }
        // 途中まで解いた盤でも、出題のマスは必ず正解と一致しているはず。
        guard (0..<n).allSatisfy({ !snapshot.given[$0] || snapshot.board[$0] == snapshot.solution[$0] })
        else { return false }
        // 完成済み・ヒント使い切り超過は「プレイ中」として復元できない。
        guard snapshot.board != snapshot.solution,
              (0...maxHints).contains(snapshot.hintsUsed),
              snapshot.elapsedSeconds >= 0 else { return false }
        // ミス回数も値域まで見る（nil は旧形式の中断データなので許可 = 0 扱い）。
        guard snapshot.mistakes.map({ (0...maxMistakes).contains($0) }) ?? true
        else { return false }
        return true
    }
}
