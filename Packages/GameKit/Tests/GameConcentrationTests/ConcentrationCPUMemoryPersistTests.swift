import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameConcentration

/// CPU の記憶を中断データに持ち回る（#2543）。離れて戻るだけで CPU を弱くできないようにする。
private struct PersistedMemoryProbe: Codable { var cpuMemory: ConcentrationCPUMemory? }

@MainActor
@Suite("神経衰弱 CPU の記憶の持ち回り（#2543）")
struct ConcentrationCPUMemoryPersistTests {

    /// 必ず覚える AI（記憶率 1）で作るモデル
    private func makeModel(services: GameServices) -> ConcentrationModel {
        ConcentrationModel(services: services, autoClearDelay: 40_000_000,
                           aiFactory: { _ in ConcentrationAI(accuracy: 1) })
    }

    @Test("人間が見せた札を CPU が覚え、中断データに書かれて復元される")
    func memorySurvivesResume() throws {
        let store = MemorySnapshotStore()
        let services = GameServices(snapshots: store, ads: NoopAdService())
        let model = makeModel(services: services)
        model.tap(index: 0)
        let symbol = model.cards[0].symbol
        let saved = try #require(store.load(PersistedMemoryProbe.self, for: "concentration")?.cpuMemory)
        #expect(saved.indices == [0])
        #expect(saved.symbols == [symbol])

        let restored = makeModel(services: services)
        #expect(restored.firstFlippedIndex == 0)
        // 復元後の保存にも記憶が残る（往復で消えない）
        restored.tap(index: restored.cards.indices.first { $0 != 0 && restored.cards[$0].symbol != symbol }!)
        let after = try #require(store.load(PersistedMemoryProbe.self, for: "concentration")?.cpuMemory)
        #expect(after.indices.contains(0))
        #expect(after.symbols.first == symbol)
    }

    @Test("AI の記憶は書き出して戻すと同じになり、盤と食い違う項目は捨てる")
    func aiMemoryRoundTripAndValidation() {
        let ai = ConcentrationAI(accuracy: 1)
        ai.observe(index: 0, symbol: "a")
        ai.observe(index: 3, symbol: "b")
        let saved = ai.persistedMemory
        #expect(saved.indices == [0, 3])
        #expect(saved.judged == [0, 3])

        let symbols = ["a", "x", "x", "b"]
        let back = ConcentrationAI(accuracy: 0)
        back.restore(saved, symbols: symbols, isMatched: [false, false, false, false])
        #expect(back.persistedMemory == saved)

        // 絵柄違い・獲得済み・範囲外は戻さない
        let bad = ConcentrationCPUMemory(indices: [0, 3, 9], symbols: ["z", "b", "a"], judged: [0, 3, 9])
        let filtered = ConcentrationAI(accuracy: 0)
        filtered.restore(bad, symbols: symbols, isMatched: [false, false, false, true])
        #expect(filtered.persistedMemory.indices.isEmpty)
        #expect(filtered.persistedMemory.judged == [0, 3])
    }

    @Test("復元後の AI が覚えた札の相方を実際に引く")
    func restoredAIPicksKnownPartner() {
        let cards = ["a", "b", "a", "b"].enumerated().map { ConcentrationCard(id: $0.offset, symbol: $0.element) }
        let ai = ConcentrationAI(accuracy: 1)
        ai.observe(index: 2, symbol: "a")
        let back = ConcentrationAI(accuracy: 0)
        back.restore(ai.persistedMemory, symbols: ["a", "b", "a", "b"], isMatched: [false, false, false, false])
        for _ in 0..<20 {
            #expect(back.chooseCard(cards: cards, firstFlipped: 0) == 2)
        }
    }

    @Test("記憶の項目を持たない旧い中断データは記憶なしとして読める")
    func legacySnapshotWithoutMemoryLoads() throws {
        struct Legacy: Codable {
            var symbols: [String]; var isFaceUp: [Bool]; var isMatched: [Bool]
            var currentPlayer = 0; var playerScore = 0; var cpuScore = 0
            var pairCount = ConcentrationPairCount.small.rawValue
            var cpuLevel = ConcentrationCPULevel.normal.rawValue
            var mattaUsed = false
        }
        let pairs = ConcentrationPairCount.small.rawValue
        let symbols = (0..<pairs).flatMap { [ConcentrationFigure.allCases[$0].rawValue, ConcentrationFigure.allCases[$0].rawValue] }
        let store = MemorySnapshotStore()
        try store.save(Legacy(symbols: symbols, isFaceUp: Array(repeating: false, count: symbols.count),
                              isMatched: Array(repeating: false, count: symbols.count)), for: "concentration")
        let model = makeModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(model.cards.map(\.symbol) == symbols)
    }
}
