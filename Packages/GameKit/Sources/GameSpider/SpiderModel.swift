import Foundation
import Observation
import Core

public enum SpiderPhase: String, Codable, Sendable, Equatable {
    /// 取り進めている最中。
    case playing
    /// 8 組すべてを取り除いた。
    case won
}

/// 「戻す」の回数制（#717）。**ソリティア（#476）・フリーセル（#492）と同じ経済**を使う。
///
/// 値は `Core.RewardedUndoBudget` が持ち、ここはスパイダーの文脈に名前を残すための転送。
public enum SpiderUndoBudget {
    /// 1 局につき無料で戻せる回数。配り直し・新規ゲームでここまで戻る。
    public static let free = RewardedUndoBudget.free
    /// リワード広告 1 本の視聴完了で補充する回数。
    public static let refill = RewardedUndoBudget.refill
}

/// いま持ち上げている札（列と添字の組。その位置から上を丸ごと動かす）。
public struct SpiderSelection: Equatable, Sendable {
    public let pile: Int
    public let cardIndex: Int

    public init(pile: Int, cardIndex: Int) {
        self.pile = pile
        self.cardIndex = cardIndex
    }
}

/// 中断スナップショット。
///
/// **配札は種とスート数から決定的に再現できる**（`SpiderDealer.deal`）ので、盤面そのものは保存せず
/// 「種 + スート数 + 指した手順」だけを持つ。undo も同じ手順の再生で実現しているため、保存と
/// 巻き戻しの経路が 1 本にまとまる（ソリティア #397・フリーセル #492 と同じ契約）。
struct SpiderSnapshot: Codable {
    let seed: UInt64
    /// 焼き込んだルール（`SpiderSuitCount.rawValue`）。1局=1RuleSet の規約 2 で、復元時はこちらを使う。
    let suitCount: Int
    let moves: [SpiderMove]
    let elapsedSeconds: Int
    /// 「戻す」の残り回数。手順から導出できないのでここだけは別に持つ。
    /// **省略可**。欠けた中断データは無料枠が丸ごと残っている扱いにする。
    let undosRemaining: Int?
}

@MainActor
@Observable
public final class SpiderModel {
    /// 計時だけが進んでいる間に中断データを保存し直す間隔（秒）。フリーセルと同じ理由（#240）。
    static let persistInterval = 30

    public private(set) var board: SpiderBoard
    public private(set) var phase: SpiderPhase = .playing
    public private(set) var elapsedSeconds: Int = 0
    public private(set) var selection: SpiderSelection?
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 拒否されたタップの通し番号（#202）。View はこの値の変化を震え演出のトリガーにする。
    public private(set) var rejectedTapCount: Int = 0
    /// 「空いた列があって配れない」で拒否された回数。View はこの変化で案内を出す。
    public private(set) var dealBlockedCount: Int = 0

    /// 指せる手が 1 つも無い状態（配ることもできない）。盤面が動いたときにだけ更新する。
    public private(set) var isDeadEnd: Bool = false

    /// 行き止まりの告知を「盤面を見る」で閉じたか。配り直すまで残る（フリーセル #492 と同じ）。
    public private(set) var didDismissDeadEndPrompt: Bool = false

    /// 「戻す」の残り回数（#717 = #476 と同じ経済）。
    public private(set) var undosRemaining: Int

    /// 配札番号（= 種）。
    public private(set) var dealNumber: UInt64

    /// この局に焼き込んだルール（#717）。**局の途中では変わらない**（1 局 = 1 RuleSet）。
    public private(set) var rules: SpiderRuleSet

    /// 直近の「配る」で場に載った札の id。View は配りの演出をこの札にだけ出す。
    /// **次の 1 手で空にする**（移動した札が配り元から飛んでくる演出になるのを防ぐ）。
    public private(set) var lastDealtCardIDs: Set<Int> = []

    private var moves: [SpiderMove] = []
    private var timerTask: Task<Void, Never>?
    private let services: GameServices?
    /// 同じモジュールの View も参照する（`reward_ad` の送信に要る・#500）。
    let gameID = "spider"

    /// 手数（記録に出す値）。「配る」も 1 手に数える。
    public var moveCount: Int { moves.count }

