import Foundation

/// 球場（受け口 2: 方向 → 柵の距離の関数）。第 1 弾は固定の 1 つだけ。
public struct HomerunStadium: Sendable {
    public var fence: @Sendable (Double) -> Double
    public init(fence: @escaping @Sendable (Double) -> Double) { self.fence = fence }

    public static let standard = HomerunStadium(fence: HomerunJudge.fence(atDirection:))
}

/// 1 球の配球（受け口 2: コース・球速）。第 1 弾は固定の並び（乱数なし = 毎日同じ 10 球で競える）。
public struct HomerunPitch: Equatable, Sendable {
    /// 9 分割のゾーン（0 = 左上 … 8 = 右下・行優先）。
    public var zone: Int
    public var speedKmh: Int

    public init(zone: Int, speedKmh: Int = 130) {
        self.zone = zone
        self.speedKmh = speedKmh
    }

    /// 縮む輪が的に重なるまでの時間（ミリ秒）。判定窓の幾何が成立するのは 1.2 秒だけ（README §3.1）。
    public static let travelMilliseconds = 1200

    /// 第 1 弾の配球: 真ん中から始め、角と外を散らす。
    public static let standardSequence: [HomerunPitch] =
        [4, 0, 8, 2, 6, 1, 7, 3, 5, 4].map { HomerunPitch(zone: $0) }
}

/// 1 挑戦（受け口 7: 球数は定数）の進行。画面は持たない。
public struct HomerunChallenge: Sendable {
    /// 1 挑戦の球数。
    public static let pitchCount = 10

    public let pitches: [HomerunPitch]
    public let abilities: HomerunAbilities
    public private(set) var results: [HomerunBattedBall] = []

    public init(pitches: [HomerunPitch] = HomerunPitch.standardSequence, abilities: HomerunAbilities = .standard) {
        self.pitches = Array(pitches.prefix(Self.pitchCount))
        self.abilities = abilities
    }

    public var isFinished: Bool { results.count >= pitches.count }

    /// 次に投げる球。終わっていれば nil。
    public var currentPitch: HomerunPitch? { isFinished ? nil : pitches[results.count] }

    /// 1 球ぶん振る（`swing` が nil なら見逃し）。終了後は何もせず nil を返す。
    @discardableResult
    public mutating func swing(_ swing: HomerunSwing?) -> HomerunBattedBall? {
        guard !isFinished else { return nil }
        let result = HomerunJudge.judge(swing, abilities: abilities)
        results.append(result)
        return result
    }

    /// 合計飛距離（順位表に送る値・m）。
    public var totalDistance: Double { results.reduce(0) { $0 + $1.distance } }
    public var homerCount: Int { results.filter { $0.kind == .homer }.count }
    public var foulCount: Int { results.filter { $0.kind == .foul }.count }
    public var missCount: Int { results.filter { $0.kind == .miss }.count }
}
