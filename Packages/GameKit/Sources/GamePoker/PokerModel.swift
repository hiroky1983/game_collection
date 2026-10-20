import Foundation
import Observation
import Core

// MARK: - Game Phase

public enum PokerPhase: String, Equatable, Sendable, Codable {
    /// 勝負の前（開始シート）。局を持たない。
    case idle
    /// 捨てる札を選んでいる。
    case exchange
    /// 1 回めの交換を終えて、勝負に進むか、広告でもう 1 回交換するかを選んでいる（その勝負でまだ使っていないときだけ）。
    case exchanged
    /// 1 回ぶんの決着。次の回へ進むか、10 回目なら勝負の終わり。
    case result
}

public enum PokerWinner: String, Sendable, Codable {
    case player, cpu, tie
}

// MARK: - Snapshot

/// 中断データ。**非 optional の鍵（`round` など）を持つ**ので、チップ制だった頃の旧データは
/// デコードに失敗し、`FileSnapshotStore` が読み飛ばして消す（#2551）。
struct PokerSnapshot: Codable {
    let playerHand: [PokerCard]
    let cpuHand: [PokerCard]
    let deck: [PokerCard]
    let phase: PokerPhase
    /// 今が何回目か（1〜10）。
    let round: Int
    let totalPoints: Int
    let playerWins: Int
    let cpuWins: Int
    let draws: Int
    /// 作った一番強い役（`PokerHandRank.rawValue`）。まだ決着が無ければ nil。
    let bestRank: Int?
    /// この勝負で「もう 1 回交換」を使ったか。
    let extraExchangeUsed: Bool
    /// この回で交換を終えた回数（0〜2）。
    let exchangesDone: Int
    let cpuAction: String
    /// 直近の決着でもらった点。`.result` を復元したときに出す。
    let lastRoundPoints: Int
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
    /// 直近のラウンドで確定した自己ベスト（#115）。勝負が終わったときに 1 行出す。
    public private(set) var recordResult: RecordResult?

    /// 今が何回目か（1〜`PokerMatch.roundsPerMatch`）。勝負の前は 0。
    public private(set) var round = 0
    /// これまでの合計点。
    public private(set) var totalPoints = 0
    public private(set) var playerWins = 0
    public private(set) var cpuWins = 0
    public private(set) var draws = 0
    /// 作った一番強い役。まだ決着が無ければ nil。
    public private(set) var bestRank: PokerHandRank?
    /// 直近の決着でもらった点（負け・引き分けは 0）。
    public private(set) var lastRoundPoints = 0
    /// この勝負で「もう 1 回交換」を使ったか。1 回の勝負につき 1 回まで。
    public private(set) var extraExchangeUsed = false
    /// この回で交換を終えた回数。2 回めの交換のあとは CPU を待たずに決着する。
    private var exchangesDone = 0

    /// 最後の回の決着まで済んだ（勝負の終わり）。
    public var isMatchOver: Bool {
        phase == .result && round >= PokerMatch.roundsPerMatch
    }

    /// 勝負全体の結果。評価リクエスト（#53）の判定にも使う。勝った回が多いほうが勝ち。
    public var reviewOutcome: GameOutcome {
        if playerWins > cpuWins { return .win }
        if playerWins < cpuWins { return .loss }
        return .draw
    }

    /// 「もう 1 回交換」（リワード広告）を出してよいか。その勝負で未使用の、1 回めの交換のあとだけ。
    public var canUseExtraExchange: Bool {
        phase == .exchanged && !extraExchangeUsed
    }

    private var deck: [PokerCard] = []
    private let services: GameServices?

    let gameID = "poker"

    /// ショーダウンで CPU の 5 枚が返り終わり、役名が出るまでの時間（#667）。勝敗の触覚をここまで遅らせる。
    /// `.zero` なら従来どおり決着の瞬間に鳴らす。
    private let showdownRevealDelay: Duration
    /// 回の通し番号。遅らせた勝敗の触覚や広告の視聴が、次の回に入ってから効かないように照合する（#667）。
    private var roundSerial = 0
    /// 遅らせた勝敗の触覚を待っている `Task`（#667）。
    private(set) var outcomeNoticeTask: Task<Void, Never>?

