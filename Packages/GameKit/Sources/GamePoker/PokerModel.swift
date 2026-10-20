import Foundation
import Observation
import Core

// MARK: - Game Phase

/// 1 回の勝負の進み方（#2551）。配る → 交換 →（広告でもう 1 回交換するかを選ぶ）→ 勝負 → 結果。
public enum PokerPhase: String, Equatable, Sendable, Codable {
    /// 10 回勝負を始める前。
    case idle
    /// 捨てる札を選んで交換する。
    case exchange
    /// 交換を終え、そのまま勝負するか、広告を見てもう 1 回交換するかを選ぶ。
    /// もう 1 回の交換を使い切った勝負では通らない（交換したらそのまま勝負になる）。
    case drawn
    /// その回の勝敗が出た。10 回目なら勝負全体の決着も出ている（`sessionOver`）。
    case result
}

public enum PokerWinner: String, Sendable, Codable {
    case player, cpu, tie
}

// MARK: - Snapshot

/// 10 回勝負の中断データ（#2551）。
///
/// **旧ルール（v1.1.12 まで）の中断データとは互換を持たない**。旧データには `format` などの鍵が無いので
/// デコードに失敗し、`FileSnapshotStore` がその場で消す（#1914）。読めても版が違えば `PokerModel.init` が消す。
/// どちらの場合も新しい 10 回勝負の開始シートから始まり、落ちない（`PokerLegacySnapshotTests`）。
struct PokerSnapshot: Codable {
    static let currentFormat = 2

    var format: Int = PokerSnapshot.currentFormat
    let playerHand: [PokerCard]
    let cpuHand: [PokerCard]
    let deck: [PokerCard]
    let phase: PokerPhase
    /// 何回目か（1 始まり）。
    let round: Int
    let playerPoints: Int
    let cpuPoints: Int
    let playerWins: Int
    let cpuWins: Int
    /// この勝負で作った一番強い役。まだ 1 回も勝負していなければ nil。
    let bestRank: PokerHandRank?
    /// 広告の「もう 1 回交換」をこの勝負で使ったか。
    let extraExchangeUsed: Bool
    let cpuAction: String
    /// `.result` のときだけ意味を持つ（その回の勝敗の画を戻すため）。
    let winner: PokerWinner?
    let playerHandRank: PokerHandRank
    let cpuHandRank: PokerHandRank
    let roundPoints: Int
    /// 連勝（#2590）。この項目を足す前の中断データには無いので optional（読めなくして続きを消さない）。
    var streak: Int? = nil
    var bestStreak: Int? = nil
    /// CPU が替えた札の位置（#2594）。この項目を足す前の中断データには無いので optional（読めなくして続きを消さない）。
    var cpuExchangedIndices: [Int]? = nil
}

// MARK: - Model

@MainActor
@Observable
public final class PokerModel {
    public private(set) var playerHand: [PokerCard] = []
    public private(set) var cpuHand: [PokerCard] = []
    public private(set) var phase: PokerPhase = .idle
    public private(set) var winner: PokerWinner? = nil
    public private(set) var playerHandRank: PokerHandRank = .highCard
    public private(set) var cpuHandRank: PokerHandRank = .highCard
    public private(set) var selectedForExchange: Set<Int> = []
    public private(set) var cpuAction: String = ""
    /// CPU が替えた札の `cpuHand` 上の位置（#2594）。決着で表になったとき、引いた札の枠に使う。
    public private(set) var cpuExchangedIndices: Set<Int> = []

    // MARK: 10 回勝負（#2551）

    /// 1 回の勝負の回数。
    public nonisolated static let roundsPerSession = 10

    /// 記録の区分キー（`GameScore.variant`）。
    ///
    /// 旧ルールの頃の記録（`poker`・`poker#bonus`）は持ち点で、点数とは桁が違う。同じ保存先に書くと
    /// 自己ベストがいつまでも旧記録のままになるので、保存先を分け、旧記録は `PlayLog` が読み飛ばす。
    public nonisolated static let recordVariant = "round10"

