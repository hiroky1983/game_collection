import Foundation
import Observation
import Core

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
    public private(set) var firstFlippedIndex: Int? = nil
    /// ターン交代時のみインクリメントし task(id:) の再起動トリガーとして使う
    public private(set) var turnID: Int = 0
    public private(set) var isGameOver: Bool = false
    public private(set) var lastMatchedIndices: [Int] = []
    public private(set) var mismatchedIndices: [Int] = []
    public private(set) var mattaUsed: Bool = false

    public var winner: ConcentrationPlayer? {
        guard isGameOver else { return nil }
        if playerScore > cpuScore { return .human }
        if cpuScore > playerScore { return .cpu }
        return nil
    }
    public var isDraw: Bool { isGameOver && playerScore == cpuScore }
    public var isHumanTurn: Bool { currentPlayer == .human }
    public var canMatta: Bool { !isGameOver && isHumanTurn && !mismatchedIndices.isEmpty }

    private let services: GameServices?
    private var ai: ConcentrationAI = ConcentrationAI(accuracy: 0.6)

    public init(services: GameServices? = nil) {
        self.services = services
        setupGame(pairCount: .medium, cpuLevel: .normal)
    }

    // MARK: - Public Actions

    public func tap(index: Int) {
        guard currentPlayer == .human, !isThinking else { return }
        guard !cards[index].isFaceUp, !cards[index].isMatched else { return }
        guard mismatchedIndices.isEmpty else { return }
        flipCard(index: index)
    }

    public func clearMismatch() {
        guard !mismatchedIndices.isEmpty else { return }
        for i in mismatchedIndices { cards[i].isFaceUp = false }
        mismatchedIndices = []
        currentPlayer = currentPlayer.next
        turnID += 1
    }

    /// ミスマッチを取り消してプレイヤーのターンを継続する（ターン交代なし）
    public func useMatta() {
        guard canMatta else { return }
        for i in mismatchedIndices { cards[i].isFaceUp = false }
        mismatchedIndices = []
        mattaUsed = true
        // currentPlayer・turnID は変えない（onChange の clearMismatch は guard で空振りする）
    }

    public func newGame(pairCount: ConcentrationPairCount, cpuLevel: ConcentrationCPULevel) {
        setupGame(pairCount: pairCount, cpuLevel: cpuLevel)
    }

    public func performCPUMoveIfNeeded() async {
        guard currentPlayer == .cpu, !isThinking, !isGameOver else { return }
        await doCPUTurn()
    }

    // MARK: - Private

    private func doCPUTurn() async {
        isThinking = true
        defer { isThinking = false }

        while currentPlayer == .cpu && !isGameOver {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard currentPlayer == .cpu, !isGameOver else { return }

            let first = ai.chooseCard(cards: cards, firstFlipped: nil)
            flipCard(index: first)

            try? await Task.sleep(nanoseconds: 700_000_000)
            guard currentPlayer == .cpu, !isGameOver else { return }

            let second = ai.chooseCard(cards: cards, firstFlipped: first)
            flipCard(index: second)

            if !mismatchedIndices.isEmpty {
                try? await Task.sleep(nanoseconds: 900_000_000)
                clearMismatch()
                return
            }

            if isGameOver { return }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func setupGame(pairCount: ConcentrationPairCount, cpuLevel: ConcentrationCPULevel) {
        self.pairCount = pairCount
        self.cpuLevel = cpuLevel
        ai = ConcentrationAI(accuracy: cpuLevel.memoryAccuracy)
        playerScore = 0
        cpuScore = 0
        currentPlayer = .human
        firstFlippedIndex = nil
        turnID = 0
        isGameOver = false
        lastMatchedIndices = []
        mismatchedIndices = []
        mattaUsed = false

        let symbols = Array(concentrationSymbols.prefix(pairCount.rawValue))
        let doubled = (symbols + symbols).shuffled()
        cards = doubled.enumerated().map { ConcentrationCard(id: $0.offset, symbol: $0.element) }
    }

    private func flipCard(index: Int) {
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
            } else {
                lastMatchedIndices = []
                mismatchedIndices = [first, index]
            }
        } else {
            firstFlippedIndex = index
            lastMatchedIndices = []
        }
    }

    private func checkGameOver() {
        if cards.allSatisfy({ $0.isMatched }) {
            isGameOver = true
        }
    }
}
