import Foundation
import Observation
import Core

// MARK: - Card

public enum PokerSuit: Int, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs
    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }
    public var isRed: Bool { self == .hearts || self == .diamonds }
}

public struct PokerCard: Identifiable, Codable, Sendable, Equatable {
    public let id: Int           // 0–51
    public let suit: PokerSuit
    public let rank: Int         // 2–14 (A=14)

    public var rankLabel: String {
        switch rank {
        case 14: return "A"
        case 13: return "K"
        case 12: return "Q"
        case 11: return "J"
        case 10: return "10"
        default: return "\(rank)"
        }
    }
}

// MARK: - Hand Rank

public enum PokerHandRank: Int, Comparable, CustomStringConvertible, Sendable {
    case highCard = 0, onePair, twoPair, threeOfAKind,
         straight, flush, fullHouse, fourOfAKind, straightFlush, royalFlush

    public static func < (lhs: PokerHandRank, rhs: PokerHandRank) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String {
        switch self {
        case .highCard:      return "ハイカード"
        case .onePair:       return "ワンペア"
        case .twoPair:       return "ツーペア"
        case .threeOfAKind:  return "スリーカード"
        case .straight:      return "ストレート"
        case .flush:         return "フラッシュ"
        case .fullHouse:     return "フルハウス"
        case .fourOfAKind:   return "フォーカード"
        case .straightFlush: return "ストレートフラッシュ"
        case .royalFlush:    return "ロイヤルフラッシュ"
        }
    }
}

// MARK: - Hand Evaluator

struct HandEvaluator {
    static func evaluate(_ cards: [PokerCard]) -> (rank: PokerHandRank, tieBreaker: [Int]) {
        guard cards.count == 5 else { return (.highCard, []) }
        let ranks = cards.map(\.rank).sorted(by: >)
        let suits = cards.map(\.suit)
        let isFlush = Set(suits).count == 1

        // ストレート（A-2-3-4-5 含む）
        let isStraight: Bool
        if Set(ranks).count == 5 && ranks[0] - ranks[4] == 4 {
            isStraight = true
        } else if ranks == [14, 5, 4, 3, 2] {
            isStraight = true
        } else {
            isStraight = false
        }

        // グループ化
        var countMap: [Int: Int] = [:]
        for r in ranks { countMap[r, default: 0] += 1 }
        let groups = countMap.values.sorted(by: >)

        if isFlush && isStraight {
            return ranks[0] == 14 && ranks[1] == 13 ? (.royalFlush, ranks) : (.straightFlush, ranks)
        }
        if groups == [4, 1] { return (.fourOfAKind, sortedTieBreaker(countMap)) }
        if groups == [3, 2] { return (.fullHouse, sortedTieBreaker(countMap)) }
        if isFlush          { return (.flush, ranks) }
        if isStraight       { return (.straight, ranks) }
        if groups == [3, 1, 1] { return (.threeOfAKind, sortedTieBreaker(countMap)) }
        if groups == [2, 2, 1] { return (.twoPair, sortedTieBreaker(countMap)) }
        if groups == [2, 1, 1, 1] { return (.onePair, sortedTieBreaker(countMap)) }
        return (.highCard, ranks)
    }

