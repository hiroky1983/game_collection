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

    @ObservationIgnored private var autoClearTask: Task<Void, Never>?

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
    private let gameID = "concentration"
    private var ai: ConcentrationAI = ConcentrationAI(accuracy: 0.6)

    public init(services: GameServices? = nil) {
        self.services = services
        if let snap = services?.snapshots.load(ConcentrationSnapshot.self, for: "concentration") {
            restoreFrom(snap)
        } else {
            setupGame(pairCount: .medium, cpuLevel: .normal)
        }
    }

    // MARK: - Public Actions

    public func tap(index: Int) {
        guard currentPlayer == .human, !isThinking else { return }
        guard !cards[index].isFaceUp, !cards[index].isMatched else { return }
        guard mismatchedIndices.isEmpty else { return }
        flipCard(index: index)
        persist()

        if !mismatchedIndices.isEmpty {
            autoClearTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled else { return }
                self?.clearMismatch()
            }
        }
    }

    public func clearMismatch() {
        guard !mismatchedIndices.isEmpty else { return }
        autoClearTask?.cancel()
        autoClearTask = nil
        for i in mismatchedIndices { cards[i].isFaceUp = false }
        mismatchedIndices = []
        currentPlayer = currentPlayer.next
        turnID += 1
        persist()
    }

    /// ミスマッチを取り消してプレイヤーのターンを継続する（ターン交代なし）
    public func useMatta() {
        guard canMatta else { return }
        autoClearTask?.cancel()
        autoClearTask = nil
        for i in mismatchedIndices { cards[i].isFaceUp = false }
        mismatchedIndices = []
        mattaUsed = true
        persist()
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
        autoClearTask?.cancel()
        autoClearTask = nil
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
        persist()
    }

    private func restoreFrom(_ snap: ConcentrationSnapshot) {
        pairCount = ConcentrationPairCount(rawValue: snap.pairCount) ?? .medium
        cpuLevel = ConcentrationCPULevel(rawValue: snap.cpuLevel) ?? .normal
        ai = ConcentrationAI(accuracy: cpuLevel.memoryAccuracy)
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
        // firstFlippedIndex や mismatchedIndices はスナップショットに含めないため、
        // 復元時に宙吊りカードが残るとゲームが詰まる。
        for i in cards.indices where cards[i].isFaceUp && !cards[i].isMatched {
            cards[i].isFaceUp = false
        }

        // CPUターン復元：turnID を非ゼロにすることで task(id:) を確実に起動させる
        if currentPlayer == .cpu { turnID = 1 }
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
            mattaUsed: mattaUsed
        )
        try? services?.snapshots.save(snap, for: gameID)
    }
}
