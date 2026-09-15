import Foundation
// 種の事前計算で CoreEngine のファイルごと 1 バイナリにまとめるときは飛ばす（`SpiderDealerTests` の手順）。
#if canImport(CoreEngine)
import CoreEngine
#endif

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
    ///
    /// - Parameter previous: 直前に配った種。これを除いて選ぶので、「新しいゲーム」で同じ配札が
    ///   続けて出ない（#914。4 スートは種が 59 個しか無く、除かないと 1 回あたり 1/59 で起きる）。
    public static func randomVerifiedSeed<G: RandomNumberGenerator>(
        for suits: SpiderSuitCount, excluding previous: UInt64? = nil, using rng: inout G
    ) -> UInt64 {
        pick(from: verifiedSeeds(for: suits), excluding: previous, using: &rng)
    }

    /// `seeds` から `previous` 以外を 1 つ選ぶ。ほかに候補が無いときだけ同じ種を返す。
    static func pick<G: RandomNumberGenerator>(
        from seeds: [UInt64], excluding previous: UInt64?, using rng: inout G
    ) -> UInt64 {
        let candidates = seeds.filter { $0 != previous }
        return candidates.randomElement(using: &rng) ?? seeds[0]
    }
}

/// 決定的な乱数生成器（SplitMix64）。配札は種から再現できる必要があるので system の乱数は使わない。
/// 実体は CoreEngine の `SplitMix64`（#916 で 5 ゲームぶんのコピーを 1 本に寄せた）。
public typealias SpiderSeededGenerator = SplitMix64