    static func compare(_ a: [PokerCard], _ b: [PokerCard]) -> Int {
        let ra = evaluate(a); let rb = evaluate(b)
        if ra.rank != rb.rank { return ra.rank > rb.rank ? 1 : -1 }
        for (x, y) in zip(ra.tieBreaker, rb.tieBreaker) {
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    private static func sortedTieBreaker(_ countMap: [Int: Int]) -> [Int] {
        countMap.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key > rhs.key
        }.map(\.key)
    }

    // CPU の捨て牌選択: 残すカードのインデックスセットを返す
    static func cpuKeepIndices(from hand: [PokerCard]) -> Set<Int> {
        let (rank, _) = evaluate(hand)
        var countMap: [Int: [Int]] = [:]
        for (i, c) in hand.enumerated() { countMap[c.rank, default: []].append(i) }

        switch rank {
        case .royalFlush, .straightFlush, .fourOfAKind, .fullHouse, .flush, .straight:
            return Set(0..<5)
        case .threeOfAKind:
            let trip = countMap.first { $0.value.count == 3 }!
            return Set(trip.value)
        case .twoPair:
            let pairs = countMap.filter { $0.value.count == 2 }
            return Set(pairs.flatMap(\.value))
        case .onePair:
            let pair = countMap.first { $0.value.count == 2 }!
            return Set(pair.value)
        case .highCard:
            // フラッシュドロー（同スーツ4枚）があればキープ
            var suitMap: [PokerSuit: [Int]] = [:]
            for (i, c) in hand.enumerated() { suitMap[c.suit, default: []].append(i) }
            if let flushDraw = suitMap.first(where: { $0.value.count == 4 }) {
                return Set(flushDraw.value)
            }
            // ストレートドロー（連続4枚）があればキープ
            let sorted = hand.enumerated().sorted { $0.element.rank > $1.element.rank }
            let ranks = sorted.map(\.element.rank)
            for start in 0..<2 {
                let seq = Array(ranks[start..<start+4])
                if Set(seq).count == 4 && seq[0] - seq[3] == 3 {
                    return Set(sorted[start..<start+4].map(\.offset))
                }
            }
            // Aまたは高カード1枚だけキープ
            if let aceIdx = hand.firstIndex(where: { $0.rank == 14 }) { return [aceIdx] }
            let highIdx = hand.enumerated().max { $0.element.rank < $1.element.rank }!.offset
            return [highIdx]
        }
    }
}

// MARK: - Game Phase

public enum PokerPhase: Equatable, Sendable {
    case idle, dealing, betting1, exchange, cpuExchange, betting2, showdown, result
}

public enum PokerBetAction: Sendable {
    case check, bet(Int), call, raise(Int), fold
}

public enum PokerWinner: Sendable {
    case player, cpu, tie
}

// MARK: - Model

@MainActor
@Observable
public final class PokerModel {
    public private(set) var playerHand: [PokerCard] = []
    public private(set) var cpuHand: [PokerCard] = []
    public private(set) var playerChips: Int = 1000
    public private(set) var cpuChips: Int = 1000
    public private(set) var pot: Int = 0
    public private(set) var phase: PokerPhase = .idle
    public private(set) var winner: PokerWinner? = nil
    public private(set) var playerHandRank: PokerHandRank = .highCard
    public private(set) var cpuHandRank: PokerHandRank = .highCard
    public private(set) var selectedForExchange: Set<Int> = []
    public private(set) var currentBet: Int = 0       // bet level this round
    public private(set) var playerBetInRound: Int = 0
    public private(set) var cpuBetInRound: Int = 0
    public private(set) var cpuFolded: Bool = false
    public private(set) var cpuAction: String = ""

    public var canStartGame: Bool { playerChips > 0 }

    private var deck: [PokerCard] = []
    private let anteAmount = 10
    private let betAmount = 20
    private let services: GameServices?

    public init(services: GameServices? = nil) {
        self.services = services
    }

    // MARK: - Start

    public func startGame() {
        guard playerChips >= anteAmount else { return }
        cpuFolded = false
        winner = nil
        cpuAction = ""
        selectedForExchange = []
        currentBet = 0
        playerBetInRound = 0
        cpuBetInRound = 0

        // アンティ
        playerChips -= anteAmount
        cpuChips -= anteAmount
        pot = anteAmount * 2

        deck = makeDeck().shuffled()
        playerHand = Array(deck.prefix(5))
        cpuHand = Array(deck.dropFirst(5).prefix(5))
        deck = Array(deck.dropFirst(10))

        phase = .betting1
    }

    // MARK: - Betting Round 1 (before exchange)

    public func bet1Action(_ action: PokerBetAction) {
        guard phase == .betting1 else { return }
        switch action {
        case .check:
            playerBetInRound = 0
            cpuBet1Response(playerBet: 0)
        case .bet(let amount):
            guard playerChips >= amount else { return }
            playerChips -= amount
            pot += amount
            playerBetInRound = amount
            cpuBet1Response(playerBet: amount)
        default: break
        }
    }

    private func cpuBet1Response(playerBet: Int) {
        let (cpuRank, _) = HandEvaluator.evaluate(cpuHand)
        if playerBet == 0 {
            // プレイヤーがチェック: CPUもチェック
            cpuAction = "チェック"
            cpuBetInRound = 0
            phase = .exchange
        } else {
            // プレイヤーがベット
            if cpuRank >= .twoPair {
                // コール
                let callAmount = min(playerBet, cpuChips)
                cpuChips -= callAmount
                pot += callAmount
                cpuBetInRound = callAmount
                cpuAction = "コール"
                phase = .exchange
            } else {
                // フォールド
                cpuFolded = true
                cpuAction = "フォールド"
                endRound()
            }
        }
    }

    // MARK: - Exchange

