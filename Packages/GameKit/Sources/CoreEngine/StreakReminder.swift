import Foundation
import Observation

// MARK: - 連続日数が途切れそうな夕方の通知（#3417）

/// 予約先。App は `UNUserNotificationCenter` で実装し、テストはスパイを注入する。
/// 予約は常に高々 1 件（同じ識別子で置き換える）。アプリ側に保存先を作らない。
@MainActor
public protocol StreakReminderScheduler: AnyObject {
    /// 現在の通知許可。**このサービスは許可ダイアログを出さない**（バックグラウンド遷移時に呼ぶため）。
    func authorization() async -> ReminderAuthorization
    /// 既に予約があれば置き換える。予約できたら true（失敗は呼び出し元が数える・#3296）。
    func schedule(fireDate: Date, title: String, body: String) async -> Bool
    /// 予約（発火済みで通知センターに残っているものも含む）を消す。無くても安全。
    func cancel()
}

/// いつ知らせるかの規則。状態を持たない純粋関数。
public enum StreakReminderPolicy {
    /// 送信時刻（端末の現地時刻の「時」）。
    public static let deliveryHour = 20
    /// 知らせる最小の連続日数（ハブの連続日数の行と同じ）。
    public static let minimumStreak = PlayDayStreak.hubMinimumDays

    /// 次に予約する通知。無ければ nil。
    public struct Plan: Equatable, Sendable {
        public let fireDate: Date
        /// 本文に出す連続日数（通知が届く時点で続いている日数）。
        public let streak: Int
    }

    /// - 今日もう遊んだ → 連続が `minimumStreak` 日以上なら**翌日**の 20:00（翌日が未プレイならその時点で途切れかけているため）。
    /// - 今日まだ遊んでいない → 昨日までの連続が `minimumStreak` 日以上で、まだ今日の 20:00 前なら**今日**の 20:00。
    /// - それ以外（連続が短い・今日の 20:00 を過ぎた・連続が切れている）は nil。
    public static func plan(days: [Int], now: Date, calendar: Calendar = .current) -> Plan? {
        let today = PlayDayStreak.dayNumber(for: now, calendar: calendar)
        let streak = PlayDayStreak.current(days: days, today: today)
        guard streak >= minimumStreak else { return nil }
        let playedToday = days.contains(today)
        let dayOffset = playedToday ? 1 : 0
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
              let fire = calendar.date(bySettingHour: deliveryHour, minute: 0, second: 0, of: day),
              fire > now
        else { return nil }
        return Plan(fireDate: fire, streak: streak)
    }
}

/// 連続日数が途切れそうな夕方の通知（#3417）。
///
/// - 自動で予約する（アプリがバックグラウンドに入るたびに判定し直す）。設定の「通知」がオフなら予約しない。
/// - **許可ダイアログは出さない**。許可が既にある人にだけ予約する（他の通知で許可済みの人向け）。
/// - 遊んだら（決着を記録したら）予約を取り消す。
@MainActor
@Observable
public final class StreakReminderService {
    /// 通知がタップされた回数。ハブが変化を見て設定・記録のシートを閉じる（ハブそのものが着地先）。
    public private(set) var tapCount = 0

    @ObservationIgnored private let scheduler: StreakReminderScheduler
    @ObservationIgnored private let isEnabledSetting: @MainActor () -> Bool
    @ObservationIgnored private let isSuppressed: Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    /// 判定の世代。新しい判定が始まったら、古い判定は予約を捨てる（置き換えるのは新しい方）。
    @ObservationIgnored private var epoch = 0
    /// 取り消しの世代。判定の途中で取り消されたら、その判定の予約を消し直す目印。
    @ObservationIgnored private var cancelEpoch = 0
    /// OS への予約追加が失敗した回数（#3296）。
    @ObservationIgnored public private(set) var scheduleFailureCount = 0

    public init(
        scheduler: StreakReminderScheduler,
        isEnabled: @escaping @MainActor () -> Bool,
        isSuppressed: Bool = false,
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler
        self.isEnabledSetting = isEnabled
        self.isSuppressed = isSuppressed
        self.now = now
        self.calendar = calendar
    }

    /// 通知がタップされた。
    public func notificationTapped() {
        tapCount += 1
    }

    /// 遊んだ日の記録から予約を組み直す。バックグラウンドへ入るたびに呼ぶ。
    public func refresh(playDays: [Int]) async {
        epoch += 1
        let token = epoch
        let cancelToken = cancelEpoch
        guard !isSuppressed, isEnabledSetting(),
              let plan = StreakReminderPolicy.plan(days: playDays, now: now(), calendar: calendar)
        else {
            scheduler.cancel()
            return
        }
        guard await scheduler.authorization().allowsScheduling else {
            scheduler.cancel()
            return
        }
        guard epoch == token, cancelEpoch == cancelToken, isEnabledSetting() else { return }
        let scheduled = await scheduler.schedule(
            fireDate: plan.fireDate,
            title: tr("連続 %@ 日あそび中", RecordFormat.number(plan.streak)),
            body: tr("今日の 1 局で続けられます")
        )
        if !scheduled { scheduleFailureCount += 1 }
        // OS への追加を待つ間に取り消されていたら、追加が済んだあとで消し直す
        // （別の判定に追い越されただけなら、新しい予約を消さない）。
        if cancelEpoch != cancelToken { scheduler.cancel() }
    }

    /// 遊んだ・設定で通知をオフにした。予約中の処理も捨てる。
    public func cancel() {
        epoch += 1
        cancelEpoch += 1
        scheduler.cancel()
    }
}
