import Foundation

/// ステージをミス 0 回でクリアした面の連続数（#3244）。ランキングの 3pt（ミス 0 回）と噛み合う記録。
/// 保存するのは「今の連続数」と「連続の最高」の 2 つの整数だけ（端末の `UserDefaults`・サーバーには送らない）。
/// 自由に遊ぶは対象外。ヒント・「猫を 1 匹教える」を使っても途切れない。
enum CatPuzzleNoMiss {
    static let streakKey = "catPuzzleNoMissStreak"
    static let bestKey = "catPuzzleNoMissBest"

    /// クリアのカードに出し始める連続数（1 面目は出さず、2 面から）。
    static let showsFrom = 2

    static func streak(_ defaults: UserDefaults) -> Int { max(0, defaults.integer(forKey: streakKey)) }
    static func best(_ defaults: UserDefaults) -> Int { max(0, defaults.integer(forKey: bestKey)) }

    /// ミス 0 回のクリアを 1 つ足す。`beatBest` は連続の最高を更新したか（初めての 1 面目は更新に数えない）。
    static func recordClear(_ defaults: UserDefaults) -> (streak: Int, best: Int, beatBest: Bool) {
        let next = streak(defaults) + 1
        let oldBest = best(defaults)
        let newBest = max(oldBest, next)
        defaults.set(next, forKey: streakKey)
        defaults.set(newBest, forKey: bestKey)
        return (next, newBest, next > oldBest && next >= showsFrom)
    }

    /// 連続を 0 に戻す（最高は残す）。
    static func reset(_ defaults: UserDefaults) {
        defaults.set(0, forKey: streakKey)
    }
}
