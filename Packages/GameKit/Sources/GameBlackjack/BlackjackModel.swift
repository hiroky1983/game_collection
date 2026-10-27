import Foundation
import Observation
import Core

// MARK: - Card

public enum BlackjackSuit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs
    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }
    public var isRed: Bool { self == .hearts || self == .diamonds }

    /// トランプ共通基盤（#397）の描画用スート。`rawValue` の一致に頼らず明示的に対応させる。
    public var playing: PlayingCardSuit {
        switch self {
        case .spades:   return .spade
        case .hearts:   return .heart
        case .diamonds: return .diamond
        case .clubs:    return .club
        }
    }
}

public struct BlackjackCard: Identifiable, Codable, Sendable, Equatable {
    public let id: Int
    public let suit: BlackjackSuit
    public let rank: Int  // 1–13 (1=A, 11=J, 12=Q, 13=K)

    public var rankLabel: String {
        switch rank {
        case 1:  return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    public var value: Int {
        switch rank {
        case 1:       return 11  // Aは最初11として扱い、バストなら1に下げる
        case 11, 12, 13: return 10
        default:      return rank
        }
    }

    /// トランプ共通基盤（#397）へ渡す面の内容。`rank` は既に A=1 表記なのでそのまま渡す。
    public var figure: PlayingCardFigure {
        .pip(suit: suit.playing, rank: rank)
    }
}

// MARK: - Hand Value

func handValue(_ hand: [BlackjackCard]) -> Int {
    var total = hand.reduce(0) { $0 + $1.value }
    var aces = hand.filter { $0.rank == 1 }.count
    while total > 21 && aces > 0 {
        total -= 10
        aces -= 1
    }
    return total
}

func isBlackjack(_ hand: [BlackjackCard]) -> Bool {
    hand.count == 2 && handValue(hand) == 21
}

// MARK: - Settlement

/// 手 1 つの勝敗を決める判定表（#413）。`resolveAll` から切り出した純関数。
///
/// ナチュラル（2枚21）は両者について対称に扱う。**ディーラーのみナチュラルなら、
/// プレイヤーが3枚以上で21に届いていてもディーラーの勝ち**（標準ルール。以前は
/// 同値としてプッシュに落ちていた）。
/// プレイヤーのバストは呼び出し側（`settleHand`）で先に弾くためここには到達しない。
///
/// - Parameter allowsPlayerNatural: プレイヤー側の2枚21をナチュラルとして扱うか。
///   **スプリットで作った21はナチュラルにしない**という標準ルールのため false を渡す（#439）。
func blackjackSettlement(
    player: [BlackjackCard],
    dealer: [BlackjackCard],
    allowsPlayerNatural: Bool = true
) -> BlackjackOutcome {
    let pVal = handValue(player)
    let dVal = handValue(dealer)
    let playerNatural = allowsPlayerNatural && isBlackjack(player)
    let dealerNatural = isBlackjack(dealer)

    if playerNatural && dealerNatural { return .push }
    if playerNatural { return .playerBlackjack }
    if dealerNatural { return .lose }
    if dVal > 21 || pVal > dVal { return .win }
    if pVal == dVal { return .push }
    return .lose
}

/// 手 1 つの勝ち点（#2552）。勝てば 1 点、最初の 2 枚の 21（ブラックジャック）で勝てば 2 点。
/// 引き分け・負け・バストは 0 点。スプリットした手はそれぞれ別に数える（分けた手の 21 はナチュラルにならないので最大 1 点）。
func blackjackPoints(for outcome: BlackjackOutcome) -> Int {
    switch outcome {
    case .playerBlackjack:    return 2
    case .win:                return 1
    case .push, .lose, .bust: return 0
    }
}

// MARK: - Game Phase

/// 1 回ぶんの進み（#2552 で配る前の選択の段を外した）。`ready` は 1 回目を配る前だけ。2 回目以降は「次の回へ」でそのまま配る。
public enum BlackjackPhase: String, Equatable, Sendable, Codable {
    case ready, playerTurn, dealerTurn, result
}

public enum BlackjackOutcome: String, Sendable, Codable {
    case playerBlackjack, win, push, lose, bust
}

// MARK: - Player Hand

/// プレイヤーの1手（#439）。スプリットすると2つに増え、それぞれ独立に勝敗と勝ち点を出す。
struct BlackjackHand: Identifiable, Codable, Sendable, Equatable {
    let id: Int
    var cards: [BlackjackCard]
    /// スプリットで生まれた手か。**この手の2枚21はナチュラル扱いしない**（標準ルール）。
    var isFromSplit: Bool = false
    /// プレイヤーの操作が終わった手か（スタンド・バスト・スプリットしたA）。
    var isDone: Bool = false
    /// 勝敗。`resolveAll()` で入る。
    var outcome: BlackjackOutcome? = nil

    var value: Int { handValue(cards) }
    var isBusted: Bool { value > 21 }
}

// MARK: - Match Format

/// 1 回の勝負の形（#2860）。1 回目を配るときに選ぶ。勝負の記録は形ごとに別の区分へ残す。
public enum BlackjackMatchFormat: String, Equatable, Sendable, Codable, CaseIterable {
    /// 10 回勝負。勝ち点の合計を競う（これまでの遊び方）。
    case tenRounds
    /// 単発戦。1 回だけ勝負して終わる。
    case single

    /// 1 回の勝負の回数。
    public var rounds: Int {
        switch self {
        case .tenRounds: return BlackjackModel.roundsPerMatch
        case .single:    return 1
        }
    }

    /// 記録の区分キー（`GameScore.variant`）。
    public var recordVariant: String {
        switch self {
        case .tenRounds: return BlackjackModel.recordVariant
        case .single:    return "single"
        }
    }

    /// 解析の `mode`。10 回勝負は従来どおり送らない。
    public var analyticsMode: AnalyticsMode? {
        self == .single ? .singleRound : nil
    }
}

// MARK: - Snapshot

/// 10 回勝負（#2552）の中断データ。
///
/// **以前の形式（#2552 より前）の中断データは読まない**。`completedRounds` などを非 optional にしてあるので、
/// 旧形式は decode に失敗して nil になる（`FileSnapshotStore` はその場で消す）。旧形式の局を勝ち点に
/// 読み替えると点の意味が変わるので、続きは捨てて 1 回目から始める。
struct BlackjackSnapshot: Codable {
    /// 決着した回数（0〜10）。結果を出している回も含む。
    let completedRounds: Int
    /// ここまでの勝ち点。
    let points: Int
    /// いまの連勝（勝ち点が入った回が続いた数）。
    let streak: Int
    /// この勝負の最高連勝。
    let bestStreak: Int
    /// 負けた回のやり直し（リワード広告）をこの勝負で使ったか。中断を挟んでも 1 回までを守る。
    let hasUsedRetry: Bool
    /// 結果を出している回より前の連勝。やり直しで連勝を元に戻すのに使う。
    let streakBeforeRound: Int
    /// 勝った手・負けた手の数（勝負全体の勝ち越し判定に使う）。
    let handsWon: Int
    let handsLost: Int
    /// ブラックジャック（最初の 2 枚の 21）で勝った回数。評価リクエストの見せ場の判定に使う。
    let naturalWins: Int
    let hands: [BlackjackHand]
    let activeHandIndex: Int
    let dealerHand: [BlackjackCard]
    let deck: [BlackjackCard]
    let phase: BlackjackPhase
    /// 勝負の形（#2860）。この項目を足す前の中断データには無いので optional（無ければ 10 回勝負）。
    var format: BlackjackMatchFormat? = nil
}

// MARK: - Model

@MainActor
@Observable
public final class BlackjackModel {
    /// 1 回の勝負の回数（#2552。数値は仮置き・QA で調整）。
    public nonisolated static let roundsPerMatch = 10
    /// 記録の区分キー（#2552）。以前の記録（区分なしのキー）と混ざらないよう、勝ち点は別のキーへ書く。
    /// 旧キーの記録は `PlayLog` が読み込み時に捨てる（`PlayLog.retiredRecordKeys`）。
    nonisolated static let recordVariant = "match10"

    /// いまの勝負の形（#2860）。`deal(format:)` で 1 回目を配るときに決まり、中断データにも載る。
    public private(set) var format: BlackjackMatchFormat = .tenRounds

    /// プレイヤーの手。通常は1つで、スプリットしたときだけ2つになる（#439）。
    private(set) var hands: [BlackjackHand] = []
    /// いま操作している手の位置。スプリット時は 0 → 1 の順に進む。
    private(set) var activeHandIndex: Int = 0

    /// いま操作している手の手札。手が1つのときは従来どおり「プレイヤーの手札」そのもの。
    public var playerHand: [BlackjackCard] {
        hands.indices.contains(activeHandIndex) ? hands[activeHandIndex].cards : []
    }
    public private(set) var dealerHand: [BlackjackCard] = []
    public private(set) var phase: BlackjackPhase = .ready
    /// 直近の回の勝敗（手が 2 つなら全体のまとめ）。
    public private(set) var outcome: BlackjackOutcome? = nil

    // MARK: 10 回勝負（#2552）

    /// 決着した回数。結果を出している回も含む。
    public private(set) var completedRounds = 0
    /// ここまでの勝ち点。10 回の合計が自己ベストの対象。
    public private(set) var points = 0
    /// いまの連勝（勝ち点が入った回が続いた数）。引き分け・負けで 0 に戻る。
    public private(set) var streak = 0
    /// この勝負の最高連勝。
    public private(set) var bestStreak = 0
    /// 10 回を終えて記録をつけたか。
    public private(set) var matchOver = false
    /// 負けた回のやり直し（リワード広告）をこの勝負で使ったか。1 回の勝負につき 1 回。
    public private(set) var hasUsedRetry = false
    /// 勝負全体の勝敗（勝った手と負けた手の数で決める）。`matchOver` のときだけ値がある。
    public private(set) var matchOutcome: GameOutcome?
    /// 勝負を終えて確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    private var streakBeforeRound = 0
    /// この勝負で勝った手の数（ブラックジャックの勝ちを含む）。結果カードの「勝ち N回」に出す。
    public private(set) var handsWon = 0
    private var handsLost = 0
    private var naturalWins = 0

    /// 勝負の通し番号。`restartMatch()` で進む（#727）。広告のあいだに勝負が入れ替わったら、やり直しを乗せない。
    private var matchSerial = 0

    /// 画面に出す「n 回目」。結果を出しているあいだはその回、それ以外はこれから・いま遊んでいる回。
    public var currentRound: Int {
        let round = (phase == .result || matchOver) ? completedRounds : completedRounds + 1
        return min(max(round, 1), format.rounds)
    }

    /// 最後の回の勝負か。配り〜決着後の結果画面まで続く（#2592）。単発戦は 1 回目がそのまま最後の回。
    public var isFinalRound: Bool { currentRound >= format.rounds }

    /// 「最終回」の印（帯の色・バッジ）を出すか。単発戦は最初から最後なので出さない（#2860）。
    public var showsFinalRoundMark: Bool { isFinalRound && format == .tenRounds }

    /// 直近の回で入った勝ち点（手ごとの点の合計）。結果を出していなければ nil。
    public var roundPoints: Int? {
        guard phase == .result, !hands.isEmpty, hands.allSatisfy({ $0.outcome != nil }) else { return nil }
        return hands.reduce(0) { $0 + ($1.outcome.map(blackjackPoints) ?? 0) }
    }

    /// 直近の回が「負けた回」か。勝ち点が 0 で、負け（バストを含む）の手が 1 つでもある回。引き分けだけの回は含めない。
    private var isRoundLost: Bool {
        guard roundPoints == 0 else { return false }
        return hands.contains { $0.outcome == .lose || $0.outcome == .bust }
    }

    /// 結果を出している回が最後の回で、まだ勝負を締めていないか（次の操作が「結果を見る」になる）。
    public var isFinalRoundResult: Bool {
        phase == .result && !matchOver && completedRounds >= format.rounds
    }

    /// 負けた回を、リワード広告と引き換えにやり直せるか（#2552）。1 回の勝負につき 1 回。
    public var canRetryRound: Bool {
        phase == .result && !matchOver && !hasUsedRetry && isRoundLost
    }

    /// 勝負の成績。勝ち点の合計が自己ベストになる。
    ///
    /// Game Center へは送らない（#2552。以前の順位表 `blackjackChips` は勝ち点と意味が違うため、
    /// `GameCenterLeaderboard` の対応表からブラックジャックを外した）。
    private var currentScore: GameScore {
        GameScore(
            metric: .points, points: points, highestValue: bestStreak, variant: format.recordVariant,
            variantLabel: RecordVariantLabels.stored(gameID: gameID, variant: format.recordVariant)
        )
    }

    public var playerValue: Int { handValue(playerHand) }
    public var dealerValue: Int { handValue(dealerHand) }
    public var dealerVisibleValue: Int {
        guard dealerHand.count >= 2 else { return handValue(dealerHand) }
        return handValue([dealerHand[0]])
    }

    private var deck: [BlackjackCard] = []
    let gameID = "blackjack"
    private let services: GameServices?
    private var seed: UInt64?

    /// ディーラーが1枚引くごとの間（#667）。`.zero` なら従来どおりその場で引き切る。
    private let dealerDrawInterval: Duration
    /// 1枚ずつ引いている最中の `Task`。「結果まで進める」とやり直しで止める。
    private(set) var dealerTask: Task<Void, Never>?
    /// 配った 2 枚で 21 が出て、伏せ札を一度見せてから結果に進むまでの待ち（#2700）。
    /// 待っているあいだは操作を受けない。
    public private(set) var isRevealingNatural = false

    /// - Parameters:
    ///   - seed: テスト用の固定種。nil ならシステムの乱数を使う。
    ///   - dealerDrawInterval: ディーラーの引きの間。画面は `BlackjackMotion.dealerDrawInterval` を渡す。
    ///     既定の `.zero` は待たずに引き切る（テストの決定性のため）。
    public init(services: GameServices? = nil, seed: UInt64? = nil, dealerDrawInterval: Duration = .zero) {
        self.services = services
        self.seed = seed
        self.dealerDrawInterval = dealerDrawInterval
        if let snap = services?.snapshots.load(BlackjackSnapshot.self, for: gameID) {
            restore(snap)
        } else if services?.snapshots.exists(for: gameID) == true {
            // 読めない中断データ（#2552 より前の形式など）は続きにならない。残すと「続きから」に数えられるので消す。
            services?.snapshots.clear(for: gameID)
        }
        // ディーラーが引いている途中で中断していたら、その続きから引く（#667）。
        if phase == .dealerTurn {
            runDealer()
        } else if phase == .playerTurn, hands.count == 1, isBlackjack(playerHand) || isBlackjack(dealerHand) {
            // 21 が出た回の演出中に離れていたら、その回は配った時点で決着済みとして結果から始める（#2973）。
            resolveAll()
        }
    }

    private func restore(_ snap: BlackjackSnapshot) {
        let snapFormat = snap.format ?? .tenRounds
        let valid = !snap.hands.isEmpty
            && snap.phase != .ready
            && (0...snapFormat.rounds).contains(snap.completedRounds)
            && snap.points >= 0
        guard valid else {
            services?.snapshots.clear(for: gameID)
            return
        }
        format = snapFormat
        completedRounds = snap.completedRounds
        points = snap.points
        streak = max(0, snap.streak)
        bestStreak = max(snap.bestStreak, streak)
        hasUsedRetry = snap.hasUsedRetry
        streakBeforeRound = max(0, snap.streakBeforeRound)
        handsWon = max(0, snap.handsWon)
        handsLost = max(0, snap.handsLost)
        naturalWins = max(0, snap.naturalWins)
        hands = snap.hands
        activeHandIndex = min(max(snap.activeHandIndex, 0), snap.hands.count - 1)
        dealerHand = snap.dealerHand
        deck = snap.deck
        phase = snap.phase
        if phase == .result {
            outcome = summaryOutcome()
            // 最後の回の結果で止まっていて、やり直しも選べないなら、その場で勝負を締める。
            if completedRounds >= format.rounds && !canRetryRound {
                finishMatch()
            }
        }
    }

    private func persist() {
        // 1 回目を配る前・勝負を締めたあとは続きが無い。
        guard !matchOver, phase != .ready else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = BlackjackSnapshot(
            completedRounds: completedRounds,
            points: points,
            streak: streak,
            bestStreak: bestStreak,
            hasUsedRetry: hasUsedRetry,
            streakBeforeRound: streakBeforeRound,
            handsWon: handsWon,
            handsLost: handsLost,
            naturalWins: naturalWins,
            hands: hands,
            activeHandIndex: activeHandIndex,
            dealerHand: dealerHand,
            deck: deck,
            phase: phase,
            format: format
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - Deal

    /// 1 回目を配る。形は 10 回勝負か単発戦（#2860）。2 回目以降は `nextRound()` が配る。
    public func deal(format: BlackjackMatchFormat = .tenRounds) {
        guard phase == .ready, !matchOver, completedRounds < format.rounds else { return }
        // 10 回勝負は 10 回で 1 プレイ・単発戦は 1 回で 1 プレイ（`gameDidFinish` は最後の回のあとに 1 回だけ呼ぶ）。
        // 1 回目でいきなりブラックジャックの決着になっても `game_start` が先に立つよう、判定より前に数える（#158）。
        if completedRounds == 0 {
            self.format = format
            services?.gameDidRestart(gameID: gameID, mode: format.analyticsMode)
        }
        dealRound()
    }

    private func dealRound() {
        deck = shuffledDeck()
        hands = [BlackjackHand(id: 0, cards: [drawCard(), drawCard()])]
        activeHandIndex = 0
        dealerHand = [drawCard(), drawCard()]
        outcome = nil
        phase = .playerTurn
        // 配った時点で勝負は動いている。ここから捨てれば途中離脱として数える（#500）。
        services?.gameDidProgress(gameID: gameID)

        services?.feedback.impact(.card(.deal)) // カードを配る（21 が出た回も鳴らす。#2700）

        // ディーラーのナチュラルも配った時点で見る（標準ルール）。
        // プレイヤーもナチュラルならプッシュ（`blackjackSettlement`）。
        if isBlackjack(playerHand) || isBlackjack(dealerHand) {
            resolveNaturalAfterDeal()
            return
        }
        persist()
    }

    /// 21 が出た回の決着。画面用の間があるときは、配りが終わって伏せ札が一度描かれてから結果に進む（#2700）。
    /// 間が `.zero`（テスト）なら従来どおりその場で決着する。
    private func resolveNaturalAfterDeal() {
        guard dealerDrawInterval > .zero else {
            resolveAll()
            return
        }
        isRevealingNatural = true
        // 演出の待ちの間に離れても配った札とフェーズを失わない。保存が直前の回のままだと、復元で前の結果画面に戻る（#2973）。
        persist()
        let wait = Duration.seconds(BlackjackMotion.dealTotalDuration) + dealerDrawInterval
        dealerTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self, self.isRevealingNatural else { return }
            self.dealerTask = nil
            self.isRevealingNatural = false
            self.resolveAll()
        }
    }

    // MARK: - Player Actions

    public func hit() {
        guard phase == .playerTurn, !isRevealingNatural, hands.indices.contains(activeHandIndex) else { return }
        hands[activeHandIndex].cards.append(drawCard())
        guard hands[activeHandIndex].isBusted else {
            services?.feedback.impact(.card(.deal)) // 1枚引く
            persist()
            return
        }
        hands[activeHandIndex].isDone = true
        // スプリットで次の手が残っているなら、この手だけが飛んだことを伝える
        // （回全体の決着音は `resolveAll()` が鳴らすので二重に鳴らさない）。
        if hasPendingHand { services?.feedback.notify(.error) }
        advanceHand()
    }

    public func stand() {
        guard phase == .playerTurn, !isRevealingNatural, hands.indices.contains(activeHandIndex) else { return }
        // 札が動かない操作なので、触覚が押せた唯一の手応え（ディーラーの引きは CPU なので鳴らさない・#2540）。
        services?.feedback.impact(.light)
        hands[activeHandIndex].isDone = true
        advanceHand()
    }

    // MARK: - Split (#439)

    /// スプリットできるか（同じ点数の2枚。**再スプリットは不可**）。
    ///
    /// 判定はランクではなく**点数**で行う（#497）。10・J・Q・K はどれも 10 点なので、
    /// 10 と K のような組み合わせも割れる。A は 11 点で他と重ならないため、
    /// この判定でも「A のペア」だけが A のスプリットになる。
    public var canSplit: Bool {
        guard phase == .playerTurn, !isRevealingNatural, hands.count == 1, let hand = activeHand else { return false }
        return hand.cards.count == 2 && !hand.isDone && hand.cards[0].value == hand.cards[1].value
    }

    /// 同じ点数の2枚を2つの手に分け、1枚ずつ配る。分けた手はそれぞれ勝てば 1 点（#2552）。
    ///
    /// 標準的な簡略化として **スプリットしたAは1枚だけで強制スタンド**（引き直せない）、
    /// **再スプリット不可**（`canSplit` が `hands.count == 1` を要求する）とする。
    /// 分けた手で作った21はナチュラルにならない（判定は `settleHand` が担う）。
    public func split() {
        guard canSplit, let source = activeHand else { return }
        let splittingAces = source.cards[0].rank == 1
        var first = BlackjackHand(id: 0, cards: [source.cards[0], drawCard()], isFromSplit: true)
        var second = BlackjackHand(id: 1, cards: [source.cards[1], drawCard()], isFromSplit: true)
        if splittingAces {
            first.isDone = true
            second.isDone = true
        }
        hands = [first, second]
        activeHandIndex = 0
        services?.feedback.impact(.card(.deal))
        if hands[0].isDone {
            advanceHand()
        } else {
            persist()
        }
    }

    // MARK: - Hand Progression

    private var activeHand: BlackjackHand? {
        hands.indices.contains(activeHandIndex) ? hands[activeHandIndex] : nil
    }

    /// いまの手より後ろに、まだ操作していない手が残っているか。
    private var hasPendingHand: Bool {
        hands.indices.contains { $0 > activeHandIndex && !hands[$0].isDone }
    }

    /// 次の手へ進む。全部終わっていればディーラーの番（全滅していれば即決着）へ移る。
    private func advanceHand() {
        if let next = hands.indices.first(where: { $0 > activeHandIndex && !hands[$0].isDone }) {
            activeHandIndex = next
            persist()
            return
        }
        // どの手も残っていなければディーラーは引く必要がない（従来のバストと同じ扱い）。
        guard hands.contains(where: { !$0.isBusted }) else {
            resolveAll()
            return
        }
        phase = .dealerTurn
        runDealer()
    }

    // MARK: - Dealer AI (17以上でスタンド)

    private func runDealer() {
        guard dealerDrawInterval > .zero else {
            drawDealerToStand()
            resolveAll()
            return
        }
        persist()
        startDealerDraws()
    }

    /// ディーラーを1枚ずつ引かせる（#667）。一気に引き切ると結果だけが瞬間的に出て、勝った実感が残らない。
    ///
    /// 伏せカードの公開 → 間 → 1枚 → 間 → … → 間 → 決着、の順に進む。17 以上で最初から止まる手でも
    /// 1回ぶん間を置き、公開の直後に勝敗が出ないようにする。決着（勝ち点・記録）は従来どおり
    /// `resolveAll()` の1か所だけで、引き終わってから1回だけ走る。
    ///
    /// ディーラーの引きは CPU の手番なので触覚は鳴らさない（指が触れていない間の振動を避ける規約。
    /// `FeedbackCPUSilentTests`）。決着の notify は `resolveAll()` が従来どおり鳴らす。
    private func startDealerDraws() {
        let interval = dealerDrawInterval
        dealerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: interval)
                // 「結果まで進める」・やり直しで止められたか、画面ごと捨てられた。
                guard !Task.isCancelled, let self, self.phase == .dealerTurn else { return }
                guard handValue(self.dealerHand) < 17 else {
                    self.dealerTask = nil
                    self.resolveAll()
                    return
                }
                self.dealerHand.append(self.drawCard())
                self.persist()
            }
        }
    }

