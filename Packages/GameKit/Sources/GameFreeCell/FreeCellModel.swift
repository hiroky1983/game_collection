import Foundation
import Observation
import Core

public enum FreeCellPhase: String, Codable, Sendable, Equatable {
    /// 取り進めている最中。
    case playing
    /// 52 枚すべてを組札に積んだ。
    case won
}

/// 「戻す」の回数制（#492）。**ソリティア（#476）と同じ経済**を使う。
///
/// 値は `Core.RewardedUndoBudget` が持ち、ここはフリーセルの文脈に名前を残すための転送。
/// `FreeCellModel` の外に置くのは、モデルが `@MainActor` なのに対し読み上げ文
/// （`FreeCellAccessibility`）が非隔離の純関数だから（`SolitaireUndoBudget` と同じ理由）。
public enum FreeCellUndoBudget {
    /// 1 局につき無料で戻せる回数。配り直し・新規ゲームでここまで戻る。
    public static let free = RewardedUndoBudget.free
    /// リワード広告 1 本の視聴完了で補充する回数。
    public static let refill = RewardedUndoBudget.refill
}

/// いま持ち上げている札。
///
/// 場札は「その位置から上を丸ごと」動かすため、列と添字の組で表す。
public enum FreeCellSelection: Equatable, Sendable {
    case cell(Int)
    case tableau(pile: Int, cardIndex: Int)
}

/// 中断スナップショット。
///
/// **配札は種から決定的に再現できる**（`FreeCellDealer.deal`）ので、盤面そのものは保存せず
/// 「種 + 指した手順」だけを持つ。undo も同じ手順の再生で実現しているため、保存と巻き戻しの
/// 経路が 1 本にまとまる（ソリティア #397 と同じ契約）。
struct FreeCellSnapshot: Codable {
    let seed: UInt64
    let moves: [FreeCellMove]
    let elapsedSeconds: Int
    /// 「戻す」の残り回数。**手順から導出できない**（消費も広告での補充も `moves` に残らない）ので
    /// ここだけは別に持つ。
    ///
    /// **省略可**。将来この欄が欠けた中断データを読んだときは、無料枠が丸ごと残っている扱いにする。
    let undosRemaining: Int?
    /// この局で使ったヒントの回数（#2025）。再開で回数が戻らないよう保存する。
    /// **省略可**。旧形式には無いので、無ければ 0（未使用）として読む。
    var hintsUsed: Int? = nil
}

@MainActor
@Observable
public final class FreeCellModel {
    /// 計時だけが進んでいる間に中断データを保存し直す間隔（秒）。麻雀ソリティア（#240）と同じ理由で、
    /// 長考のあとにアプリを終了しても最短タイムが実際より短く記録されないようにする。
    static let persistInterval = 30

    public private(set) var board: FreeCellBoard
    public private(set) var phase: FreeCellPhase = .playing
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var selection: FreeCellSelection?
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 拒否されたタップの通し番号（#202）。View はこの値の変化を震え演出のトリガーにする。
    public private(set) var rejectedTapCount: Int = 0

    /// 指せる手が 1 つも無い状態。**毎描画で数え直すと重い**ので、盤面が動いたときにだけ更新する。
    ///
    /// ソリティアの (a)(b) 二段構えと違い、フリーセルはこれ 1 つで足りる
    /// （`FreeCellBoard.isDeadEnd` の注記のとおり、近似の入る余地が無いため）。
    public private(set) var isDeadEnd: Bool = false

    /// 行き止まりの告知を「このまま続ける」で閉じたか。配り直すまで残る。
    ///
    /// 合法手がゼロなので盤には触れないが、**告知を閉じて盤面を眺める**のはフリーセルでは
    /// 普通の行為（どこで間違えたかを読み返してから戻す）。閉じられないと盤を隠されたまま
    /// 選択を迫られる（#491 でソリティアに入れた判断と同じ）。
    public private(set) var didDismissDeadEndPrompt: Bool = false

    /// 「戻す」の残り回数（#492 = #476 と同じ経済）。
    ///
    /// 本作は**クリア可能と検証済みの配札しか出さない**ため、無制限に戻せると理論上どの局面からも
    /// やり直して必ず勝ててしまう。ソリティア・将棋の「待った」と同型の回数制にする。
    public private(set) var undosRemaining: Int

