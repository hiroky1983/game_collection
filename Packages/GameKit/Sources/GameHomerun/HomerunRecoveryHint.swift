import Foundation

/// 結果の「広告を見てプレイ」の上に出す「あと少し」の案内（#2724）。自己ベストに届かなかったが近いときだけ、差を数字で出す。
/// 「あと n 回」には広告の分を含めない決まりなので、回数ではなく距離の差だけを言う。
enum HomerunRecoveryHint {
    /// 自己ベストの何割まで届いていたら「あと少し」とするか（0.8 = 8 割以上）。
    static let closeRatio = 0.8

    /// 自己ベストまでの差（m・切り上げ）。更新した・記録が無い・差が大きいときは nil（案内を出さない）。
    /// - Parameters:
    ///   - totalTenths: 今回の合計（1/10 m）。
    ///   - bestTenths: 自己ベスト（1/10 m。今回の記録を含む）。
    static func metersToBest(totalTenths: Int, bestTenths: Int, isNewBest: Bool) -> Int? {
        guard !isNewBest, bestTenths > 0, totalTenths < bestTenths,
              Double(totalTenths) >= Double(bestTenths) * closeRatio else { return nil }
        return (bestTenths - totalTenths + 9) / 10
    }
}
