import Foundation
import Observation

// MARK: - 「回数が戻ったら知らせる」（#1576）

/// 予約先。App は `UNUserNotificationCenter` で実装し、テストはスパイを注入する。
/// 予約は常に高々 1 件（同じ識別子で置き換える）。**アプリ側に保存先を作らない**ため、
/// 予約の有無は OS の予約一覧から読み直す。
@MainActor
public protocol ChallengeReturnReminderScheduler: AnyObject {
    func authorization() async -> ReminderAuthorization
    /// 標準の許可ダイアログを出して求める（`.provisional` は含めない。#663・#1229 と同じ決裁）。
    func requestExplicitAuthorization() async -> ReminderAuthorization
    /// 予約済みの発火時刻。無ければ nil。
    func pendingFireDate() async -> Date?
    /// 既に予約があれば置き換える。
    func schedule(fireDate: Date, title: String, body: String) async
    /// 予約（発火済みで通知センターに残っているものも含む）を消す。無くても安全。
    func cancel()
}

/// 挑戦回数を使い切ったゲームの「戻ったら知らせる」（#1576）。
///
/// - 操作はユーザーのトグルだけ（既定オフ。自動では予約しない）。オンで 1 回だけ予約し、繰り返さない。
/// - 通知の許可は既存の共有設定（`isEnabled` = 設定の「通知」）に従う。オフなら予約しない
/// - 許諾が未決定なら標準の許可ダイアログを求めてから予約する
@MainActor
@Observable
public final class ChallengeReturnReminderService {
    public enum EnableResult: Equatable, Sendable {
        case scheduled
        /// 設定の「通知」がオフ。
        case notificationsOff
        /// OS の通知許可が無い。
        case denied
        /// 発火時刻が既に過ぎている（日付をまたいだ直後）。
        case expired
        /// 待っている間に取り消された。
        case superseded
    }

    @ObservationIgnored private let scheduler: ChallengeReturnReminderScheduler
    @ObservationIgnored private let isEnabledSetting: @MainActor () -> Bool
    @ObservationIgnored private let now: @MainActor () -> Date
    /// 予約〜取り消しの世代。許諾ダイアログを待っている間に取り消されたら、その予約を捨てる目印（#663 と同じ設計）。
    @ObservationIgnored private var epoch = 0

    public init(
        scheduler: ChallengeReturnReminderScheduler,
        isEnabled: @escaping @MainActor () -> Bool,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.scheduler = scheduler
        self.isEnabledSetting = isEnabled
        self.now = now
    }

    /// 設定の「通知」がオンか（シートのトグルを使えるか）。
    public var isNotificationsEnabled: Bool { isEnabledSetting() }

    /// 予約済みの発火時刻（トグルの初期状態を決める材料）。
    public func pendingFireDate() async -> Date? { await scheduler.pendingFireDate() }

    /// 予約する。
    public func enable(fireDate: Date, title: String, body: String) async -> EnableResult {
        guard isEnabledSetting() else { return .notificationsOff }
        epoch += 1
        let token = epoch
        var status = await scheduler.authorization()
        if status == .notDetermined {
            status = await scheduler.requestExplicitAuthorization()
        }
        guard status.allowsScheduling else { return .denied }
        guard epoch == token, isEnabledSetting() else { return .superseded }
        guard fireDate > now() else { return .expired }
        await scheduler.schedule(fireDate: fireDate, title: title, body: body)
        return .scheduled
    }

    /// トグルをオフにした・設定で通知をオフにした。予約中の処理も捨てる。
    public func cancel() {
        epoch += 1
        scheduler.cancel()
    }
}
