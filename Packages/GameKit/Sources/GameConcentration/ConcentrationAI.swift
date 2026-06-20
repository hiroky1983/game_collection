import Foundation

/// CPU の記憶AIロジック。難易度に応じた確率でカードの位置を記憶し、
/// 知っているペアがあれば優先的に選択する。
final class ConcentrationAI {
    private let accuracy: Double
    /// 記憶: カードインデックス → シンボル
    private var memory: [Int: String] = [:]

    init(accuracy: Double) {
        self.accuracy = accuracy
    }

    /// 表向きにされたカードを確率的に記憶する
    func observe(index: Int, symbol: String) {
        let shouldMemorize = Double.random(in: 0..<1) < accuracy
        if shouldMemorize {
            memory[index] = symbol
        }
    }

    /// マッチしたカードをメモリから削除する
    func forget(indices: [Int]) {
        indices.forEach { memory.removeValue(forKey: $0) }
    }

    /// CPUがカードを選ぶ。firstIndex が nil なら1枚目、あれば2枚目を選ぶ。
    func chooseCard(cards: [ConcentrationCard], firstFlipped: Int?) -> Int {
        let available = cards.indices.filter { !cards[$0].isFaceUp && !cards[$0].isMatched }

        if let first = firstFlipped {
            let firstSymbol = cards[first].symbol
            // 記憶の中に1枚目とペアになるカードがあれば選ぶ
            if let matched = memory.first(where: { $0.key != first && $0.value == firstSymbol && !cards[$0.key].isMatched && !cards[$0.key].isFaceUp }) {
                return matched.key
            }
            // なければランダム
            let remaining = available.filter { $0 != first }
            return remaining.randomElement() ?? remaining.first ?? first
        } else {
            // 記憶の中にペアの両方が分かっているカードがあれば優先する
            let knownPairs = findKnownPair(cards: cards)
            if let pair = knownPairs {
                return pair.0
            }
            // なければランダム
            return available.randomElement() ?? 0
        }
    }

    /// 2枚目選択時、最初のカードに対するペア候補を記憶の中から探す
    func knownMatchFor(firstIndex: Int, firstSymbol: String, cards: [ConcentrationCard]) -> Int? {
        return memory.first(where: {
            $0.key != firstIndex &&
            $0.value == firstSymbol &&
            !cards[$0.key].isMatched &&
            !cards[$0.key].isFaceUp
        })?.key
    }

    private func findKnownPair(cards: [ConcentrationCard]) -> (Int, Int)? {
        var symbolToIndex: [String: Int] = [:]
        for (index, symbol) in memory {
            guard !cards[index].isMatched, !cards[index].isFaceUp else { continue }
            if let other = symbolToIndex[symbol] {
                return (other, index)
            } else {
                symbolToIndex[symbol] = index
            }
        }
        return nil
    }

    func reset() {
        memory = [:]
    }
}
