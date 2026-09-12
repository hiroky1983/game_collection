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

/// 勝敗とチップの増減を決める判定表（#413）。`resolveResult` から切り出した純関数。
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
    bet: Int,
    allowsPlayerNatural: Bool = true
) -> (outcome: BlackjackOutcome, chipDelta: Int) {
    let pVal = handValue(player)
    let dVal = handValue(dealer)
    let playerNatural = allowsPlayerNatural && isBlackjack(player)
    let dealerNatural = isBlackjack(dealer)

    if playerNatural && dealerNatural { return (.push, 0) }
    if playerNatural { return (.playerBlackjack, Int(Double(bet) * 1.5)) }  // 1.5倍払い
    if dealerNatural { return (.lose, -bet) }
    if dVal > 21 || pVal > dVal { return (.win, bet) }
    if pVal == dVal { return (.push, 0) }
    return (.lose, -bet)
}

// MARK: - Game Phase

public enum BlackjackPhase: String, Equatable, Sendable, Codable {
    case idle, betting, playerTurn, dealerTurn, result
}

public enum BlackjackOutcome: String, Sendable, Codable {
    case playerBlackjack, win, push, lose, bust
}

// MARK: - Player Hand

/// プレイヤーの1手（#439）。スプリットすると2つに増え、それぞれ独立にベット・精算する。
struct BlackjackHand: Identifiable, Codable, Sendable, Equatable {
    let id: Int
    var cards: [BlackjackCard]
    /// この手に賭けている額。ダブルダウンで倍になる。
    var bet: Int
    /// スプリットで生まれた手か。**この手の2枚21はナチュラル扱いしない**（標準ルール）。
    var isFromSplit: Bool = false
    /// ダブルダウン済みか（1枚だけ引いて強制スタンド）。
    var isDoubled: Bool = false
    /// プレイヤーの操作が終わった手か（スタンド・ダブル・バスト・スプリットしたA）。
    var isDone: Bool = false
    /// 精算結果。`resolveAll()` で入る。
    var outcome: BlackjackOutcome? = nil

    var value: Int { handValue(cards) }
    var isBusted: Bool { value > 21 }
}

// MARK: - Snapshot

struct BlackjackSnapshot: Codable {
    /// 旧形式（#439 以前）との互換のために残している「今操作している手」の手札。
    let playerHand: [BlackjackCard]
    let dealerHand: [BlackjackCard]
    let deck: [BlackjackCard]
    let chips: Int
    let bet: Int
    let phase: BlackjackPhase
    /// #439 で追加。旧形式のスナップショットには無いので optional にし、
    /// 欠けているときは `playerHand` + `bet` から手を1つ組み立てて読む
    /// （更新前に中断した1局が、復帰時に黙って消えないようにする）。
    let hands: [BlackjackHand]?
    let activeHandIndex: Int?
    /// チップ切れ復活（#499）をこのセッションで使い切ったか。中断を挟んでも
    /// 「1 セッション 1 回まで」を守るために持ち回る（麻雀のトビ復活 #338 と同じ方式）。
    /// **旧データには鍵が無い**ので optional にする（非 optional にすると旧データの
    /// デコードが丸ごと失敗し、中断が黙って消える）。nil は「まだ使っていない」に倒す。
    var hasRevivedThisSession: Bool? = nil
}

// MARK: - Model

@MainActor
@Observable
public final class BlackjackModel {
    /// プレイヤーの手。通常は1つで、スプリットしたときだけ2つになる（#439）。
    private(set) var hands: [BlackjackHand] = []
    /// いま操作している手の位置。スプリット時は 0 → 1 の順に進む。
    private(set) var activeHandIndex: Int = 0

    /// いま操作している手の手札。手が1つのときは従来どおり「プレイヤーの手札」そのもの。
    public var playerHand: [BlackjackCard] {
        hands.indices.contains(activeHandIndex) ? hands[activeHandIndex].cards : []
    }
    public private(set) var dealerHand: [BlackjackCard] = []
    public private(set) var chips: Int = BlackjackModel.initialChips
    /// いま場に出ている総ベット額（スプリット・ダブルダウンで増える）。決着すると 0 に戻る。
    public private(set) var bet: Int = 0
    public private(set) var phase: BlackjackPhase = .betting
    public private(set) var outcome: BlackjackOutcome? = nil
    public private(set) var sessionOver: Bool = false
    /// 直近のラウンドで確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

    // MARK: チップ切れ復活（#499）

    /// セッション開始時の持ちチップ。復活はこの**半分**から再開する。
    static let initialChips = 1000
    /// 復活で戻るチップ。導線の文言もこの値から作る（数え違いを1か所に閉じる）。
    public static let reviveChips = initialChips / 2

