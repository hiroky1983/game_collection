import Testing
import Foundation
@testable import GameConcentration

// MARK: - Helpers

/// 種から決まる擬似乱数（SplitMix64）。記憶判定を決定的に検証するために使う。
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `0..<1` の一様乱数を種から順に返す差し込み口を作る。
private func seededRoll(seed: UInt64) -> () -> Double {
    let box = RollBox(seed: seed)
    return { box.next() }
}

private final class RollBox {
    private var generator: SeededGenerator
    init(seed: UInt64) { generator = SeededGenerator(seed: seed) }
    func next() -> Double { Double.random(in: 0..<1, using: &generator) }
}

/// 決まった値を順に返す差し込み口。使い切ったら最後の値を返し続ける。
private func scriptedRoll(_ values: [Double]) -> () -> Double {
    let box = ScriptBox(values)
    return { box.next() }
}

private final class ScriptBox {
    private var values: [Double]
    private var last: Double
    init(_ values: [Double]) {
        self.values = values
        self.last = values.last ?? 0
    }
    func next() -> Double {
        guard !values.isEmpty else { return last }
        return values.removeFirst()
    }
}

/// 2枚ずつ対になるカード列（index 2i と 2i+1 が同じ絵柄）。すべて裏向き・未獲得。
private func pairedCards(pairs: Int) -> [ConcentrationCard] {
    (0..<pairs)
        .flatMap { ["s\($0)", "s\($0)"] }
        .enumerated()
        .map { ConcentrationCard(id: $0.offset, symbol: $0.element) }
}

/// その札を CPU が覚えているか。
///
/// `memory` は private なので、同じ絵柄の相方を1枚目として `knownMatchFor` に渡し、
/// 記憶から引けるかどうかで見る（相方を覚えているかには左右されない）。
private func remembers(_ ai: ConcentrationAI, index: Int, cards: [ConcentrationCard]) -> Bool {
    let partner = cards.indices.first { $0 != index && cards[$0].symbol == cards[index].symbol }!
    return ai.knownMatchFor(firstIndex: partner, firstSymbol: cards[index].symbol, cards: cards) == index
}

/// 各札を `times` 回ずつ観測し、覚えた札の割合を返す。
private func memorizedRatio(accuracy: Double, pairs: Int, times: Int, seed: UInt64) -> Double {
    let cards = pairedCards(pairs: pairs)
    let ai = ConcentrationAI(accuracy: accuracy, roll: seededRoll(seed: seed))
    for _ in 0..<times {
        for i in cards.indices { ai.observe(index: i, symbol: cards[i].symbol) }
    }
    let remembered = cards.indices.filter { remembers(ai, index: $0, cards: cards) }.count
    return Double(remembered) / Double(cards.count)
}

// MARK: - Tests

@Suite("ConcentrationAI の記憶率")
struct ConcentrationAIMemoryTests {

    @Test("覚え損ねた札は何度めくられても覚えない（記憶率が累積しない・#442）")
    func failedObservationIsNotRetried() {
        let cards = pairedCards(pairs: 1)
        // 1回目は外し、以降はすべて当たりになる乱数列。判定を繰り返せば必ず覚えてしまう。
        let ai = ConcentrationAI(accuracy: 0.3, roll: scriptedRoll([0.9, 0.0]))

        for _ in 0..<50 { ai.observe(index: 0, symbol: cards[0].symbol) }

        #expect(remembers(ai, index: 0, cards: cards) == false)
    }

    @Test("一度覚えた札は再観測で忘れない")
    func memorizedCardStaysMemorized() {
        let cards = pairedCards(pairs: 1)
        // 1回目だけ当たり、以降はすべて外れになる乱数列。
        let ai = ConcentrationAI(accuracy: 0.3, roll: scriptedRoll([0.0, 0.99]))

        for _ in 0..<50 { ai.observe(index: 0, symbol: cards[0].symbol) }

        #expect(remembers(ai, index: 0, cards: cards))
    }

