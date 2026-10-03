import Core
import Foundation
import HomerunCore

/// 実績（#1794）の解除・表示・Game Center との突き合わせ。判定そのものは `HomerunAchievement` の純粋関数。
extension HomerunModel {
    /// 「実績解禁」を出している時間（秒）。
    public static let unlockBannerDuration: TimeInterval = 2.6
    /// 消える前に薄くする時間（秒）。
    static let unlockBannerFade: TimeInterval = 0.3

    /// 解除する。新しく解除したものだけを端末に保存し、Game Center に連携していれば送り、表示の順番待ちに積む。
    func earn(_ candidates: [HomerunAchievement]) {
        let fresh = achievements.unlock(candidates)
        guard !fresh.isEmpty else { return }
        HomerunStorage.saveAchievements(achievements, defaults)
        pendingBanner += fresh
        unlockedThisChallenge += fresh
        services?.gameCenter?.reportUnlocked(fresh.map(\.gameCenterID))
    }

    /// 1 球の結果の演出が終わったところで、解除した実績を打席に出す。
    func showPendingUnlockBanner(now: Date) {
        guard !pendingBanner.isEmpty else { return }
        unlockBanner = pendingBanner
        pendingBanner = []
        unlockBannerUntil = now.addingTimeInterval(Self.unlockBannerDuration)
    }

    /// `now` に出す「実績解禁」。消す時刻を過ぎたら空。
    public func unlockBanner(at now: Date) -> [HomerunAchievement] {
        guard let until = unlockBannerUntil, now < until else { return [] }
        return unlockBanner
    }

    /// 消える直前に薄くする度合い（1 = くっきり）。
    public func unlockBannerOpacity(at now: Date) -> Double {
        guard let until = unlockBannerUntil else { return 0 }
        return min(1, max(0, until.timeIntervalSince(now) / Self.unlockBannerFade))
    }

    func resetUnlockDisplay() {
        unlockBanner = []
        unlockBannerUntil = nil
        pendingBanner = []
    }

    /// Game Center の解除済みを読んで端末の記録と和集合で合わせ、端末にだけあるぶん（あとから連携した人のそれまでの分）を送る。
    /// 打席前に出るたびに呼ぶ。未連携・読めなかったとき（オフライン等）は何もしない（`gameCenterLinked` だけ更新する）。
    public func syncGameCenterAchievements() async {
        guard let reporter = services?.gameCenter else { return }
        gameCenterLinked = reporter.isSignedIn
        guard let remote = await reporter.fetchUnlockedAchievementIDs() else { return }
        if !achievements.merge(gameCenterIDs: remote).isEmpty {
            HomerunStorage.saveAchievements(achievements, defaults)
        }
        let missing = achievements.missing(fromGameCenterIDs: remote)
        if !missing.isEmpty { reporter.reportUnlocked(missing.map(\.gameCenterID)) }
    }
}
