import Core
import Observation

/// 2048 の「戻す」の回数制（#2023）。値は `RewardedUndoBudget` が持ち、ここは 2048 の文脈に
/// 名前を残すための転送（`SudokuUndoBudget` と同じ作り）。
public enum Game2048UndoBudget {
    /// 1 局につき無料で戻せる回数。新規ゲームでここまで戻る。
    public static let free = RewardedUndoBudget.free
    /// リワード広告 1 本の視聴完了で補充する回数。
    public static let refill = RewardedUndoBudget.refill
    /// 持ち越す履歴の上限（手数）。中断データを際限なく太らせないための歯止めで、
    /// 戻せる回数（無料 3 + 広告補充）を普通に使い切る範囲では届かない。
    public static let historyLimit = 100
}

/// 盤に描くタイル 1 枚（#2253）。`id` を手をまたいで保つので、View は座標をアニメーションさせて滑らせられる。
public struct Game2048Tile: Identifiable, Equatable, Sendable {
    /// このタイルが今の位置に来た経緯。View が出方（すぐ出す・滑る・弾む・後から出る）を選ぶ。
    public enum Arrival: Equatable, Sendable {
        /// 盤から作り直した（再開・戻す・コンティニュー）。その場に出す。
        case placed
        /// 前の手から同じタイルが滑ってきた（動かなかったものも含む）。
        case slid
        /// 2 枚が合体してできた。滑り終えてから出て軽く弾む。
        case merged
        /// 新しく出現した。滑り終えてから出る。
        case spawned
    }

    public let id: Int
    public let value: Int
    public let row: Int
    public let col: Int
    public let arrival: Arrival
}

/// 2048 のゲーム状態。盤面・スコア・終局を保持し、永続化サービスへ中断スナップショットを書く。
/// 純粋ロジックは `Game2048Logic` に委譲し、ここは乱数生成・永続化・終局管理のみ担う。
@MainActor
@Observable
public final class Game2048Model {
    public private(set) var board: [[Int]]
    public private(set) var score: Int
    public private(set) var gameOver: Bool
    public private(set) var continueUsed: Bool = false
    /// この局で 2048 に到達済みか（#438）。勝利演出を局に 1 度だけ出すための印。
    public private(set) var hasWon: Bool = false
    /// 勝利演出（「続ける / もう一度」）を出しているか（#438）。`continueAfterWin()` で下ろす。
    public private(set) var showWinPrompt: Bool = false
    /// 直近の終局で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?
    /// 直近のスワイプの結果（VoiceOver の読み上げ用・#2687）。View は値が変わったときだけ読む。
    public private(set) var lastResult: OperationResult?
    /// 局の通し番号（#729）。新規ゲームのたびに増やし、中断データには書かない。
    /// 広告を出す前に控えておき、見終えたときに照合する（ロード中に「もう一度」で局が入れ替わったら適用しない）。
    public private(set) var gameSerial = 0
    /// 直前の終局を「負け」として記録したか（#764）。2048 を作った手で詰んだ局は勝ちで記録するので、
    /// コンティニューで巻き戻してよいのはこれが true のときだけ。終局後の中断・復元経路は無いので中断データには書かない。
    private var lastFinishWasLoss = false

    /// 戻すための履歴（古い順・末尾が直前の 1 手の前）。中断データにも保存する（#2023）。
    public private(set) var history: [Game2048Step] = []
    /// 今使える「戻す」の回数。新規ゲームで無料枠へ戻り、中断・復元では戻らない。
    public private(set) var undosRemaining = Game2048UndoBudget.free

    /// 盤に描くタイル（#2253）。常に `board` と 1 対 1 で一致する（空きマスは含まない）。
    public private(set) var tiles: [Game2048Tile] = []
    /// 直前の手で合体した元の 2 枚。行き先まで滑らせてから消すために、`tiles` とは別に少しのあいだ残す。
    /// View が滑り終えた後に `settleVanishing(ids:)` で片付ける。次の手・戻す・新しいゲームでも片付く。
    public private(set) var vanishing: [Game2048Tile] = []
    /// タイルの通し番号。合体・出現のたびに新しい番号を振り、使い回さない。
    private var nextTileID = 0