    /// 戻せる手があるか。**残り回数は見ない**（意味は `FreeCellModel.canUndo` と同じ）。
    public var canUndo: Bool { phase == .playing && !moves.isEmpty }

    public var hasUndoCredit: Bool { undosRemaining > 0 }

    public var needsUndoRefill: Bool { canUndo && !hasUndoCredit }

    public var showsDeadEndPrompt: Bool {
        phase == .playing && isDeadEnd && !didDismissDeadEndPrompt
    }

    /// 配ったまま 1 手も指していないか（View は配札の演出を出すかの判定に使う）。
    public var isFreshDeal: Bool { moves.isEmpty }

    /// 配り直しの通し番号。`newGame()` のたびに増える（フリーセルと同じ理由・#421）。
    public private(set) var dealSerial: Int = 0

    /// 計時が動いているか（テスト用）。
    public var isCounting: Bool { timerTask != nil }

    /// - Parameters:
    ///   - seed: テスト・撮影用の固定種。nil なら検証済みの種から 1 つ選ぶ。
    ///   - rules: 開始時に焼き込むルール。中断データがあればそちらが優先される。
    public init(services: GameServices? = nil, seed: UInt64? = nil, rules: SpiderRuleSet = .standard) {
        self.services = services

        var startRules = rules
        var startSeed = seed ?? Self.pickSeed(for: rules.suitCount)
        var startMoves: [SpiderMove] = []
        var startElapsed = 0
        var startUndos = SpiderUndoBudget.free
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = true

        if let snap = services?.snapshots.load(SpiderSnapshot.self, for: "spider"),
           let suitCount = SpiderSuitCount(rawValue: snap.suitCount) {
            startRules = SpiderRuleSet(suitCount: suitCount)
            startSeed = snap.seed
            startMoves = snap.moves
            startElapsed = max(0, snap.elapsedSeconds)
            startUndos = max(0, snap.undosRemaining ?? SpiderUndoBudget.free)
            isFreshStart = false
        }

        self.rules = startRules
        self.dealNumber = startSeed
        self.elapsedSeconds = startElapsed
        self.undosRemaining = startUndos
        // 壊れた（または食い違った）中断データは、**適用できたところで打ち切る**（#406 申し送り2）。
        let restored = Self.replay(startMoves, seed: startSeed, rules: startRules)
        self.moves = Array(startMoves.prefix(restored.applied))
        self.board = restored.board
        refreshDerivedState()
        if board.isWon { phase = .won }

        if isFreshStart {
            services?.gameDidStart(gameID: gameID, level: rules.suitCount.analyticsLevel)
        }
    }

    private static func pickSeed(for suits: SpiderSuitCount) -> UInt64 {
        var system = SystemRandomNumberGenerator()
        return SpiderDealer.randomVerifiedSeed(for: suits, using: &system)
    }

    /// 種から配り直して手順を再生する。undo も新規配札もこの 1 本を通る。
    private static func replay(
        _ moves: [SpiderMove], seed: UInt64, rules: SpiderRuleSet
    ) -> (board: SpiderBoard, applied: Int) {
        var board = SpiderDealer.deal(seed: seed, suits: rules.suitCount)
        for (index, move) in moves.enumerated() {
            guard board.apply(move) else { return (board, index) }
        }
        return (board, moves.count)
    }

    // MARK: - タップ

    /// 場札の列をタップ。持ち上げる / 置く。
    ///
    /// - Parameter cardIndex: 列の中の添字。省略時は一番上の 1 枚（列全体の受け皿としての扱い）。
    public func tapPile(_ pile: Int, cardIndex: Int? = nil) {
        guard phase == .playing, board.piles.indices.contains(pile) else { return }

        if let selection {
            if selection.pile == pile {
                // 同じ列の同じ札をもう一度 → 選択解除。別の札 → 選び直し。
                if cardIndex == nil || cardIndex == selection.cardIndex { return deselect() }
            } else {
                let move = SpiderMove.move(from: selection.pile, cardIndex: selection.cardIndex, to: pile)
                return board.isLegal(move) ? perform(move) : reject()
            }
        }

        guard !board.piles[pile].isEmpty else { return reject() }
        let index = cardIndex ?? (board.piles[pile].cards.count - 1)
        guard board.isMovableRun(pile: pile, from: index) else { return reject() }
        selection = SpiderSelection(pile: pile, cardIndex: index)
        services?.feedback.impact(.rigid)
    }

