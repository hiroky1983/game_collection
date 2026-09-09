import Foundation

/// CPU の記憶AIロジック。難易度に応じた確率でカードの位置を記憶し、
/// 知っているペアがあれば優先的に選択する。
///
/// 選択にランダム性があるため、テストが CPU の手を固定したいときは `chooseCard` を
/// override したサブクラスを `ConcentrationModel` の `aiFactory` から返す（#137 の Bug 1 回帰テスト）。
class ConcentrationAI {
    private let accuracy: Double
    /// 記憶: カードインデックス → シンボル
    private var memory: [Int: String] = [:]
    /// 「覚えるか」の判定を済ませたカード。再観測で判定をやり直さないための記録（#442）
    private var judged: Set<Int> = []
    /// 判定に使う 0..<1 の乱数。テストから決定的な列を注入できるようにしている（#442）
    private let roll: () -> Double

    init(accuracy: Double, roll: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.accuracy = accuracy
        self.roll = roll
    }

    /// 表向きにされたカードを確率的に記憶する。
    ///
    /// 判定は**カードごとに1回だけ**行う。観測のたびに独立に判定すると、同じ札を n 回見た
    /// 実効記憶率が `1-(1-p)^n` まで上がり、難易度ラベル（「記憶30%」等）より賢くなる（#442）。
    /// 覚えられなかった札は、何度めくられても覚えられないままにする。
    func observe(index: Int, symbol: String) {
        guard judged.insert(index).inserted else { return }
        if roll() < accuracy {
            memory[index] = symbol
        }
    }

    /// マッチしたカードをメモリから削除する。
    ///
    /// 判定済みの記録（`judged`）は消さない。消すと、その札がもう一度観測されたときに
    /// 判定をやり直せてしまい、`observe` が潰した記憶率の累積が戻る。
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
        judged = []
    }
}
