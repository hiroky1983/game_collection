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
    /// 確認用（DEBUG の起動引数 `-homerunForceMoon`）: 振れば（見送り以外）必ず月まで飛ぶ。出荷ビルドでは立てる経路が無い。
    public let forcesMoon: Bool
    /// 確認用（DEBUG の起動引数 `-homerunForcePole`）: 振れば（見送り以外）必ずファウルポールに当たる（#1686）。月の強制が優先。
    public let forcesPole: Bool
    public private(set) var results: [HomerunBattedBall] = []

    /// 1 挑戦の中でこの回数目の月で月が割れ、挑戦が終わる（#1680）。
    public static let moonBreakCount = 2

    public init(pitches: [HomerunPitch] = HomerunPitch.standardSequence, abilities: HomerunAbilities = .standard,
                forcesMoon: Bool = false, forcesPole: Bool = false) {
        self.pitches = Array(pitches.prefix(Self.pitchCount))
        self.abilities = abilities
        self.forcesMoon = forcesMoon
        self.forcesPole = forcesPole
    }

    /// 10 球を投げ終えた、または月が割れた（残りの球は没収・#1680）。
    public var isFinished: Bool { results.count >= pitches.count || isMoonBroken }

    /// この挑戦でたんこぶの演出（#1793）が出た回数。
    public var tankobuCount: Int { results.filter(\.isTankobu).count }
    /// この挑戦で月まで飛んだ回数。
    public var moonCount: Int { results.filter(\.isMoon).count }
    /// この挑戦で月が割れた（2 回目の月）。
    public var isMoonBroken: Bool { results.contains { $0.moon == .broken } }

    /// 次に投げる球。終わっていれば nil。
    public var currentPitch: HomerunPitch? { isFinished ? nil : pitches[results.count] }

    /// 1 球ぶん振る（`swing` が nil なら見逃し）。終了後は何もせず nil を返す。
    /// `tankobuRoll`（0 以上 1 未満の乱数）は、ポップの擦り当たりをたんこぶの演出にするか決める（#1793・既定の 1 = 出さない）。
    @discardableResult
    public mutating func swing(_ swing: HomerunSwing?, tankobuRoll: Double = 1) -> HomerunBattedBall? {
        guard !isFinished else { return nil }
        // 月まで飛ぶ（#1680）: 条件（`HomerunJudge.isMoonShot`）か、確認用の強制。見送りは月にならない。
        // ポール直撃（#1686）はふだんの判定（`judge`）の中。確認用の強制（`forcesPole`）は月の次。
        var result = if let swing, forcesMoon || HomerunJudge.isMoonShot(swing) {
            HomerunJudge.moonBall(swing)
        } else if let swing, forcesPole {
            HomerunJudge.forcedPoleBall(swing, abilities: abilities)
        } else {
            HomerunJudge.judge(swing, abilities: abilities)
        }
        if let swing, tankobuCount < HomerunTankobu.perChallenge, tankobuRoll < HomerunTankobu.chance,
           HomerunTankobu.qualifies(swing: swing, ball: result) {
            result = HomerunTankobu.apply(to: result)
        }
        if result.isMoon, moonCount + 1 >= Self.moonBreakCount { result.moon = .broken }
        results.append(result)
        return result
    }

    /// 合計飛距離（順位表に送る値・m）。
    public var totalDistance: Double { results.reduce(0) { $0 + $1.distance } }
    public var homerCount: Int { results.filter { $0.kind == .homer }.count }
    public var foulCount: Int { results.filter { $0.kind == .foul }.count }
    public var missCount: Int { results.filter { $0.kind == .miss }.count }
}
