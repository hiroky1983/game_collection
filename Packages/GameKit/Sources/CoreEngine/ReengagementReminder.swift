import Foundation
import Observation

// MARK: - 再エンゲージメント通知（#1193）

/// 対象判定に使う 1 ゲームぶんの入力（通算プレイ回数・最終プレイ日時）。
public struct ReengagementCandidateInput: Equatable, Sendable {
    public let gameID: String
    public let plays: Int
    public let lastPlayedAt: Date?

    public init(gameID: String, plays: Int, lastPlayedAt: Date?) {
        self.gameID = gameID
        self.plays = plays
        self.lastPlayedAt = lastPlayedAt
    }
}

/// お知らせの予約先。#663（`ResumeReminderScheduler`）と違い、狙う対象は常に高々1ゲームなので、
/// 予約の一覧を読み直す設計ではなく「今の対象」を都度 OS へ聞く形にする
/// （予約済みの一覧は OS が真実の源で、アプリ側に新しい保存先を作らない方針は #663 と同じ）。
@MainActor
public protocol ReengagementReminderScheduler: AnyObject {
    func authorization() async -> ReminderAuthorization
    /// 標準の許可ダイアログを出して求める。**`.provisional` は含めない**
    /// （会長決裁 2026-09-21。#663 の `requestProvisionalAuthorization` とは異なる）。
    func requestExplicitAuthorization() async -> ReminderAuthorization
    /// 現在 OS に予約が残っているゲーム。無ければ nil。
    func scheduledGameID() async -> String?
    /// 対象ゲームの予約を `fireDates` ぶん入れる（既存の同ゲームの予約があれば置き換える）。
    func schedule(gameID: String, fireDates: [Date], title: String, body: String) async
    /// そのゲームぶんの予約（発火済みで通知センターに残っているものも含む）を消す。無くても安全。
    func cancel(gameID: String)
    /// 設定でオフにしたときにすべて消す。
    func cancelAll()
}

/// いつ・どのゲームに知らせるかの規則。状態を持たない。
public enum ReengagementReminderPolicy {
    /// 対象になるための最低の未プレイ日数（会長決裁 2026-09-20）。
    public static let minimumIdleDays = 7
    /// 最終プレイからの発火オフセット（長期スパン。会長決裁 2026-09-20）。
    public static let offsetDays = [7, 30, 60]
    /// 送信時刻（端末の現地時刻の「時」。会長決裁 2026-09-20）。
    public static let deliveryHour = 19

    /// `minimumIdleDays` 日以上遊んでいないゲームのうち、プレイ回数が最も多いもの 1 件を選ぶ。
    /// 同率は `availableIDs`（ハブの並び順）の先頭を採る（会長決裁 2026-09-20）。
    ///
    /// - Parameters:
    ///   - games: 全ゲームの入力（登録ゲームぶん）。
    ///   - availableIDs: ハブに並んでいるゲーム（非表示を除く、ハブの並び順）。
    public static func candidate(
        games: [ReengagementCandidateInput],
        availableIDs: [String],
        now: Date
    ) -> String? {
        let available = Set(availableIDs)
        let eligible = games.filter { input in
            guard available.contains(input.gameID), input.plays > 0, let last = input.lastPlayedAt else { return false }
            return now.timeIntervalSince(last) >= Double(minimumIdleDays) * 86_400
        }
        guard let maxPlays = eligible.map(\.plays).max() else { return nil }
        let topGameIDs = Set(eligible.filter { $0.plays == maxPlays }.map(\.gameID))
        return availableIDs.first { topGameIDs.contains($0) }
    }

    /// 最終プレイ日時から `offsetDays` ぶんの発火時刻。既に過去に落ちるものは含めない
    /// （例: 40日ぶりに評価すると7日後・30日後は既に過去なので60日後だけになる）。
    public static func fireDates(lastPlayedAt: Date, now: Date, calendar: Calendar) -> [Date] {
        offsetDays.compactMap { days in
            let base = lastPlayedAt.addingTimeInterval(Double(days) * 86_400)
            let atHour = calendar.date(bySettingHour: deliveryHour, minute: 0, second: 0, of: base) ?? base
            return atHour > now ? atHour : nil
        }
    }

    /// 通知の文言。
    public static func content(gameTitle: String) -> (title: String, body: String) {
        ("「\(gameTitle)」、久しぶりに遊んでみませんか？", "以前よく遊んでいたあそびです。")
    }
}

