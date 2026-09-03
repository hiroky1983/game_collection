import Foundation
import Observation
import Core

public enum MinesweeperState: Equatable, Sendable {
    case idle, playing, won, lost
}

/// 新規対局シートの難易度プリセット（#444）。
///
/// **新規対局シート・記録区分のラベル・テストが同じ値を見るための唯一の出どころ**。
/// 以前は View の `switch level` に数値が直書きされており、記録区分のラベル
/// （`MinesweeperModel.recordVariantLabel`）と二重管理になっていた。
///
/// 業界慣行（Windows 標準）に合わせるのは**地雷密度**で、盤の縦横比までは合わせない。
/// 本家の上級は 30×16 の横長で、スマホの縦画面にそのまま置くと 1 マスが潰れるため、
/// 正方形のまま面積と密度で寄せる:
///
/// | 難易度 | あそびば | 密度 | Windows 標準 | 密度 |
/// |---|---|---|---|---|
/// | 初級 | 9×9 / 10 | 12.3% | 9×9 / 10 | 12.3%（完全一致）|
/// | 中級 | 16×16 / 40 | 15.6% | 16×16 / 40 | 15.6%（本家が正方形なので完全一致）|
/// | 上級 | 20×20 / 82 | 20.5% | 30×16 / 99 | 20.6% |
public enum MinesweeperDifficulty: String, CaseIterable, Sendable {
    case beginner, intermediate, advanced

    public var label: String {
        switch self {
        case .beginner:     return "初級"
        case .intermediate: return "中級"
        case .advanced:     return "上級"
        }
    }

    public var rows: Int {
        switch self {
        case .beginner:     return 9
        case .intermediate: return 16
        case .advanced:     return 20
        }
    }

    /// 盤は正方形に保つ（縦画面で 1 マスが潰れないための制約）。
    public var cols: Int { rows }

    public var mines: Int {
        switch self {
        case .beginner:     return 10
        case .intermediate: return 40
        case .advanced:     return 82
        }
    }

    /// 新規対局シートの副題（例: "16×16  40地雷"）。
    public var subtitle: String { "\(rows)×\(cols)  \(mines)地雷" }
}

/// マスに置くマーク（#444）。本家と同じ「なし → 旗 → ? → なし」の循環を表す。
///
/// **`?` は旗ではない**。「たぶん地雷だが確信が無い」という保留のメモなので、
/// 残り地雷カウンタにもコード（一括開放）の旗数にも数えず、通常の未開放マスと同じく
/// 開くことができる。旗の有無を見たい箇所は必ず `MinesweeperCell.isFlagged` を通すこと。
public enum MinesweeperMark: String, Codable, Sendable {
    case none, flag, question
}

public struct MinesweeperCell: Sendable {
    public var isRevealed      = false
    /// 置かれているマーク（#444）。旗だけを見たいときは `isFlagged` を使う。
    public var mark: MinesweeperMark = .none
    public var isMine          = false
    public var adjacentMines   = 0
    public var isContinuedMine = false  // コンティニューで確定した爆弾マス
    /// このマスが開いたときの連鎖の波（タップ地点からの距離・#203）。
    ///
    /// View が「開く演出をどれだけ遅らせるか」を決めるためだけに使う表示用の値で、
    /// ゲームの進行には影響しない。中断スナップショットにも含めない
    /// （復元したマスは最初から開いているので演出を再生する余地が無い）。
    public var revealWave      = 0

    /// 旗が立っているか。**残り地雷カウンタとコードの旗数はすべてここを通す**（#444）。
    /// `?` を旗と数えないという性質を1箇所に閉じ込めるため、`mark` を直接比べない。
    public var isFlagged: Bool { mark == .flag }
}

struct MinesweeperSnapshot: Codable {
    let rows: Int
    let cols: Int
    let totalMines: Int
    let cells: [[CellData]]
    let flagCount: Int
    let revealedCount: Int
    let elapsedSeconds: Int