    /// 「結果まで進める」（#667）。ディーラーの残りを待たずに引き切って決着させる。
    /// 引く札は待った場合と同じ（山札の順に引くだけ）なので、飛ばしても結果は変わらない。
    public func skipDealerDraws() {
        guard phase == .dealerTurn else { return }
        dealerTask?.cancel()
        dealerTask = nil
        drawDealerToStand()
        resolveAll()
    }

    private func drawDealerToStand() {
        while handValue(dealerHand) < 17 {
            dealerHand.append(drawCard())
        }
    }

    // MARK: - Result

    /// 手1つぶんの勝敗。バストは相手を見るまでもなく負け。
    private func settleHand(_ hand: BlackjackHand) -> BlackjackOutcome {
        if hand.isBusted { return .bust }
        return blackjackSettlement(player: hand.cards, dealer: dealerHand, allowsPlayerNatural: !hand.isFromSplit)
    }

    /// 回全体のまとめ。手が1つならその結果。スプリットした回は、勝ち点が入れば勝ち・負けた手があれば負け・それ以外は引き分け。
    private func summaryOutcome() -> BlackjackOutcome? {
        guard !hands.isEmpty, hands.allSatisfy({ $0.outcome != nil }) else { return nil }
        if hands.count == 1 { return hands[0].outcome }
        if (roundPoints ?? 0) > 0 { return .win }
        return hands.contains { $0.outcome == .lose || $0.outcome == .bust } ? .lose : .push
    }

