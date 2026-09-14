import Foundation

/// 先読みした全画面広告を 1 本だけ預かる置き場（#658）。
///
/// リワード広告をタップのたびに読み込むと、回線が弱いときに「押したのに何も起きない → エラー」になる。
/// 先に 1 本読んでおき、タップ時はそれを使う。実際の `GADRewardedAd` は端末側なので、
/// 「預かった広告をまだ出してよいか」の判断だけをここに置いて純粋に検証する（`BannerSlot` と同じ流儀）。
public struct PreloadedAdSlot<Ad> {
    /// 読み込んでから使える時間。AdMob のリワード広告は読み込みから 1 時間で失効するため、
    /// 境目で表示に失敗しないよう 5 分手前で捨てる。
    public static var defaultLifetime: TimeInterval { 55 * 60 }

    public let lifetime: TimeInterval
    private var stored: (ad: Ad, loadedAt: Date)?

    public init(lifetime: TimeInterval = defaultLifetime) {
        self.lifetime = lifetime
    }

    /// 読み込めた広告を預ける。先に預かっていたものは捨てる（複数本は持たない）。
    public mutating func store(_ ad: Ad, loadedAt: Date) {
        stored = (ad, loadedAt)
    }

    /// まだ使える広告を預かっているか。先読みを始めるかどうかの判断に使う。
    public func hasFreshAd(now: Date) -> Bool {
        guard let stored else { return false }
        return now.timeIntervalSince(stored.loadedAt) < lifetime
    }

    /// 使える広告を取り出す。取り出したら空になる（同じ広告は 2 回出せない）。
    /// 失効していたら捨てて nil を返し、呼び出し側はその回だけ読み込みに戻る。
    public mutating func take(now: Date) -> Ad? {
        defer { stored = nil }
        guard hasFreshAd(now: now) else { return nil }
        return stored?.ad
    }
}
