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

// MARK: - Game Phase

public enum BlackjackPhase: String, Equatable, Sendable, Codable {
    case idle, betting, playerTurn, dealerTurn, result
}

public enum BlackjackOutcome: String, Sendable, Codable {
    case playerBlackjack, win, push, lose, bust
}

// MARK: - Snapshot

struct BlackjackSnapshot: Codable {
    let playerHand: [BlackjackCard]
    let dealerHand: [BlackjackCard]
    let deck: [BlackjackCard]
    let chips: Int
    let bet: Int
    let phase: BlackjackPhase
}

// MARK: - Model

@MainActor
@Observable
public final class BlackjackModel {
    public private(set) var playerHand: [BlackjackCard] = []
    public private(set) var dealerHand: [BlackjackCard] = []
    public private(set) var chips: Int = 1000
    public private(set) var bet: Int = 0
    public private(set) var phase: BlackjackPhase = .betting
    public private(set) var outcome: BlackjackOutcome? = nil
    public private(set) var sessionOver: Bool = false
    /// 直近のラウンドで確定した自己ベスト（#115）。リザルトに1行出す。
    public private(set) var recordResult: RecordResult?

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
    private var currentScore: GameScore {
        GameScore(metric: .points, points: chips)
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
            self.playerHand = snap.playerHand
            self.dealerHand = snap.dealerHand
            self.deck       = snap.deck
            self.chips      = snap.chips
            self.bet        = snap.bet
            self.phase      = snap.phase
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
            phase: phase
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
        bet = amount
        deal()
    }

    // MARK: - Deal

    private func deal() {
        deck = shuffledDeck()
        playerHand = [drawCard(), drawCard()]
        dealerHand = [drawCard(), drawCard()]
        phase = .playerTurn
        // 1 ラウンド = 1 プレイ（`gameDidFinish` もラウンドごとに呼んでいる）。
        // 決着が即決まるブラックジャックでも `game_start` が先に立つよう、判定より前に数える（#158）。
        services?.gameDidRestart(gameID: gameID)

        if isBlackjack(playerHand) {
            resolveResult()
            return
        }
        services?.feedback.impact(.medium) // カードを配る
        persist()
    }

    // MARK: - Player Actions

    public func hit() {
        guard phase == .playerTurn else { return }
        playerHand.append(drawCard())
        if playerValue > 21 {
            outcome = .bust
            chips -= bet
            bet = 0
            phase = .result
            services?.feedback.notify(.error)
            recordResult = services?.gameDidFinish(gameID: gameID, outcome: .loss, score: currentScore)
            checkSessionOver()
            persist()
        } else {
            services?.feedback.impact(.light) // 1枚引く
            persist()
        }
    }

    public func stand() {
        guard phase == .playerTurn else { return }
        phase = .dealerTurn
        runDealer()
    }

    // MARK: - Dealer AI (17以上でスタンド)

    private func runDealer() {
        while handValue(dealerHand) < 17 {
            dealerHand.append(drawCard())
        }
        resolveResult()
    }

    // MARK: - Result

    private func resolveResult() {
        let pVal = playerValue
        let dVal = dealerValue

        if isBlackjack(playerHand) && !isBlackjack(dealerHand) {
            // ブラックジャック: 1.5倍払い
            let payout = Int(Double(bet) * 1.5)
            chips += payout
            outcome = .playerBlackjack
        } else if isBlackjack(playerHand) && isBlackjack(dealerHand) {
            outcome = .push
        } else if dVal > 21 || pVal > dVal {
            chips += bet
            outcome = .win
        } else if pVal == dVal {
            outcome = .push
        } else {
            chips -= bet
            outcome = .lose
        }

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
        if chips <= 0 {
            chips = 0
            sessionOver = true
        }
    }

    // MARK: - Next Round

    public func nextRound() {
        guard !sessionOver else { return }
        outcome = nil
        playerHand = []
        dealerHand = []
        bet = 0
        phase = .betting
    }

    // MARK: - Reward Ad Recovery

    /// リワード広告を表示し、**視聴完了したときだけ**チップを回復する。
    /// 視聴中断・ロード失敗時は何も変更せず false を返す（呼び出し側でユーザーに通知する）。
    /// services 未注入時（プレビュー・テスト）は広告機構自体が無いため従来どおり回復させる。
    @discardableResult
    public func recoverChipsAfterAd() async -> Bool {
        guard await services?.ads.showRewardedAd() ?? true else { return false }
        chips = 500
        sessionOver = false
        outcome = nil
        playerHand = []
        dealerHand = []
        bet = 0
        phase = .betting
        return true
    }

    // MARK: - Restart

    public func restartSession() {
        recordResult = nil
        chips = 1000
        sessionOver = false
        outcome = nil
        playerHand = []
        dealerHand = []
        bet = 0
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