    /// 山札をタップ。各列へ 1 枚ずつ配る。空いた列があるときは配れない（案内を出す）。
    public func tapStock() {
        guard phase == .playing else { return }
        selection = nil
        if board.canDeal { return perform(.deal) }
        if board.isDealBlockedByEmptyPile { dealBlockedCount += 1 }
        reject()
    }

    public func deselect() {
        selection = nil
        services?.feedback.impact(.rigid)
    }

    /// 行き止まりの告知を閉じる。配り直すまで再表示しない。
    public func dismissDeadEndPrompt() {
        if isDeadEnd { didDismissDeadEndPrompt = true }
    }

    // MARK: - 巻き戻し

    /// 1 手戻す。**1 局につき無料 `SpiderUndoBudget.free` 回まで**（使い切ったら `grantUndos()` で補充）。
    @discardableResult
    public func undo() -> Bool {
        guard canUndo, hasUndoCredit else {
            reject()
            return false
        }
        undosRemaining -= 1
        moves.removeLast()
        board = Self.replay(moves, seed: dealNumber, rules: rules).board
        selection = nil
        lastDealtCardIDs = []
        services?.feedback.impact(.medium)
        refreshDerivedState()
        persist()
        return true
    }

    /// リワード広告の**視聴完了後**に「戻す」を補充する（契約は `FreeCellModel.grantUndos` と同じ）。
    @discardableResult
    public func grantUndos(forDeal serial: Int) -> Bool {
        guard phase == .playing, serial == dealSerial else { return false }
        undosRemaining += SpiderUndoBudget.refill
        services?.feedback.notify(.success)
        persist()
        return true
    }

    // MARK: - 新規配札

    /// 新しい配札を配る。
    ///
    /// **1 手でも指した盤面を捨てたときは敗北として記録する**（判定の境目は `canUndo`。#397 と同じ）。
    /// - Parameter rules: 次の局に焼き込むルール。省略すると**今の局と同じルール**で配り直す。
    public func newGame(rules: SpiderRuleSet? = nil) {
        if phase == .playing, canUndo {
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
        }
        self.rules = rules ?? self.rules
        dealNumber = Self.pickSeed(for: self.rules.suitCount)
        moves = []
        undosRemaining = SpiderUndoBudget.free
        board = Self.replay(moves, seed: dealNumber, rules: self.rules).board
        phase = .playing
        selection = nil
        lastDealtCardIDs = []
        didDismissDeadEndPrompt = false
        elapsedSeconds = 0
        recordResult = nil
        dealSerial += 1
        refreshDerivedState()
        timerTask?.cancel()
        timerTask = nil
        startTimer()
        services?.feedback.impact(.medium)
        services?.snapshots.clear(for: gameID)
        services?.gameDidRestart(gameID: gameID, level: self.rules.suitCount.analyticsLevel)
    }

    // MARK: - 計時

    public func resumeTimerIfNeeded() {
        guard phase == .playing, timerTask == nil else { return }
        startTimer()
    }

    /// 画面を離れるときに計時を止める（`onDisappear` から呼ぶ。理由は `FreeCellModel.pauseTimer`）。
    public func pauseTimer() {
        persist()
        timerTask?.cancel()
        timerTask = nil
    }

    public func clearSnapshot() { services?.snapshots.clear(for: gameID) }

    // MARK: - 内部

    private func perform(_ move: SpiderMove) {
        let completedBefore = board.completed.count
        guard board.apply(move) else { return reject() }
        moves.append(move)
        if case .deal = move {
            lastDealtCardIDs = Set(board.piles.compactMap { $0.top?.id })
        } else {
            lastDealtCardIDs = []
        }
        // 盤が動いた = 捨てたら途中離脱として数える盤面（#500）。
        services?.gameDidProgress(gameID: gameID)
        selection = nil
        services?.feedback.impact(.medium)
        refreshDerivedState()

        if board.isWon {
            finish()
        } else {
            if board.completed.count > completedBefore {
                services?.feedback.notify(.success)
            } else if isDeadEnd {
                services?.feedback.notify(.warning)
            }
            persist()
        }
    }

