/// 種から決まる擬似乱数（MMIX の線形合同法 + 上位ビットの折り返し）。
/// Zobrist ハッシュの表（将棋・チェス・五目並べ）と、対局テストの「でたらめ役」が共通で使う（#1150）。
///
/// 同じ実装が製品 3 本・テスト 2 本に写されていて、`SplitMix64` を 1 本化した #1074 の対象外のまま
/// 残っていたものを寄せた。**出力が 1 ビットでも変わると Zobrist の表が別物になり、
/// 千日手判定と置換表、それに固定してある対局テストの期待値がすべて崩れる**ので、
/// 定数と手順は変えないこと（`MMIXRandomTests` の golden vector が見張る）。
///
/// `SplitMix64` と違い状態をそのまま返さず `state ^ (state >> 33)` で折り返すだけなので、
/// 統計的な質は `SplitMix64` に劣る。新しく種から何かを組み立てるときは `SplitMix64` を使うこと。
/// こちらは既存の系列を保つためだけに残している。
///
/// Foundation にも依存しない（`SplitMix64` と同じく、純ロジックだけを `swiftc -O` で
/// 1 バイナリにする手順にそのまま並べられるようにしてある）。
public struct MMIXRandom: RandomNumberGenerator, Sendable {
    /// MMIX（Knuth）の乗数。
    public static let multiplier: UInt64 = 6364136223846793005
    /// MMIX（Knuth）の増分。
    public static let increment: UInt64 = 1442695040888963407

    @usableFromInline var state: UInt64

    /// 内部状態をそのまま与える（Zobrist の表はこちら。表ごとに違う「合言葉」を状態に置く）。
    public init(state: UInt64) { self.state = state }

    /// 種を 1 歩進めた値を初期状態にする（対局テストの「でたらめ役」はこちら。
    /// 連番の種をそのまま状態に置くと初手が似通うため）。
    public init(seed: UInt64) { self.state = seed &* Self.multiplier &+ Self.increment }

    @inlinable
    public mutating func next() -> UInt64 {
        state = state &* Self.multiplier &+ Self.increment
        return state ^ (state >> 33)
    }
}