    /// 配札番号（= 種）。フリーセルは番号付きディールの文化があるので画面に出す。
    public private(set) var dealNumber: UInt64

    /// この局のヒントの残り（#2025）。無料 3 回・広告で最大 5 回。回数と順位表の扱いは Core の `BoardHintBudget` が持つ。
    /// 戻すとは別の回数で、戻してもここは戻らない。
    public private(set) var hints = BoardHintBudget(
        freeLimit: FreeCellHintPolicy.freeCount, adLimit: FreeCellHintPolicy.adRefillMax
    )
    /// ヒントの読みの最中か。
    public var isHintThinking: Bool { hintReader.isThinking }
    /// 示している手。**盤が動いたら消える**（`refreshDerivedState`）ので、印が古い盤の手を指すことは無い。永続化しない。
    public private(set) var hintMove: FreeCellMove?
    /// 勝てないと分かったときの知らせ（回数は減らさない）。View が閉じるまで残る。
    public var showsHintHopeless: Bool { hintReader.showsHopeless }
    /// テスト専用: 読みが終わった直後（結果を取り込む前）に呼ぶ。読みの最中に盤が動いた状況を決定的に作る。
    var hintSearchDidFinishForTesting: (() -> Void)?
    /// 読み・広告経路・回数の消費の流れ（盤の版番号・読みの Task は Core が持つ・#2125）。
    private let hintReader = BoardHintReader<FreeCellHintResult>()

    private var moves: [FreeCellMove] = []
    /// 「ここから組札へ送るだけで勝ち切れる」手順。無ければ nil。
    private var autoFinishPlan: [FreeCellMove]?
    /// 計時の動かし方・止め方（#1857）。経過秒は実経過時間で求める（#1751）。
    private let stopwatch = GameStopwatch(persistInterval: FreeCellModel.persistInterval)
    /// 直前にタップした札と時刻（ダブルタップの判定用・#2598）。
    private var lastCardTap: (selection: FreeCellSelection, at: ContinuousClock.Instant)?
    /// この間隔に同じ札を 2 回タップしたらダブルタップ（組札へ直接送る）。仮置きの値で、会長 QA で調整する。
    static let doubleTapInterval: Duration = .milliseconds(350)
    /// 現在時刻の取り出し口（テストが時間を進めるために差し替える）。
    var clockNow: ElapsedClock.Now {
        get { stopwatch.now }
        set { stopwatch.now = newValue }
    }
    private let services: GameServices?
    /// 同じモジュールの View も参照する（`reward_ad` の送信に要る・#500）。
    let gameID = "freecell"

    /// 手数（記録に出す値）。フリーセルには山めくりのような「数えると無意味になる手」が無いので全部数える。
    public var moveCount: Int { moves.count }

    /// 戻せる手があるか。**残り回数は見ない**。
    ///
    /// この値は「1 手でも指したか」の意味でも使われている（`newGame()` の敗北記録・配り直しの
    /// 確認ダイアログ）。ここに残り回数を混ぜると、回数を使い切った盤面を捨てても
    /// 「クリアできなかった」として記録されなくなり、クリア率が実態とずれる（#476 と同じ）。
    public var canUndo: Bool { phase == .playing && !moves.isEmpty }

    /// 無料で戻せる回数が残っているか。
    public var hasUndoCredit: Bool { undosRemaining > 0 }

    /// 「戻す」を押したときにリワード広告の提案を出す局面か。
    /// 戻せる手が無いときは提案しない（広告を見ても何も起きないため）。
    public var needsUndoRefill: Bool { canUndo && !hasUndoCredit }

    /// 行き止まりの告知を出す局面か。
    public var showsDeadEndPrompt: Bool {
        phase == .playing && isDeadEnd && !didDismissDeadEndPrompt
    }

    /// 配ったまま 1 手も指していないか（View は配札の演出を出すかの判定に使う）。
    public var isFreshDeal: Bool { moves.isEmpty }