    private let services: GameServices?
    /// 同じモジュールの View も参照する（`reward_ad` の送信に要る・#500）。
    let gameID = "2048"

    /// ヘッダーに常時出す「ベスト」（#2615）。保存済みの自己ベストと今のスコアの大きい方。
    /// 記録は決着時にしか書かれないので、今のスコアが超えた瞬間にここで追従させる。0 のときは nil（出さない）。
    var liveBestScore: Int? {
        let best = max(services?.playLog?.record(gameID: gameID)?.bestPoints ?? 0, score)
        return best > 0 ? best : nil
    }

    /// 今の盤で一番大きいタイル（#2812）。ヘッダーに「最高」として出す。
    var highestTile: Int { board.flatMap { $0 }.max() ?? 0 }

    /// services を渡すと、中断スナップショットがあれば復元、無ければ新規開始する。
    public init(services: GameServices? = nil) {
        self.services = services
        var initialBoard: [[Int]]
        var initialScore: Int
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = false
        var loaded = services?.snapshots.load(Game2048Snapshot.self, for: gameID)
        // 盤が 4x4 でない中断データは、読むと添字が範囲外になり開くたびに落ちる（#1384）。
        // 消して新規開始に倒す。
        if let snap = loaded, !Self.isRestorable(snap.board) {
            services?.snapshots.clear(for: gameID)
            loaded = nil
        }
        if let snap = loaded {
            initialBoard = snap.board
            initialScore = snap.score
            // 再起動でコンティニュー権が復活しないよう、使用済みフラグも復元する。
            continueUsed = snap.continueUsed
            // 到達済みフラグも復元する。復元しないと再起動のたびに勝利演出が出せてしまう（#438）。
            hasWon = snap.hasWon
            // 演出を出したまま中断していたら出し直す（#516）。ここで落とすと「続ける / もう一度」を
            // 選ばないうちに選択肢が消え、続行が次の 1 プレイとして数え直されない。
            showWinPrompt = snap.showWinPrompt
            // 履歴の盤が 1 枚でも壊れていたら、戻した先で添字が範囲外になるので履歴ごと捨てる（#1384 と同じ理由）。
            if let saved = snap.history, saved.allSatisfy({ Self.isRestorable($0.board) && $0.score >= 0 }) {
                history = Array(saved.suffix(Game2048UndoBudget.historyLimit))
            }
            // 復元で回数が戻らないよう保存した残数を読む。無い（旧データ）なら無料枠から。
            undosRemaining = max(0, snap.undosRemaining ?? Game2048UndoBudget.free)
        } else {
            initialBoard = Game2048Logic.emptyBoard()
            initialScore = 0
            // 初期タイル 2 個。
            _ = Self.spawn(into: &initialBoard)
            _ = Self.spawn(into: &initialBoard)
            isFreshStart = true
        }
        board = initialBoard
        score = initialScore
        gameOver = Game2048Logic.isGameOver(initialBoard)
        rebuildTiles(arrival: .placed)
        persist()
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshStart { services?.gameDidStart(gameID: gameID) }
    }

    /// 盤面を直接与えて開始する。初期タイルの乱数生成と中断スナップショットの復元を
    /// 経由しないので、狙った局面（1マスも動かない方向がある盤面など）から検証できる。
    /// テスト用の経路で、`init(services:)` の挙動には影響しない。
    public init(services: GameServices? = nil, board: [[Int]], score: Int = 0) {
        self.services = services
        self.board = board
        self.score = score
        gameOver = Game2048Logic.isGameOver(board)
        // 既に 2048 が乗っている盤から始めたときは到達済みとして扱う（次の合体で演出が出ない）。
        hasWon = Game2048Logic.hasWinningTile(board)
        rebuildTiles(arrival: .placed)
        persist()
    }