    private func resolveAll() {
        for index in hands.indices {
            hands[index].outcome = settleHand(hands[index])
        }
        phase = .result
        let gained = roundPoints ?? 0
        streakBeforeRound = streak
        points += gained
        completedRounds += 1
        handsWon += hands.filter { $0.outcome == .win || $0.outcome == .playerBlackjack }.count
        handsLost += hands.filter { $0.outcome == .lose || $0.outcome == .bust }.count
        naturalWins += hands.filter { $0.outcome == .playerBlackjack }.count
        if gained > 0 {
            streak += 1
            bestStreak = max(bestStreak, streak)
        } else {
            streak = 0
        }
        outcome = summaryOutcome()

        switch outcome {
        case .playerBlackjack, .win: services?.feedback.notify(.success)
        case .push:                  services?.feedback.notify(.warning)
        default:                     services?.feedback.notify(.error)
        }
        // 10 回目を終えたら勝負を締める。負けた 10 回目でやり直しが残っていれば、選んでもらうまで締めない
        // （締めてからやり直すと、記録と `game_end` が二重になる）。
        if completedRounds >= format.rounds && !canRetryRound {
            finishMatch()
            return
        }
        persist()
    }

    /// 10 回の合計で 1 回の決着をつける（#2552）。記録・解析（`game_end`）・評価リクエストはここで 1 回だけ。
    private func finishMatch() {
        guard !matchOver else { return }
        matchOver = true
        let result: GameOutcome
        if format == .single {
            // 単発戦は 1 回の結果がそのまま勝負の結果（スプリットで一勝一敗でも、点が入れば勝ち。結果画面の見出しと揃える）。
            switch outcome {
            case .playerBlackjack, .win: result = .win
            case .lose, .bust:           result = .loss
            default:                     result = .draw
            }
        } else {
            result = handsWon > handsLost ? .win : (handsWon < handsLost ? .loss : .draw)
        }
        matchOutcome = result
        // 評価リクエストの見せ場は、ブラックジャックで勝った回を含む勝負に勝ち越したとき（#1471 の「ブラックジャックで勝った」を
        // 10 回勝負へ移したもの。普通に勝ち越しただけでは絞る）。
        recordResult = services?.gameDidFinish(
            gameID: gameID,
            outcome: result,
            score: currentScore,
            isReviewHighlight: result == .win && naturalWins > 0
        )
        persist()
    }

