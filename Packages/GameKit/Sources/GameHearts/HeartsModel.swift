import Foundation
import Observation
import Core
import CoreEngine

// MARK: - Phase

public enum HeartsPhase: String, Equatable, Sendable, Codable {
    /// 開始前。
    case idle
    /// 配った直後。左隣へ渡す 3 枚を選ぶ。
    case passing
    /// 札を出し合っている。
    case playing
    /// 1 手（13 巡）が終わり、この手の点を見せている。
    case handResult
    /// 誰かが目標点に届いて対局が決着した。
    case result
}

// MARK: - Snapshot

struct HeartsSnapshot: Codable {
    let phase: HeartsPhase
    let hands: [[HeartsCard]]
    let currentTrick: [HeartsPlay]
    let currentPlayer: Int
    let heartsBroken: Bool
    let trickNumber: Int
    let takenPoints: [Int]
    let totals: [Int]
    let handNumber: Int
    let playedIDs: [Int]
    let lastTrick: [HeartsPlay]
    let lastTrickWinner: Int?
    let receivedIDs: [Int]
    let aiLevel: Int
    let turnSerial: Int
    /// 渡す場面のヒントを使った回数（#3003）。鍵を持たない古い中断データは未使用として読む。
    let hintsUsed: Int?
}

// MARK: - Model

/// ハーツ（CPU 3 人との対戦・Issue #1884）。プレイヤーは常に番号 0（下）で、1 = 左・2 = 上・3 = 右。
/// 札は 0 → 1 → 2 → 3 の順（時計回り）に出し、渡す相手の「左隣」は番号 1 の側。
///
/// 出せる札・巡の決着は `HeartsRules`、CPU の選択は `HeartsCPU`（どちらも純粋関数）に寄せ、
/// この型は**進行・永続化・演出**だけを持つ。CPU の手番の回し方は大富豪・いろリレーと同じ定石
/// （`AITurnGuarded`・#531）で、画面を離れたあとに CPU の手が確定しない（#1621）。
@MainActor
@Observable
public final class HeartsModel: AITurnGuarded {
    /// 人間プレイヤーの番号。
    public static let humanIndex = HeartsRules.humanIndex
    public static let playerCount = HeartsRules.playerCount
    /// `GameModule.id` と同じ値。`ModuleTests` が一致を確かめる。
    public static let gameID = "hearts"

    public private(set) var phase: HeartsPhase = .idle
    public private(set) var hands: [[HeartsCard]] = Array(repeating: [], count: playerCount)
    /// いまの巡に出た札（先頭が出だし）。4 枚そろったら少し見せてから片付ける。
    public private(set) var currentTrick: [HeartsPlay] = []
    /// 次に出す人。巡がそろっている間は、片付けたあとに取った人へ移る。
    public private(set) var currentPlayer = humanIndex
    /// ハートが場に出たか（出るまでハートを先頭に出せない）。
    public private(set) var heartsBroken = false
    /// この手で片付いた巡の数（0〜13）。
    public private(set) var trickNumber = 0
    /// この手で各人が取った点。
    public private(set) var takenPoints: [Int] = Array(repeating: 0, count: playerCount)
    /// 対局の合計点（手の終わりに足す）。
    public private(set) var totals: [Int] = Array(repeating: 0, count: playerCount)
    /// 何手目か（1 始まり）。
    public private(set) var handNumber = 0
    /// これまでに片付いた札の ID（CPU の記憶）。
    public private(set) var playedIDs: Set<Int> = []
    /// 直前に片付いた巡（画面の「前の巡」と読み上げ用）。
    public private(set) var lastTrick: [HeartsPlay] = []
    public private(set) var lastTrickWinner: Int?
    /// 右隣から受け取った札（手札で印を付ける）。次の手を配るまで残す。
    public private(set) var receivedIDs: Set<Int> = []
    /// 渡す札として選んでいる ID（最大 3 枚）。
    public private(set) var passSelection: Set<Int> = []
    /// 出す札として選んでいる ID。
    public private(set) var selectedID: Int?
    /// CPU の強さ（`CPUStrength.rawValue`）。
    public private(set) var aiLevel = CPUStrength.standard.rawValue
    /// 決着後の最終順位（1 位から順のプレイヤー番号）。
    public private(set) var ranking: [Int] = []
    /// 手番の通し番号。番が動くたびに進む。
    public private(set) var turnSerial = 0
    /// 直近の決着で確定した自己ベスト（#115）。リザルトに 1 行出す。
    public private(set) var recordResult: RecordResult?
    /// 渡す場面のヒントの残り（#3003）。回数・広告での補充・順位表の扱いは Core の `BoardHintBudget`
    /// （将棋・チェス・15パズルなどと共通）。1 対局で数え、`startMatch` で戻る。
    public private(set) var passHints = BoardHintBudget()
    /// ヒントが示した「渡すとよい 3 枚」の ID。この手の渡す場面だけ持ち、保存しない。
    public private(set) var passHintIDs: Set<Int> = []
    /// 対局の最初の手を配ったまま、まだ 1 枚も渡していない局か（#240）。保存しない。
    private var isUntouchedDeal = false

