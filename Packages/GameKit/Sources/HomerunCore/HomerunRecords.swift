import Foundation

/// 保存する 1 球（方向・距離・種別）。JSON では `[方向(0.1° 単位), 距離(0.1m 単位), 種別]` の 3 要素に畳んで小さく持つ。
public struct HomerunShot: Codable, Equatable, Sendable {
    public var directionTenths: Int
    public var distanceTenths: Int
    public var kind: HomerunKind

    public init(_ ball: HomerunBattedBall) {
        directionTenths = Int((ball.direction * 10).rounded())
        distanceTenths = Int((ball.distance * 10).rounded())
        kind = ball.kind
    }

    public var direction: Double { Double(directionTenths) / 10 }
    public var distance: Double { Double(distanceTenths) / 10 }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        directionTenths = try c.decode(Int.self)
        distanceTenths = try c.decode(Int.self)
        let raw = try c.decode(Int.self)
        guard let kind = HomerunKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unknown kind \(raw)")
        }
        self.kind = kind
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(directionTenths)
        try c.encode(distanceTenths)
        try c.encode(kind.rawValue)
    }
}

/// 蓄積（README §3.6）。通算の要約 + 方向 × 距離帯の集計 + 直近 `recentLimit` 挑戦だけ。全部で数 KB 未満。
/// 全履歴は持たない（上限は定数）。日次台帳は別（`HomerunLedger`）。
public struct HomerunRecords: Codable, Equatable, Sendable {
    /// 直近の挑戦を残す数（受け入れ条件: 21 挑戦目で最古が消える）。
    public static let recentLimit = 20
    /// 距離帯の上限値（m）。この未満で 1 段上がり、最後の帯は 135 以上。
    public static let distanceBounds: [Double] = [60, 80, 100, 110, 116, 122, 135]
    public static var distanceBandCount: Int { distanceBounds.count + 1 }

    public var schemaVersion = 1
    public var challenges = 0
    public var pitches = 0
    public var homers = 0
    public var totalDistanceTenths = 0
    /// 自己ベスト（1 挑戦の合計飛距離・0.1m 単位）。
    public var bestTotalTenths = 0
    /// 最長の 1 本（0.1m 単位）。
    public var longestTenths = 0
    public var fouls = 0
    public var misses = 0
    /// 方向 5 区分 × 距離帯 8 段 = 40 セルの本数（行 = 方向）。フェアに飛んだ球（ゴロ・ポップも含む）だけ数える。ファウル・空振りは数えない。
    public var heatmap = [Int](repeating: 0, count: HomerunSector.allCases.count * HomerunRecords.distanceBandCount)
    /// 新しい挑戦が末尾。
    public var recent: [[HomerunShot]] = []
    /// 将来の受け口（解放した球場・バット・称号）。第 1 弾は空。
    public var unlockedStadiums: [String] = []
    public var unlockedBats: [String] = []
    public var titles: [String] = []

    public init() {}

    public static func distanceBand(_ meters: Double) -> Int {
        distanceBounds.firstIndex { meters < $0 } ?? distanceBounds.count
    }

    public static func heatmapIndex(direction: Double, distance: Double) -> Int {
        HomerunSector(direction: direction).rawValue * distanceBandCount + distanceBand(distance)
    }

    /// 終わった 1 挑戦を取り込む。
    public mutating func record(_ challenge: HomerunChallenge) {
        let balls = challenge.results
        challenges += 1
        pitches += balls.count
        homers += challenge.homerCount
        fouls += challenge.foulCount
        misses += challenge.missCount
        let total = Int((challenge.totalDistance * 10).rounded())
        totalDistanceTenths += total
        bestTotalTenths = max(bestTotalTenths, total)
        for ball in balls {
            longestTenths = max(longestTenths, Int((ball.distance * 10).rounded()))
            if ball.kind != .miss && ball.kind != .foul {
                heatmap[Self.heatmapIndex(direction: ball.direction, distance: ball.distance)] += 1
            }
        }
        recent.append(balls.map(HomerunShot.init))
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
    }
}