    // MARK: - 決着の表示（#1754）

    /// 決着した回の、卓の中央に出す結果。`.result` でなければ nil。
    ///
    /// 見出しは `outcome`（`resolveAll` が手ごとの勝敗から出したまとめ）で決め、入った勝ち点を理由の行に添える。
    /// スプリットで手ごとに勝敗が割れても、表示と実際の点は食い違わない。
    public var handResult: HandResult? {
        guard phase == .result, let outcome else { return nil }
        let kind: HandResult.Kind
        let headline: String
        switch outcome {
        case .playerBlackjack: (kind, headline) = (.win, tr("ブラックジャック！"))
        case .win:             (kind, headline) = (.win, tr("勝ち！"))
        case .push:            (kind, headline) = (.draw, tr("引き分け"))
        case .lose, .bust:     (kind, headline) = (.lose, tr("負け"))
        }
        let reason: String
        if hands.count > 1 {
            reason = hands.enumerated().map { index, hand in
                tr("ハンド%lld %@", index + 1, hand.outcome.map(Self.shortLabel) ?? "")
            }.joined(separator: " / ")
        } else {
            reason = singleHandReason(outcome)
        }
        // 入った点は理由文に埋めず、幕の大きな増減欄に出す（#2702）。点が入らない回（負け・引き分け）は出さない。
        let gained = roundPoints.flatMap { $0 > 0 ? $0 : nil }
        return HandResult(
            kind: kind, headline: headline, reason: reason, chipDelta: gained, unit: .points,
            spokenResult: BlackjackAccessibility.outcomeAnnouncement(outcome: outcome, isSplit: hands.count > 1)
        )
    }