    private let services: GameServices?
    let gameID = HeartsModel.gameID
    private let cpuDelay: Duration
    /// 4 枚そろった巡を見せておく時間。
    private let trickPause: Duration
    private var rng: SplitMix64
    /// ヒント表示のオン / オフ（#190）。
    private let hints: FeedbackPreference
    /// CPU の連続手番が二重に走らないようにする門番。テストが同期ゲートに使うので `internal`。
    var isRunningCPUTurns = false

    public init(
        services: GameServices? = nil,
        cpuDelay: Duration = .milliseconds(550),
        trickPause: Duration = .milliseconds(900),
        seed: UInt64? = nil,
        hints: FeedbackPreference = .hints
    ) {
        self.services = services
        self.cpuDelay = cpuDelay
        self.trickPause = trickPause
        self.hints = hints
        rng = SplitMix64(seed: seed ?? UInt64.random(in: 0...UInt64.max))
        // 手書き・壊れた中断データで落ちないよう、配列の長さと番号の範囲を見てから戻す。
        if let snap = services?.snapshots.load(HeartsSnapshot.self, for: gameID), Self.isConsistent(snap) {
            phase           = snap.phase
            hands           = snap.hands
            currentTrick    = snap.currentTrick
            currentPlayer   = snap.currentPlayer
            heartsBroken    = snap.heartsBroken
            trickNumber     = snap.trickNumber
            takenPoints     = snap.takenPoints
            totals          = snap.totals
            handNumber      = snap.handNumber
            playedIDs       = Set(snap.playedIDs)
            lastTrick       = snap.lastTrick
            lastTrickWinner = snap.lastTrickWinner
            receivedIDs     = Set(snap.receivedIDs)
            aiLevel         = snap.aiLevel
            turnSerial      = snap.turnSerial
            passHints       = BoardHintBudget(used: snap.hintsUsed ?? 0)
        }
    }

    /// 中断データとして戻してよい形か。札が 52 枚ちょうど（手札・場・片付いた札で重複なし）であることまで見る。
    static func isConsistent(_ snap: HeartsSnapshot) -> Bool {
        guard [HeartsPhase.passing, .playing, .handResult].contains(snap.phase),
              snap.hands.count == playerCount, snap.takenPoints.count == playerCount, snap.totals.count == playerCount,
              (0..<playerCount).contains(snap.currentPlayer), (0...HeartsRules.handSize).contains(snap.trickNumber),
              snap.currentTrick.count <= playerCount else { return false }
        let ids = snap.hands.flatMap { $0.map(\.id) } + snap.currentTrick.map(\.card.id) + snap.playedIDs
        let valid = HeartsCard.makeDeck().map(\.id)
        return ids.count == 52 && Set(ids) == Set(valid)
    }

    // MARK: - 公開状態

    public var playerHand: [HeartsCard] { hands[Self.humanIndex] }
    public var strength: CPUStrength { CPUStrength.strength(for: aiLevel) }

    /// 4 枚そろって、片付けを待っている巡か。
    public var isTrickComplete: Bool { currentTrick.count == Self.playerCount }

    /// 人間が札を出す番か。
    public var isPlayerTurn: Bool {
        phase == .playing && !isTrickComplete && currentPlayer == Self.humanIndex
    }

    /// 人間がいま出せる札の ID。
    public var playableCardIDs: Set<Int> {
        guard isPlayerTurn else { return [] }
        return Set(HeartsRules.legalPlays(
            hand: playerHand, trick: currentTrick, heartsBroken: heartsBroken, isFirstTrick: trickNumber == 0
        ).map(\.id))
    }

    /// 選択中の札を出せるか。
    public var canPlaySelection: Bool {
        guard let selectedID else { return false }
        return playableCardIDs.contains(selectedID)
    }