    private func reject() {
        rejectedTapCount += 1
        services?.feedback.notify(.warning)
    }

    private func refreshDerivedState() {
        isDeadEnd = phase == .playing && board.isDeadEnd
    }

    /// テスト専用: 盤面だけを差し替えて派生状態を組み直す（`FreeCellModel` と同じ口）。
    func replaceBoardForTesting(_ board: SpiderBoard) {
        self.board = board
        refreshDerivedState()
    }

    /// 今の局の成績。タイムと手数は勝ったときだけ自己ベストに取り込まれる（`PlayRecord.applying`）。
    ///
    /// スート数ごとに `variant` を分けて自己ベストを別枠にする（1 スートと 4 スートではタイムの
    /// 水準がまったく違う）。順位表もスート数ごとに別の表へ送る（`GameCenterLeaderboard`）。
    /// 盤面を有利にする救済アイテムは持たないので `isLeaderboardEligible` は常に true。
    private var currentScore: GameScore {
        GameScore(
            metric: .shortestTime,
            seconds: elapsedSeconds,
            moves: moveCount,
            variant: rules.suitCount.recordVariant,
            variantLabel: rules.suitCount.recordLabel
        )
    }

    private func finish() {
        phase = .won
        timerTask?.cancel()
        timerTask = nil
        selection = nil
        isDeadEnd = false
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
        let snapshot = SpiderSnapshot(
            seed: dealNumber,
            suitCount: rules.suitCount.rawValue,
            moves: moves,
            elapsedSeconds: elapsedSeconds,
            undosRemaining: undosRemaining
        )
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

    /// 計時の 1 秒ぶん（テストは実時間を待たずに検証できる・#375）。
    func tick() {
        elapsedSeconds += 1
        if elapsedSeconds % Self.persistInterval == 0 { persist() }
    }

    #if DEBUG
    /// 撮影用（#717）: ソルバーの勝ち筋を途中まで進めて「遊んでいる最中」の盤面を作る。
    ///
    /// 4 スートはソルバーが重い（-O で十数秒・Debug ではその数倍）ので何もしない。
    /// - Parameter ratio: 勝ち筋のうち先頭から進める割合（0...1）。
    public func applyPreviewProgressForTesting(ratio: Double = 0.45) {
        guard moves.isEmpty, phase == .playing, rules.suitCount != .four else { return }
        let deal = SpiderDealer.deal(seed: dealNumber, suits: rules.suitCount)
        guard let solution = SpiderSolver.solve(
            deal, maxStates: SpiderSolver.defaultMaxStates(for: rules.suitCount)
        ).solution else { return }
        let count = max(0, min(solution.count, Int(Double(solution.count) * ratio)))
        for move in solution.prefix(count) {
            guard board.apply(move) else { break }
            moves.append(move)
        }
        lastDealtCardIDs = []
        refreshDerivedState()
    }

    /// 撮影用（#717）: 行き止まりの告知が出た面を直接作る。
    ///
    /// 山札を空にし、10 列の一番上を K（8 列）と A（2 列）にする。K の上に置ける札は無く、
    /// A を置ける 2 も上に出ていない。空いた列も無いので合法手がゼロになる。
    /// K は 8 枚しか無いので 10 列すべてを K にはできない（同じ札を 2 列に置くと id が重複して
    /// 描画が壊れる）。
    public func applyDeadEndPreviewForTesting() {
        guard phase == .playing else { return }
        let deck = SpiderCard.makeDeck(suits: rules.suitCount)
        let tops = deck.filter { $0.rank == 13 } + deck.filter { $0.rank == 1 }.prefix(2)
        let others = deck.filter { $0.rank != 13 && $0.rank != 1 }
        var piles: [SpiderPile] = []
        for pile in 0..<SpiderBoard.pileCount {
            let hidden = Array(others[(pile * 3)..<(pile * 3 + 3)])
            piles.append(SpiderPile(cards: hidden + [tops[pile]], faceDownCount: 3))
        }
        board = SpiderBoard(piles: piles, stock: [])
        moves = []
        lastDealtCardIDs = []
        didDismissDeadEndPrompt = false
        refreshDerivedState()
    }
    #endif
}