    private static func shortLabel(_ outcome: BlackjackOutcome) -> String {
        switch outcome {
        case .playerBlackjack: return tr("ブラックジャック")
        case .win:             return tr("勝ち")
        case .push:            return tr("引き分け")
        case .lose:            return tr("負け")
        case .bust:            return tr("バスト")
        }
    }

    /// 手が 1 つのときの理由 1 行（例: "21 対 19" / "バスト（24）"）。
    private func singleHandReason(_ outcome: BlackjackOutcome) -> String {
        switch outcome {
        case .bust:
            return tr("バスト（%lld）", playerValue)
        case .playerBlackjack:
            return tr("最初の2枚で21")
        case .win where dealerValue > 21:
            return tr("ディーラーがバスト（%lld）", dealerValue)
        case .lose where isBlackjack(dealerHand):
            return tr("ディーラーがブラックジャック")
        default:
            return tr("あなた%1$lld 対 ディーラー%2$lld", playerValue, dealerValue)
        }
    }

    // MARK: - Next Round

    /// 次の回を配る。最後の回の結果からは、勝負を締めて記録をつける（「結果を見る」）。
    public func nextRound() {
        guard phase == .result, !matchOver else { return }
        if completedRounds >= format.rounds {
            finishMatch()
            return
        }
        dealRound()
    }