    /// 配り直しの通し番号。`newGame()` のたびに増える。
    ///
    /// View はこの値を札のビューの identity に混ぜる。**SwiftUI は同一性が保たれている限り
    /// `@State` を作り直さない**ため、これが無いと配り直しで同じ列に同じ札が残った場合に
    /// 「もう配り終わった」状態のビューが再利用され、その札だけ配札の演出が出ない（#421 と同型）。
    public private(set) var dealSerial: Int = 0

    /// 組札へ送る手だけで勝ち切れる状態か。終盤の 52 回タップを 1 回に畳む。
    public var canAutoFinish: Bool { phase == .playing && autoFinishPlan != nil }

    /// 計時が動いているか（テスト用）。
    public var isCounting: Bool { stopwatch.isRunning }

    /// - Parameter seed: テスト・撮影用の固定種。nil なら検証済みの種から 1 つ選ぶ。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services

        var startSeed = seed ?? Self.pickSeed()
        var startMoves: [FreeCellMove] = []
        var startElapsed = 0
        var startUndos = FreeCellUndoBudget.free
        var startHintsUsed = 0
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = true

        if let snap = services?.snapshots.load(FreeCellSnapshot.self, for: "freecell") {
            startSeed = snap.seed
            startMoves = snap.moves
            startElapsed = max(0, snap.elapsedSeconds)
            startUndos = max(0, snap.undosRemaining ?? FreeCellUndoBudget.free)
            startHintsUsed = snap.hintsUsed ?? 0
            isFreshStart = false
        }

        self.dealNumber = startSeed
        self.elapsedSeconds = startElapsed
        self.undosRemaining = startUndos
        self.hints = BoardHintBudget(
            used: startHintsUsed,
            freeLimit: FreeCellHintPolicy.freeCount, adLimit: FreeCellHintPolicy.adRefillMax
        )
        // 壊れた（または食い違った）中断データは、**適用できたところで打ち切る**。
        // 落ちた手を黙って読み飛ばすと、以降の手順が 1 手ずつずれた別の盤面になる（#406 申し送り2）。
        let restored = Self.replay(startMoves, seed: startSeed)
        self.moves = Array(startMoves.prefix(restored.applied))
        self.board = restored.board
        refreshDerivedState()
        // 取り切った局はスナップショットを消しているので、ここで `won` に復元されることは無い。
        // それでも念のため、勝ち盤面が入ってきたら勝ちとして扱う（記録はしない = 二重計上を避ける）。
        if board.isWon { phase = .won }