    /// 指定方向へスライド。動いたときのみ新タイルを生成し、終局判定・永続化する。
    public func move(_ direction: Direction) {
        // 勝利演出はスワイプ領域の上に重なるだけで、盤面へのジェスチャは生きている。
        // ここで止めないと、演出を出したまま裏で盤面・スコア・中断データが進む（PR #450 指摘）。
        guard !gameOver, !showWinPrompt else { return }
        let result = Game2048Logic.slide(board, direction)
        guard result.moved else {
            announce(tr("その方向には動かせません"))
            services?.feedback.notify(.warning) // 1マスも動かない方向へのスワイプ
            return
        }

        // 戻す先は「この手の前」。出現したタイルも含めた盤とスコアをそのまま控える（#2023）。
        history.append(Game2048Step(board: board, score: score, hasWon: hasWon))
        if history.count > Game2048UndoBudget.historyLimit { history.removeFirst() }
        let moves = Game2048Logic.moves(board, direction)
        board = result.board
        score += result.gained
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。
        services?.gameDidProgress(gameID: gameID)
        let spawned = Self.spawn(into: &board)
        applyTileMoves(moves, spawned: spawned)
        announce(Game2048Accessibility.moveResult(
            gained: result.gained,
            spawned: spawned.map { (row: $0.row, col: $0.col, value: board[$0.row][$0.col]) }
        ))

        // この手で初めて 2048 を作ったか（#438）。新タイルは 2 か 4 なので、判定は合体の結果だけを見る。
        let justWon = !hasWon && Game2048Logic.hasWinningTile(board)
        if justWon { hasWon = true }

        if Game2048Logic.isGameOver(board) {
            gameOver = true
            lastFinishWasLoss = !justWon
            services?.feedback.notify(justWon ? .success : .error)
            let highestTile: Int? = board.flatMap { $0 }.max()
            // 2048 を作った手がそのまま盤を埋め切った場合だけ、終局でも勝ちとして記録する
            // （到達自体は成立しているため）。決着 1 回につき `gameDidFinish` は 1 回だけ呼ぶ。
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: justWon ? .win : .loss,
                score: GameScore(metric: .points, points: score, highestValue: highestTile)
            )
            services?.snapshots.clear(for: gameID) // 終局でスナップショット破棄
        } else if justWon {
            // 原典と同じく、勝ってもそのまま続けられる。演出を出して決着だけ先に記録する。
            showWinPrompt = true
            services?.feedback.notify(.success)
            recordResult = services?.gameDidFinish(
                gameID: gameID,
                outcome: .win,
                score: GameScore(metric: .points, points: score, highestValue: board.flatMap { $0 }.max())
            )
            persist()
        } else {
            services?.feedback.impact(result.gained > 0 ? .medium : .light)
            persist()
        }
    }

    private func announce(_ text: String) {
        lastResult = .next(after: lastResult, text: text)
    }

    /// 勝利演出の「続ける」。盤面もスコアもそのままに、続きを次の 1 プレイとして数え直す（#438）。
    ///
    /// `continueAfterAd` と同じ理由で `gameDidRestart` を呼ぶ: 到達時点で `game_end` を送っており、
    /// ここで数え直さないと `game_start` 1 回に対して `game_end` が 2 回付いて対応が崩れる（#158）。
    public func continueAfterWin() {
        guard showWinPrompt else { return }
        showWinPrompt = false
        recordResult = nil
        // 下ろしたことを中断データにも書く（#516）。書かないと、続行後に中断・復元するたびに
        // 演出が出直し、そのつど `gameDidRestart` が走って `game_start` だけが増える。
        persist()
        services?.gameDidRestart(gameID: gameID)
        // 続きの盤面は既に指した盤面なので、数え直した 1 プレイも最初から「指した」扱いにする（#1953）。
        // これが無いと、無操作で「もう一度」を押したとき `game_end`（quit）が出ず `game_start` だけが残る。
        services?.gameDidProgress(gameID: gameID)
    }

    /// 広告を出す前に控えた `gameSerial` の局にだけコンティニューを適用する（#729）。
    /// - Returns: 適用できたか。false のとき View は「コンティニューできなかった」と知らせる。
    @discardableResult
    public func continueAfterAd(forGame serial: Int) -> Bool {
        guard serial == gameSerial else { return false }
        return continueAfterAd()
    }

    /// リワード広告視聴後にコンティニュー。盤面・スコアを保持したまま再開。1回のみ使用可。
    @discardableResult
    public func continueAfterAd() -> Bool {
        guard gameOver, !continueUsed else { return false }
        // 同じ盤面・同じスコアの続きなので、直前に記録した「負け」は無かったことにする
        // （そのままだと1回のプレイが2回分として数えられる）。到達済みのスコアは取り消さない。
        // 勝ちで終局した局では巻き戻すものが無い。呼ぶとこの局と無関係な過去の負けが消える（#764）。
        if lastFinishWasLoss {
            services?.playLog?.cancelLoss(gameID: gameID)
        }
        lastFinishWasLoss = false
        recordResult = nil
        gameOver = false
        continueUsed = true
        // 終局盤面は必ず全埋まりなので、ここで新タイルを置こうとしても空振りする（それが #122 の不具合）。
        // 最小値のタイルを消して空きマスを確保し、確実に続きを遊べる盤面で再開する。新タイルは置かない
        // （コンティニューは手番ではないうえ、せっかく確保した空きマスを潰して続行手数を削るだけのため）。
        board = Game2048Logic.revive(board)
        rebuildTiles(arrival: .placed)
        persist()
        // `game_end` はもう送信済みなので、続きは次の1プレイとして数える（#158）。
        // こうしないと `game_start` 1 回に対して `game_end` が 2 回付き、対応が崩れる。
        services?.gameDidRestart(gameID: gameID)
        // 続きの盤面は既に指した盤面（#1953）。`continueAfterWin` と同じ理由で数え直した 1 プレイを「指した」扱いにする。
        services?.gameDidProgress(gameID: gameID)
        return true
    }

    // MARK: - 戻す（#2023）

    /// 「戻す」を押せるか。勝利演出が出ているあいだは「続ける / もう一度」を先に選ばせる（`move` と同じ扱い）。
    /// 負けの局面からも戻せる。
    public var canUndo: Bool { !history.isEmpty && !showWinPrompt }

    /// 残り回数があるか。
    public var hasUndoCredit: Bool { undosRemaining > 0 }

    /// 押せるが回数を使い切っている（View は広告の提案を出す）。
    public var needsUndoRefill: Bool { canUndo && !hasUndoCredit }

    /// 1 手戻す。**1 局につき無料 `Game2048UndoBudget.free` 回まで**（使い切ったら `grantUndos(forGame:)` で補充）。
    /// 連続で押せば、さらに前へ戻れる。
    @discardableResult
    public func undo() -> Bool {
        guard canUndo, hasUndoCredit, let step = history.popLast() else { return false }
        undosRemaining -= 1
        board = step.board
        score = step.score
        rebuildTiles(arrival: .placed)
        if gameOver {
            // 終局から戻る。`continueAfterAd` と同じ理由で、記録した「負け」は無かったことにし、
            // 続きを次の 1 プレイとして数え直す（`game_end` は送信済み）。勝ちで終局した局には取り消す負けが無い（#764）。
            if lastFinishWasLoss {
                services?.playLog?.cancelLoss(gameID: gameID)
            }
            lastFinishWasLoss = false
            recordResult = nil
            gameOver = false
            // 2048 を作った手で終局していたら、到達の印も手前に戻す（#2056）。戻さないと同じ手で再び 2048 を
            // 作っても `justWon` が立たず、勝てた局が負けとして記録される。勝ちの二重記録は上の数え直しと同じ扱い。
            // 非終局で勝ってから戻すときは復元しない（勝利演出を局に 1 度だけ出す #438 を保つ）。旧データ（nil）は触らない。
            if let before = step.hasWon { hasWon = before }
            persist()
            services?.gameDidRestart(gameID: gameID)
            services?.gameDidProgress(gameID: gameID)
        } else {
            persist()
        }
        services?.feedback.impact(.medium)
        return true
    }

    /// リワード広告の**視聴完了後**に「戻す」を補充する。
    ///
    /// - Parameter serial: 広告を出す前に控えた `gameSerial`。広告のロード中に新規ゲームを始めたら補充しない
    ///   （`newGame` は残数を無料枠へ戻すので、そのまま足すと無料 + 補充から始まる）。
    /// - Returns: 補充できたか。false のとき View は「補充できなかった」と伝える。
    @discardableResult
    public func grantUndos(forGame serial: Int) -> Bool {
        guard serial == gameSerial else { return false }
        undosRemaining += Game2048UndoBudget.refill
        services?.feedback.notify(.success)
        persist()
        return true
    }

    /// 「リセット」で失われる進行があるか（#1011）。
    ///
    /// 開始直後の盤は 2 枚だけで得点 0。1 手動かすと（合体すれば得点が入り、しなければ 1 枚増えて）
    /// このどちらかが変わる。終局後は捨てるものが無いので false。
    public var hasProgressToLose: Bool {
        guard !gameOver else { return false }
        return score > 0 || board.joined().filter { $0 != 0 }.count > 2
    }

    /// 新規ゲーム。
    public func newGame() {
        gameSerial += 1
        board = Game2048Logic.emptyBoard()
        score = 0
        gameOver = false
        continueUsed = false
        hasWon = false
        showWinPrompt = false
        recordResult = nil
        lastFinishWasLoss = false
        history = []
        undosRemaining = Game2048UndoBudget.free
        _ = Self.spawn(into: &board)
        _ = Self.spawn(into: &board)
        rebuildTiles(arrival: .spawned)
        persist()
        services?.gameDidRestart(gameID: gameID)
    }

    #if DEBUG
    /// 撮影・動作確認用: ゲームオーバーの画を直接作る（`-simulate2048GameOver`・#1486）。
    /// 指し手で自然に詰ませようとすると新しいタイルの出現がランダムで時間もかかるため、
    /// 隣どうしが必ず異なる 2 のべき乗を蛇行順に敷き詰めて（合体できない・空きも無い）確定で詰ませる。
    public func debugForceGameOver() {
        let n = Game2048Logic.size
        var value = 1
        board = (0..<n).map { r in
            let row = (0..<n).map { _ -> Int in
                value *= 2
                return value
            }
            // 蛇行順（行ごとに向きを反転）にすることで、上下の行境界でも値が必ず食い違う。
            return r % 2 == 0 ? row : Array(row.reversed())
        }
        rebuildTiles(arrival: .placed)
        gameOver = true
    }
    #endif

    private func persist() {
        guard !gameOver else { return }
        try? services?.snapshots.save(
            Game2048Snapshot(
                board: board,
                score: score,
                continueUsed: continueUsed,
                hasWon: hasWon,
                showWinPrompt: showWinPrompt,
                history: history,
                undosRemaining: undosRemaining
            ),
            for: gameID
        )
    }

    /// 復元してよい盤か。4x4 で、どのタイルも 0 以上であること。
    private static func isRestorable(_ board: [[Int]]) -> Bool {
        board.count == Game2048Logic.size
            && board.allSatisfy { $0.count == Game2048Logic.size && $0.allSatisfy { $0 >= 0 } }
    }

    /// 空きマスへランダムに 2(90%)/4(10%) を 1 個置く。置いたマスを返す（空きが無ければ nil）。
    private static func spawn(into board: inout [[Int]]) -> Game2048Cell? {
        let cells = Game2048Logic.emptyCells(board)
        guard let cell = cells.randomElement() else { return nil }
        board[cell.row][cell.col] = Int.random(in: 0..<10) == 0 ? 4 : 2
        return Game2048Cell(row: cell.row, col: cell.col)
    }

    // MARK: - 描くタイル（#2253）

    /// 合体元の 2 枚を片付ける。View が滑り終えた後に、待ち始めたときの ID を渡して呼ぶ。
    /// その間に次の手が入って `vanishing` が入れ替わっていたら何もしない（次の手の合体元を途中で消さない）。
    public func settleVanishing(ids: [Int]) {
        guard !vanishing.isEmpty, vanishing.map(\.id) == ids else { return }
        vanishing = []
    }

    private func makeTile(value: Int, row: Int, col: Int, arrival: Game2048Tile.Arrival) -> Game2048Tile {
        nextTileID += 1
        return Game2048Tile(id: nextTileID, value: value, row: row, col: col, arrival: arrival)
    }

    /// `board` からタイルを作り直す（ID も新しくする）。滑らせる元が無い場面（再開・戻す・新しいゲーム）で使う。
    private func rebuildTiles(arrival: Game2048Tile.Arrival) {
        vanishing = []
        var rebuilt: [Game2048Tile] = []
        for r in board.indices {
            for c in board[r].indices where board[r][c] != 0 {
                rebuilt.append(makeTile(value: board[r][c], row: r, col: c, arrival: arrival))
            }
        }
        tiles = rebuilt
    }

    /// 1 手ぶんのタイルの動きを反映する。`moves` は手の前の盤から求めたもの、`board` は手の後（出現込み）。
    /// - 合体しないタイル: ID を保ったまま行き先へ（View が座標をアニメーションして滑らせる）。
    /// - 合体する 2 枚: ID を保ったまま行き先へ滑らせて `vanishing` に移し、行き先には新しい ID の合体タイルを置く。
    /// - 出現: 新しい ID で置く。
    /// 前の手の `vanishing` はここで入れ替わる（連続スワイプで取り残さない）。
    private func applyTileMoves(_ moves: [Game2048TileMove], spawned: Game2048Cell?) {
        var byCell: [Game2048Cell: Game2048Tile] = [:]
        for tile in tiles { byCell[Game2048Cell(row: tile.row, col: tile.col)] = tile }

        var next: [Game2048Tile] = []
        var gone: [Game2048Tile] = []
        var mergedAt: [Game2048Cell] = []
        for move in moves {
            guard let tile = byCell[move.from] else { continue }
            let moved = Game2048Tile(id: tile.id, value: tile.value, row: move.to.row, col: move.to.col,
                                     arrival: .slid)
            if move.merges {
                gone.append(moved)
                if !mergedAt.contains(move.to) { mergedAt.append(move.to) }
            } else {
                next.append(moved)
            }
        }
        for cell in mergedAt {
            next.append(makeTile(value: board[cell.row][cell.col], row: cell.row, col: cell.col, arrival: .merged))
        }
        if let spawned {
            next.append(makeTile(value: board[spawned.row][spawned.col], row: spawned.row, col: spawned.col,
                                 arrival: .spawned))
        }
        tiles = next
        vanishing = gone
        // 万一タイルと盤が食い違ったら、取り残しを出さないよう盤から作り直す。
        if !tilesMatchBoard() { rebuildTiles(arrival: .placed) }
    }

    /// `tiles` が `board` と 1 対 1 で一致しているか。
    private func tilesMatchBoard() -> Bool {
        var drawn = Game2048Logic.emptyBoard()
        for tile in tiles {
            guard drawn.indices.contains(tile.row), drawn[tile.row].indices.contains(tile.col),
                  drawn[tile.row][tile.col] == 0 else { return false }
            drawn[tile.row][tile.col] = tile.value
        }
        return drawn == board
    }
}