    @Test("何回観測しても実効記憶率が表示ラベルの p から乖離しない（#442）")
    func effectiveAccuracyMatchesLabel() {
        for level in ConcentrationCPULevel.allCases {
            let p = level.memoryAccuracy
            // 5回ずつ観測する。累積する実装なら 1-(1-p)^5（0.3 → 0.83）まで上がり、必ず外れる。
            let ratio = memorizedRatio(accuracy: p, pairs: 300, times: 5, seed: 20260903)

            #expect(abs(ratio - p) < 0.05, "\(level.displayName): 実効記憶率 \(ratio) が表示ラベル \(p) から離れている")
        }
    }

    @Test("1回だけの観測でも実効記憶率は同じ（回数に依存しない）")
    func accuracyDoesNotDependOnObservationCount() {
        for level in ConcentrationCPULevel.allCases {
            let once = memorizedRatio(accuracy: level.memoryAccuracy, pairs: 300, times: 1, seed: 20260903)
            let many = memorizedRatio(accuracy: level.memoryAccuracy, pairs: 300, times: 8, seed: 20260903)
            #expect(once == many, "\(level.displayName): 1回 \(once) と8回 \(many) で食い違う")
        }
    }

    @Test("難易度の強さの順序が保たれる（よわい < ふつう < つよい）")
    func difficultyOrderIsPreserved() {
        let weak = memorizedRatio(accuracy: ConcentrationCPULevel.weak.memoryAccuracy, pairs: 300, times: 3, seed: 424242)
        let normal = memorizedRatio(accuracy: ConcentrationCPULevel.normal.memoryAccuracy, pairs: 300, times: 3, seed: 424242)
        let strong = memorizedRatio(accuracy: ConcentrationCPULevel.strong.memoryAccuracy, pairs: 300, times: 3, seed: 424242)

        #expect(weak < normal)
        #expect(normal < strong)
    }

    @Test("記憶率 0 と 1 は極端なまま（判定を1回に絞っても境界が壊れない）")
    func extremeAccuraciesAreUnchanged() {
        let cards = pairedCards(pairs: 4)

        let never = ConcentrationAI(accuracy: 0, roll: seededRoll(seed: 7))
        let always = ConcentrationAI(accuracy: 1, roll: seededRoll(seed: 7))
        for _ in 0..<3 {
            for i in cards.indices {
                never.observe(index: i, symbol: cards[i].symbol)
                always.observe(index: i, symbol: cards[i].symbol)
            }
        }

        #expect(cards.indices.allSatisfy { remembers(never, index: $0, cards: cards) == false })
        #expect(cards.indices.allSatisfy { remembers(always, index: $0, cards: cards) })
    }

    @Test("マッチで忘れた札を再観測しても判定はやり直さない")
    func forgettingDoesNotAllowAnotherRoll() {
        let cards = pairedCards(pairs: 1)
        // 1回目は外し、以降は当たりになる乱数列。
        let ai = ConcentrationAI(accuracy: 0.3, roll: scriptedRoll([0.9, 0.0]))

        ai.observe(index: 0, symbol: cards[0].symbol)
        ai.forget(indices: [0])
        ai.observe(index: 0, symbol: cards[0].symbol)

        #expect(remembers(ai, index: 0, cards: cards) == false)
    }

    @Test("reset は判定の記録ごと消す（次の対局で覚え直せる）")
    func resetClearsJudgedCards() {
        let cards = pairedCards(pairs: 1)
        // 1回目は外し、以降は当たりになる乱数列。
        let ai = ConcentrationAI(accuracy: 0.3, roll: scriptedRoll([0.9, 0.0]))

        ai.observe(index: 0, symbol: cards[0].symbol)
        ai.reset()
        ai.observe(index: 0, symbol: cards[0].symbol)

        #expect(remembers(ai, index: 0, cards: cards))
    }
}