        if isFreshStart { services?.gameDidStart(gameID: gameID) }
    }

    private static func pickSeed(excluding previous: UInt64? = nil) -> UInt64 {
        var system = SystemRandomNumberGenerator()
        return FreeCellDealer.randomVerifiedSeed(excluding: previous, using: &system)
    }

    /// 種から配り直して手順を再生する。undo も新規配札もこの 1 本を通る。
    ///
    /// - Returns: 再生後の盤面と、**実際に適用できた手数**。手数が `moves.count` より少なければ
    ///   中断データが壊れている（呼び出し側はそこで手順を切り詰める）。
    private static func replay(_ moves: [FreeCellMove], seed: UInt64) -> (board: FreeCellBoard, applied: Int) {
        var board = FreeCellDealer.deal(seed: seed)
        for (index, move) in moves.enumerated() {
            guard board.apply(move) else { return (board, index) }
        }
        return (board, moves.count)
    }

    // MARK: - タップ

    /// フリーセルの 1 枠をタップ。札があれば持ち上げ / 空いていれば置く。
    public func tapCell(_ cell: Int) {
        guard phase == .playing, board.cells.indices.contains(cell) else { return }
        if board.cells[cell] != nil, registerCardTap(.cell(cell)), sendToFoundation(.cell(cell)) { return }
        if selection == .cell(cell) { return deselect() }

        if let selection, board.cells[cell] == nil {
            // 空きセルへは**場札の一番上の 1 枚だけ**入れられる（並びは入らない）。
            guard case .tableau(let pile, let index) = selection,
                  index == board.tableau[pile].count - 1 else { return reject() }
            return perform(.tableauToCell(from: pile, cell: cell))
        }

        guard board.cells[cell] != nil else { return reject() }
        selection = .cell(cell)
        services?.feedback.impact(.rigid)
    }

    /// 組札をタップ。選択中の札を送る。
    public func tapFoundation(_ suit: PlayingCardSuit) {
        guard phase == .playing else { return }
        guard let selection, let move = foundationMove(from: selection), board.isLegal(move) else {
            return reject()
        }
        // 送り先のスートが選択中の札と違うなら、それは誤タップ（拒否して選択は残す）。
        guard card(at: selection)?.suit == suit else { return reject() }
        perform(move)
    }

    /// 場札の列をタップ。持ち上げる / 置く。
    ///
    /// - Parameter cardIndex: 列の中の添字。省略時は一番上の 1 枚（列全体の受け皿としての扱い）。
    public func tapPile(_ pile: Int, cardIndex: Int? = nil) {
        guard phase == .playing, board.tableau.indices.contains(pile) else { return }

        if !board.tableau[pile].isEmpty {
            let top = cardIndex ?? (board.tableau[pile].count - 1)
            let target = FreeCellSelection.tableau(pile: pile, cardIndex: top)
            if registerCardTap(target), sendToFoundation(target) { return }
        }

        if let selection {
            if case .tableau(let from, let index) = selection, from == pile {
                // 同じ列の同じ札をもう一度 → 選択解除。別の札 → 選び直し。
                if cardIndex == nil || cardIndex == index { return deselect() }
            } else if let move = tableauMove(from: selection, to: pile), board.isLegal(move) {
                return perform(move)
            } else {
                return reject()
            }
        }

        guard !board.tableau[pile].isEmpty else { return reject() }
        let index = cardIndex ?? (board.tableau[pile].count - 1)
        guard board.tableau[pile].indices.contains(index),
              board.isOrderedRun(pile: pile, from: index) else { return reject() }
        selection = .tableau(pile: pile, cardIndex: index)
        services?.feedback.impact(.rigid)
    }

    public func deselect() {
        selection = nil
        // ドラッグの落とし先は deselect → 合成タップで処理される。ダブルタップと取り違えない（#2598）。
        lastCardTap = nil
        services?.feedback.impact(.rigid)
    }

    /// 行き止まりの告知を閉じる。配り直すまで再表示しない。
    public func dismissDeadEndPrompt() {
        if isDeadEnd { didDismissDeadEndPrompt = true }
    }

    // MARK: - 巻き戻し

    /// 1 手戻す。**1 局につき無料 `FreeCellUndoBudget.free` 回まで**（使い切ったら `grantUndos()` で補充）。
    @discardableResult
    public func undo() -> Bool {
        guard canUndo, hasUndoCredit else {
            reject()
            return false
        }
        undosRemaining -= 1
        moves.removeLast()
        board = Self.replay(moves, seed: dealNumber).board
        selection = nil
        services?.feedback.impact(.medium)
        refreshDerivedState()
        persist()
        return true
    }

    /// リワード広告の**視聴完了後**に「戻す」を補充する。
    ///
    /// 呼ぶのは視聴完了を確認したあとだけ（自動再生禁止・プレイヤーが「見る」を選んだときだけ）。
    ///
    /// - Parameter serial: 広告を出す前に控えた `dealSerial`。**広告のロード〜視聴の間に配り直されたら
    ///   補充しない**。`newGame()` は残数を無料枠へ戻すので、そのまま足すと配り直した局が
    ///   `無料3 + 補充3 = 6` から始まる（PR #480 の敵対的検証で見つかった型の欠陥）。
    @discardableResult
    public func grantUndos(forDeal serial: Int) -> Bool {
        guard phase == .playing, serial == dealSerial else { return false }
        undosRemaining += FreeCellUndoBudget.refill
        services?.feedback.notify(.success)
        persist()
        return true
    }

    // MARK: - ヒント（#2025）

    /// 示している手の、動かす札の場所。タップ選択と同じ型（セル、または列の添字から上）。
    public var hintSource: FreeCellSelection? {
        switch hintMove {
        case .tableauToCell(let from, _), .tableauToFoundation(let from):
            let count = board.tableau.indices.contains(from) ? board.tableau[from].count : 0
            return count > 0 ? .tableau(pile: from, cardIndex: count - 1) : nil
        case .tableauToTableau(let from, let index, _): return .tableau(pile: from, cardIndex: index)
        case .cellToTableau(let cell, _), .cellToFoundation(let cell): return .cell(cell)
        case nil: return nil
        }
    }

    /// 示している手の、行き先。
    var hintDestination: FreeCellDropTarget? {
        switch hintMove {
        case .tableauToCell(_, let cell): return .cell(cell)
        case .tableauToFoundation, .cellToFoundation:
            guard let hintSource, let card = card(at: hintSource) else { return nil }
            return .foundation(card.suit)
        case .tableauToTableau(_, _, let to), .cellToTableau(_, let to): return .pile(to)
        case nil: return nil
        }
    }

    /// 残り回数（無料 + 広告の合計）。
    public var hintsRemaining: Int { hints.remaining }

    /// いまヒントを押せるか。遊んでいる最中で、読みが走っておらず、残りが在るとき。
    public var canUseHint: Bool { phase == .playing && !isHintThinking && !hints.isExhausted }

    /// 無料枠を使い切っていて、次の 1 回に広告が要るか。
    public var needsAdForHint: Bool { !hints.hasFreeRemaining && !hints.isExhausted }

    public func dismissHintHopeless() { hintReader.showsHopeless = false }

    /// 無料の 1 回。勝ち筋を探して最初の 1 手を示す。**求まらなかった・盤が変わった・勝てない盤では回数を減らさない**。
    /// 呼ぶ側は画面を離れたら取り消せる Task で走らせる（`GameScreenGeneration.runUntilLeave`）。
    public func requestHint() async {
        await hintReader.requestFree(hintContext)
    }

    /// 無料枠を使い切った後、広告を見て 1 回ぶん追加する。**先に読み**、勝てない盤では広告を流さない（`BoardHintReader.requestAd`）。
    public func requestAdHint() async -> RewardedModelOutcome {
        await hintReader.requestAd(hintContext)
    }

    /// `requestAdHint()` のうち、読みを終えて広告を出す直前に知らせる形（先読みの間は計時を止めない・#2125）。
    public func requestAdHint(readDidFinish: () -> Void) async -> RewardedModelOutcome {
        await hintReader.requestAd(hintContext, readDidFinish: readDidFinish)
    }

    private var hintContext: BoardHintReader<FreeCellHintResult>.Context {
        .init(
            services: services, gameID: gameID, canUse: canUseHint, needsAd: needsAdForHint, isPlaying: phase == .playing,
            cachedAnswer: { nil },
            makeSearch: { [self] in
                let board = self.board
                return { FreeCellHint.find(in: board, isCancelled: { Task.isCancelled }) }
            },
            searchDidFinish: { [self] in hintSearchDidFinishForTesting?() },
            verdict: { [self] result in
                switch result {
                case .hopeless: return .hopeless
                case .move(let move): return board.isLegal(move) ? .legal : .illegal
                }
            },
            show: { [self] result in
                guard case .move(let move) = result else { return }
                hintMove = move
            },
            persist: { [self] in persist() },
            consumeFree: { [self] in hints.consume() },
            consumeAd: { [self] in hints.consumeAd() }
        )
    }

    // MARK: - 自動で上がる

    /// 組札へ送る手だけで勝ち切れるなら、まとめて送って決着させる。
    @discardableResult
    public func autoFinish() -> Bool {
        guard phase == .playing, let plan = autoFinishPlan else { return false }
        for move in plan {
            board.apply(move)
            moves.append(move)
        }
        selection = nil
        refreshDerivedState()
        finish()
        return true
    }

    // MARK: - 新規配札

    /// 新しい配札を配る。
    ///
    /// **1 手でも指した盤面を捨てたときは敗北として記録する**（クリア率を意味のある数字にするため）。
    /// 判定の境目は「新規ゲームの確認ダイアログを出すか」と同じ `canUndo` に揃えてある
    /// （＝ユーザーが「今の盤面が失われます」と読んだ操作だけが記録に乗る）。ソリティア #397 と同じ。
    public func newGame() {
        deal(sameDeal: false)
    }

    /// 今と同じ配札を最初から配り直す（#2603）。記録の扱いは `newGame` と同じ。
    public func restartSameDeal() {
        deal(sameDeal: true)
    }

    private func deal(sameDeal: Bool) {
        syncElapsed()   // 止める・確定する前に、直近の秒の境目からの端数も実経過時間で取り込む（#1751）
        if phase == .playing, canUndo {
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        }
        // 直前の配札は除く（#914）。
        if !sameDeal {
            dealNumber = Self.pickSeed(excluding: dealNumber)
        }
        moves = []
        undosRemaining = FreeCellUndoBudget.free
        hints.reset()
        hintReader.reset()
        board = Self.replay(moves, seed: dealNumber).board
        phase = .playing
        selection = nil
        didDismissDeadEndPrompt = false
        elapsedSeconds = 0
        recordResult = nil
        dealSerial += 1
        refreshDerivedState()
        // 画面は開いたままなので計時を入れ直す（View の `.task` は初回表示のときしか走らない）。
        stopwatch.stop()
        startTimer()
        services?.feedback.impact(.medium)
        services?.snapshots.clear(for: gameID)
        services?.gameDidRestart(gameID: gameID)
    }

    // MARK: - 計時

    /// 中断から復帰したときに計時を再開する（View の `.task` から呼ぶ）。
    public func resumeTimerIfNeeded() {
        guard phase == .playing, !stopwatch.isRunning else { return }
        startTimer()
    }

    /// 画面を離れるときに計時を止める（`onDisappear` から呼ぶ）。
    ///
    /// 計時の `Task` は `self` を強く握るので、止めないと**モデルが解放されず**、
    /// 画面を離れたあとも 1 秒ごとに経過秒とスナップショットが進み続ける（#375）。
    /// 止める前に保存し直すのは、直近の保存から最大 `persistInterval` 秒ぶんの計時が
    /// 失われるのを防ぐため（#240 と同じ理由）。
    public func pauseTimer() {
        syncElapsed()   // 止める・確定する前に、直近の秒の境目からの端数も実経過時間で取り込む（#1751）
        persist()
        stopwatch.stop()
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 内部

    /// 選択中の札（場札なら持ち上げる並びの下端）。
    func card(at selection: FreeCellSelection) -> FreeCellCard? {
        switch selection {
        case .cell(let cell):
            guard board.cells.indices.contains(cell) else { return nil }
            return board.cells[cell]
        case .tableau(let pile, let index):
            guard board.tableau.indices.contains(pile),
                  board.tableau[pile].indices.contains(index) else { return nil }
            return board.tableau[pile][index]
        }
    }

    /// 札のタップを控え、直前に同じ札をタップしてから `doubleTapInterval` 以内ならダブルタップとして true を返す。
    ///
    /// 1 回目のタップは今までどおり選択に使うので、シングルタップの反応は遅らせない。
    private func registerCardTap(_ target: FreeCellSelection) -> Bool {
        let now = clockNow()
        defer { lastCardTap = (target, now) }
        guard let last = lastCardTap, last.selection == target else { return false }
        return now - last.at <= Self.doubleTapInterval
    }

    /// 札を選択なしで組札へ送る。送れなければ何もせず false（拒否の演出も出さない）。
    private func sendToFoundation(_ target: FreeCellSelection) -> Bool {
        guard let move = foundationMove(from: target), board.isLegal(move) else { return false }
        lastCardTap = nil
        perform(move)
        return true
    }

    private func foundationMove(from selection: FreeCellSelection) -> FreeCellMove? {
        switch selection {
        case .cell(let cell):
            return .cellToFoundation(cell: cell)
        case .tableau(let pile, let index):
            // 組札へ送れるのは一番上の 1 枚だけ。
            guard index == board.tableau[pile].count - 1 else { return nil }
            return .tableauToFoundation(pile: pile)
        }
    }

    private func tableauMove(from selection: FreeCellSelection, to pile: Int) -> FreeCellMove? {
        switch selection {
        case .cell(let cell):
            return .cellToTableau(cell: cell, to: pile)
        case .tableau(let from, let index):
            guard from != pile else { return nil }
            return .tableauToTableau(from: from, cardIndex: index, to: pile)
        }
    }

    private func perform(_ move: FreeCellMove) {
        lastCardTap = nil
        guard board.apply(move) else { return reject() }
        moves.append(move)
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。
        // 立つ契機は `canUndo` と同じ「1 手指したか」だが、**一度立つとその局の間は下りない**
        // （`canUndo` は `undo()` で false に戻る）。全部戻して配り直しても遊んだ事実は消えない。
        services?.gameDidProgress(gameID: gameID)
        selection = nil
        services?.feedback.impact(.medium)
        refreshDerivedState()

        if board.isWon {
            finish()
        } else {
            if isDeadEnd { services?.feedback.notify(.warning) }
            persist()
        }
    }

    private func reject() {
        rejectedTapCount += 1
        services?.feedback.notify(.warning)
    }

    private func refreshDerivedState() {
        // 盤が変わった = 示していた手も、走っている読みも古い（#2025）。
        hintMove = nil
        hintReader.boardDidChange()
        isDeadEnd = phase == .playing && board.isDeadEnd
        autoFinishPlan = Self.autoFinishPlan(from: board)
    }

    /// 組札へ送る手だけで勝ち切れる手順。勝ち切れなければ nil。
    ///
    /// 場札を積み替える手もセルへの退避も一切使わない。ここで返せるのは「あとは積むだけ」の
    /// 局面だけで、積み替えが要る局面をプレイヤーの代わりに解いてしまわない。
    static func autoFinishPlan(from board: FreeCellBoard) -> [FreeCellMove]? {
        var board = board
        guard !board.isWon else { return nil }
        var plan: [FreeCellMove] = []

        while !board.isWon {
            var sent = false
            for pile in board.tableau.indices where board.isLegal(.tableauToFoundation(pile: pile)) {
                board.apply(.tableauToFoundation(pile: pile))
                plan.append(.tableauToFoundation(pile: pile))
                sent = true
            }
            for cell in board.cells.indices where board.isLegal(.cellToFoundation(cell: cell)) {
                board.apply(.cellToFoundation(cell: cell))
                plan.append(.cellToFoundation(cell: cell))
                sent = true
            }
            guard sent else { return nil }
        }
        return plan
    }

    /// テスト専用: 盤面だけを差し替えて派生状態を組み直す。
    ///
    /// 行き止まり・「あとは積むだけ」は「種 + 手順」から作るのが現実的でない（検証済み配札を
    /// まともに指している限りまず起きない）ため、局面そのものを組んで検証する口をここに 1 つだけ開ける。
    /// `internal` なのでアプリ側からは触れない。`moves` は動かさないので、この口を使ったあとの
    /// undo と保存は意味を持たない（検証したいのは派生状態だけ）。
    func replaceBoardForTesting(_ board: FreeCellBoard) {
        self.board = board
        refreshDerivedState()
    }

    /// 今の局の成績。タイムと手数は勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    ///
    /// フリーセルは**盤面を有利にする救済アイテムを持たない**（#492 の仕様。詰みは手順のミスなので
    /// undo で戻す）ため、`isLeaderboardEligible` は常に true でよい。ソリティアのジョーカーのような
    /// 「広告を見れば盤面が変わる」仕掛けが無いので、順位表が「何回広告を見たか」の表にならない。
    private var currentScore: GameScore {
        // ヒントを使った局は順位表に送らない（ジョーカーと同じ。自己ベストには残す・#2025）。
        GameScore(metric: .shortestTime, seconds: elapsedSeconds, moves: moveCount,
                  isLeaderboardEligible: !hints.wasUsed)
    }

    private func finish() {
        syncElapsed()   // 止める・確定する前に、直近の秒の境目からの端数も実経過時間で取り込む（#1751）
        phase = .won
        stopwatch.stop()
        selection = nil
        isDeadEnd = false
        autoFinishPlan = nil
        services?.feedback.notify(.success)
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: .win, score: currentScore)
        services?.snapshots.clear(for: gameID)
    }

    private func persist() {
        // 配ったばかりの盤面は保存しない（ハブに「続きから」が出続けるのを避ける）。
        guard phase == .playing, !moves.isEmpty else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snapshot = FreeCellSnapshot(
            seed: dealNumber,
            moves: moves,
            elapsedSeconds: elapsedSeconds,
            undosRemaining: undosRemaining,
            hintsUsed: hints.used
        )
        try? services?.snapshots.save(snapshot, for: gameID)
    }

    private func startTimer() {
        stopwatch.start(base: elapsedSeconds) { [weak self] in self?.syncElapsed() }
    }

    /// 計時の 1 秒ぶん。タイマーのループから切り出してあるので、テストは実時間を待たずに
    /// 経過秒の進み方と保存の間隔を検証できる（実時間で待つテストはフレークする・#375）。
    func tick() {
        elapsedSeconds += 1
        if elapsedSeconds % Self.persistInterval == 0 { persist() }
    }

    /// タイマーのループが秒の境目ごとに呼ぶ。経過秒を実経過時間（`ElapsedClock`）に合わせ、保存間隔（`persistInterval` 秒）の境目を跨いだら保存する。
    /// 計時中でないときは何もしない。`tick()` は 1 秒ぶんを直接進めるテスト用の入口として残している。
    func syncElapsed() {
        guard let advanced = stopwatch.advance(from: elapsedSeconds) else { return }
        elapsedSeconds = advanced.seconds
        if advanced.crossedPersistBoundary { persist() }
    }

    #if DEBUG
    /// 撮影用（#492）: ソルバーの勝ち筋を途中まで進めて「遊んでいる最中」の盤面を作る。
    ///
    /// シミュレータは自動タップができないため、配ったばかりの初期盤面以外を撮る手段がこれしかない
    /// （ソリティアの `applyPreviewProgressForTesting` と同じ理由）。
    /// - Parameter ratio: 勝ち筋のうち先頭から進める割合（0...1）。
    public func applyPreviewProgressForTesting(ratio: Double = 0.45) {
        guard moves.isEmpty, phase == .playing else { return }
        guard let solution = FreeCellSolver.solve(FreeCellDealer.deal(seed: dealNumber)).solution else { return }
        let count = max(0, min(solution.count, Int(Double(solution.count) * ratio)))
        for move in solution.prefix(count) {
            guard board.apply(move) else { break }
            moves.append(move)
        }
        refreshDerivedState()
    }

    /// 撮影用（#492）: 行き止まりの告知が出た面を直接作る。
    ///
    /// 行き止まりは自然に到達させられない（検証済み配札なので、まともに指している限りまず起きない）。
    /// **合法手がゼロになる盤面を組み立てて** `isDeadEnd` を立てる。
    ///
    /// 組み方: セルに K を4枚（`rank + 1` の札が存在しないのでどこにも置けず、組札は空なので送れない）、
    /// 場札はスートごとに A〜6 / 7〜Q を**昇順**に積んだ 8 列（上に来るのは 6 と Q だけ。
    /// 昇順なので「1つ小さくて色ちがい」の並びにならず、まとめても動かせない）。
    /// A は全部 6 枚組の底に埋まるので組札にも送れない。
    public func applyDeadEndPreviewForTesting() {
        guard phase == .playing else { return }
        var tableau: [[FreeCellCard]] = []
        for suit in PlayingCardSuit.allCases {
            tableau.append((1...6).map { FreeCellCard(suit, $0) })
            tableau.append((7...12).map { FreeCellCard(suit, $0) })
        }
        let cells: [FreeCellCard?] = PlayingCardSuit.allCases.map { FreeCellCard($0, 13) }
        board = FreeCellBoard(tableau: tableau, cells: cells)
        moves = []
        didDismissDeadEndPrompt = false
        refreshDerivedState()
    }

    /// 確認用（#1755）: クリア直前／クリア済みの局を作る（ソリティアの `clearPreviewForTesting` と同じ）。
    ///
    /// **`services` を持たない局として作る**ので、中断データ・記録・解析には一切触れない。
    /// - Parameter remainingMoves: 勝ち筋の残り手数。0 ならクリア済みの盤で返す。
    public static func clearPreviewForTesting(remainingMoves: Int) -> FreeCellModel {
        let model = FreeCellModel(services: nil)
        guard let solution = FreeCellSolver.solve(FreeCellDealer.deal(seed: model.dealNumber)).solution else {
            return model
        }
        for move in solution.dropLast(max(0, remainingMoves)) {
            guard model.board.apply(move) else { break }
            model.moves.append(move)
        }
        model.elapsedSeconds = 205
        model.refreshDerivedState()
        if model.board.isWon { model.finish() }
        return model
    }
    #endif
}
