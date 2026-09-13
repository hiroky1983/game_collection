import Foundation

/// 配札（#717）。種とスート数から決定的に作るので、同じ組み合わせはいつでも同じ盤面を再現する。
///
/// 乱数は `FreeCellSeededGenerator` と同じ SplitMix64（ゲームごとにアルゴリズムを変える理由が無い）。
public enum SpiderDealer {

    /// 種から配札を作る。
    ///
    /// 104 枚を混ぜ、先頭 54 枚を 10 列へ 1 枚ずつ順に配る（左 4 列が 6 枚・右 6 列が 5 枚）。
    /// 各列は一番上だけ表向き。残り 50 枚は 10 枚ずつ 5 回ぶんの山札になる。
    public static func deal(seed: UInt64, suits: SpiderSuitCount) -> SpiderBoard {
        var rng = SpiderSeededGenerator(seed: seed)
        var deck = SpiderCard.makeDeck(suits: suits)
        deck.shuffle(using: &rng)

        var piles: [[SpiderCard]] = Array(repeating: [], count: SpiderBoard.pileCount)
        let tableauCount = 54
        for (index, card) in deck.prefix(tableauCount).enumerated() {
            piles[index % SpiderBoard.pileCount].append(card)
        }
        var stock: [[SpiderCard]] = []
        var cursor = tableauCount
        while cursor + SpiderBoard.dealSize <= deck.count {
            stock.append(Array(deck[cursor..<(cursor + SpiderBoard.dealSize)]))
            cursor += SpiderBoard.dealSize
        }
        return SpiderBoard(
            piles: piles.map { SpiderPile(cards: $0, faceDownCount: $0.count - 1) },
            stock: stock
        )
    }

    /// 出題に使う、ソルバーで勝ち筋を確認済みの種（スート数ごと）。
    ///
    /// 生成手順は `GameSpiderTests/SpiderDealerTests.swift` の「検証済みの種を作り直す」に置いてある。
    /// テストは**この配列の中身が本当に解けること**を抜き取って確かめる。
    public static func verifiedSeeds(for suits: SpiderSuitCount) -> [UInt64] {
        switch suits {
        case .one:  return spiderVerifiedSeedsOneSuit
        case .two:  return spiderVerifiedSeedsTwoSuits
        case .four: return spiderVerifiedSeedsFourSuits
        }
    }

    /// 出題用に 1 つ選ぶ。
    public static func randomVerifiedSeed<G: RandomNumberGenerator>(
        for suits: SpiderSuitCount, using rng: inout G
    ) -> UInt64 {
        let seeds = verifiedSeeds(for: suits)
        return seeds.randomElement(using: &rng) ?? seeds[0]
    }
}

/// 決定的な乱数生成器（SplitMix64）。配札は種から再現できる必要があるので system の乱数は使わない。
public struct SpiderSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
