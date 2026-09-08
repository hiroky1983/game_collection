import Foundation

/// 配札（#492）。種（= 配札番号）から決定的に作るので、同じ番号はいつでも同じ盤面を再現する。
///
/// フリーセルは「番号付きディール」の文化があるゲームなので、種をそのまま**配札番号**として
/// 画面に出す（`FreeCellView` のステータスバー）。乱数は `SolitaireSeededGenerator` と同じ
/// SplitMix64 を使う（ゲームごとにアルゴリズムを変える理由が無い）。
public enum FreeCellDealer {

    /// 種から配札を作る。8 列へ 1 枚ずつ順に配るので、左 4 列が 7 枚・右 4 列が 6 枚になる。
    public static func deal(seed: UInt64) -> FreeCellBoard {
        var rng = FreeCellSeededGenerator(seed: seed)
        var deck = FreeCellCard.makeDeck()
        deck.shuffle(using: &rng)

        var tableau: [[FreeCellCard]] = Array(repeating: [], count: FreeCellBoard.pileCount)
        for (index, card) in deck.enumerated() {
            tableau[index % FreeCellBoard.pileCount].append(card)
        }
        return FreeCellBoard(tableau: tableau)
    }

    /// 出題に使う、ソルバーで勝ち筋を確認済みの種。
    ///
    /// 生成手順は `GameFreeCellTests/FreeCellDealerTests.swift` の
    /// 「検証済みの種を作り直す」に置いてある（`FREECELL_REGENERATE_SEEDS=<本数>` で実行）。
    /// テストは**この配列の中身が本当に解けること**を抜き取って確かめる。
    public static let verifiedSeeds: [UInt64] = freeCellVerifiedSeeds

    /// 出題用に1つ選ぶ。
    public static func randomVerifiedSeed<G: RandomNumberGenerator>(using rng: inout G) -> UInt64 {
        verifiedSeeds.randomElement(using: &rng) ?? verifiedSeeds[0]
    }
}

/// 決定的な乱数生成器（SplitMix64）。配札は種から再現できる必要があるので system の乱数は使わない。
public struct FreeCellSeededGenerator: RandomNumberGenerator {
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