    // MARK: - Reward Ad Retry (#2552)

    /// リワード広告を表示し、**視聴完了したときだけ**負けた回をやり直す（#2552）。
    ///
    /// - **負けた回の結果を出しているときだけ**効く（勝ち点が 0 で、負けの手がある回）。引き分けだけの回は対象外。
    /// - **1 回の勝負につき 1 回**（`hasUsedRetry`）。中断を挟んでも戻らない（中断データに持ち回る）。
    /// - やり直すと、その回は無かったことになる（回数・連勝・勝ち越しの数を戻し、新しく配り直す）。
    ///   負けた回は勝ち点が 0 なので、合計点は動かない。
    /// - 視聴しなかった・読み込めなかったときは何も変えず `.notEarned`。
    /// - 広告のあいだに勝負が入れ替わった・次の回へ進んだなど、やり直せる状態でなくなっていたら `.unavailable`（#727）。
    /// - services 未注入時（プレビュー・テスト）は広告機構自体が無いため、そのままやり直す。
    public func retryRoundAfterAd() async -> RewardedModelOutcome {
        guard canRetryRound else { return .unavailable }
        let serialBeforeAd = matchSerial
        let roundBeforeAd = completedRounds
        // 画面の世代（#653）。広告のロード中にハブへ戻られたら、このモデルは捨てられている。
        let generationBeforeAd = services?.screenGeneration.current
        guard await services?.showRewardedAd(gameID: gameID, purpose: .undo) ?? true else { return .notEarned }
        guard services?.screenGeneration.current == generationBeforeAd else { return .unavailable }
        guard matchSerial == serialBeforeAd, completedRounds == roundBeforeAd, canRetryRound else { return .unavailable }
        handsWon -= hands.filter { $0.outcome == .win || $0.outcome == .playerBlackjack }.count
        handsLost -= hands.filter { $0.outcome == .lose || $0.outcome == .bust }.count
        completedRounds -= 1
        streak = streakBeforeRound
        hasUsedRetry = true
        dealRound()
        return .granted
    }

