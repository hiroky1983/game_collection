import Foundation
import CoreEngine

/// 種から決まる擬似乱数（SplitMix64）。
///
/// MCTS と死活判定はランダムプレイアウトで動くため、そのままではテストが再現しない。
/// **種を固定すれば結果が 1 ビットも変わらない**ようにして、「シード固定で決定的に再現」
/// （#398 のテスト計画 5）を満たす。`SystemRandomNumberGenerator` は使わない。
/// 実装は CoreEngine の共通部品で、ここは種の前混合だけを持つ（#1074）。
public struct GoRandom: RandomNumberGenerator, Sendable {
    private var base: SplitMix64

    public init(seed: UInt64) {
        // 種 0 でも縮退しないよう定数を混ぜる。
        self.base = SplitMix64(seed: seed &+ SplitMix64.goldenGamma)
    }

    public mutating func next() -> UInt64 {
        base.next()
    }

    /// 0..<upperBound の一様乱数。`upperBound` が 0 のときは 0 を返す。
    public mutating func index(below upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}
