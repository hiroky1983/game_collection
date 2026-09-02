import Foundation
import Observation
import Core

public enum SolitairePhase: String, Codable, Sendable, Equatable {
    /// 取り進めている最中。
    case playing
    /// 52 枚すべてを組札に積んだ。
    case won
}

/// いま持ち上げている札。
///
/// 場札は「その位置から上を丸ごと」動かすため、列と `faceUp` の添字の組で表す。
public enum SolitaireSelection: Equatable, Sendable {
    case waste
    case tableau(pile: Int, cardIndex: Int)
}

/// 中断スナップショット。
///
/// **配札は種から決定的に再現できる**（`SolitaireDealer.deal`）ので、盤面そのものは保存せず
/// 「種 + 指した手順」だけを持つ。undo も同じ手順の再生で実現しているため、保存と巻き戻しの
/// 経路が 1 本にまとまる。
struct SolitaireSnapshot: Codable {
    let seed: UInt64
    let moves: [SolitaireMove]
    let elapsedSeconds: Int
}

@MainActor
@Observable
public final class SolitaireModel {
    /// 計時だけが進んでいる間に中断データを保存し直す間隔（秒）。麻雀ソリティア（#240）と同じ理由で、
    /// 長考のあとにアプリを終了しても最短タイムが実際より短く記録されないようにする。
    static let persistInterval = 30

    public private(set) var board: SolitaireBoard
    public private(set) var phase: SolitairePhase = .playing
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var selection: SolitaireSelection?
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 拒否されたタップの通し番号（#202）。View はこの値の変化を震え演出のトリガーにする。
    public private(set) var rejectedTapCount: Int = 0

    /// 山札を循環させるほかに進める手が無い状態（#397 の詰み検知）。
    /// **毎描画で数え直すと重い**ので、盤面が動いたときにだけ更新する。
    public private(set) var isDeadEnd: Bool = false

    /// 直前の手で伏せ札から表に出た札の id（#421 のめくり演出）。
    /// View はこの集合に入っている札だけを「裏から返る」演出で描く。
    public private(set) var revealedCardIDs: Set<Int> = []

    /// 直前の手が山めくりだったか（#421。捨て札の 1 枚を裏から返す演出のトリガー）。
    /// 捨て札の一番上は札を場に出したときにも入れ替わるが、そちらは**もともと表**なので返さない。
    public private(set) var lastMoveWasDraw: Bool = false

    private var seed: UInt64
    private var moves: [SolitaireMove] = []
    /// 「ここから組札へ送るだけで勝ち切れる」手順。無ければ nil。`isDeadEnd` と同じ理由で控えておく。
    private var autoFinishPlan: [SolitaireMove]?
    private var timerTask: Task<Void, Never>?
    private let services: GameServices?
    private let gameID = "solitaire"

    /// 手数（記録に出す値）。**山めくりは数えない**。
    /// 山札 1 枚めくりの循環は無制限なので、数えると 1 局で数百手になり、指し回しの巧拙を表さなくなる。
    public var moveCount: Int { moves.filter { $0 != .draw }.count }

    /// この局でジョーカー（中継札）を使ったか。
    /// undo で置いた手を巻き戻せば所持に戻る（#397 吟味2）ため、`moves` から毎回導出する。
    public var jokerUsed: Bool {
        moves.contains { if case .placeJoker = $0 { return true } else { return false } }
    }

    public var canUndo: Bool { phase == .playing && !moves.isEmpty }

    /// 配ったまま 1 手も指していないか（#421。View は配札の演出を出すかの判定に使う）。
    /// 中断から復元した局面では手順が入っているので false になり、再開のたびに配り直して見えない。
    public var isFreshDeal: Bool { moves.isEmpty }

    /// 配り直しの通し番号（#421）。`newGame()` のたびに増える。
    ///
    /// View はこの値を札のビューの identity に混ぜる。**SwiftUI は同一性が保たれている限り
    /// `@State` を作り直さない**ため、これが無いと配り直しで同じ列に同じ札が残った場合に
    /// 「もう配り終わった」状態のビューが再利用され、その札だけ配札の演出が出ない。
    public private(set) var dealSerial: Int = 0

    /// 組札へ送る手（と山めくり）だけで勝ち切れる状態か。終盤の 52 回タップを 1 回に畳む。
    public var canAutoFinish: Bool { phase == .playing && autoFinishPlan != nil }

    /// 計時が動いているか（テスト用）。
    public var isCounting: Bool { timerTask != nil }

    /// - Parameter seed: テスト・撮影用の固定種。nil なら検証済みの種から 1 つ選ぶ。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services