    // MARK: - Restart

    /// 新しい 10 回勝負に戻す（1 回目を配る前）。
    public func restartMatch() {
        // ディーラーが引いている途中なら止める（#667。新しい勝負の卓に前の回の札が足されない）。
        dealerTask?.cancel()
        dealerTask = nil
        isRevealingNatural = false
        recordResult = nil
        matchSerial += 1
        format = .tenRounds  // 配る前の帯に前の形（単発戦）を残さない（次の形は `deal(format:)` が決める）
        completedRounds = 0
        points = 0
        streak = 0
        bestStreak = 0
        streakBeforeRound = 0
        handsWon = 0
        handsLost = 0
        naturalWins = 0
        hasUsedRetry = false
        matchOver = false
        matchOutcome = nil
        outcome = nil
        hands = []
        activeHandIndex = 0
        dealerHand = []
        phase = .ready
        services?.snapshots.clear(for: gameID)
    }

    // MARK: - Deck

    private func makeDeck() -> [BlackjackCard] {
        var cards: [BlackjackCard] = []
        var id = 0
        for suit in BlackjackSuit.allCases {
            for rank in 1...13 {
                cards.append(BlackjackCard(id: id, suit: suit, rank: rank))
                id += 1
            }
        }
        return cards
    }

    /// 山札を切る。`seed` があるときは決定的に切り、次の配りが同じにならないよう種を進める。
    private func shuffledDeck() -> [BlackjackCard] {
        var cards = makeDeck()
        if let current = seed {
            var generator = BlackjackSeededGenerator(seed: current)
            cards.shuffle(using: &generator)
            seed = generator.next()
        } else {
            cards.shuffle()
        }
        return cards
    }

    private func drawCard() -> BlackjackCard {
        if deck.isEmpty { deck = shuffledDeck() }
        return deck.removeFirst()
    }
}

// MARK: - Seeded RNG

/// テスト用の決定的な乱数生成器（CoreEngine の `SplitMix64`・#1074）。本番は `seed` を渡さないので system の乱数を使う。
typealias BlackjackSeededGenerator = SplitMix64
