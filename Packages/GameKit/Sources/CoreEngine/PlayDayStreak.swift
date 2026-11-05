import Foundation

/// 「連続プレイ日数」（#1625）の計算。遊んだ日（端末のローカル日付）の整数列から出す**純粋関数**。
///
/// 「日」は `dayNumber(for:calendar:)` が返す連番（1970-01-01 を 0 とする、その日付をそのまま数えた値）。
/// 時刻やタイムゾーンの差を日番号に畳み込んでおくので、連続かどうかは `+1` の比較だけで決まる。
public enum PlayDayStreak {
    /// 保存する日の上限。これより古い日は捨てる（連続日数も上限で頭打ち）。
    public static let maxStoredDays = 366

    /// ハブに 1 行出す最小の連続日数。0 日・1 日のときは出さない。
    public static let hubMinimumDays = 2

    /// `date` を `calendar`（端末のローカル日付）で見たときの日番号。
    public static func dayNumber(for date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        // 年月日をそのまま UTC の 0 時に置き直して数える。ローカルの UTC オフセットが日番号に混ざらない。
        guard let normalized = utc.date(from: parts) else { return 0 }
        return Int((normalized.timeIntervalSince1970 / 86_400).rounded(.down))
    }

    /// 保存済みの日に `day` を足して、昇順・重複なし・新しい側から `maxStoredDays` 個に揃える。
    public static func inserting(_ day: Int, into days: [Int]) -> [Int] {
        guard !days.contains(day) else { return days }
        return Array((days + [day]).sorted().suffix(maxStoredDays))
    }

    /// 今日時点の連続日数。
    ///
    /// - 今日遊んでいれば今日から、遊んでいなくても昨日遊んでいれば昨日から遡って数える
    ///   （今日はまだ終わっていないので、昨日までの連続はそのまま残す）。
    /// - 昨日も今日も遊んでいなければ 0（1 日空くと途切れる）。
    /// - `today` より未来の日は無視する（端末の時刻を戻された場合に、未来の日が連続を水増ししない）。
    public static func current(days: [Int], today: Int) -> Int {
        let played = Set(days.filter { $0 <= today })
        let anchor: Int
        if played.contains(today) {
            anchor = today
        } else if played.contains(today - 1) {
            anchor = today - 1
        } else {
            return 0
        }
        var count = 0
        while played.contains(anchor - count) { count += 1 }
        return count
    }

    /// 保存している日の中で最も長かった連続日数（#2886）。途切れた過去の連続も含む。
    ///
    /// - `today` より未来の日は無視する（`current` と同じ）。
    /// - 保存は直近 `maxStoredDays` 日ぶんだけなので、それより古い連続は数えられない。
    public static func longest(days: [Int], today: Int) -> Int {
        let sorted = Set(days.filter { $0 <= today }).sorted()
        var best = 0
        var run = 0
        var previous: Int?
        for day in sorted {
            run = (previous == day - 1) ? run + 1 : 1
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// きろく画面の「最長 N 日」を添えるか。今の連続が最長に並んでいるときと、最長が 1 日以下のときは出さない。
    public static func showsLongest(current: Int, longest: Int) -> Bool {
        longest > current && longest >= hubMinimumDays
    }

    /// ハブの 1 行。連続日数が `hubMinimumDays` 未満なら nil（出さない）。
    public static func hubText(streak: Int) -> String? {
        streak >= hubMinimumDays ? tr("連続 %@ 日あそび中", RecordFormat.number(streak)) : nil
    }

    /// ハブの 1 行（#3060）。今日遊んだかで 3 状態に分ける。
    /// - 今日遊んだ: `hubText(streak:)` と同じ（2 日以上のときだけ）。
    /// - 昨日まで続いていて今日はまだ: 「あと 1 局で連続 N+1 日」（N=1 でも出す）。
    /// - それ以外（昨日も今日も遊んでいない）: nil。
    public static func hubText(days: [Int], today: Int) -> String? {
        let streak = current(days: days, today: today)
        if days.contains(today) { return hubText(streak: streak) }
        guard streak > 0 else { return nil }
        return tr("あと 1 局で連続 %@ 日", RecordFormat.number(streak + 1))
    }
}