    /// いちばん安いベット額。**ベットボタンの並びと破産判定の両方がここを見る**（#656）。
    /// 残高がこれに届かなければ、たとえ 0 枚でなくても打つ手が一つも無い＝そのセッションは
    /// 終わりなので、`checkSessionOver()` はこの値を境にする。
    ///
    /// 50 枚ベットでブラックジャックを引いたときだけ 1.5 倍払いで 25 の端数が生まれるため、
    /// 「0 枚になるまで遊べる」という前提は成り立たない（25 枚だと全ボタンが無効になり、
    /// 破産カードも出ないのでハブに戻る以外の脱出手段が無くなっていた）。
    public static let minimumBet = 50

    /// このセッションで復活を既に使ったか。1 セッション 1 回までの制限に使う。
    private var hasRevivedThisSession = false

    /// チップ切れをリワード広告で 1 回だけ取り消せる状態か（#499）。
    /// 麻雀のトビ復活（#338）と同じで、1 セッション 1 回まで。
    public var canReviveAfterBust: Bool { sessionOver && !hasRevivedThisSession }

    /// 決着の種類（評価リクエスト #53 の判定用。リザルト表示時に参照する）。
    /// プッシュは引き分け、バストは敗北として扱う。
    public var reviewOutcome: GameOutcome {
        switch outcome {
        case .playerBlackjack, .win: return .win
        case .push:                  return .draw
        default:                     return .loss
        }
    }

    /// 今のラウンドの成績。チップは精算後の残高で、これが「最高チップ数」の自己ベストになる。
    ///
    /// 復活（#499）を使ったセッションは順位表へ送らない（ソリティアのジョーカー #406 と同じ思想。
    /// 送ると「広告を何回見たか」の表になる）。**ローカルの自己ベストには残す**ので、
    /// 分けるのは `variant` ではなく `isLeaderboardEligible` のほう。
    private var currentScore: GameScore {
        GameScore(metric: .points, points: chips, isLeaderboardEligible: !hasRevivedThisSession)
    }

    public var playerValue: Int { handValue(playerHand) }
    public var dealerValue: Int { handValue(dealerHand) }
    public var dealerVisibleValue: Int {
        guard dealerHand.count >= 2 else { return handValue(dealerHand) }
        return handValue([dealerHand[0]])
    }

    private var deck: [BlackjackCard] = []
    private let gameID = "blackjack"
    private let services: GameServices?
    private var seed: UInt64?

    /// - Parameter seed: テスト用の固定種。nil ならシステムの乱数を使う。
    public init(services: GameServices? = nil, seed: UInt64? = nil) {
        self.services = services
        self.seed = seed
        if let snap = services?.snapshots.load(BlackjackSnapshot.self, for: "blackjack") {
            self.dealerHand = snap.dealerHand
            self.deck       = snap.deck
            self.chips      = snap.chips
            self.bet        = snap.bet
            self.phase      = snap.phase
            if let saved = snap.hands, !saved.isEmpty {
                self.hands = saved
                self.activeHandIndex = min(max(snap.activeHandIndex ?? 0, 0), saved.count - 1)
            } else if !snap.playerHand.isEmpty {
                // 旧形式（#439 以前）。手は必ず1つで、総ベット額がその手のベット額だった。
                self.hands = [BlackjackHand(id: 0, cards: snap.playerHand, bet: snap.bet)]
                self.activeHandIndex = 0
            }
            // 旧データには鍵が無い。復活が存在しなかった頃の中断なので「未使用」に倒す。
            self.hasRevivedThisSession = snap.hasRevivedThisSession ?? false
            // 手を復元できなければ操作のしようがないので、賭ける前に戻す。
            if self.hands.isEmpty {
                self.phase = .betting
                self.bet = 0
                // 賭けに戻したのに賭けられない残高なら、その場で終わりにする（#656）。
                // 判定を精算のときだけに置くと、賭ける前に戻った局面が
                // 「ボタンが全部無効・破産カードも出ない」で詰む。
                self.checkSessionOver()
            }
        }
    }

    private func persist() {
        guard phase == .playerTurn else {
            services?.snapshots.clear(for: gameID)
            return
        }
        let snap = BlackjackSnapshot(
            playerHand: playerHand,
            dealerHand: dealerHand,
            deck: deck,
            chips: chips,
            bet: bet,
            phase: phase,
            hands: hands,
            activeHandIndex: activeHandIndex,
            hasRevivedThisSession: hasRevivedThisSession
        )
        try? services?.snapshots.save(snap, for: gameID)
    }

    // MARK: - Betting

    public func placeBet(_ amount: Int) {
        guard phase == .betting, amount > 0 else { return }
        guard chips >= amount else {
            services?.feedback.notify(.warning) // チップ不足でベットできない
            return
        }
        deal(bet: amount)
    }

