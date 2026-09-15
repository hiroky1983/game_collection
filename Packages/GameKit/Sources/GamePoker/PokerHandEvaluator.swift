import Foundation

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

        let isWheel = ranks == [14, 5, 4, 3, 2]
        let straightTieBreaker = isWheel ? [5, 4, 3, 2, 1] : ranks

        if isFlush && isStraight {
            return ranks[0] == 14 && ranks[1] == 13 ? (.royalFlush, ranks) : (.straightFlush, straightTieBreaker)
        }
        if groups == [4, 1] { return (.fourOfAKind, sortedTieBreaker(countMap)) }
        if groups == [3, 2] { return (.fullHouse, sortedTieBreaker(countMap)) }
        if isFlush          { return (.flush, ranks) }
        if isStraight       { return (.straight, straightTieBreaker) }
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

    /// CPU が「強い役を目指す」バイアスの分母（#443・2026-09-06 会長決裁「10回に1回は強い役を目指す」）。
    static let ambitionDenominator: UInt64 = 10

    /// 強い役を狙うときに拾う4枚。4フラッシュを優先し、無ければオープンエンドの4連続。
    /// どちらも無ければ nil。インサイドストレート（ガットショット）は期待値が低いので狙わない。
    static func strongDrawIndices(in hand: [PokerCard]) -> Set<Int>? {
        // フラッシュドロー（同スーツ4枚）
        var suitMap: [PokerSuit: [Int]] = [:]
        for (i, c) in hand.enumerated() { suitMap[c.suit, default: []].append(i) }
        if let flushDraw = suitMap.first(where: { $0.value.count == 4 }) {
            return Set(flushDraw.value)
        }
        // ストレートドロー（連続4枚）。同じランクが2枚あっても筋としては1枚ぶんなので、
        // ランクごとに代表1枚へ畳んでから4連続を探す（畳まないと 10-9-9-8-7 のように
        // ペアが連続の中間に挟まる形で、どの窓にも重複が入って検出できない・#517）
        let sorted = hand.enumerated().sorted { $0.element.rank > $1.element.rank }
        var seenRanks: Set<Int> = []
        let distinct = sorted.filter { seenRanks.insert($0.element.rank).inserted }
        guard distinct.count >= 4 else { return nil }
        for start in 0...(distinct.count - 4) {
            let window = distinct[start..<start+4]
            if window.first!.element.rank - window.last!.element.rank == 3 {
                return Set(window.map(\.offset))
            }
        }
        return nil
    }

    // CPU の捨て牌選択: 残すカードのインデックスセットを返す
    static func cpuKeepIndices(from hand: [PokerCard]) -> Set<Int> {
        var rng = SystemRandomNumberGenerator()
        return cpuKeepIndices(from: hand, using: &rng)
    }

    /// 乱数生成器を注入できる版（テスト用。バイアスの当たり外れを固定できる）。
    static func cpuKeepIndices<G: RandomNumberGenerator>(from hand: [PokerCard], using rng: inout G) -> Set<Int> {
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
            // ふだんはペアを残す（実測でこちらが強い）が、10回に1回だけペアを崩して
            // 強い役を狙う（#443・会長決裁 2026-09-06）。狙える形が無ければ賽は振らない
            if let draw = strongDrawIndices(in: hand), rng.next() % ambitionDenominator == 0 {
                return draw
            }
            return Set(pair.value)
        case .highCard:
            // フラッシュドロー・オープンエンドの4連続があればキープ
            if let draw = strongDrawIndices(in: hand) { return draw }
            // Aまたは高カード1枚だけキープ
            if let aceIdx = hand.firstIndex(where: { $0.rank == 14 }) { return [aceIdx] }
            let highIdx = hand.enumerated().max { $0.element.rank < $1.element.rank }!.offset
            return [highIdx]
        }
    }
}
