import Foundation

/// ねこさがしの 1 か月のランキングイベント（#3204）。ステージをクリアするたびに、その面のミスの数でポイントがつき、
/// **日本時間の 1 日ごと**（0:00 区切り）に貯めたその日の合計を、Game Center の繰り返しのリーダーボード
/// （`GameCenterLeaderboard.catPuzzleEvent`・期間 1 日）へ送る（#3221。1 か月通しの合計から変更）。
///
/// - ポイント: ミス 0 回 = 3pt・1 回 = 2pt・2 回 = 1pt（鍵の面は 2 倍の 6・4・2pt・#3259）。ミス 3 回はゲームオーバーなのでクリアできず 0pt。
///   **ヒント・「猫を 1 匹教える」を使っても減らさない**。ミスは画面に出ている数で数える（コンティニューで戻した
///   ぶんは含まない。広告で続けて 2 回ミスのままクリアしたら 1pt）。
/// - 期間外のクリアは加算しない。合計は端末に保存し、Game Center に未ログインでも貯まる（ログインしたら、その日のうちなら送る。前日分は送らない）。
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

    /// その面のクリアで得られるポイント。`mistakes` は画面に出ているミスの数。鍵の面（#3259）は 2 倍（6・4・2pt）。
    static func points(mistakes: Int, isKey: Bool = false) -> Int {
        let base = switch mistakes {
        case ..<0, 0: 3
        case 1: 2
        case 2: 1
        default: 0
        }
        return isKey ? base * keyMultiplier : base
    }

    /// 鍵の面のクリアにかかる倍率。
    static let keyMultiplier = 2

    /// 保存するのは「日付（JST）・その日の合計・その日に Game Center へ送り済みの値」の 3 つだけ。日付が変わったら 0 から数え直す。
    static let dayKey = "catPuzzleEventDay"
    static let totalKey = "catPuzzleEventDayTotal"
    /// 今日クリアした面の数（共有の「n 面クリア」・#3237）。日付と同じく 0:00 JST で数え直す。
    static let clearsKey = "catPuzzleEventDayClears"
    static let sentKey = "catPuzzleEventDaySent"

    /// 日本時間の日付（`yyyy-MM-dd`）。0:00 JST で変わる。
    static func day(of date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// 今日（`now` の日付）の合計。保存されている日付が今日でなければ 0。
    static func total(_ defaults: UserDefaults, now: Date = Date()) -> Int {
        defaults.string(forKey: dayKey) == day(of: now) ? max(0, defaults.integer(forKey: totalKey)) : 0
    }

    /// 今日クリアした面の数。今日でなければ 0。
    static func clears(_ defaults: UserDefaults, now: Date = Date()) -> Int {
        defaults.string(forKey: dayKey) == day(of: now) ? max(0, defaults.integer(forKey: clearsKey)) : 0
    }

    /// 今日の合計のうち Game Center へ送り済みの値。今日でなければ 0。
    static func sent(_ defaults: UserDefaults, now: Date = Date()) -> Int {
        defaults.string(forKey: dayKey) == day(of: now) ? max(0, defaults.integer(forKey: sentKey)) : 0
    }

    /// クリアした時点の日付で合計を足して、足したあとの今日の合計を返す。日付が変わっていたら 0 から数え直す。
    @discardableResult
    static func add(_ points: Int, to defaults: UserDefaults, now: Date = Date()) -> Int {
        let today = day(of: now)
        if defaults.string(forKey: dayKey) != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: totalKey)
            defaults.set(0, forKey: sentKey)
            defaults.set(0, forKey: clearsKey)
        }
        defaults.set(clears(defaults, now: now) + 1, forKey: clearsKey)
        let next = total(defaults, now: now) + max(0, points)
        defaults.set(next, forKey: totalKey)
        return next
    }

    /// 送り済みを控える。`day` は送り始めた日で、保存されている日付と違えば（日をまたいだ）控えない。
    static func markSent(_ value: Int, day: String, in defaults: UserDefaults) {
        guard defaults.string(forKey: dayKey) == day, value > max(0, defaults.integer(forKey: sentKey)) else { return }
        defaults.set(value, forKey: sentKey)
    }
}
