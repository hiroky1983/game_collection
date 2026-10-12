import Foundation

/// 挑戦回数を使い切ったあとの「戻る時刻」と「戻ったら知らせる」の規則（#1576）。状態を持たない。
///
/// 回数が戻る境目は `HomerunLedger.dayKey(for:calendar:)` が日付キーを切り替える瞬間（端末のタイムゾーンの 0:00）と
/// 同じでなければならないので、ここでも `Calendar` の日の始まりから求める（夏時間で 0:00 が存在しない日も
/// `startOfDay` が正しい瞬間を返す）。
public enum HomerunReturnPolicy {
    /// 通知を 0:00 ちょうどに出さず、境目の少し後ろへずらす秒数（台帳の日付切り替えより前に届かないようにする）。
    public static let notificationDelay: TimeInterval = 60

    /// 次に回数が戻る時刻（`now` の翌日の 0:00）。
    public static func nextReset(after now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(24 * 60 * 60)
        return calendar.startOfDay(for: tomorrow)
    }

    /// 戻るまでの残りの分数（秒は切り上げ。0 分と表示して待たせない）。
    public static func minutesUntilReset(from now: Date, calendar: Calendar) -> Int {
        let seconds = nextReset(after: now, calendar: calendar).timeIntervalSince(now)
        return max(1, Int((seconds / 60).rounded(.up)))
    }

    /// 回数 0 の打席前に出す「あと約◯時間◯分で戻ります」。結果画面は `freePlays` を立てて
    /// 「あと◯時間◯分で無料枠が戻ります」にする（会長指示 2026-10-05）。
    /// 英語では語順も単位の書き方も変わるので、前後の語を組み立てずに文ごと表に載せる（多言語④ #2167）。
    public static func remainingText(from now: Date, calendar: Calendar, freePlays: Bool = false) -> String {
        let minutes = minutesUntilReset(from: now, calendar: calendar)
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest, freePlays) {
        case (0, _, false): return tr("あと約%lld分で戻ります", rest)
        case (0, _, true):  return tr("あと%lld分で無料枠が戻ります", rest)
        case (_, 0, false): return tr("あと約%lld時間で戻ります", hours)
        case (_, 0, true):  return tr("あと%lld時間で無料枠が戻ります", hours)
        case (_, _, false): return tr("あと約%lld時間%lld分で戻ります", hours, rest)
        case (_, _, true):  return tr("あと%lld時間%lld分で無料枠が戻ります", hours, rest)
        }
    }

    /// 「戻ったら知らせる」を予約する時刻（翌 0:00 の少し後）。使い切りにつき 1 回だけなので、
    /// 予約は常にこの 1 点（同じ識別子で置き換える）。
    public static func reminderFireDate(after now: Date, calendar: Calendar) -> Date {
        nextReset(after: now, calendar: calendar).addingTimeInterval(notificationDelay)
    }

    /// 予約が生きているか（トグルの初期状態）。予約の実体は OS が持つので、その発火時刻から判定する。
    public static func isReminderActive(pendingFireDate: Date?, now: Date) -> Bool {
        guard let pendingFireDate else { return false }
        return pendingFireDate > now
    }

    /// 通知の文言。
    public static var notificationContent: (title: String, body: String) {
        (tr("柵越えおじさん"), tr("挑戦回数が %lld 回に戻りました。今日も 10 球勝負！", HomerunLedger.freePerDay))
    }
}
