import Foundation
import Observation
import Core

// MARK: - Card

public enum BlackjackSuit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs
    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }
    public var isRed: Bool { self == .hearts || self == .diamonds }
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

    public var playerValue: Int { handValue(playerHand) }
    public var dealerValue: Int { handValue(dealerHand) }
    public var dealerVisibleValue: Int {
        guard dealerHand.count >= 2 else { return handValue(dealerHand) }
        return handValue([dealerHand[0]])
    }

    private var deck: [BlackjackCard] = []
    private let gameID = "blackjack"
    private let services: GameServices?

    public init(services: GameServices? = nil) {
        self.services = services
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
        guard phase == .betting, chips >= amount, amount > 0 else { return }
        bet = amount
        deal()
    }

    // MARK: - Deal

    private func deal() {
        deck = makeDeck().shuffled()
        playerHand = [drawCard(), drawCard()]
        dealerHand = [drawCard(), drawCard()]
        phase = .playerTurn

        if isBlackjack(playerHand) {
            resolveResult()
            return
        }
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
            checkSessionOver()
            persist()
        } else {
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

    public func recoverChipsAfterAd() {
        Task {
            await services?.ads.showInterstitial()
            chips = 500
            sessionOver = false
            outcome = nil
            playerHand = []
            dealerHand = []
            bet = 0
            phase = .betting
        }
    }

    // MARK: - Restart

    public func restartSession() {
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

    private func drawCard() -> BlackjackCard {
        if deck.isEmpty { deck = makeDeck().shuffled() }
        return deck.removeFirst()
    }
}
