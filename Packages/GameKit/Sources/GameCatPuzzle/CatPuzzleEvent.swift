import Foundation

/// ねこさがしの 1 か月のランキングイベント（#3204）。ステージをクリアするたびに、その面のミスの数でポイントがつき、
/// 期間中に貯めた合計を Game Center のリーダーボード（`GameCenterLeaderboard.catPuzzleEvent`）へ送る。
///
/// - ポイント: ミス 0 回 = 3pt・1 回 = 2pt・2 回 = 1pt。ミス 3 回はゲームオーバーなのでクリアできず 0pt。
///   **ヒント・「猫を 1 匹教える」を使っても減らさない**。ミスは画面に出ている数で数える（コンティニューで戻した
///   ぶんは含まない。広告で続けて 2 回ミスのままクリアしたら 1pt）。
/// - 期間外のクリアは加算しない。合計は端末に保存し、Game Center に未ログインでも貯まる（ログインしたら送る）。
enum CatPuzzleEvent {
    /// 開催期間（JST）。**期間はここ 1 か所だけで持つ**。終わりは 12/9 の終わりまで（翌日 0:00 の手前）。
    static let start = date(2026, 11, 9)
    static let end = date(2026, 12, 10)

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func isActive(now: Date = Date()) -> Bool { now >= start && now < end }

    /// その面のクリアで得られるポイント。`mistakes` は画面に出ているミスの数。
    static func points(mistakes: Int) -> Int {
        switch mistakes {
        case ..<0, 0: 3
        case 1: 2
        case 2: 1
        default: 0
        }
    }

    /// 合計と、Game Center へ送り済みの値の保存。
    static let totalKey = "catPuzzleEventTotal202611"
    static let sentKey = "catPuzzleEventSent202611"

    static func total(_ defaults: UserDefaults) -> Int { max(0, defaults.integer(forKey: totalKey)) }
    static func sent(_ defaults: UserDefaults) -> Int { max(0, defaults.integer(forKey: sentKey)) }

    /// 合計を足して、足したあとの合計を返す。
    @discardableResult
    static func add(_ points: Int, to defaults: UserDefaults) -> Int {
        let next = total(defaults) + max(0, points)
        defaults.set(next, forKey: totalKey)
        return next
    }

    static func markSent(_ value: Int, in defaults: UserDefaults) {
        if value > sent(defaults) { defaults.set(value, forKey: sentKey) }
    }
}