    /// いま何回目か（1 始まり）。10 回勝負を始める前は 0。
    public private(set) var round = 0
    /// この勝負でのあなたの合計点。
    public private(set) var playerPoints = 0
    /// この勝負での CPU の合計点。勝負全体の勝ち負けはこれと比べて決める。
    public private(set) var cpuPoints = 0
    /// この勝負で勝った回数。
    public private(set) var playerWins = 0
    /// この勝負で CPU が勝った回数。
    public private(set) var cpuWins = 0
    /// この勝負で作った一番強い役（勝ち負けに関わらず、勝負した手で数える）。
    public private(set) var bestRank: PokerHandRank?
    /// 今の連勝（勝った回で +1、負け・引き分けで 0）。ブラックジャックと同じ定義（#2590）。
    public private(set) var streak = 0
    /// この勝負での最高連勝。
    public private(set) var bestStreak = 0
    /// 直近の回に勝った側へ入った点（引き分けは 0）。
    public private(set) var roundPoints = 0
    /// 広告の「もう 1 回交換」をこの勝負で使ったか（1 回の勝負につき 1 回まで）。
    public private(set) var extraExchangeUsed = false
    /// 10 回目の勝敗が出て、勝負全体が決着した。
    public private(set) var sessionOver = false
    /// 勝負全体の勝者（合計点で比べる）。決着するまでは nil。
    public private(set) var sessionWinner: PokerWinner? = nil
    /// 勝負全体の決着で確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    /// 10 回目の勝負か。
    public var isFinalRound: Bool { round >= Self.roundsPerSession }

    /// 広告を見てもう 1 回交換できるか。山札は 52 枚から 2 人に配って 42 枚、1 回目の交換で多くても
    /// 5 枚減るので、もう 1 回ぶん（最大 5 枚）と CPU の交換ぶんは必ず残るが、念のため確かめる。
    public var canUseExtraExchange: Bool {
        phase == .drawn && !extraExchangeUsed && deck.count >= 10
    }

    /// 勝負全体の決着の種類（評価リクエスト #53・解析の `game_end`）。合計点で比べる。
    public var reviewOutcome: GameOutcome {
        switch sessionWinner {
        case .player: return .win
        case .tie:    return .draw
        default:      return .loss
        }
    }

    private var deck: [PokerCard] = []
    private let services: GameServices?

    let gameID = "poker"

    /// ショーダウンで CPU の 5 枚が返り終わり、役名が出るまでの時間（#667）。勝敗の触覚をここまで遅らせる。
    /// `.zero` なら決着の瞬間に鳴らす。
    private let showdownRevealDelay: Duration
    /// 回の通し番号。遅らせた勝敗の触覚が次の回に入ってから鳴らないように、また広告のあいだに
    /// 回が進んでいないかを照合する（#667・#728）。
    private var roundSerial = 0
    /// 遅らせた勝敗の触覚を待っている `Task`（#667）。
    private(set) var outcomeNoticeTask: Task<Void, Never>?

    /// - Parameter showdownRevealDelay: 勝敗の触覚を遅らせる時間。画面は `PokerMotion.showdownRevealDelay` を渡す。
    ///   既定の `.zero` は決着の瞬間に鳴らす（テストの決定性のため）。
    public init(services: GameServices? = nil, showdownRevealDelay: Duration = .zero) {
        self.services = services
        self.showdownRevealDelay = showdownRevealDelay
        guard let services else { return }
        if let snap = services.snapshots.load(PokerSnapshot.self, for: gameID),
           snap.format == PokerSnapshot.currentFormat, snap.phase != .idle {
            playerHand = snap.playerHand
            cpuHand = snap.cpuHand
            deck = snap.deck
            phase = snap.phase
            round = snap.round
            playerPoints = snap.playerPoints
            cpuPoints = snap.cpuPoints
            playerWins = snap.playerWins
            cpuWins = snap.cpuWins
            bestRank = snap.bestRank
            streak = max(0, snap.streak ?? 0)
            bestStreak = max(snap.bestStreak ?? 0, streak)
            extraExchangeUsed = snap.extraExchangeUsed
            cpuAction = snap.cpuAction
            cpuExchangedIndices = Set((snap.cpuExchangedIndices ?? []).filter { (0..<snap.cpuHand.count).contains($0) })
            winner = snap.winner
            playerHandRank = snap.playerHandRank
            cpuHandRank = snap.cpuHandRank
            roundPoints = snap.roundPoints
        } else if services.snapshots.exists(for: gameID) {
            // 旧ルールの頃の中断データ（#2551）。続きは無いので消し、開始シートから始める。
            services.snapshots.clear(for: gameID)
        }
    }