    /// 追加で賭けられる額。`chips` は精算までベットぶんを引かないので、
    /// ダブルダウン・スプリットの可否は「残高 − 場に出ている総額」で見る（#439）。
    private var availableChips: Int { chips - bet }

    // MARK: - Deal

    private func deal(bet amount: Int) {
        deck = shuffledDeck()
        hands = [BlackjackHand(id: 0, cards: [drawCard(), drawCard()], bet: amount)]
        activeHandIndex = 0
        dealerHand = [drawCard(), drawCard()]
        bet = amount
        phase = .playerTurn
        // 1 ラウンド = 1 プレイ（`gameDidFinish` もラウンドごとに呼んでいる）。
        // 決着が即決まるブラックジャックでも `game_start` が先に立つよう、判定より前に数える（#158）。
        services?.gameDidRestart(gameID: gameID)
        // 配った時点でベットは確定済み。ここから捨てれば途中離脱として数える（#500）。
        services?.gameDidProgress(gameID: gameID)

        if isBlackjack(playerHand) {
            resolveAll()
            return
        }
        services?.feedback.impact(.medium) // カードを配る
        persist()
    }

    // MARK: - Player Actions

    public func hit() {
        guard phase == .playerTurn, hands.indices.contains(activeHandIndex) else { return }
        hands[activeHandIndex].cards.append(drawCard())
        guard hands[activeHandIndex].isBusted else {
            services?.feedback.impact(.light) // 1枚引く
            persist()
            return
        }
        hands[activeHandIndex].isDone = true
        // スプリットで次の手が残っているなら、この手だけが飛んだことを伝える
        // （ラウンド全体の決着音は `resolveAll()` が鳴らすので二重に鳴らさない）。
        if hasPendingHand { services?.feedback.notify(.error) }
        advanceHand()
    }

    public func stand() {
        guard phase == .playerTurn, hands.indices.contains(activeHandIndex) else { return }
        hands[activeHandIndex].isDone = true
        advanceHand()
    }

    // MARK: - Double Down / Split (#439)

    /// 手の形としてダブルダウンできるか（最初の2枚のときだけ）。チップ不足でも true を返すので、
    /// ボタンは出したうえで `canDoubleDown` で `disabled` にする。
    public var isDoubleDownApplicable: Bool {
        guard phase == .playerTurn, let hand = activeHand else { return false }
        return hand.cards.count == 2 && !hand.isDone
    }

    /// 実際にダブルダウンできるか（形が合っていて、かつ同額を追加で賭けられる）。
    public var canDoubleDown: Bool {
        guard isDoubleDownApplicable, let hand = activeHand else { return false }
        return availableChips >= hand.bet
    }

    /// 手の形としてスプリットできるか（同じ点数の2枚。**再スプリットは不可**）。
    ///
    /// 判定はランクではなく**点数**で行う（#497）。10・J・Q・K はどれも 10 点なので、
    /// 10 と K のような組み合わせも割れる（標準カジノルール）。A は 11 点で他と重ならないため、
    /// この判定でも「A のペア」だけが A のスプリットになる。
    public var isSplitApplicable: Bool {
        guard phase == .playerTurn, hands.count == 1, let hand = activeHand else { return false }
        return hand.cards.count == 2 && !hand.isDone && hand.cards[0].value == hand.cards[1].value
    }

    /// 実際にスプリットできるか（形が合っていて、かつ同額を追加で賭けられる）。
    public var canSplit: Bool {
        guard isSplitApplicable, let hand = activeHand else { return false }
        return availableChips >= hand.bet
    }

    /// ベット額を倍にして1枚だけ引き、強制スタンドする。
    public func doubleDown() {
        guard canDoubleDown else { return }
        hands[activeHandIndex].bet *= 2
        hands[activeHandIndex].isDoubled = true
        hands[activeHandIndex].cards.append(drawCard())
        hands[activeHandIndex].isDone = true
        bet = totalBet
        services?.feedback.impact(.medium)
        advanceHand()
    }

    /// 同じ点数の2枚を2つの手に分け、それぞれに同額を賭けて1枚ずつ配る。
    ///
    /// 標準的な簡略化として **スプリットしたAは1枚だけで強制スタンド**（引き直せない）、
    /// **再スプリット不可**（`isSplitApplicable` が `hands.count == 1` を要求する）とする。
    /// 分けた手で作った21はナチュラルにならない（精算は `settleHand` が担う）。
    public func split() {
        guard canSplit, let source = activeHand else { return }
        let stake = source.bet
        let splittingAces = source.cards[0].rank == 1
        var first = BlackjackHand(id: 0, cards: [source.cards[0], drawCard()],
                                  bet: stake, isFromSplit: true)
        var second = BlackjackHand(id: 1, cards: [source.cards[1], drawCard()],
                                   bet: stake, isFromSplit: true)
        if splittingAces {
            first.isDone = true
            second.isDone = true
        }
        hands = [first, second]
        activeHandIndex = 0
        bet = totalBet
        services?.feedback.impact(.medium)
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

    private var totalBet: Int { hands.reduce(0) { $0 + $1.bet } }

    /// いまの手より後ろに、まだ操作していない手が残っているか。
    private var hasPendingHand: Bool {
        hands.indices.contains { $0 > activeHandIndex && !hands[$0].isDone }
    }

    /// 次の手へ進む。全部終わっていればディーラーの番（全滅していれば即精算）へ移る。
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
        while handValue(dealerHand) < 17 {
            dealerHand.append(drawCard())
        }
        resolveAll()
    }