    struct CellData: Codable {
        let isRevealed: Bool
        /// 旗が立っているか。**`mark` を足した後も残す旧形式との互換フィールド**（#444）。
        /// `?` を知らない版が保存した中断データはこれしか持たないため、
        /// 読み込み側は `mark` が無ければここから復元する。
        let isFlagged: Bool
        let isMine: Bool
        let adjacentMines: Int
        let isContinuedMine: Bool
        /// マーク（#444）。旧形式には無いので optional。**宣言順の最後に置く**ことで、
        /// 既存の呼び出し（テストの盤面組み立てなど）がそのまま通る。
        var mark: MinesweeperMark? = nil
    }
}

@MainActor
@Observable
public final class MinesweeperModel {
    public private(set) var cells: [[MinesweeperCell]]
    public private(set) var gameState: MinesweeperState = .idle
    public private(set) var rows: Int
    public private(set) var cols: Int
    public private(set) var totalMines: Int
    public private(set) var flagCount: Int = 0
    public private(set) var revealedCount: Int = 0
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var hitMine: (row: Int, col: Int)?
    /// 直近の終局で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private var timerTask: Task<Void, Never>?
    private let services: GameServices?
    private let gameID = "minesweeper"

    public var remainingMines: Int { totalMines - flagCount }
    public var safeCellCount: Int  { rows * cols - totalMines }
    public var gameOver: Bool      { gameState == .won || gameState == .lost }

    /// 記録を分ける区分のキー。盤の大きさと地雷数が同じものを同じ難易度として扱う。
    /// 難易度の enum を持たない（View が rows/cols/mines を直接渡す）ため、盤の構成から導く。
    private var recordVariant: String { "\(rows)x\(cols)-\(totalMines)" }

    /// 区分の表示名。新規対局シートのプリセット3種は日本語名、それ以外は盤サイズで表す。
    ///
    /// **旧プリセット（12×12/25・15×15/40）は意図的に載せない**（#444）。プリセットを
    /// 業界慣行へ寄せた結果、記録の区分（`recordVariant`）としては別物になったため、
    /// 「中級」の名前を新旧で共有すると自己ベストが混ざって見える。旧記録は default に
    /// 落ちて「12×12・地雷25」と盤サイズで表示され、別区分だと分かる。
    ///
    /// `private` にせず `@testable` から読めるようにしているのは `isTimerRunning` と同じ理由で、
    /// プリセットとラベルの対応をテストで固定するため。
    var recordVariantLabel: String {
        if let preset = MinesweeperDifficulty.allCases.first(where: {
            $0.rows == rows && $0.cols == cols && $0.mines == totalMines
        }) {
            return preset.label
        }
        // 区分は地雷数込みで分かれるため、ラベルにも地雷数を入れて別区分だと分かるようにする。
        return "\(rows)×\(cols)・地雷\(totalMines)"
    }

