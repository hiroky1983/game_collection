import Foundation
import Observation
import Core

private struct ConcentrationSnapshot: Codable {
    let symbols: [String]
    let isFaceUp: [Bool]
    let isMatched: [Bool]
    let currentPlayer: Int   // 0=human, 1=cpu
    let playerScore: Int
    let cpuScore: Int
    let pairCount: Int
    let cpuLevel: Int
    let mattaUsed: Bool
    /// 不一致のまま中断された2枚（#415）。復元側が「自動ターン交代の途中だった」ことを
    /// 知るための唯一の手がかり。この鍵を持たない旧い中断データもあるため optional で持つ。
    let mismatchedIndices: [Int]?
}

@MainActor
@Observable
public final class ConcentrationModel {
    public private(set) var cards: [ConcentrationCard] = []
    public private(set) var currentPlayer: ConcentrationPlayer = .human
    public private(set) var playerScore: Int = 0
    public private(set) var cpuScore: Int = 0
    public private(set) var isThinking: Bool = false
    public private(set) var pairCount: ConcentrationPairCount = .medium
    public private(set) var cpuLevel: ConcentrationCPULevel = .normal
    public internal(set) var firstFlippedIndex: Int? = nil
    /// ターン交代時のみインクリメントし task(id:) の再起動トリガーとして使う
    public private(set) var turnID: Int = 0
    public private(set) var isGameOver: Bool = false
    public private(set) var lastMatchedIndices: [Int] = []
    public private(set) var mismatchedIndices: [Int] = []
    public private(set) var mattaUsed: Bool = false
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    ///
    /// 神経衰弱は CPU と交互にめくる**対戦もの**で、手数はプレイヤーの技量だけでは決まらない
    /// （CPU が当てた回数に左右される）。そのため記録は手数ではなく勝敗・連勝で持つ。
    public private(set) var recordResult: RecordResult?

    public var winner: ConcentrationPlayer? {
        guard isGameOver else { return nil }
        if playerScore > cpuScore { return .human }
        if cpuScore > playerScore { return .cpu }
        return nil
    }
    public var isDraw: Bool { isGameOver && playerScore == cpuScore }
    /// 決着の種類（評価リクエスト #53 の判定用。リザルト表示時に参照する）。
    public var reviewOutcome: GameOutcome {
        if isDraw { return .draw }
        return winner == .human ? .win : .loss
    }
    public var isHumanTurn: Bool { currentPlayer == .human }
    public var canMatta: Bool { !isGameOver && isHumanTurn && !mismatchedIndices.isEmpty }

    private let services: GameServices?
    private let gameID = "concentration"
    private var ai: ConcentrationAI = ConcentrationAI(accuracy: 0.6)

    /// 人間がミスマッチしてから自動で裏返すまでの待ち時間（#137）。
    /// この間だけ「待った」を出すため、0 にはしない。
    static let defaultAutoClearDelay: UInt64 = 1_200_000_000
    private let autoClearDelay: UInt64

    /// 人間のミスマッチを自動で裏返すタスク（#137）。
    ///
    /// 以前あった自動クリアは View の `onChange(of: mismatchedIndices)` を発火点にしていたため、
    /// CPU のミスマッチにも反応して `doCPUTurn` の `clearMismatch()` と二重に走り、ターンが
    /// 詰まった（`a234262` Bug 1 → `30fc8fb` で削除）。今回は発火点を **人間の `tap` だけ**に
    /// 限定し、CPU 側の経路（`doCPUTurn`）からは一切スケジュールしない。
    private var autoClearTask: Task<Void, Never>?

    /// CPU の AI を作る。難易度が変わるたびに作り直すため関数で持つ
    /// （テストは CPU の手を固定したサブクラスを返してくる）。
    private let aiFactory: (Double) -> ConcentrationAI

    public convenience init(services: GameServices? = nil) {
        self.init(services: services, autoClearDelay: Self.defaultAutoClearDelay)
    }

