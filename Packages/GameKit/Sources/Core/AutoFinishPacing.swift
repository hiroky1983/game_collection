/// 「自動で上がる」で 1 手ずつ適用するときの間隔（#2706・ソリティア / フリーセル共通）。
///
/// 1 手 0.05 秒。残りが多い（20 手超）ときは 0.03 秒に詰め、それでも合計が 2 秒を超える長さなら
/// 2 秒に収まるところまで詰める。
public enum AutoFinishPacing {
    /// 通常の 1 手の間隔。
    public static let step: Duration = .milliseconds(50)
    /// 残りが `longPlanThreshold` 手を超えるときの 1 手の間隔。
    public static let fastStep: Duration = .milliseconds(30)
    public static let longPlanThreshold = 20
    /// 全体の上限。
    public static let totalLimit: Duration = .seconds(2)

    /// 手順が `moveCount` 手のときの 1 手ごとの間隔。
    public static func interval(moveCount: Int) -> Duration {
        guard moveCount > 0 else { return .zero }
        let base = moveCount > longPlanThreshold ? fastStep : step
        return min(base, totalLimit / moveCount)
    }
}