    /// 渡す 3 枚が選べたか。
    public var canConfirmPass: Bool { phase == .passing && passSelection.count == HeartsRules.passCount }

    /// 手札 1 枚のヒント（#190）。設定でオフ / 相手の番 / 全部出せる ときは `.none`。
    public func hint(for card: HeartsCard, playable: Set<Int>) -> HeartsCardHint {
        // 渡す場面のヒントは押して求めたものなので、表示設定（オフ）には従わない。
        if phase == .passing { return passHintIDs.contains(card.id) ? .recommendedPass : .none }
        guard hints.isEnabled, isPlayerTurn, playable.count < playerHand.count else { return .none }
        return playable.contains(card.id) ? .playable : .unplayable
    }

    /// 渡す場面のヒントを押せるか。渡す場面で、残りがあり、この手でまだ示していないとき（同じ手札なら同じ答えなので 2 回は使わせない）。
    public var canUseHint: Bool { phase == .passing && !passHints.isExhausted && passHintIDs.isEmpty }

    /// 無料ぶんを使い切っていて、次の 1 回に広告が要るか。
    public var needsAdForHint: Bool { !passHints.hasFreeRemaining && !passHints.isExhausted }

    /// 渡す場面のヒントを無料で 1 回使う。使い切っていれば何もしない（広告の 1 回は `grantAdHint(forTurn:)`）。
    public func requestHint() {
        guard canUseHint, !needsAdForHint, passHints.consume() else { return }
        showPassHint()
    }

    /// 広告を最後まで見たあとの 1 回。`turn` は広告を出す前に控えた `turnSerial`（手や対局が入れ替わっていたら適用せず false）。
    @discardableResult
    public func grantAdHint(forTurn turn: Int) -> Bool {
        guard turn == turnSerial, canUseHint, needsAdForHint, passHints.consumeAd() else { return false }
        showPassHint()
        return true
    }

    private func showPassHint() {
        passHintIDs = Set(HeartsCPU.recommendedPass(hand: playerHand).map(\.id))
        services?.gameDidUseHint(gameID: gameID)
        services?.feedback.impact(.light)
        persist()
    }

    /// 人間の最終順位（0 始まり。同点は同じ順位）。決着していなければ nil。
    public var playerPlace: Int? {
        phase == .result ? HeartsRules.place(of: Self.humanIndex, totals: totals) : nil
    }

    /// 評価リクエスト（#53）・記録の判定用。合計がいちばん少なければ（同点を含む）勝ち。
    public var reviewOutcome: GameOutcome { playerPlace == 0 ? .win : .loss }

    public func playerName(_ index: Int) -> String { HeartsAccessibility.playerName(index) }

    /// いまの巡で `player` が出した札。
    public func trickCard(of player: Int) -> HeartsCard? {
        currentTrick.first { $0.player == player }?.card
    }

    /// いまの巡でいちばん強い札を出している人（そろう前は暫定）。
    public var trickLeader: Int? { HeartsRules.trickWinner(currentTrick) }

    // MARK: - 対局の開始

    /// 新しい対局を始める（合計点を 0 に戻して 1 手目を配る）。
    public func startMatch(aiLevel: Int? = nil) {
        if let aiLevel { self.aiLevel = aiLevel }
        totals = Array(repeating: 0, count: Self.playerCount)
        handNumber = 0
        ranking = []
        recordResult = nil
        passHints.reset()
        dealHand()
        isUntouchedDeal = true
        // 配ったばかりの局は保存しない。前の対局の中断データも残さない。
        services?.snapshots.clear(for: gameID)
        services?.feedback.impact(.card(.shuffle))   // 札が切られて配られた
        // 1 対局 = 1 プレイ。中断からの復元は init が状態を戻すだけでここを通らないので数えない（#158）。
        services?.gameDidRestart(gameID: gameID, level: CPUStrength.analyticsLevel(forLevel: self.aiLevel))
    }

    /// 1 手を配る。
    private func dealHand() {
        var deck = HeartsCard.makeDeck()
        deck.shuffle(using: &rng)
        hands = (0..<Self.playerCount).map { player in
            let start = player * HeartsRules.handSize
            return deck[start..<(start + HeartsRules.handSize)].sorted { $0.sortKey < $1.sortKey }
        }
        handNumber += 1
        currentTrick = []
        heartsBroken = false
        trickNumber = 0
        takenPoints = Array(repeating: 0, count: Self.playerCount)
        playedIDs = []
        lastTrick = []
        lastTrickWinner = nil
        receivedIDs = []
        passSelection = []
        passHintIDs = []
        selectedID = nil
        currentPlayer = Self.humanIndex
        turnSerial += 1
        phase = .passing
    }