    /// テストが待ち時間と CPU の手を固定するための入口
    init(services: GameServices?,
         autoClearDelay: UInt64,
         aiFactory: @escaping (Double) -> ConcentrationAI = { ConcentrationAI(accuracy: $0) }) {
        self.services = services
        self.autoClearDelay = autoClearDelay
        self.aiFactory = aiFactory
        // 中断からの復元は「新しいプレイ」ではないので解析の開始は数えない（#158）。
        var isFreshStart = false

        if let snap = services?.snapshots.load(ConcentrationSnapshot.self, for: "concentration") {
            // 壊れたスナップショットは復元できず新しい盤で始まる。それは実質「新しいプレイ」
            // なので数える（数えないと、続く終局が「開始していない」として捨てられる。#212）。
            isFreshStart = !restoreFrom(snap)
        } else {
            setupGame(pairCount: .medium, cpuLevel: .normal)
            isFreshStart = true
        }
        // 再描画で init が何度走っても増えない（`gameDidStart` は冪等）。
        if isFreshStart { services?.gameDidStart(gameID: gameID) }
    }

    // MARK: - Public Actions

    public func tap(index: Int) {
        guard currentPlayer == .human, !isThinking, !isGameOver else { return }
        guard !cards[index].isFaceUp, !cards[index].isMatched, mismatchedIndices.isEmpty else {
            services?.feedback.notify(.warning) // めくり済み・獲得済み、または不一致の表示中
            return
        }
        flipCard(index: index)
        persist()
        // 人間がミスマッチしたら「次へ」を押させず自動で進める（#137）
        if !mismatchedIndices.isEmpty { scheduleAutoClear() }
    }

    public func clearMismatch() {
        guard !mismatchedIndices.isEmpty else { return }
        cancelAutoClear()
        for i in mismatchedIndices { cards[i].isFaceUp = false }
        mismatchedIndices = []
        currentPlayer = currentPlayer.next
        turnID += 1
        persist()
    }

    /// ミスマッチを取り消してプレイヤーのターンを継続する（ターン交代なし）
    public func useMatta() {
        guard canMatta else { return }
        cancelAutoClear()
        for i in mismatchedIndices { cards[i].isFaceUp = false }
        mismatchedIndices = []
        mattaUsed = true
        services?.feedback.impact(.rigid)
        persist()
    }

    /// 「待った」の確認ダイアログを出す前に自動ターン交代を止める（#137）。
    /// 止めないと、ユーザーが確認している最中にターンが CPU へ移り「戻す」が空振りする。
    public func pauseAutoTurn() {
        cancelAutoClear()
    }

    /// 「待った」を使わずに確認ダイアログを閉じたときに自動ターン交代を再開する（#137）
    public func resumeAutoTurn() {
        guard isHumanTurn, !isGameOver, !mismatchedIndices.isEmpty else { return }
        scheduleAutoClear()
    }

    public func newGame(pairCount: ConcentrationPairCount, cpuLevel: ConcentrationCPULevel) {
        setupGame(pairCount: pairCount, cpuLevel: cpuLevel)
        services?.gameDidRestart(gameID: gameID)
    }

    public func performCPUMoveIfNeeded() async {
        guard currentPlayer == .cpu, !isThinking, !isGameOver else { return }
        await doCPUTurn()
    }

    // MARK: - Private

    private func scheduleAutoClear() {
        autoClearTask?.cancel()
        autoClearTask = Task { [weak self, delay = autoClearDelay] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
            // 待っている間に「待った」・新規ゲーム・画面離脱で状況が変わっていたら何もしない
            guard self.isHumanTurn, !self.isGameOver, !self.mismatchedIndices.isEmpty else { return }
            self.clearMismatch()
        }
    }

    private func cancelAutoClear() {
        autoClearTask?.cancel()
        autoClearTask = nil
    }

    /// 予約中の自動ターン交代（#151 のテスト用の待ち合わせ口）。
    ///
    /// テストが実時間（`Task.sleep`）で自動ターン交代を待つと、並列実行で MainActor が混んだときに
    /// サスペンションからの復帰が遅れて落ちる（当番の実測で 1ms の `Task.sleep` の復帰に 3.5 秒）。
    /// 時間ではなくタスクの完了で待ち合わせられるよう、予約中のタスクだけをテストに見せる。
    /// `nil` は「自動ターン交代が予約されていない」ことの表明にも使う。
    var pendingAutoClear: Task<Void, Never>? { autoClearTask }