    /// - Parameter showdownRevealDelay: 勝敗の触覚を遅らせる時間。画面は `PokerMotion.showdownRevealDelay` を渡す。
    ///   既定の `.zero` は決着の瞬間に鳴らす（テストの決定性のため）。
    public init(services: GameServices? = nil, showdownRevealDelay: Duration = .zero) {
        self.services = services
        self.showdownRevealDelay = showdownRevealDelay
        if let snap = services?.snapshots.load(PokerSnapshot.self, for: "poker") {
            self.playerHand = snap.playerHand
            self.cpuHand = snap.cpuHand
            self.deck = snap.deck
            self.phase = snap.phase
            self.round = snap.round
            self.totalPoints = snap.totalPoints
            self.playerWins = snap.playerWins
            self.cpuWins = snap.cpuWins
            self.draws = snap.draws
            self.bestRank = snap.bestRank.flatMap(PokerHandRank.init(rawValue:))
            self.extraExchangeUsed = snap.extraExchangeUsed
            self.exchangesDone = snap.exchangesDone
            self.cpuAction = snap.cpuAction
            self.lastRoundPoints = snap.lastRoundPoints
            if snap.phase == .result {
                // 決着の画は中断データに持っていないので、手札から数え直す。
                playerHandRank = HandEvaluator.evaluate(playerHand).rank
                cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
                let cmp = HandEvaluator.compare(playerHand, cpuHand)
                winner = cmp > 0 ? .player : cmp < 0 ? .cpu : .tie
            }
        }
    }

