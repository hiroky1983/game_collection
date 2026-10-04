import Foundation

/// 柵越えおじさんの実績（#1794）。**名前も条件も、解除するまで一覧には出さない**（すべて「？？？」の枠）。
/// 判定は打球・挑戦の結果だけから決まる純粋関数で、保存と Game Center への送信は呼び出し側（`HomerunModel`）が担う。
public enum HomerunAchievement: String, CaseIterable, Sendable {
    /// 柵越えを初めて打った。
    case firstHomer
    /// 場外（スタンドの最後列の後端を越えた・#1654）。
    case outOfPark
    /// ファウルポールに当てて柵を越えた（#1686）。
    case poleHit
    /// 月まで飛ばした（#1680）。
    case moon
    /// 1 挑戦の中で月に 2 回当てて月を割った（`HomerunChallenge.isMoonBroken`・会長指示 2026-10-04）。
    case moonBroken
    /// 1 挑戦の 10 球がすべて柵越え。
    case allTenHomers
    /// ジャストミート（#1775）。
    case justMeet
    /// 1 挑戦の合計飛距離が `farTotalMeters` を超えた。
    case farTotal
    /// 空振りで回って倒れた（#1681 の演出が出た）。
    case whiffSpin
    /// 打ち上げた球が自分の頭に落ちてたんこぶになった（#1793・会長指示 2026-10-04）。
    case tankobu

    /// `farTotal` の合計飛距離（m）。10 球すべて芯なら約 1,800m、ナイスの柵越えを 10 本そろえて約 1,300〜1,450m。
    public static let farTotalMeters = 1500.0

    /// App Store Connect に登録する実績 ID。`GameCenterAchievements.homerunIDs`（Core）と一致することをテストが縛る。
    public var gameCenterID: String { "asobiba.homerun.achievement.\(rawValue.lowercased())" }

    /// 解除したあとに見せる名前。
    public var title: String {
        switch self {
        case .firstHomer: "はじめての柵越え"
        case .outOfPark: "場外ホームラン"
        case .poleHit: "ポール直撃"
        case .moon: "月まで飛ばした"
        case .moonBroken: "月を割った"
        case .allTenHomers: "10球すべて柵越え"
        case .justMeet: "ジャストミート"
        case .farTotal: "合計 1,500m 超え"
        case .whiffSpin: "回って倒れた"
        case .tankobu: "ゴツン！"
        }
    }

    /// 解除したあとに見せる条件。
    public var detail: String {
        switch self {
        case .firstHomer: "柵を越える打球を初めて打った"
        case .outOfPark: "スタンドの最後列まで越えて場外へ飛ばした"
        case .poleHit: "ファウルポールに当てて柵を越えた"
        case .moon: "打球が月まで届いた"
        case .moonBroken: "同じ挑戦で月に 2 回当てて、月を割った"
        case .allTenHomers: "1 挑戦の 10 球をすべて柵越えにした"
        case .justMeet: "タイミングも芯もぴったりでとらえた"
        case .farTotal: "1 挑戦の合計飛距離が 1,500m を超えた"
        case .whiffSpin: "空振りの勢いで回って倒れた"
        case .tankobu: "打ち上げた球が自分の頭に落ちてきた"
        }
    }

    /// 1 球の結果で解除される実績。
    /// - Parameters:
    ///   - outOfPark: 場外か（距離の基準は表示側の `HomerunBallChase` にあるので呼び出し側が渡す）。
    ///   - whiffSpin: 空振りで回って倒れる演出が出たか。
    public static func earned(byBall ball: HomerunBattedBall, outOfPark: Bool, whiffSpin: Bool) -> [HomerunAchievement] {
        var result: [HomerunAchievement] = []
        if ball.kind == .homer { result.append(.firstHomer) }
        if outOfPark { result.append(.outOfPark) }
        if ball.isPoleHit { result.append(.poleHit) }
        if ball.isMoon { result.append(.moon) }
        if ball.isJustMeet { result.append(.justMeet) }
        if whiffSpin { result.append(.whiffSpin) }
        if ball.isTankobu { result.append(.tankobu) }
        return result
    }

    /// 終わった挑戦（10 球を投げ終えた・月が割れて途中で終わった）で解除される実績
    /// （月が割れて途中で終わった挑戦は 10 球に届かないので `allTenHomers` にならない）。
    public static func earned(byFinished challenge: HomerunChallenge) -> [HomerunAchievement] {
        var result: [HomerunAchievement] = []
        let balls = challenge.results
        if balls.count == HomerunChallenge.pitchCount, balls.allSatisfy({ $0.kind == .homer }) {
            result.append(.allTenHomers)
        }
        if challenge.totalDistance > farTotalMeters { result.append(.farTotal) }
        if challenge.isMoonBroken { result.append(.moonBroken) }
        return result
    }
}

/// 解除済みの実績の記録（端末の UserDefaults に 1 キーで持つ・#1794）。実績一覧はいつもこの記録を見て描く
/// （Game Center の連携・通信の有無に関係なく見られる）。Game Center 側の解除済みとは和集合で合わせる（`merge`）。
///
/// 保存は実績の `rawValue` の配列。知らない値（将来の版が足したもの）は読み捨てずに持ち続け、一覧・件数には出さない。
public struct HomerunAchievementLog: Codable, Equatable, Sendable {
    private var raws: Set<String> = []

    public init() {}

    public init(from decoder: Decoder) throws {
        raws = Set(try decoder.singleValueContainer().decode([String].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raws.sorted())
    }

    public func contains(_ achievement: HomerunAchievement) -> Bool { raws.contains(achievement.rawValue) }

    /// 解除済みの数（この版が知っている実績だけ）。
    public var count: Int { HomerunAchievement.allCases.filter(contains).count }

    /// 解除する。**新しく解除されたものだけ**を返す（すでに持っているものは返さない）。
    @discardableResult
    public mutating func unlock(_ achievements: [HomerunAchievement]) -> [HomerunAchievement] {
        var fresh: [HomerunAchievement] = []
        for a in achievements where !contains(a) && !fresh.contains(a) {
            raws.insert(a.rawValue)
            fresh.append(a)
        }
        return fresh
    }

    /// Game Center の解除済み（実績 ID）を取り込む（和集合）。端末に無かった実績を返す。
    @discardableResult
    public mutating func merge(gameCenterIDs ids: Set<String>) -> [HomerunAchievement] {
        unlock(HomerunAchievement.allCases.filter { ids.contains($0.gameCenterID) })
    }

    /// 端末にあって、Game Center の解除済み（`ids`）に無い実績（あとから連携した人のぶんをまとめて送る）。
    public func missing(fromGameCenterIDs ids: Set<String>) -> [HomerunAchievement] {
        HomerunAchievement.allCases.filter { contains($0) && !ids.contains($0.gameCenterID) }
    }
}