    private func doCPUTurn() async {
        isThinking = true

        while currentPlayer == .cpu && !isGameOver {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard currentPlayer == .cpu, !isGameOver else { isThinking = false; return }

            let first = ai.chooseCard(cards: cards, firstFlipped: nil)
            flipCard(index: first)

            try? await Task.sleep(nanoseconds: 700_000_000)
            guard currentPlayer == .cpu, !isGameOver else { isThinking = false; return }

            let second = ai.chooseCard(cards: cards, firstFlipped: first)
            flipCard(index: second)
            persist()

            if !mismatchedIndices.isEmpty {
                isThinking = false  // clearMismatch前にfalseにして新タスクが動けるようにする
                try? await Task.sleep(nanoseconds: 900_000_000)
                clearMismatch()     // ← turnID++でtaskが再起動するが isThinking=false なので競合しない
                return
            }

            if isGameOver { isThinking = false; return }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        isThinking = false
    }

    private func setupGame(pairCount: ConcentrationPairCount, cpuLevel: ConcentrationCPULevel) {
        cancelAutoClear()
        self.pairCount = pairCount
        self.cpuLevel = cpuLevel
        ai = aiFactory(cpuLevel.memoryAccuracy)
        playerScore = 0
        cpuScore = 0
        currentPlayer = .human
        firstFlippedIndex = nil
        turnID = 0
        isGameOver = false
        lastMatchedIndices = []
        mismatchedIndices = []
        mattaUsed = false
        recordResult = nil

        let symbols = Array(concentrationSymbols.prefix(pairCount.rawValue))
        let doubled = (symbols + symbols).shuffled()
        cards = doubled.enumerated().map { ConcentrationCard(id: $0.offset, symbol: $0.element) }
        persist()
    }

    /// スナップショットから状態を戻す。
    /// - Returns: 復元できたら `true`。中身が壊れていて新しい盤へフォールバックしたときは `false`
    ///   （呼び出し側はこれを「新しいプレイ」として数える。#212）。
    private func restoreFrom(_ snap: ConcentrationSnapshot) -> Bool {
        guard let setting = Self.validatedSetting(of: snap) else {
            setupGame(pairCount: .medium, cpuLevel: .normal)
            return false
        }

        pairCount = setting.pairCount
        cpuLevel = setting.cpuLevel
        ai = aiFactory(cpuLevel.memoryAccuracy)
        playerScore = snap.playerScore
        cpuScore = snap.cpuScore
        currentPlayer = snap.currentPlayer == 0 ? .human : .cpu
        mattaUsed = snap.mattaUsed
        isThinking = false
        firstFlippedIndex = nil
        turnID = 0
        isGameOver = false
        lastMatchedIndices = []
        mismatchedIndices = []

        cards = snap.symbols.enumerated().map { i, symbol in
            ConcentrationCard(
                id: i,
                symbol: symbol,
                isFaceUp: snap.isFaceUp[i],
                isMatched: snap.isMatched[i]
            )
        }

        // 途中でめくれていたカード（非マッチ・フェイスアップ）を裏返す。
        // firstFlippedIndex は復元しないため、宙吊りカードが残るとゲームが詰まる。
        for i in cards.indices where cards[i].isFaceUp && !cards[i].isMatched {
            cards[i].isFaceUp = false
        }

        // 不一致のまま中断していたら、伏せるだけでなく**手番も進める**（#415）。
        // 手番交代は `clearMismatch()`（= 1.2 秒後の自動ターン交代）だけが行うため、
        // その猶予の間に画面を離れて戻ると「外したら相手番」を操作だけで踏み倒せていた。
        let hadPendingMismatch = Self.validatedMismatch(of: snap) != nil
        if hadPendingMismatch { currentPlayer = currentPlayer.next }

        // CPUターン復元：turnID を非ゼロにすることで task(id:) を確実に起動させる
        if currentPlayer == .cpu { turnID = 1 }
        // 交代後の手番を中断データにも書き戻し、次の復元が同じ判定を繰り返さないようにする
        if hadPendingMismatch { persist() }
        return true
    }

    /// 中断データに残った「不一致で中断した2枚」を検証して取り出す（#415）。
    ///
    /// 壊れた値で手番だけ進むことがないよう、`clearMismatch()` が実際に起きうる形
    /// （相異なる2枚・範囲内・表向き・未獲得・絵柄が不一致）だけを認める。
    /// 呼び出しは `validatedSetting(of:)` を通った後に限る（配列長の一致が前提）。
    private static func validatedMismatch(of snap: ConcentrationSnapshot) -> [Int]? {
        guard let indices = snap.mismatchedIndices,
              indices.count == 2,
              indices[0] != indices[1],
              indices.allSatisfy({ snap.symbols.indices.contains($0) }),
              indices.allSatisfy({ snap.isFaceUp[$0] && !snap.isMatched[$0] }),
              snap.symbols[indices[0]] != snap.symbols[indices[1]] else { return nil }
        return indices
    }

    /// 中断データが「最後まで遊べる盤面」かを検証し、復元に使う設定を取り出す（#218）。
    ///
    /// 配列長の一致だけを見ていると、シンボルが対を成さない並び（例: 全て異なる）も
    /// 「復元成功」として通ってしまい、一致するカードが1組も無い＝終局できない盤面が
    /// 復元される（PR #217 の CodeRabbit 指摘）。
    ///
    /// 難易度も列挙値として妥当かを見る。`?? .medium` のように既定値へ読み替えると、
    /// 枚数と食い違った設定のまま復元が続いてしまうため、読み替えではなく棄却する。
    private static func validatedSetting(
        of snap: ConcentrationSnapshot
    ) -> (pairCount: ConcentrationPairCount, cpuLevel: ConcentrationCPULevel)? {
        let count = snap.symbols.count
        guard snap.isFaceUp.count == count, snap.isMatched.count == count else { return nil }
        guard let pairCount = ConcentrationPairCount(rawValue: snap.pairCount),
              let cpuLevel = ConcentrationCPULevel(rawValue: snap.cpuLevel),
              count == pairCount.rawValue * 2 else { return nil }

        // 各シンボルがちょうど2枚ずつ = すべてのカードが対になる
        let occurrences = snap.symbols.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        guard occurrences.values.allSatisfy({ $0 == 2 }) else { return nil }

        return (pairCount, cpuLevel)
    }

    private func flipCard(index: Int) {
        // めくった手応えは自分がめくったときだけ。CPU の手番では鳴らさない
        // （1ターンで2枚めくるため、鳴らすと触れていない間に連続で振動してしまう）。
        let isHumanMove = currentPlayer == .human
        cards[index].isFaceUp = true
        ai.observe(index: index, symbol: cards[index].symbol)

        if let first = firstFlippedIndex {
            firstFlippedIndex = nil
            if cards[first].symbol == cards[index].symbol {
                cards[first].isMatched = true
                cards[index].isMatched = true
                ai.forget(indices: [first, index])
                lastMatchedIndices = [first, index]
                if currentPlayer == .human { playerScore += 1 } else { cpuScore += 1 }
                checkGameOver()
                if !isGameOver, isHumanMove { services?.feedback.impact(.medium) } // ペア成立
            } else {
                lastMatchedIndices = []
                mismatchedIndices = [first, index]
                if isHumanMove { services?.feedback.impact(.light) }
            }
        } else {
            firstFlippedIndex = index
            lastMatchedIndices = []
            if isHumanMove { services?.feedback.impact(.light) }
        }
    }

    private func checkGameOver() {
        if cards.allSatisfy({ $0.isMatched }) {
            isGameOver = true
            if isDraw {
                services?.feedback.notify(.warning)
            } else {
                services?.feedback.notify(winner == .human ? .success : .error)
            }
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: GameScore(metric: .winLoss))
            services?.snapshots.clear(for: gameID)
        }
    }

    private func persist() {
        guard !isGameOver else { return }
        let snap = ConcentrationSnapshot(
            symbols: cards.map(\.symbol),
            isFaceUp: cards.map(\.isFaceUp),
            isMatched: cards.map(\.isMatched),
            currentPlayer: currentPlayer == .human ? 0 : 1,
            playerScore: playerScore,
            cpuScore: cpuScore,
            pairCount: pairCount.rawValue,
            cpuLevel: cpuLevel.rawValue,
            mattaUsed: mattaUsed,
            mismatchedIndices: mismatchedIndices
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