    public func toggleCardSelection(_ card: PokerCard) {
        guard phase == .exchange else { return }
        if selectedForExchange.contains(card.id) {
            selectedForExchange.remove(card.id)
        } else {
            selectedForExchange.insert(card.id)
        }
    }

    public func confirmExchange() {
        guard phase == .exchange else { return }
        // プレイヤー交換
        for i in playerHand.indices where selectedForExchange.contains(playerHand[i].id) {
            if let newCard = deck.first {
                deck.removeFirst()
                playerHand[i] = newCard
            }
        }
        selectedForExchange = []
        phase = .cpuExchange
        performCPUExchange()
    }

    private func performCPUExchange() {
        let keepIdx = HandEvaluator.cpuKeepIndices(from: cpuHand)
        let discardCount = 5 - keepIdx.count
        cpuAction = discardCount == 0 ? "カード交換なし" : "\(discardCount)枚交換"
        var newHand = cpuHand
        for i in newHand.indices where !keepIdx.contains(i) {
            if let newCard = deck.first {
                deck.removeFirst()
                newHand[i] = newCard
            }
        }
        cpuHand = newHand

        currentBet = 0
        playerBetInRound = 0
        cpuBetInRound = 0
        phase = .betting2
    }

    // MARK: - Betting Round 2 (after exchange)

    public func bet2Action(_ action: PokerBetAction) {
        guard phase == .betting2 else { return }
        switch action {
        case .check:
            playerBetInRound = 0
            cpuBet2Response(playerBet: 0)
        case .bet(let amount):
            guard playerChips >= amount else { return }
            playerChips -= amount
            pot += amount
            playerBetInRound = amount
            cpuBet2Response(playerBet: amount)
        case .fold:
            cpuFolded = false
            // プレイヤーがフォールド
            cpuChips += pot
            pot = 0
            winner = .cpu
            cpuAction = "プレイヤーフォールド"
            phase = .result
        default: break
        }
    }

    private func cpuBet2Response(playerBet: Int) {
        let (cpuRank, _) = HandEvaluator.evaluate(cpuHand)
        if playerBet == 0 {
            if cpuRank >= .twoPair {
                // CPUベット
                let amount = min(betAmount, cpuChips)
                cpuChips -= amount
                pot += amount
                cpuBetInRound = amount
                cpuAction = "ベット \(amount)"
                // プレイヤーはコールかフォールドへ → 一時停止してプレイヤーに選択させる
                phase = .betting2
                currentBet = amount
            } else {
                cpuAction = "チェック"
                phase = .showdown
                resolveShowdown()
            }
        } else {
            // プレイヤーがベット → CPUの応答
            if cpuRank >= .onePair {
                let callAmount = min(playerBet, cpuChips)
                cpuChips -= callAmount
                pot += callAmount
                cpuBetInRound = callAmount
                cpuAction = "コール"
                phase = .showdown
                resolveShowdown()
            } else {
                cpuFolded = true
                cpuAction = "フォールド"
                endRound()
            }
        }
    }

    public func callCPUBet() {
        guard phase == .betting2, currentBet > 0 else { return }
        let amount = min(currentBet, playerChips)
        playerChips -= amount
        pot += amount
        playerBetInRound += amount
        currentBet = 0
        phase = .showdown
        resolveShowdown()
    }

    public func foldToCPUBet() {
        guard phase == .betting2, currentBet > 0 else { return }
        cpuChips += pot
        pot = 0
        winner = .cpu
        currentBet = 0
        phase = .result
    }

    // MARK: - Showdown

    private func resolveShowdown() {
        playerHandRank = HandEvaluator.evaluate(playerHand).rank
        cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
        let cmp = HandEvaluator.compare(playerHand, cpuHand)
        if cmp > 0 {
            winner = .player
            playerChips += pot
        } else if cmp < 0 {
            winner = .cpu
            cpuChips += pot
        } else {
            winner = .tie
            playerChips += pot / 2
            cpuChips += pot / 2
        }
        pot = 0
        phase = .result
    }

    // MARK: - End Round (fold by CPU or player)

    private func endRound() {
        playerHandRank = HandEvaluator.evaluate(playerHand).rank
        cpuHandRank = HandEvaluator.evaluate(cpuHand).rank
        if cpuFolded {
            winner = .player
            playerChips += pot
        }
        pot = 0
        phase = .result
    }

    // MARK: - Reward Ad (chip recovery)

    public func recoverChipsAfterAd() {
        Task {
            await services?.ads.showInterstitial()
            playerChips = 500
        }
    }

    public var needsChipRecovery: Bool { playerChips == 0 && phase == .idle }

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