    // MARK: - 渡す

    /// 渡す札の選択を切り替える。3 枚選んでいるときは新しく足さない。
    public func togglePass(_ card: HeartsCard) {
        guard phase == .passing, playerHand.contains(card) else { return }
        if passSelection.contains(card.id) {
            passSelection.remove(card.id)
        } else if passSelection.count < HeartsRules.passCount {
            passSelection.insert(card.id)
        } else {
            services?.feedback.notify(.warning)
            return
        }
        services?.feedback.impact(.rigid)
    }

    /// 選んだ 3 枚を左隣へ渡し、右隣から 3 枚受け取って 1 巡目を始める。CPU の 3 人も同時に渡す。
    public func confirmPass() {
        guard canConfirmPass else {
            services?.feedback.notify(.warning)
            return
        }
        var passes: [[HeartsCard]] = Array(repeating: [], count: Self.playerCount)
        passes[Self.humanIndex] = playerHand.filter { passSelection.contains($0.id) }
        let cpu = HeartsCPU(strength: strength)
        for player in 1..<Self.playerCount {
            passes[player] = cpu.choosePass(hand: hands[player], using: &rng)
        }
        for player in 0..<Self.playerCount {
            hands[player].removeAll { passes[player].contains($0) }
        }
        for player in 0..<Self.playerCount {
            hands[HeartsRules.passTarget(from: player)] += passes[player]
        }
        hands = hands.map { $0.sorted { $0.sortKey < $1.sortKey } }
        receivedIDs = Set(passes[HeartsRules.passSource(to: Self.humanIndex)].map(\.id))
        passSelection = []
        passHintIDs = []
        isUntouchedDeal = false
        currentPlayer = HeartsRules.startingPlayer(hands: hands)
        turnSerial += 1
        phase = .playing
        services?.feedback.impact(.card(.deal))   // 札を渡し合った
        // 札を渡した = 盤面が動いた。配っただけの局面を捨てても離脱には数えない境目（#500）。
        services?.gameDidProgress(gameID: gameID)
        persist()
    }

    // MARK: - 出す

    /// 手札をタップ。同じ札をもう一度タップすると選択を外す。
    public func toggleSelection(_ card: HeartsCard) {
        guard isPlayerTurn else { return }
        selectedID = selectedID == card.id ? nil : card.id
        services?.feedback.impact(.rigid)
    }

    /// 選択中の札を出す。
    public func playSelected() {
        guard isPlayerTurn, let id = selectedID, canPlaySelection,
              let card = playerHand.first(where: { $0.id == id }) else {
            services?.feedback.notify(.warning)
            return
        }
        selectedID = nil
        services?.feedback.impact(.card(.place))
        play(card, by: Self.humanIndex)
        persist()
    }

    private func play(_ card: HeartsCard, by player: Int) {
        hands[player].removeAll { $0 == card }
        currentTrick.append(HeartsPlay(player: player, card: card))
        if card.suit == .heart { heartsBroken = true }
        if !isTrickComplete { currentPlayer = (player + 1) % Self.playerCount }
        turnSerial += 1
        services?.gameDidProgress(gameID: gameID)
    }

    /// そろった巡を片付ける。取った人に点を足し、次の巡はその人から。13 巡そろえば手を締める。
    private func collectTrick() {
        guard isTrickComplete, let winner = HeartsRules.trickWinner(currentTrick) else { return }
        let cards = currentTrick.map(\.card)
        takenPoints[winner] += HeartsRules.points(cards)
        playedIDs.formUnion(cards.map(\.id))
        lastTrick = currentTrick
        lastTrickWinner = winner
        currentTrick = []
        trickNumber += 1
        currentPlayer = winner
        turnSerial += 1
        if winner == Self.humanIndex, HeartsRules.points(cards) > 0 {
            services?.feedback.notify(.warning)   // 点を取ってしまった
        }
        if trickNumber == HeartsRules.handSize { finishHand() }
    }

    private func finishHand() {
        for player in 0..<Self.playerCount { totals[player] += takenPoints[player] }
        if HeartsRules.isMatchOver(totals: totals) {
            concludeMatch()
        } else {
            phase = .handResult
        }
    }

