/// 種から決まる擬似乱数（SplitMix64）。配札・出題を種から再現するゲームが共通で使う（#916）。
///
/// ソリティア・フリーセル・スパイダー・ブロックならべ・ナンプレが同じ実装を別々に持っていたものを
/// 1 本に寄せた（各ゲームの `…SeededGenerator` / `BlockPuzzleRandom` はこの型の別名）。
/// ブラックジャック・大富豪・麻雀・麻雀ソリティア・チャリンコおじさんの別名と、囲碁・花札の前混合つきの包みも
/// この型に寄せてある（#1074）。
/// **出力が 1 ビットでも変わると、検証済みの種（`…VerifiedSeeds.swift`）と保存した勝ち筋が
/// すべて無効になる**ので、定数と手順は変えないこと。
///
/// Foundation にも依存しない。スパイダーの種の事前計算（`swiftc -O` で純ロジックのファイルだけを
/// 1 バイナリにする手順・`SpiderDealerTests`）にこのファイルをそのまま並べられるようにしてある。
public struct SplitMix64: RandomNumberGenerator, Sendable {
    @usableFromInline var state: UInt64

    /// 1 手ごとに状態へ足す増分（黄金比由来の定数）。種を前混合する囲碁・花札と、チェスの Zobrist 表の種が
    /// 使う（#1074）。定数を各ゲームに書き写すと実装のコピーを走査テストで見分けられなくなるので、ここから参照する。
    public static let goldenGamma: UInt64 = 0x9E3779B97F4A7C15

    public init(seed: UInt64) { self.state = seed }

    @inlinable
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