    private func persist() {
        guard phase != .idle, !sessionOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = PokerSnapshot(
            playerHand: playerHand, cpuHand: cpuHand, deck: deck, phase: phase,
            round: round, playerPoints: playerPoints, cpuPoints: cpuPoints,
            playerWins: playerWins, cpuWins: cpuWins, bestRank: bestRank,
            extraExchangeUsed: extraExchangeUsed, cpuAction: cpuAction,
            winner: winner, playerHandRank: playerHandRank, cpuHandRank: cpuHandRank,
            roundPoints: roundPoints, streak: streak, bestStreak: bestStreak,
            cpuExchangedIndices: cpuExchangedIndices.sorted()
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - 決着の表示（#1754）

    /// 決着の幕を強調する役の線引き（#2593）。評価リクエストの見せ場（`isReviewHighlight`）と同じ。
    static let strongHandRank: PokerHandRank = .threeOfAKind

    /// 決着した回の、卓の中央に出す結果。`.result` でなければ nil。
    public var handResult: HandResult? {
        guard phase == .result, let winner else { return nil }
        let kind: HandResult.Kind
        let headline: String
        let spoken: String
        switch winner {
        case .player: (kind, headline, spoken) = (.win, tr("勝ち！"), tr("勝ちです"))
        case .cpu:    (kind, headline, spoken) = (.lose, tr("負け"), tr("負けです"))
        case .tie:    (kind, headline, spoken) = (.draw, tr("引き分け"), tr("引き分けです"))
        }
        let reason: String
        switch winner {
        case .tie:
            reason = tr("どちらも%@", playerHandRank.description)
        case .player:
            reason = tr("%1$@ 対 %2$@・+%3$lld点", playerHandRank.description, cpuHandRank.description, roundPoints)
        case .cpu:
            reason = tr("%1$@ 対 %2$@・CPUに+%3$lld点", playerHandRank.description, cpuHandRank.description, roundPoints)
        }
        return HandResult(kind: kind, headline: headline, reason: reason, chipDelta: nil, spokenResult: spoken,
                          isEmphasized: winner == .player && playerHandRank >= Self.strongHandRank)
    }

    // MARK: - CPU の行動の表示（#2166）

    /// CPU の行動のバッジに出す文言。`cpuAction` は中断データに載る値なので日本語の原文で持ち、訳は表示の境目で引く。
    public var cpuActionLabel: String {
        if cpuAction == "カード交換なし" { return tr("カード交換なし") }  // i18n-keep: 中断データに保存する CPU の行動（表示は cpuActionLabel で訳す）
        if cpuAction.hasSuffix("枚交換"), let count = Int(cpuAction.dropLast(3)) {  // i18n-keep: 中断データに保存する CPU の行動（表示は cpuActionLabel で訳す）
            return tr("%lld枚交換", count)
        }
        return cpuAction
    }

    // MARK: - Start

    /// 10 回勝負を新しく始め、1 回目を配る。
    ///
    /// 勝負の途中では始め直さない。開始ボタンの連打で 2 回届くと `game_start` が二重に数えられる（#2416）。
    public func startGame() {
        guard phase == .idle || sessionOver else { return }
        outcomeNoticeTask?.cancel()
        outcomeNoticeTask = nil
        round = 0
        playerPoints = 0
        cpuPoints = 0
        playerWins = 0
        cpuWins = 0
        bestRank = nil
        streak = 0
        bestStreak = 0
        extraExchangeUsed = false
        sessionOver = false
        sessionWinner = nil
        recordResult = nil
        // 10 回で 1 プレイ（`gameDidFinish` も 10 回目の決着で 1 回だけ呼ぶ）。
        // 中断からの復元は init が状態を戻すだけでここを通らないので数えない（#158）。
        services?.gameDidRestart(gameID: gameID)
        dealRound()
    }

    /// 次の回を配る。10 回目の決着のあとは何もしない（新しい勝負は `startGame()`）。
    public func nextRound() {
        guard phase == .result, !sessionOver else { return }
        dealRound()
    }

    private func dealRound() {
        roundSerial += 1
        round += 1
        winner = nil
        cpuAction = ""
        cpuExchangedIndices = []
        selectedForExchange = []
        playerHandRank = .highCard
        cpuHandRank = .highCard
        roundPoints = 0

        deck = makeDeck().shuffled()
        playerHand = Array(deck.prefix(5))
        cpuHand = Array(deck.dropFirst(5).prefix(5))
        deck = Array(deck.dropFirst(10))

        phase = .exchange
        services?.feedback.impact(.medium) // カードを配る
        persist()
    }

    // MARK: - Exchange

    public func toggleCardSelection(_ card: PokerCard) {
        guard phase == .exchange else { return }
        if selectedForExchange.contains(card.id) {
            selectedForExchange.remove(card.id)
        } else {
            selectedForExchange.insert(card.id)
        }
        services?.feedback.impact(.rigid)
    }

    /// 選んだ札を引き直す。もう 1 回の交換が残っていれば選ぶ段（`.drawn`）へ、使い切っていればそのまま勝負する。
    public func confirmExchange() {
        guard phase == .exchange else { return }
        for i in playerHand.indices where selectedForExchange.contains(playerHand[i].id) {
            if let newCard = deck.first {
                deck.removeFirst()
                playerHand[i] = newCard
            }
        }
        selectedForExchange = []
        services?.feedback.impact(.medium) // 交換成立
        // 1 回でも交換すれば、捨てたら途中離脱として数える（#500）。
        services?.gameDidProgress(gameID: gameID)
        if !extraExchangeUsed && deck.count >= 10 {
            phase = .drawn
            persist()
        } else {
            resolveShowdown()
        }
    }

    /// 交換を終えた手でそのまま勝負する（`.drawn` の「勝負する」）。
    public func showdown() {
        guard phase == .drawn else { return }
        resolveShowdown()
    }

    private func performCPUExchange() {
        let keepIdx = HandEvaluator.cpuKeepIndices(from: cpuHand)
        let discardCount = 5 - keepIdx.count
        cpuAction = discardCount == 0 ? "カード交換なし" : "\(discardCount)枚交換"  // i18n-keep: 中断データに保存する CPU の行動（表示は cpuActionLabel で訳す）
        var newHand = cpuHand
        var exchanged: Set<Int> = []
        for i in newHand.indices where !keepIdx.contains(i) {
            if let newCard = deck.first {
                deck.removeFirst()
                newHand[i] = newCard
                exchanged.insert(i)
            }
        }
        cpuHand = newHand
        cpuExchangedIndices = exchanged
    }

    // MARK: - Showdown

    private func resolveShowdown() {
        performCPUExchange()
        playerHandRank = HandEvaluator.evaluate(playerHand).rank
        cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
        bestRank = max(bestRank ?? playerHandRank, playerHandRank)
        let cmp = HandEvaluator.compare(playerHand, cpuHand)
        if cmp > 0 {
            winner = .player
            roundPoints = PokerScoreTable.points(for: playerHandRank)
            playerPoints += roundPoints
            playerWins += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
        } else if cmp < 0 {
            winner = .cpu
            roundPoints = PokerScoreTable.points(for: cpuHandRank)
            cpuPoints += roundPoints
            cpuWins += 1
            streak = 0
        } else {
            winner = .tie
            roundPoints = 0
            streak = 0
        }
        phase = .result
        notifyOutcome(after: showdownRevealDelay)
        if isFinalRound {
            finishSession()
        } else {
            persist()
        }
    }

    /// 勝敗の触覚を鳴らす。`delay` があれば、その間に次の回へ進んでいないことを確かめてから鳴らす（#667）。
    private func notifyOutcome(after delay: Duration) {
        let notice: FeedbackNotice
        switch winner {
        case .player: notice = .success
        case .cpu:    notice = .error
        default:      notice = .warning
        }
        guard delay > .zero else {
            services?.feedback.notify(notice)
            return
        }
        let round = roundSerial
        outcomeNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.roundSerial == round else { return }
            self.services?.feedback.notify(notice)
        }
    }

    /// 10 回目の決着。合計点で勝負全体の勝ち負けを決め、記録を 1 回だけ確定する。
    private func finishSession() {
        sessionOver = true
        if playerPoints > cpuPoints {
            sessionWinner = .player
        } else if playerPoints < cpuPoints {
            sessionWinner = .cpu
        } else {
            sessionWinner = .tie
        }
        recordResult = services?.gameDidFinish(
            gameID: gameID,
            outcome: reviewOutcome,
            score: GameScore(
                metric: .points,
                points: playerPoints,
                // 歴代のいちばん強い役（#2591）。`PokerHandRank` の序数で、表示は `RecordFormat` が役名にする。
                highestValue: (bestRank ?? .highCard).rawValue,
                variant: Self.recordVariant,
                variantLabel: RecordVariantLabels.stored(gameID: gameID, variant: Self.recordVariant),
                // Game Center の順位表（旧ルールの頃の表）へは送らない（#2551）。
                // 枚数の表に点数を混ぜると意味を成さない。ローカルの自己ベストには残す。
                isLeaderboardEligible: false
            ),
            // 評価リクエストの見せ場は、スリーカード以上の役を作ったとき（#1471）。
            isReviewHighlight: (bestRank ?? .highCard) >= .threeOfAKind
        )
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - Reward Ad（もう 1 回交換・#2551）

    /// リワード広告を表示し、**視聴完了したときだけ**もう 1 回交換できるようにする。
    ///
    /// - 交換を終えて勝負する前（`.drawn`）だけ、1 回の勝負（10 回）につき 1 回まで効く。
    /// - 広告のあいだに回が進んだ・勝負が始め直された・画面を離れたら適用しない（#728・#653）。
    /// - services 未注入時（プレビュー・テスト）は広告機構自体が無いため、そのまま適用する。
    public func extraExchangeAfterAd() async -> RewardedModelOutcome {
        guard canUseExtraExchange else { return .unavailable }
        let roundBeforeAd = roundSerial
        // 画面の世代（#653）。広告のロード中にハブへ戻られたら、このモデルは捨てられている。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .undo) ?? true else { return .notEarned }
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        guard roundSerial == roundBeforeAd, canUseExtraExchange else { return .unavailable }
        extraExchangeUsed = true
        selectedForExchange = []
        phase = .exchange
        persist()
        return .granted
    }

    /// 勝負を捨てて最初に戻す（開始シートの前の状態）。
    public func restartSession() {
        // 前の回の勝敗の触覚を待っていたら止める（#667）。
        outcomeNoticeTask?.cancel()
        outcomeNoticeTask = nil
        recordResult = nil
        roundSerial += 1
        round = 0
        playerPoints = 0
        cpuPoints = 0
        playerWins = 0
        cpuWins = 0
        bestRank = nil
        streak = 0
        bestStreak = 0
        extraExchangeUsed = false
        sessionOver = false
        sessionWinner = nil
        winner = nil
        phase = .idle
        services?.snapshots.clear(for: gameID)
    }

    #if DEBUG
    /// 撮影用: 交換せずに勝負を 10 回目の決着まで進める（実際のモデルの経路を通る）。
    func debugPlayToEnd() {
        if phase == .idle || sessionOver { startGame() }
        while !sessionOver {
            switch phase {
            case .exchange: confirmExchange()
            case .drawn:    showdown()
            case .result:   nextRound()
            case .idle:     return
            }
        }
    }
    #endif

    // MARK: - Deck

    private func makeDeck() -> [PokerCard] {
        var cards: [PokerCard] = []
        var id = 0
        for suit in PokerSuit.allCases {
            for rank in 2...14 {
                cards.append(PokerCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        return cards
    }
}