    /// この手の点を見たあと、次の手を配る。
    public func nextHand() {
        guard phase == .handResult else { return }
        dealHand()
        services?.feedback.impact(.card(.shuffle))
        persist()
    }

    /// 決着で記録に渡す点。**「ふつう」は区分なし**（それまでの記録をそのまま引き継ぐ）で、
    /// それ以外の強さは強さ別の区分に分ける（大富豪と同じ作法・#2604、#2716）。
    var recordScore: GameScore {
        let strength = CPUStrength.strength(for: aiLevel)
        // ヒントを 1 回でも使った対局は順位表へ送らない（`BoardHintBudget.winLossScore` と同じ扱い）。
        guard strength != .standard else { return passHints.winLossScore }
        let variant = strength.recordVariantKey
        return GameScore(
            metric: .winLoss, variant: variant,
            variantLabel: RecordVariantLabels.stored(gameID: gameID, variant: variant),
            isLeaderboardEligible: !passHints.wasUsed
        )
    }

    private func concludeMatch() {
        ranking = HeartsRules.ranking(totals: totals)
        selectedID = nil
        phase = .result
        switch reviewOutcome {
        case .win:  services?.feedback.notify(.success)
        case .loss: services?.feedback.notify(.error)
        case .draw: services?.feedback.notify(.warning)
        }
        recordResult = services?.gameDidFinish(
            gameID: gameID, outcome: reviewOutcome, score: recordScore,
            // 「入門」「かんたん」に勝っても評価を頼むほどの手応えとは言えない（#1471）。
            isReviewHighlight: CPUStrength.isReviewWorthy(level: aiLevel)
        )
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - CPU

    /// CPU の手番とそろった巡の片付けを、人間の番になるか手が終わるまで進める。
    /// View から複数の契機で呼ばれても内部で 1 本に制限する（`withAITurnRunner`・#531）。
    public func runCPUTurnsIfNeeded() async {
        await withAITurnRunner(running: \.isRunningCPUTurns) {
            while needsAutomaticStep {
                // 間合いが 0 の手番には suspend が無く、下の sleep 後の判定を通らない。ループ先頭でも見る（#287）。
                guard !Task.isCancelled else { return }
                let delay = isTrickComplete ? trickPause : cpuDelay
                if delay > .zero {
                    // sleep の直後にキャンセルを見る。見ないと画面を離れた瞬間に残りの手番が間合いゼロで走り抜け、
                    // その結果が中断データに残る（#287・#1621）。
                    guard await pauseCPUTurn(for: delay) else { return }
                    guard needsAutomaticStep else { return }
                }
                if isTrickComplete {
                    collectTrick()
                } else {
                    performCPUTurn(currentPlayer)
                }
                persist()
            }
        }
    }

    /// 人間の操作を待たずに進める段があるか（CPU の番、またはそろった巡の片付け）。
    private var needsAutomaticStep: Bool {
        phase == .playing && (isTrickComplete || currentPlayer != Self.humanIndex)
    }

    /// CPU の 1 手。CPU の着手では触覚を鳴らさない（人間の操作と区別するため）。
    private func performCPUTurn(_ player: Int) {
        let view = HeartsCPU.Situation(
            hand: hands[player], trick: currentTrick, heartsBroken: heartsBroken,
            isFirstTrick: trickNumber == 0, playedIDs: playedIDs
        )
        let legal = HeartsRules.legalPlays(
            hand: view.hand, trick: view.trick, heartsBroken: heartsBroken, isFirstTrick: view.isFirstTrick
        )
        // 念のため合法手に含まれるかを確かめ、外れていれば合法手の先頭で代える（ループを止めない）。
        guard let fallback = legal.first else { return }
        var card = HeartsCPU(strength: strength).choosePlay(view, using: &rng) ?? fallback
        if !legal.contains(card) { card = fallback }
        play(card, by: player)
    }

    // MARK: - テスト用

    /// テスト専用: 任意の局面から検証するための組み立て口（`@testable import` からのみ見える）。
    func configureForTesting(
        hands: [[HeartsCard]],
        trick: [HeartsPlay] = [],
        currentPlayer: Int = HeartsModel.humanIndex,
        heartsBroken: Bool = false,
        trickNumber: Int = 1,
        takenPoints: [Int] = [0, 0, 0, 0],
        totals: [Int] = [0, 0, 0, 0],
        playedIDs: Set<Int>? = nil,
        handNumber: Int = 1
    ) {
        self.hands = hands.map { $0.sorted { $0.sortKey < $1.sortKey } }
        currentTrick = trick
        self.currentPlayer = currentPlayer
        self.heartsBroken = heartsBroken
        self.trickNumber = trickNumber
        self.takenPoints = takenPoints
        self.totals = totals
        self.handNumber = handNumber
        // 指定が無ければ、手札と場に無い札は全部片付いた扱いにする（52 枚の整合を保つ）。
        let inPlay = Set(hands.flatMap { $0.map(\.id) } + trick.map(\.card.id))
        self.playedIDs = playedIDs ?? Set(HeartsCard.makeDeck().map(\.id)).subtracting(inPlay)
        lastTrick = []
        lastTrickWinner = nil
        selectedID = nil
        passSelection = []
        ranking = []
        isUntouchedDeal = false
        turnSerial += 1
        phase = .playing
        persist()
    }

    #if DEBUG
    /// 撮影・動作確認用（Release には残らない）。`-heartsScenario <name>` で局面を差し替える。
    ///
    /// - `queen`: 自分の番。スペードが出され、CPU がキングを出したところでクイーンを押し付けられる
    /// - `handResult`: 1 手が終わった直後（点の一覧）
    /// - `result`: 対局の決着（自分が 1 位）
    public func applyDebugScenario(_ name: String) {
        func c(_ suit: HeartsSuit, _ rank: Int) -> HeartsCard { HeartsCard(suit, rank) }
        switch name {
        case "queen":
            configureForTesting(
                hands: [
                    [c(.club, 9), c(.diamond, 4), c(.diamond, 11), c(.spade, 3), c(.spade, 12), c(.heart, 5), c(.heart, 13)],
                    [c(.club, 10), c(.diamond, 2), c(.spade, 7), c(.heart, 2), c(.heart, 8), c(.club, 3)],
                    [c(.club, 12), c(.diamond, 9), c(.heart, 10), c(.heart, 11), c(.spade, 2), c(.diamond, 6)],
                    [c(.club, 13), c(.diamond, 13), c(.spade, 10), c(.heart, 3), c(.heart, 6), c(.club, 4)],
                ],
                trick: [HeartsPlay(player: 1, card: c(.spade, 9)), HeartsPlay(player: 2, card: c(.spade, 13)),
                        HeartsPlay(player: 3, card: c(.spade, 6))],
                currentPlayer: 0, heartsBroken: true, trickNumber: 6,
                takenPoints: [0, 2, 1, 0], totals: [8, 14, 3, 1], handNumber: 2
            )
            selectedID = c(.spade, 12).id
        case "handResult", "result":
            let totalsBefore = name == "result" ? [18, 40, 24, 33] : [8, 14, 3, 1]
            configureForTesting(
                hands: [[c(.club, 2)], [c(.club, 3)], [c(.club, 4)], [c(.club, 14)]],
                currentPlayer: 0, heartsBroken: true, trickNumber: 12,
                takenPoints: [3, 13, 2, 8], totals: totalsBefore, handNumber: 3
            )
            // 残りの 1 巡を進めて手を締める（クラブの A を出した CPU3 が取る）。
            selectedID = c(.club, 2).id
            playSelected()
            for player in 1..<Self.playerCount { performCPUTurn(player) }
            collectTrick()
            persist()
        default:
            break
        }
    }
    #endif

    // MARK: - 永続化

    private func persist() {
        // 対局の最初の手を配っただけの盤面は保存しない（#240）。2 手目以降は合計点があるので、渡す前でも保存する。
        guard [HeartsPhase.passing, .playing, .handResult].contains(phase), !isUntouchedDeal else {
            if phase != .result { services?.snapshots.clear(for: gameID) }
            return
        }
        let snap = HeartsSnapshot(
            phase: phase,
            hands: hands,
            currentTrick: currentTrick,
            currentPlayer: currentPlayer,
            heartsBroken: heartsBroken,
            trickNumber: trickNumber,
            takenPoints: takenPoints,
            totals: totals,
            handNumber: handNumber,
            playedIDs: playedIDs.sorted(),
            lastTrick: lastTrick,
            lastTrickWinner: lastTrickWinner,
            receivedIDs: receivedIDs.sorted(),
            aiLevel: aiLevel,
            turnSerial: turnSerial,
            hintsUsed: passHints.used
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