        var startSeed = seed ?? Self.pickSeed()
        var startMoves: [SolitaireMove] = []
        var startElapsed = 0
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = true

        if let snap = services?.snapshots.load(SolitaireSnapshot.self, for: "solitaire") {
            startSeed = snap.seed
            startMoves = snap.moves
            startElapsed = snap.elapsedSeconds
            isFreshStart = false
        }

        self.seed = startSeed
        self.moves = startMoves
        self.elapsedSeconds = startElapsed
        self.board = Self.replay(startMoves, seed: startSeed)
        refreshDerivedState()
        // 取り切った局はスナップショットを消しているので、ここで `won` に復元されることは無い。
        // それでも念のため、勝ち盤面が入ってきたら勝ちとして扱う（記録はしない = 二重計上を避ける）。
        if board.isWon { phase = .won }

        if isFreshStart { services?.gameDidStart(gameID: gameID) }
    }

    private static func pickSeed() -> UInt64 {
        var system = SystemRandomNumberGenerator()
        return SolitaireDealer.randomVerifiedSeed(using: &system)
    }

    /// 種から配り直して手順を再生する。undo も新規配札もこの 1 本を通る。
    private static func replay(_ moves: [SolitaireMove], seed: UInt64) -> SolitaireBoard {
        var board = SolitaireDealer.deal(seed: seed)
        for move in moves { board.apply(move) }
        return board
    }

    // MARK: - タップ

    /// 山札（伏せた束）をタップ。1 枚めくる。空なら捨て札を戻して循環させる。
    public func tapStock() {
        guard phase == .playing else { return }
        selection = nil
        guard board.isLegal(.draw) else { return reject() }
        perform(.draw)
    }

    /// 捨て札の一番上をタップ。持ち上げる / 置く。
    public func tapWaste() {
        guard phase == .playing else { return }
        if selection == .waste { return deselect() }
        guard board.waste.last != nil else { return reject() }
        selection = .waste
        services?.feedback.impact(.rigid)
    }

    /// 組札（スートごとの積み札）をタップ。選んでいる札をそこへ送る。
    public func tapFoundation(_ suit: SolitaireSuit) {
        // 決着後は無音で無視する（`tapStock` / `tapWaste` / `tapPile` と同じ規約）。
        // ここを拒否に倒すと、クリア画面に残った組札に触るたび警告の振動と音が鳴る。
        guard phase == .playing else { return }
        guard let selection else { return reject() }
        guard let card = card(at: selection), card.suit == suit,
              let move = foundationMove(from: selection), board.isLegal(move)
        else { return reject() }
        perform(move)
    }

    /// 場札の列をタップ。
    ///
    /// **持ち上げている札があって、そこへ置けるなら置く**。置けなければ、タップした札を持ち上げ直す。
    /// この優先順位にしておくと「置きたい札の上をタップしたら選択が入れ替わった」が起きない。
    ///
    /// - Parameter cardIndex: タップした `faceUp` の添字。nil なら一番上の札。
    public func tapPile(_ pile: Int, cardIndex: Int? = nil) {
        guard phase == .playing, board.tableau.indices.contains(pile) else { return }

        if let selection, let move = tableauMove(from: selection, to: pile), board.isLegal(move) {
            perform(move)
            return
        }

        let index = cardIndex ?? (board.tableau[pile].faceUp.count - 1)
        guard board.tableau[pile].faceUp.indices.contains(index) else { return reject() }
        if selection == .tableau(pile: pile, cardIndex: index) { return deselect() }
        // 途中で切れている並び（降順・交互色でない）は動かせないので持ち上げさせない。
        guard board.isMovableRun(pile: pile, from: index) else { return reject() }
        selection = .tableau(pile: pile, cardIndex: index)
        services?.feedback.impact(.rigid)
    }

    /// ジョーカー（中継札）を場札の列に置く（#397 ルール1）。
    ///
    /// **盤上の規則だけ**をここに置く。所持の入手経路（初期 1 枚・リワード広告での補充）と
    /// 提示のしかたは #406 の決裁待ちで、この段階では実装しない。所持していなければ
    /// `SolitaireBoard.canPlaceJoker` が false を返すので、この関数は何もしない。
    @discardableResult
    public func placeJoker(onPile pile: Int) -> Bool {
        guard phase == .playing else { return false }
        guard board.isLegal(.placeJoker(pile: pile)) else {
            reject()
            return false
        }
        selection = nil
        perform(.placeJoker(pile: pile))
        return true
    }

    public func deselect() {
        selection = nil
        services?.feedback.impact(.rigid)
    }

    // MARK: - 巻き戻し

    /// 1 手戻す。**無料・無制限**（ジャンル標準・#397）。
    ///
    /// 種からの再生で戻すので、ジョーカーを置いた手を戻せば所持に自然に返る（#397 吟味2）。
    @discardableResult
    public func undo() -> Bool {
        guard canUndo else {
            reject()
            return false
        }
        moves.removeLast()
        board = Self.replay(moves, seed: seed)
        selection = nil
        clearFlips()
        services?.feedback.impact(.medium)
        refreshDerivedState()
        persist()
        return true
    }

    // MARK: - 自動で上がる

    /// 組札へ送る手だけで勝ち切れるなら、まとめて送って決着させる。
    @discardableResult
    public func autoFinish() -> Bool {
        guard phase == .playing, let plan = autoFinishPlan else { return false }
        let before = board
        for move in plan {
            board.apply(move)
            moves.append(move)
        }
        revealedCardIDs = SolitaireBoard.revealedCardIDs(before: before, after: board)
        lastMoveWasDraw = plan.last == .draw
        selection = nil
        refreshDerivedState()
        finish()
        return true
    }

    // MARK: - 新規配札

    /// 新しい配札を配る。
    ///
    /// **1 手でも指した盤面を捨てたときは敗北として記録する**（受け入れ条件の「クリア率」を
    /// 意味のある数字にするため・#397）。ジャンルの慣行どおりで、判定の境目は
    /// 「新規ゲームの確認ダイアログを出すか」と同じ `canUndo` に揃えてある
    /// （＝ユーザーが「今の盤面が失われます」と読んだ操作だけが記録に乗る）。
    ///
    /// 麻雀ソリティア（#240）が「捨てた盤面はどちらの経路でも記録しない」に倒したのとは
    /// 逆だが、あちらは手詰まりを並べ替えで必ず解消でき「負け」に相当する状態が存在しない。
    /// クロンダイクは配札を落とすことが普通に起きるゲームで、クリア率はその前提でこそ意味を持つ。
    public func newGame() {
        if phase == .playing, canUndo {
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        }
        seed = Self.pickSeed()
        moves = []
        board = Self.replay(moves, seed: seed)
        phase = .playing
        selection = nil
        elapsedSeconds = 0
        recordResult = nil
        clearFlips()
        dealSerial += 1
        refreshDerivedState()
        // 画面は開いたままなので計時を入れ直す（View の `.task` は初回表示のときしか走らない）。
        timerTask?.cancel()
        timerTask = nil
        startTimer()
        services?.feedback.impact(.medium)
        services?.snapshots.clear(for: gameID)
        services?.gameDidRestart(gameID: gameID)
    }

    // MARK: - 計時

    /// 中断から復帰したときに計時を再開する（View の `.task` から呼ぶ）。
    public func resumeTimerIfNeeded() {
        guard phase == .playing, timerTask == nil else { return }
        startTimer()
    }

    /// 画面を離れるときに計時を止める（`onDisappear` から呼ぶ）。
    ///
    /// 計時の `Task` は `self` を強く握るので、止めないと**モデルが解放されず**、
    /// 画面を離れたあとも 1 秒ごとに経過秒とスナップショットが進み続ける（#375。数独・
    /// マインスイーパーにも同型があった）。止める前に保存し直すのは、直近の保存から最大
    /// `persistInterval` 秒ぶんの計時が失われるのを防ぐため（#240 と同じ理由）。
    /// 画面に戻れば `resumeTimerIfNeeded()` が計時を再開するので、経過時間は失われない。
    public func pauseTimer() {
        persist()
        timerTask?.cancel()
        timerTask = nil
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 内部

    /// 選択中の札（場札なら持ち上げる並びの下端）。
    func card(at selection: SolitaireSelection) -> SolitaireCard? {
        switch selection {
        case .waste:
            return board.waste.last
        case .tableau(let pile, let index):
            guard board.tableau.indices.contains(pile),
                  board.tableau[pile].faceUp.indices.contains(index) else { return nil }
            return board.tableau[pile].faceUp[index]
        }
    }

    private func foundationMove(from selection: SolitaireSelection) -> SolitaireMove? {
        switch selection {
        case .waste:
            return .wasteToFoundation
        case .tableau(let pile, let index):
            // 組札へ送れるのは一番上の 1 枚だけ。
            guard index == board.tableau[pile].faceUp.count - 1 else { return nil }
            return .tableauToFoundation(pile: pile)
        }
    }

    private func tableauMove(from selection: SolitaireSelection, to pile: Int) -> SolitaireMove? {
        switch selection {
        case .waste:
            return .wasteToTableau(pile: pile)
        case .tableau(let from, let index):
            guard from != pile else { return nil }
            return .tableauToTableau(from: from, cardIndex: index, to: pile)
        }
    }

    private func perform(_ move: SolitaireMove) {
        let before = board
        guard board.apply(move) else { return reject() }
        noteFlips(from: before, move: move)
        moves.append(move)
        selection = nil
        services?.feedback.impact(move == .draw ? .light : .medium)
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

    /// 直前の手で「裏から表へ返った」ものを控える（#421 のめくり演出）。
    ///
    /// 巻き戻し・配り直しでは `clearFlips()` を呼んで空にする。戻した札まで返して見せると
    /// 「新しくめくれた」と読めてしまい、盤面の意味と演出が食い違う。
    private func noteFlips(from before: SolitaireBoard, move: SolitaireMove) {
        revealedCardIDs = SolitaireBoard.revealedCardIDs(before: before, after: board)
        lastMoveWasDraw = move == .draw
    }

    private func clearFlips() {
        revealedCardIDs = []
        lastMoveWasDraw = false
    }

    private func refreshDerivedState() {
        isDeadEnd = phase == .playing && board.isDeadEnd
        autoFinishPlan = Self.autoFinishPlan(from: board)
    }

    /// 組札へ送る手（詰まったら山めくり）だけで勝ち切れる手順。勝ち切れなければ nil。
    ///
    /// 場札を積み替える手は一切使わない。ここで返せるのは「あとは積むだけ」の局面だけで、
    /// 積み替えが要る局面をプレイヤーの代わりに解いてしまわない。
    static func autoFinishPlan(from board: SolitaireBoard) -> [SolitaireMove]? {
        var board = board
        guard !board.isWon else { return nil }
        var plan: [SolitaireMove] = []
        /// 何も送れないまま山をめくった回数。山 + 捨て札を 1 周しても送れなければ諦める。
        var idleDraws = 0

        while !board.isWon {
            var sent = false
            for pile in board.tableau.indices where board.isLegal(.tableauToFoundation(pile: pile)) {
                board.apply(.tableauToFoundation(pile: pile))
                plan.append(.tableauToFoundation(pile: pile))
                sent = true
            }
            if board.isLegal(.wasteToFoundation) {
                board.apply(.wasteToFoundation)
                plan.append(.wasteToFoundation)
                sent = true
            }
            if sent {
                idleDraws = 0
                continue
            }
            let cycle = board.stock.count + board.waste.count
            guard cycle > 0, idleDraws < cycle, board.isLegal(.draw) else { return nil }
            board.apply(.draw)
            plan.append(.draw)
            idleDraws += 1
        }
        return plan
    }

    /// 今の局の成績。タイムと手数は勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    private var currentScore: GameScore {
        GameScore(metric: .shortestTime, seconds: elapsedSeconds, moves: moveCount)
    }

    private func finish() {
        phase = .won
        timerTask?.cancel()
        timerTask = nil
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
        let snapshot = SolitaireSnapshot(seed: seed, moves: moves, elapsedSeconds: elapsedSeconds)
        try? services?.snapshots.save(snapshot, for: gameID)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                tick()
            }
        }
    }

    /// 計時の 1 秒ぶん。タイマーのループから切り出してあるので、テストは実時間を待たずに
    /// 経過秒の進み方と保存の間隔を検証できる（実時間で待つテストはフレークする）。
    func tick() {
        elapsedSeconds += 1
        if elapsedSeconds % Self.persistInterval == 0 { persist() }
    }

    #if DEBUG
    /// 撮影用（#397）: ソルバーの勝ち筋を途中まで進めて「遊んでいる最中」の盤面を作る。
    ///
    /// シミュレータは自動タップができないため、配ったばかりの初期盤面以外を撮る手段がこれしかない
    /// （囲碁の `applyPreviewMidgameForTesting` と同じ理由）。
    /// - Parameter ratio: 勝ち筋のうち先頭から進める割合（0...1）。
    public func applyPreviewProgressForTesting(ratio: Double = 0.45) {
        guard moves.isEmpty, phase == .playing else { return }
        guard let solution = SolitaireSolver.solve(SolitaireDealer.deal(seed: seed)).solution else { return }
        let count = max(0, min(solution.count, Int(Double(solution.count) * ratio)))
        for move in solution.prefix(count) {
            guard board.apply(move) else { break }
            moves.append(move)
        }
        refreshDerivedState()
    }
    #endif
}
