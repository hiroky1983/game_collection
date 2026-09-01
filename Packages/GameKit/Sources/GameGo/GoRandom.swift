import Foundation

/// 種から決まる擬似乱数（SplitMix64）。
///
/// MCTS と死活判定はランダムプレイアウトで動くため、そのままではテストが再現しない。
/// **種を固定すれば結果が 1 ビットも変わらない**ようにして、「シード固定で決定的に再現」
/// （#398 のテスト計画 5）を満たす。`SystemRandomNumberGenerator` は使わない。
public struct GoRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // 種 0 でも縮退しないよう定数を混ぜる。
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<upperBound の一様乱数。`upperBound` が 0 のときは 0 を返す。
    public mutating func index(below upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}