    private func persist() {
        guard phase != .idle, !isMatchOver else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = PokerSnapshot(
            playerHand: playerHand, cpuHand: cpuHand, deck: deck,
            phase: phase, round: round, totalPoints: totalPoints,
            playerWins: playerWins, cpuWins: cpuWins, draws: draws,
            bestRank: bestRank?.rawValue,
            extraExchangeUsed: extraExchangeUsed, exchangesDone: exchangesDone,
            cpuAction: cpuAction, lastRoundPoints: lastRoundPoints
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - 決着の表示（#1754）

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
        var reason = winner == .tie
            ? tr("どちらも%@", playerHandRank.description)
            : tr("%1$@ 対 %2$@", playerHandRank.description, cpuHandRank.description)
        if lastRoundPoints > 0 { reason += tr("（+%lld点）", lastRoundPoints) }
        return HandResult(kind: kind, headline: headline, reason: reason,
                          chipDelta: nil, spokenResult: spoken)
    }

    // MARK: - CPU の行動の表示（#2166）

    /// CPU の行動のバッジに出す文言。
    ///
    /// `cpuAction` は中断データ（`PokerSnapshot.cpuAction`）に載る値なので、日本語の原文で持ち、
    /// 訳は表示の境目のここで引く（保存した時点の言語に固まらない）。
    public var cpuActionLabel: String {
        if cpuAction == "カード交換なし" { return tr("カード交換なし") }  // i18n-keep: 中断データに保存する CPU の行動（表示は cpuActionLabel で訳す）
        if cpuAction.hasSuffix("枚交換"), let count = Int(cpuAction.dropLast(3)) {  // i18n-keep: 中断データに保存する CPU の行動（表示は cpuActionLabel で訳す）
            return tr("%lld枚交換", count)
        }
        return cpuAction
    }

    // MARK: - Start

    /// 新しい勝負（10 回）を始めて、1 回めを配る。
    ///
    /// 勝負の前（`.idle`）か、前の勝負が終わったあとだけ受け付ける。進行中に開始ボタンが連打されても
    /// 二重に始めない（`game_start` の二重計上を避ける・#2416）。
    public func startGame() {
        guard phase == .idle || isMatchOver else { return }
        round = 0
        totalPoints = 0
        playerWins = 0
        cpuWins = 0
        draws = 0
        bestRank = nil
        extraExchangeUsed = false
        recordResult = nil
        dealRound()
        // 1 勝負 = 1 プレイ（`gameDidFinish` も勝負ごとに呼んでいる）。
        // 中断からの復元は init が状態を戻すだけでここを通らないので数えない（#158）。
        services?.gameDidRestart(gameID: gameID)
        // 配った時点から、捨てれば途中離脱として数える（#500）。
        services?.gameDidProgress(gameID: gameID)
    }

    /// 次の回を配る。決着のあと、10 回目でなければ受け付ける。
    public func nextRound() {
        guard phase == .result, !isMatchOver else { return }
        dealRound()
    }

    private func dealRound() {
        roundSerial += 1
        round += 1
        winner = nil
        cpuAction = ""
        selectedForExchange = []
        exchangesDone = 0
        lastRoundPoints = 0
        playerHandRank = .highCard
        cpuHandRank = .highCard

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

    /// 選んだ札を引き直す。1 回めの交換のあとは CPU も交換し、その勝負で「もう 1 回交換」を使えるなら
    /// 勝負に進むか選ばせる。使えないなら、そのまま決着する。
    public func confirmExchange() {
        guard phase == .exchange else { return }
        for i in playerHand.indices where selectedForExchange.contains(playerHand[i].id) {
            if let newCard = deck.first {
                deck.removeFirst()
                playerHand[i] = newCard
            }
        }
        selectedForExchange = []
        exchangesDone += 1
        services?.feedback.impact(.medium) // 交換成立
        if exchangesDone == 1 {
            performCPUExchange()
            if extraExchangeUsed {
                resolveShowdown()
            } else {
                phase = .exchanged
            }
        } else {
            resolveShowdown()
        }
        persist()
    }

    private func performCPUExchange() {
        let keepIdx = HandEvaluator.cpuKeepIndices(from: cpuHand)
        let discardCount = 5 - keepIdx.count
        cpuAction = discardCount == 0 ? "カード交換なし" : "\(discardCount)枚交換"  // i18n-keep: 中断データに保存する CPU の行動（表示は cpuActionLabel で訳す）
        var newHand = cpuHand
        for i in newHand.indices where !keepIdx.contains(i) {
            if let newCard = deck.first {
                deck.removeFirst()
                newHand[i] = newCard
            }
        }
        cpuHand = newHand
    }

    /// 交換を終えて勝負する（「もう 1 回交換」を使わない）。
    public func finishExchange() {
        guard phase == .exchanged else { return }
        resolveShowdown()
        persist()
    }

    // MARK: - Showdown

    private func resolveShowdown() {
        playerHandRank = HandEvaluator.evaluate(playerHand).rank
        cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
        let cmp = HandEvaluator.compare(playerHand, cpuHand)
        if cmp > 0 {
            winner = .player
            playerWins += 1
            lastRoundPoints = PokerPointTable.points(for: playerHandRank)
            totalPoints += lastRoundPoints
        } else if cmp < 0 {
            winner = .cpu
            cpuWins += 1
        } else {
            winner = .tie
            draws += 1
        }
        if bestRank.map({ playerHandRank > $0 }) ?? true { bestRank = playerHandRank }
        phase = .result
        notifyOutcome(after: showdownRevealDelay)
        if isMatchOver { concludeMatch() }
    }

    /// 勝敗の触覚を鳴らす。`delay` があれば、その間に次の回へ進んでいないことを確かめてから鳴らす（#667）。
    ///
    /// ショーダウンで決着の瞬間に鳴らすと、CPU の手札が裏向きのうちに勝敗が指へ伝わる。
    /// 役名が出る瞬間まで遅らせ、公開 → 役名と勝敗の手応え、の順にする。記録の確定は遅らせない。
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

    /// 10 回目の決着で、勝負の記録を確定する（1 勝負につき 1 回だけ呼ばれる）。
    ///
    /// 順位表（Game Center）には送らない。チップ制の頃の表（`asobiba.poker.chips`）とは単位が違うため。
    private func concludeMatch() {
        recordResult = services?.gameDidFinish(
            gameID: gameID,
            outcome: reviewOutcome,
            score: GameScore(
                metric: .points,
                points: totalPoints,
                variant: PokerMatch.recordVariant,
                variantLabel: RecordVariantLabels.stored(gameID: gameID, variant: PokerMatch.recordVariant),
                isLeaderboardEligible: false
            ),
            // 評価リクエストの見せ場は、スリーカード以上の役を作って勝ち越したとき（#1471）。
            isReviewHighlight: reviewOutcome == .win && (bestRank ?? .highCard) >= .threeOfAKind
        )
        persist()
    }

    // MARK: - Reward Ad（もう 1 回交換）

    /// リワード広告を表示し、**視聴完了したときだけ**もう 1 回交換できるようにする。
    ///
    /// - 1 回の勝負につき 1 回まで（`extraExchangeUsed`）。1 回めの交換のあと（`.exchanged`）だけ効く。
    /// - 広告のあいだに次の回・新しい勝負へ進んでいたら適用しない（`roundSerial` の照合・#728）。
    /// - 視聴中断・ロード失敗時は何も変更せず `.notEarned` を返す。
    /// - services 未注入時（プレビュー・テスト）は広告機構自体が無いため、そのまま適用する。
    public func extraExchangeAfterAd() async -> RewardedModelOutcome {
        guard canUseExtraExchange else { return .unavailable }
        let serialBeforeAd = roundSerial
        // 画面の世代（#653）。広告のロード中にハブへ戻られたら、このモデルは捨てられている。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .undo) ?? true else { return .notEarned }
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        guard roundSerial == serialBeforeAd, canUseExtraExchange else { return .unavailable }
        extraExchangeUsed = true
        selectedForExchange = []
        phase = .exchange
        persist()
        return .granted
    }

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
