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

    func requestExplicitAuthorization() async -> ReminderAuthorization {
        // `.provisional` を含めない = 標準の許可ダイアログが出る（会長決裁 2026-09-21・#1219）。
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
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
        // 再エンゲージメント通知（#1193）が別の識別子空間で予約されるようになったため、
        // 全消し（removeAllPendingNotificationRequests）は使わず、続きのお知らせだけを対象にする
        // （CodeRabbit 指摘・PR #1228。全消しだとオンのままの再エンゲージメント通知も巻き込む）。
        Task { await Self.cancelAllPendingAndDelivered() }
    }

    // 通知センターの応答型は Sendable でないため、MainActor へ持ち込まずに値だけ取り出す。

    nonisolated private static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated private static func cancelAllPendingAndDelivered() async {
        let center = UNUserNotificationCenter.current()
        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ResumeReminderNotification.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        let deliveredIDs = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(ResumeReminderNotification.identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
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

/// 再エンゲージメント通知（#1193）の識別子。3件（7日・30日・60日後）を同じゲームで
/// 区別するため、末尾に発火順のインデックスを付ける。
enum ReengagementReminderNotification {
    static let identifierPrefix = "reengagement-reminder."
    static let gameIDKey = "gameID"

    static func identifier(for gameID: String, index: Int) -> String {
        identifierPrefix + gameID + ".\(index)"
    }
}

/// `ReengagementReminderService`（Core）の予約先を `UNUserNotificationCenter` で実装する。
/// #663 と識別子の名前空間を分けているので、お互いの予約を巻き込まずに操作できる。
@MainActor
final class UserNotificationReengagementScheduler: ReengagementReminderScheduler {
    private var center: UNUserNotificationCenter { .current() }

    /// `schedule` / `cancelAll` は通知センターへの問い合わせを挟むため、直列化しないと
    /// 「`cancelAll` が問い合わせている間に `schedule` が割り込み、その予約ごと消される」
    /// 競合が起きうる（CodeRabbit 指摘・PR #1228）。#663 の `pendingWork` と同じ設計。
    private var pendingOperation: Task<Void, Never>?

    func authorization() async -> ReminderAuthorization {
        switch await Self.authorizationStatus() {
        case .authorized:               return .authorized
        case .provisional, .ephemeral:  return .provisional
        case .notDetermined:            return .notDetermined
        case .denied:                   return .denied
        @unknown default:               return .denied
        }
    }

    func requestExplicitAuthorization() async -> ReminderAuthorization {
        // `.provisional` を含めない = 標準の許可ダイアログが出る（会長決裁 2026-09-21）。
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    func scheduledGameID() async -> String? {
        await Self.pendingGameID()
    }

    func schedule(gameID: String, fireDates: [Date], title: String, body: String) async {
        let previous = pendingOperation
        let task = Task<Void, Never> {
            await previous?.value
            // 前回の予約が残っているとインデックスがずれて末尾が重複するため、採番し直す前に必ず消す。
            let identifiers = ReengagementReminderPolicy.offsetDays.indices
                .map { ReengagementReminderNotification.identifier(for: gameID, index: $0) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
            await Self.add(gameID: gameID, fireDates: fireDates, title: title, body: body)
        }
        pendingOperation = task
        await task.value
    }

    func cancel(gameID: String) {
        let identifiers = ReengagementReminderPolicy.offsetDays.indices
            .map { ReengagementReminderNotification.identifier(for: gameID, index: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAll() {
        let previous = pendingOperation
        let task = Task<Void, Never> {
            await previous?.value
            await Self.cancelAllPendingAndDelivered()
        }
        pendingOperation = task
    }

    // 通知センターの応答型は Sendable でないため、MainActor へ持ち込まずに値だけ取り出す。

    nonisolated private static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated private static func pendingGameID() async -> String? {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .first { $0.identifier.hasPrefix(ReengagementReminderNotification.identifierPrefix) }
            .flatMap { $0.content.userInfo[ReengagementReminderNotification.gameIDKey] as? String }
    }

    nonisolated private static func cancelAllPendingAndDelivered() async {
        let center = UNUserNotificationCenter.current()
        let pendingIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReengagementReminderNotification.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        let deliveredIDs = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(ReengagementReminderNotification.identifierPrefix) }
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
    }

    nonisolated private static func add(gameID: String, fireDates: [Date], title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        for (index, fireDate) in fireDates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = [ReengagementReminderNotification.gameIDKey: gameID]
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: fireDate
            )
            let request = UNNotificationRequest(
                identifier: ReengagementReminderNotification.identifier(for: gameID, index: index),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

/// 通知のタップを受ける（#663・#1193）。アプリが終了していた状態からのタップも拾うため、
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
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let request = response.notification.request
        let userInfo = request.content.userInfo
        // gameIDKey は両方とも "gameID" で共通のため、先に識別子の接頭辞で通知の種類を判定する。
        if request.identifier.hasPrefix(ResumeReminderNotification.identifierPrefix),
           let gameID = userInfo[ResumeReminderNotification.gameIDKey] as? String {
            await MainActor.run {
                AppEnvironment.reminders.notificationTapped(gameID: gameID)
            }
        } else if request.identifier.hasPrefix(ReengagementReminderNotification.identifierPrefix),
                  let gameID = userInfo[ReengagementReminderNotification.gameIDKey] as? String {
            await MainActor.run {
                AppEnvironment.reengagement.notificationTapped(gameID: gameID)
            }
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
