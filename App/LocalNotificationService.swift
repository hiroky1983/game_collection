import UIKit
import UserNotifications
import Core

/// 中断したゲームのお知らせ（#663）の通知の識別子。delegate（非隔離）からも読むため、
/// MainActor に隔離される型の中ではなくここに置く。
enum ResumeReminderNotification {
    static let identifierPrefix = "resume-reminder."
    static let gameIDKey = "gameID"

    static func identifier(for gameID: String) -> String {
        identifierPrefix + gameID
    }
}

/// `ResumeReminderService`（Core）の予約先を `UNUserNotificationCenter` で実装する。
/// 件数・時刻・許諾の判断は Core が持ち、ここは OS へ渡すだけ。
@MainActor
final class UserNotificationReminderScheduler: ResumeReminderScheduler {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> ReminderAuthorization {
        switch await Self.authorizationStatus() {
        case .authorized:               return .authorized
        case .provisional, .ephemeral:  return .provisional
        case .notDetermined:            return .notDetermined
        case .denied:                   return .denied
        @unknown default:               return .denied
        }
    }

    func requestProvisionalAuthorization() async -> ReminderAuthorization {
        // `.provisional` を含めると許可ダイアログは出ず、通知センターに静かに届く（#663 の決裁 (a)）。
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
        return await authorization()
    }

    func pendingReminders() async -> [ResumeReminder] {
        await Self.pendingReminderRequests()
    }

    func schedule(_ reminder: ResumeReminder, title: String, body: String) async {
        await Self.add(reminder, title: title, body: body)
    }

    func cancel(gameIDs: [String]) {
        let identifiers = gameIDs.map(ResumeReminderNotification.identifier(for:))
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        // 既に届いて通知センターに残っているものも消す（開いたゲームの「途中のままです」を残さない）。
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAll() {
        // このアプリが出す通知はこのお知らせだけなので、まとめて消してよい。
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // 通知センターの応答型は Sendable でないため、MainActor へ持ち込まずに値だけ取り出す。

    nonisolated private static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated private static func pendingReminderRequests() async -> [ResumeReminder] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            guard request.identifier.hasPrefix(ResumeReminderNotification.identifierPrefix),
                  let gameID = request.content.userInfo[ResumeReminderNotification.gameIDKey] as? String,
                  let fireDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            else { return nil }
            return ResumeReminder(gameID: gameID, fireDate: fireDate)
        }
    }

    nonisolated private static func add(_ reminder: ResumeReminder, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [ResumeReminderNotification.gameIDKey: reminder.gameID]
        // 時間間隔のトリガーは `nextTriggerDate()` が「問い合わせた時点から」の時刻を返し、
        // 上限の判定（古いものから外す）に使えないため、日時で指定する。
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate
        )
        let request = UNNotificationRequest(
            identifier: ResumeReminderNotification.identifier(for: reminder.gameID),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// 通知のタップを受ける（#663）。アプリが終了していた状態からのタップも拾うため、
/// 起動処理の中で delegate を立てる（SwiftUI の `App` だけでは起動時のタップを受け取れない）。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// タップされた。そのゲームを開くようハブへ伝える。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let gameID = response.notification.request.content.userInfo[ResumeReminderNotification.gameIDKey] as? String
        else { return }
        await MainActor.run {
            AppEnvironment.reminders.notificationTapped(gameID: gameID)
        }
    }

    /// アプリを開いている最中に届いたら出さない。ハブを見ている人に「途中のままです」は要らない。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }
}