    // MARK: - Result

    /// 手1つぶんの精算。バストは相手を見るまでもなく賭け金を失う。
    private func settleHand(_ hand: BlackjackHand) -> (outcome: BlackjackOutcome, chipDelta: Int) {
        if hand.isBusted { return (.bust, -hand.bet) }
        return blackjackSettlement(player: hand.cards, dealer: dealerHand, bet: hand.bet,
                                   allowsPlayerNatural: !hand.isFromSplit)
    }

    private func resolveAll() {
        var totalDelta = 0
        for index in hands.indices {
            let settlement = settleHand(hands[index])
            hands[index].outcome = settlement.outcome
            totalDelta += settlement.chipDelta
        }
        chips += totalDelta
        // 手が1つなら従来どおりその結果をそのまま出す。スプリットしたラウンドは
        // 手ごとに勝敗が割れるので、まとめの表示・評価判定は収支で決める。
        outcome = hands.count == 1
            ? hands.first?.outcome
            : (totalDelta > 0 ? .win : (totalDelta < 0 ? .lose : .push))

        bet = 0
        phase = .result
        switch outcome {
        case .playerBlackjack, .win: services?.feedback.notify(.success)
        case .push:                  services?.feedback.notify(.warning)
        default:                     services?.feedback.notify(.error)
        }
        recordResult = services?.gameDidFinish(gameID: gameID, outcome: reviewOutcome, score: currentScore)
        checkSessionOver()
        services?.snapshots.clear(for: gameID)
    }

    private func checkSessionOver() {
        // 0 枚ではなく「いちばん安いベットに届かない」で終わりにする（#656）。
        // 残高は端数（25 枚）で止まりうるので、`chips = 0` に丸めずそのまま見せる
        // ——チップバーの表示と食い違わせない。
        if chips < BlackjackModel.minimumBet {
            chips = max(0, chips)
            sessionOver = true
        }
    }

    // MARK: - Next Round

    public func nextRound() {
        guard !sessionOver else { return }
        outcome = nil
        clearHands()
        dealerHand = []
        phase = .betting
    }

    /// 手・操作位置・総ベット額をラウンド開始前の状態へ戻す。
    private func clearHands() {
        hands = []
        activeHandIndex = 0
        bet = 0
    }

    // MARK: - Reward Ad Recovery

    /// リワード広告を表示し、**視聴完了したときだけ**チップ切れから復活する（#499）。
    ///
    /// - **チップが尽きたときだけ**効く。まだ遊べる残高で呼んでも広告は出さない
    ///   （プレイヤーが明示的に選んだ救済であって、いつでも押せる増量ボタンではない）。
    /// - **1 セッション 1 回まで**。中断を挟んでも回数は戻らない（`hasRevivedThisSession` を
    ///   スナップショットに持ち回る）。回数が戻るのは `restartSession()` の新しいセッションだけ。
    /// - 視聴中断・ロード失敗時は何も変更せず false を返す（呼び出し側でユーザーに通知する）。
    /// - services 未注入時（プレビュー・テスト）は広告機構自体が無いため従来どおり回復させる。
    @discardableResult
    public func recoverChipsAfterAd() async -> Bool {
        guard canReviveAfterBust else { return false }
        guard await services?.showRewardedAd(gameID: gameID, purpose: .revival) ?? true else { return false }
        hasRevivedThisSession = true
        chips = BlackjackModel.reviveChips
        sessionOver = false
        outcome = nil
        clearHands()
        dealerHand = []
        phase = .betting
        return true
    }

    // MARK: - Restart

    public func restartSession() {
        recordResult = nil
        chips = BlackjackModel.initialChips
        // 新しいセッションなので復活の回数も戻る（#499）。
        hasRevivedThisSession = false
        sessionOver = false
        outcome = nil
        clearHands()
        dealerHand = []
        phase = .betting
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

/// テスト用の決定的な乱数生成器（SplitMix64）。本番は `seed` を渡さないので system の乱数を使う。
struct BlackjackSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