    /// 今の対局の成績。クリアタイムは勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    private var currentScore: GameScore {
        GameScore(
            metric: .shortestTime,
            seconds: elapsedSeconds,
            variant: recordVariant,
            variantLabel: recordVariantLabel
        )
    }

    public init(services: GameServices? = nil, rows: Int = 9, cols: Int = 9, mines: Int = 10) {
        self.services = services

        if let snap = services?.snapshots.load(MinesweeperSnapshot.self, for: "minesweeper") {
            self.rows          = snap.rows
            self.cols          = snap.cols
            self.totalMines    = snap.totalMines
            self.flagCount     = snap.flagCount
            self.revealedCount = snap.revealedCount
            self.elapsedSeconds = snap.elapsedSeconds
            self.gameState     = .playing
            self.cells = snap.cells.map { row in
                row.map { data in
                    var cell = MinesweeperCell()
                    cell.isRevealed    = data.isRevealed
                    // 旧形式（`mark` 以前）は旗の有無しか持たないので、そこから復元する（#444）。
                    cell.mark          = data.mark ?? (data.isFlagged ? .flag : .none)
                    cell.isMine        = data.isMine
                    cell.adjacentMines = data.adjacentMines
                    cell.isContinuedMine = data.isContinuedMine
                    return cell
                }
            }
        } else {
            self.rows       = rows
            self.cols       = cols
            self.totalMines = mines
            self.cells      = Self.emptyBoard(rows: rows, cols: cols)
        }
    }

    // MARK: - New game

    public func newGame(rows: Int, cols: Int, mines: Int) {
        timerTask?.cancel()
        timerTask      = nil
        self.rows       = rows
        self.cols       = cols
        self.totalMines = mines
        self.cells      = Self.emptyBoard(rows: rows, cols: cols)
        self.gameState  = .idle
        self.flagCount  = 0
        self.revealedCount = 0
        self.elapsedSeconds = 0
        self.hitMine    = nil
        self.recordResult = nil
        persist()
    }

    // MARK: - Timer resume (call from onAppear when restoring saved game)

    public func resumeTimerIfNeeded() {
        guard gameState == .playing, timerTask == nil else { return }
        startTimer()
    }

    /// 画面を離れるときに計時を止める（`onDisappear` から呼ぶ）。
    ///
    /// 計時の `Task` は `self` を強く握るので、止めないと**モデルが解放されず**、
    /// 画面を離れたあとも 1 秒ごとに経過秒が進み続ける（#375。数独にも同型があった）。
    /// 画面に戻れば `resumeTimerIfNeeded()` が計時を再開するので、経過時間は失われない。
    public func pauseTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// 計時が動いているか。`@testable` から計時の開始・停止を実時間に依存せず確かめるために持つ。
    var isTimerRunning: Bool { timerTask != nil }

    // MARK: - Actions

    /// このマスを開けるか。VoiceOver に「いま何ができるか」を伝えるためにも使うので、
    /// 判定を `tap` の中に埋めずここに出しておく（二重管理で食い違わせないため・#188）。
    public func canReveal(row: Int, col: Int) -> Bool {
        !gameOver && !cells[row][col].isRevealed && !cells[row][col].isFlagged
    }

    /// このマスの旗を立て下ろしできるか。開き済み・確定爆弾マスには置けない。
    public func canToggleFlag(row: Int, col: Int) -> Bool {
        !gameOver && !cells[row][col].isRevealed && !cells[row][col].isContinuedMine
    }

    /// このマスでコード（数字タップによる周囲の一括開放）ができるか（#437）。
    ///
    /// 開いている数字マスで、周囲8マスの旗の数がその数字と一致し、かつ開く先が1マス以上
    /// あるときだけ成立する。旗数が合わないときに成立させないのが誤爆防止の要。
    /// 判定を `chord` の中に埋めずここに出すのは `canReveal` と同じ理由で、
    /// 「やっても何も起きない操作」を VoiceOver に案内しないため（#188）。
    public func canChord(row: Int, col: Int) -> Bool {
        guard !gameOver else { return false }
        let cell = cells[row][col]
        guard cell.isRevealed, !cell.isMine, cell.adjacentMines > 0 else { return false }
        let around = neighbors(row: row, col: col)
        let flagsAround = around.filter { cells[$0.row][$0.col].isFlagged }.count
        guard flagsAround == cell.adjacentMines else { return false }
        return around.contains { !cells[$0.row][$0.col].isRevealed && !cells[$0.row][$0.col].isFlagged }
    }

    public func tap(row: Int, col: Int) {
        guard !gameOver else { return }
        // 開いているマスのタップはコード（周囲の一括開放）として扱う（#437）。
        // 成立しない場合は `chord` 側で警告フィードバックを出して盤面を変えない。
        if cells[row][col].isRevealed {
            chord(row: row, col: col)
            return
        }
        guard canReveal(row: row, col: col) else {
            services?.feedback.notify(.warning) // 旗付きマスは開けない
            return
        }

        if gameState == .idle {
            placeMines(avoiding: row, col: col)
            gameState = .playing
            startTimer()
            // 地雷を置いて計時が始まるここが 1 プレイの開始（#158）。
            // 盤を用意しただけの `.idle` や、中断からの復元（`.playing` で始まる）では数えない。
            services?.gameDidRestart(gameID: gameID)
        }

        if cells[row][col].isMine {
            loseGame(hitRow: row, hitCol: col)
        } else {
            floodReveal(row: row, col: col)
            settleAfterReveal()
        }

        persist()
    }

    /// コード: 開いている数字マスのタップで周囲を一括開放する（#437）。
    ///
    /// 旗が誤っていれば地雷を踏んで負ける（本家と同じ挙動。安全化しない）。
    /// 旗数が一致しないときは `canChord` が false になるので盤面は一切変わらない。
    private func chord(row: Int, col: Int) {
        guard canChord(row: row, col: col) else {
            services?.feedback.notify(.warning) // 旗数が合っていない・開く先が無い
            return
        }
        let targets = neighbors(row: row, col: col).filter {
            !cells[$0.row][$0.col].isRevealed && !cells[$0.row][$0.col].isFlagged
        }

        if let mine = targets.first(where: { cells[$0.row][$0.col].isMine }) {
            loseGame(hitRow: mine.row, hitCol: mine.col)
        } else {
            // 開いた 0 マスからは既存のゼロ連鎖がそのまま波及する。
            for target in targets { floodReveal(row: target.row, col: target.col) }
            settleAfterReveal()
        }

        persist()
    }

    /// 地雷を踏んだときの終局処理。1マスのタップとコード（#437）で共有する。
    private func loseGame(hitRow: Int, hitCol: Int) {
        hitMine = (hitRow, hitCol)
        revealAllMines()
        gameState = .lost
        timerTask?.cancel()
        timerTask = nil
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
    }

    /// 安全マスを開いたあとの後始末（勝利判定と触覚）。同じく両方の入口から呼ぶ。
    private func settleAfterReveal() {
        if revealedCount == safeCellCount {
            flagAllMines()
            gameState = .won
            timerTask?.cancel()
            timerTask = nil
            services?.feedback.notify(.success)
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
        } else {
            services?.feedback.impact(.light)
        }
    }

    // MARK: - Continue

    public func continueAfterAd() {
        guard gameState == .lost, let hit = hitMine else { return }
        // 同じ盤面の続きなので、直前に記録した「負け」は無かったことにする
        // （そのままだと1回のプレイが2回分として数えられる）。
        services?.playLog?.cancelLoss(gameID: gameID, variant: recordVariant)
        recordResult = nil

        // ゲームオーバーで露出した地雷を再び隠す
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isMine && !cells[r][c].isFlagged {
                cells[r][c].isRevealed = false
                // 隠し直したマスは次に開くときの起点になるので、古い波を残さない（#203）。
                cells[r][c].revealWave = 0
            }
        }

        // 踏んだ地雷は専用マークで確定爆弾として残す。
        // 踏めたということは旗が立っていなかった（`canReveal`）ので、? だった場合も含めて
        // ここで必ず旗が1本増える（? は数えていない・#444）。
        cells[hit.row][hit.col].mark            = .flag
        cells[hit.row][hit.col].isContinuedMine = true
        flagCount += 1
        hitMine = nil
        gameState = .playing
        startTimer()
        // `game_end` はもう送信済みなので、続きは次の1プレイとして数える（#158）。
        services?.gameDidRestart(gameID: gameID)

        // すでに全安全マスを開けていた場合（まずないが念のため）
        if revealedCount == safeCellCount {
            flagAllMines()
            gameState = .won
            timerTask?.cancel()
            timerTask = nil
            services?.feedback.notify(.success)
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
        }

        persist()
    }

    public func toggleFlag(row: Int, col: Int) {
        guard !gameOver else { return }
        guard canToggleFlag(row: row, col: col) else {
            services?.feedback.notify(.warning) // 開き済み・確定爆弾マスには旗を置けない
            return
        }
        // なし → 旗 → ? → なし（#444）。`flagCount` は旗だけを数えるので、
        // **旗に入る遷移で増やし、旗から出る遷移で減らす**。? への遷移で減らし忘れると
        // 残り地雷カウンタが狂う。
        switch cells[row][col].mark {
        case .none:
            cells[row][col].mark = .flag
            flagCount += 1
        case .flag:
            cells[row][col].mark = .question
            flagCount -= 1
        case .question:
            cells[row][col].mark = .none
        }
        services?.feedback.impact(.rigid)
        persist()
    }

    public func giveUp() {
        guard gameState == .playing else { return }
        revealAllMines()
        gameState = .lost
        services?.feedback.notify(.error)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        timerTask?.cancel()
        timerTask = nil
        services?.snapshots.clear(for: gameID)
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - Private helpers

    private func persist() {
        guard gameState == .playing else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = MinesweeperSnapshot(
            rows: rows,
            cols: cols,
            totalMines: totalMines,
            cells: cells.map { row in
                row.map { cell in
                    MinesweeperSnapshot.CellData(
                        isRevealed: cell.isRevealed,
                        // 旧形式のフィールドも書き続ける（互換の要・#444）。
                        isFlagged: cell.isFlagged,
                        isMine: cell.isMine,
                        adjacentMines: cell.adjacentMines,
                        isContinuedMine: cell.isContinuedMine,
                        mark: cell.mark
                    )
                }
            },
            flagCount: flagCount,
            revealedCount: revealedCount,
            elapsedSeconds: elapsedSeconds
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    /// タップ地点から幅優先で開いていく。**探索の深さを `revealWave` として各マスに残す**（#203）。
    ///
    /// FIFO で処理するので波は必ず非減少に並び、同じ波のマスは同じ遅延で一斉に開く。
    /// 深さを持たせるだけなので探索そのものの計算量は従来と変わらない。
    private func floodReveal(row: Int, col: Int) {
        var queue = [(row: row, col: col, wave: 0)]
        var i = 0
        while i < queue.count {
            let (r, c, wave) = queue[i]; i += 1
            guard r >= 0, r < rows, c >= 0, c < cols,
                  !cells[r][c].isRevealed,
                  !cells[r][c].isFlagged,
                  !cells[r][c].isMine else { continue }
            cells[r][c].isRevealed = true
            cells[r][c].revealWave = wave
            revealedCount += 1
            if cells[r][c].adjacentMines == 0 {
                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        queue.append((r + dr, c + dc, wave + 1))
                    }
                }
            }
        }
    }

    /// 盤内に収まる 8 近傍の座標（#437）。
    private func neighbors(row: Int, col: Int) -> [(row: Int, col: Int)] {
        var result: [(row: Int, col: Int)] = []
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr, c = col + dc
                if r >= 0, r < rows, c >= 0, c < cols { result.append((row: r, col: c)) }
            }
        }
        return result
    }

    private func revealAllMines() {
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isMine && !cells[r][c].isFlagged {
                cells[r][c].isRevealed = true
                // 決着時の一斉公開は連鎖ではないので波を持たせない（全マス同時に出す・#203）。
                cells[r][c].revealWave = 0
            }
        }
    }

    private func flagAllMines() {
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isMine && !cells[r][c].isFlagged {
                // ? を置いたままの地雷もここで旗に変わる。? は数えていないので +1 で合う（#444）。
                cells[r][c].mark = .flag
                flagCount += 1
            }
        }
    }

    private func placeMines(avoiding safeRow: Int, col safeCol: Int) {
        var excluded = Set<Int>()
        for dr in -1...1 {
            for dc in -1...1 {
                let r = safeRow + dr, c = safeCol + dc
                if r >= 0, r < rows, c >= 0, c < cols {
                    excluded.insert(r * cols + c)
                }
            }
        }
        var candidates = (0..<rows * cols).filter { !excluded.contains($0) }.shuffled()
        if candidates.count < totalMines {
            candidates = (0..<rows * cols).filter { $0 != safeRow * cols + safeCol }.shuffled()
        }
        for i in 0..<min(totalMines, candidates.count) {
            cells[candidates[i] / cols][candidates[i] % cols].isMine = true
        }
        for r in 0..<rows {
            for c in 0..<cols {
                guard !cells[r][c].isMine else { continue }
                var count = 0
                for dr in -1...1 {
                    for dc in -1...1 {
                        if dr == 0 && dc == 0 { continue }
                        let nr = r + dr, nc = c + dc
                        if nr >= 0, nr < rows, nc >= 0, nc < cols, cells[nr][nc].isMine {
                            count += 1
                        }
                    }
                }
                cells[r][c].adjacentMines = count
            }
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

    private static func emptyBoard(rows: Int, cols: Int) -> [[MinesweeperCell]] {
        Array(repeating: Array(repeating: MinesweeperCell(), count: cols), count: rows)
    }
}