/// よく遊んでいたのに最近開いていないゲームへの再エンゲージメント通知（#1193）。
///
/// - アプリがバックグラウンドに入るたびに対象を判定し直す（`applicationDidEnterBackground`）。
///   対象が変われば古い対象の予約を消して新しい対象へ置き換え、対象が無くなれば消すだけにする
/// - そのゲームを開くと、それ以降の予約は止める（1回でも開いたら以降は停止・会長決裁 2026-09-20）
/// - 許諾が未決定なら、標準の許可ダイアログ（明示的な許可）を求めてから予約する。**#663 とは異なり
///   `.provisional` は使わない**（会長決裁 2026-09-21）
/// - 撮影モード・DEBUG ビルドでは予約しない
@MainActor
@Observable
public final class ReengagementReminderService {
    /// 通知がタップされて開くよう求められたゲーム。ハブが読んで遷移し、nil に戻す。
    public var requestedGameID: String?

    @ObservationIgnored private let scheduler: ReengagementReminderScheduler
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let isSuppressed: Bool
    @ObservationIgnored private let reminderTitle: @MainActor (String) -> String?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// 判定〜予約の世代。待っている間に次の判定が始まった処理を捨てる目印（#663 と同じ設計）。
    @ObservationIgnored private var epoch = 0
    @ObservationIgnored public private(set) var pendingWork: Task<Void, Never>?

    public init(
        scheduler: ReengagementReminderScheduler,
        isEnabled: @escaping @MainActor () -> Bool,
        isSuppressed: Bool,
        reminderTitle: @escaping @MainActor (String) -> String?,
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler
        self.isEnabled = isEnabled
        self.isSuppressed = isSuppressed
        self.reminderTitle = reminderTitle
        self.now = now
        self.calendar = calendar
    }

    /// アプリがバックグラウンドに入った（`GameCollectionApp` の `scenePhase` から呼ぶ）。
    public func applicationDidEnterBackground(games: [ReengagementCandidateInput], availableIDs: [String]) {
        guard !isSuppressed, isEnabled() else { return }
        let target = ReengagementReminderPolicy.candidate(games: games, availableIDs: availableIDs, now: now())
        let lastPlayedAt = target.flatMap { id in games.first(where: { $0.gameID == id })?.lastPlayedAt }
        epoch += 1
        let token = epoch
        let previous = pendingWork
        pendingWork = Task { [weak self] in
            await previous?.value
            await self?.apply(target: target, lastPlayedAt: lastPlayedAt, token: token)
        }
    }

    /// そのゲームを開いた。予約が残っていれば消す（識別子はゲーム単位で決まるので、
    /// 予約が無いゲームに対して呼んでも何も起きない）。
    public func gameDidOpen(gameID: String) {
        scheduler.cancel(gameID: gameID)
    }

    /// 設定でオフにした。予約済みのものもすべて取り消す。
    public func cancelAll() {
        epoch += 1
        scheduler.cancelAll()
    }

    /// 通知がタップされた。対象外の ID（アプリの更新で外れたゲーム等）は無視する。
    public func notificationTapped(gameID: String) {
        guard reminderTitle(gameID) != nil else { return }
        requestedGameID = gameID
    }

    private func apply(target: String?, lastPlayedAt: Date?, token: Int) async {
        let previousTarget = await scheduler.scheduledGameID()
        guard epoch == token else { return }

        guard let target, let lastPlayedAt, let title = reminderTitle(target) else {
            if let previousTarget { scheduler.cancel(gameID: previousTarget) }
            return
        }
        if let previousTarget, previousTarget != target {
            scheduler.cancel(gameID: previousTarget)
        }

        var status = await scheduler.authorization()
        if status == .notDetermined {
            status = await scheduler.requestExplicitAuthorization()
        }
        guard status.allowsScheduling else { return }
        guard epoch == token, isEnabled() else { return }

        let fireDates = ReengagementReminderPolicy.fireDates(lastPlayedAt: lastPlayedAt, now: now(), calendar: calendar)
        guard !fireDates.isEmpty else {
            scheduler.cancel(gameID: target)
            return
        }
        let content = ReengagementReminderPolicy.content(gameTitle: title)
        await scheduler.schedule(gameID: target, fireDates: fireDates, title: content.title, body: content.body)
        // 追加の完了を待つ間に判定がやり直された・設定を切られたなら、入った予約を取り消す
        // （取り消しが追加より先に処理されると残ってしまうため。PR #697 の CodeRabbit 指摘と同型）。
        guard epoch == token, isEnabled() else {
            scheduler.cancel(gameID: target)
            return
        }
    }
}
