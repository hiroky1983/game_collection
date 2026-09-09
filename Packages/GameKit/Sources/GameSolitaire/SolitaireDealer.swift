import Foundation

/// 配札。種（seed）から決定的に作るので、同じ種はいつでも同じ盤面を再現する。
///
/// #397 の受け入れ条件「全配札がソルバー検証済みで理論上クリア可能」は、
/// **検証済みの種だけを出題する**ことで満たす。実行時に生成して検証すると、
/// 不能な配札を引くたびにソルバーを回し直すことになり、端末で待たせてしまう。
public enum SolitaireDealer {

    /// 種から配札を作る。場札は7列（1枚〜7枚）で各列の一番上だけが表向き、残りは山札。
    public static func deal(seed: UInt64) -> SolitaireBoard {
        var rng = SolitaireSeededGenerator(seed: seed)
        var deck = SolitaireCard.makeDeck()
        deck.shuffle(using: &rng)

        var tableau: [SolitairePile] = []
        var index = 0
        for column in 0..<SolitaireBoard.pileCount {
            let cards = Array(deck[index...(index + column)])
            index += column + 1
            tableau.append(SolitairePile(faceDown: Array(cards.dropLast()), faceUp: [cards.last!]))
        }
        // 残りは山札。`last` が次にめくる1枚なので、配った順が上から来るように反転する。
        // `Array(...)` を外側に置いて `[SolitaireCard]` を返す `reversed()` を明示する
        // （引数の型から解決させると、式を let に切り出した瞬間に ReversedCollection に変わる）。
        return SolitaireBoard(tableau: tableau, stock: Array(deck[index...].reversed()))
    }

    /// 出題に使う、ソルバーで勝ち筋を確認済みの種。
    ///
    /// 生成手順は `GameSolitaireTests/SolitaireDealerTests.swift` の
    /// `再現手順: 検証済みの種を作り直す` に置いてある（`SOLITAIRE_REGENERATE_SEEDS=1` で実行）。
    /// テストは**この配列の中身が本当に解けること**を毎回ランダムに抜き取って確かめる。
    public static let verifiedSeeds: [UInt64] = solitaireVerifiedSeeds

    /// 出題用に1つ選ぶ。
    public static func randomVerifiedSeed<G: RandomNumberGenerator>(using rng: inout G) -> UInt64 {
        verifiedSeeds.randomElement(using: &rng) ?? verifiedSeeds[0]
    }
}

/// 決定的な乱数生成器（SplitMix64）。配札は種から再現できる必要があるので system の乱数は使わない。
public struct SolitaireSeededGenerator: RandomNumberGenerator {
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
