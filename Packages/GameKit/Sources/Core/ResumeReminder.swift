import Foundation
import Observation

// MARK: - 中断したゲームのお知らせ（#663）

/// 通知の許諾状態。`UNAuthorizationStatus` を Core から見える形に縮めたもの
/// （Core は UserNotifications を import しない。macOS の `swift test` で規則を検証するため）。
public enum ReminderAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    /// ダイアログを出さずに得る仮の許可（`.provisional`）。通知センターに静かに届く。
    case provisional
    case authorized

    /// 予約してよい状態か。
    public var allowsScheduling: Bool {
        switch self {
        case .provisional, .authorized: return true
        case .notDetermined, .denied:   return false
        }
    }
}

/// 予約済みのお知らせ 1 件。ゲームごとに高々 1 件なので `gameID` が識別子を兼ねる。
public struct ResumeReminder: Equatable, Sendable {
    public let gameID: String
    public let fireDate: Date

    public init(gameID: String, fireDate: Date) {
        self.gameID = gameID
        self.fireDate = fireDate
    }
}

/// お知らせの予約先。App は `UNUserNotificationCenter` で実装し、テストはスパイを注入する。
///
/// 予約済みの一覧は OS（通知センター）が持っている。**アプリ側に新しい保存先を作らない**ため、
/// 件数の上限や置き換えの判定は毎回ここから読み直す。
@MainActor
public protocol ResumeReminderScheduler: AnyObject {
    func authorization() async -> ReminderAuthorization
    /// `.provisional` で許可を求め、その後の状態を返す。**許可ダイアログは出ない**（#663 の決裁 (a)）。
    func requestProvisionalAuthorization() async -> ReminderAuthorization
    func pendingReminders() async -> [ResumeReminder]
    /// 同じゲームの予約が既にあれば置き換える。
    func schedule(_ reminder: ResumeReminder, title: String, body: String) async
    func cancel(gameIDs: [String])
    func cancelAll()
}

/// いつ・何件・どんな文言で知らせるかの規則。状態を持たない。
public enum ResumeReminderPolicy {
    /// ハブへ戻ってから知らせるまでの基本の間隔。
    public static let delay: TimeInterval = 24 * 60 * 60
    /// 同時に予約しておく件数の上限（全ゲーム合計）。
    public static let maxPending = 3
    /// 知らせてよい時間帯（端末の現地時刻の「時」）。基本の間隔がこの外に落ちたら、
    /// 次にこの時間帯が始まる時刻まで後ろへずらす。ずらしても 36 時間後が最大で、
    /// Issue の「24〜48時間後」に収まる。
    public static let deliveryHours = 9..<21

    public static func fireDate(leftAt: Date, calendar: Calendar) -> Date {
        let candidate = leftAt.addingTimeInterval(delay)
        let hour = calendar.component(.hour, from: candidate)
        guard !deliveryHours.contains(hour) else { return candidate }
        let startOfDay = calendar.startOfDay(for: candidate)
        let day = hour < deliveryHours.lowerBound
            ? startOfDay
            : calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        return calendar.date(bySettingHour: deliveryHours.lowerBound, minute: 0, second: 0, of: day)
            ?? candidate
    }

    /// `gameID` を新しく予約するときに取り消す予約。同じゲームの既存の予約は置き換わるので数えず、
    /// 他のゲームの予約が上限に達していれば**知らせる時刻が早いもの（＝古い中断）から**外す。
    public static func evictions(pending: [ResumeReminder], adding gameID: String) -> [String] {
        let others = pending
            .filter { $0.gameID != gameID }
            .sorted { $0.fireDate < $1.fireDate }
        let overflow = others.count - (maxPending - 1)
        guard overflow > 0 else { return [] }
        return others.prefix(overflow).map(\.gameID)
    }

    /// 通知の文言。汎用の「遊びに来てね」は送らず、戻る理由（途中の局）だけを書く。
    public static func content(gameTitle: String) -> (title: String, body: String) {
        ("「\(gameTitle)」が途中のままです", "続きから、そのまま遊べます。")
    }
}

/// 中断したゲームのお知らせ（#663）。**中断データを持ってハブへ戻ったときだけ**、
/// 1 日ほど後に「続きから遊べます」を 1 件予約する。
///
/// - 同じゲームは 1 件、全体で `ResumeReminderPolicy.maxPending` 件まで
/// - そのゲームを開く・中断データが消える（終局・やり直し・設定の切り替え）と取り消す
/// - 許諾が未決定なら `.provisional` を求めてから予約する。**許可ダイアログは出さない**
/// - 決着済みの局は、次のプレイを始めるか1手指すまで予約しない（将棋・チェスは終局後の見返しを
///   中断データに残すため、「中断データがある」だけでは途中の局と見分けられない）
/// - 撮影モード・DEBUG ビルドでは予約しない（`isSuppressed`）
@MainActor
@Observable
public final class ResumeReminderService {
    /// 通知がタップされて開くよう求められたゲーム。ハブが読んで遷移し、nil に戻す
    /// （`RecommendationService.requestedGameID` と同じ受け渡し）。
    public var requestedGameID: String?

    @ObservationIgnored private let scheduler: ResumeReminderScheduler
    @ObservationIgnored private let isEnabled: @MainActor () -> Bool
    @ObservationIgnored private let isSuppressed: Bool
    @ObservationIgnored private let reminderTitle: @MainActor (String) -> String?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar

    /// ゲームごとの世代。開いた・中断データが消えたで進める。予約は OS への問い合わせを
    /// 挟むため、**待っている間に開き直された**予約を捨てる目印に使う。
    @ObservationIgnored private var epochs: [String: Int] = [:]
    /// 全体の世代。すべて取り消したときに進める。
    @ObservationIgnored private var globalEpoch = 0
    /// 決着済みのゲーム。中断データが残っていても（将棋・チェスは終局後の見返しを保存する）
    /// 戻った先に続きが無いので予約しない。新しいプレイを始めた・1手指したで外す。
    @ObservationIgnored private var finishedGameIDs: Set<String> = []
    /// 最後に始めた予約の処理。予約は 1 件ずつ直列に流す（並ぶと上限の判定が古い一覧で走る）。
    @ObservationIgnored public private(set) var pendingWork: Task<Void, Never>?

    /// - Parameters:
    ///   - isEnabled: 設定の「続きのお知らせ」。
    ///   - isSuppressed: 撮影モード・DEBUG ビルド。true なら予約も許諾の要求もしない。
    ///   - reminderTitle: 通知に出すゲーム名。対象外のゲーム（登録外・中断データから局を
    ///     復元しない `GameModule.resumesFromSnapshot == false`）は nil を返す。
    public init(
        scheduler: ResumeReminderScheduler,
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

    /// ゲーム画面からハブへ戻った（`GameServices.gameDidLeave` から呼ぶ）。
    public func gameDidLeave(gameID: String, hasSnapshot: Bool) {
        guard !isSuppressed, hasSnapshot, !finishedGameIDs.contains(gameID), isEnabled(),
              let title = reminderTitle(gameID)
        else { return }
        let token = epochs[gameID, default: 0]
        let global = globalEpoch
        let leftAt = now()
        let previous = pendingWork
        pendingWork = Task { [weak self] in
            await previous?.value
            await self?.schedule(gameID: gameID, title: title, leftAt: leftAt, token: token, global: global)
        }
    }

    /// 決着した（`GameServices.gameDidFinish`・見返しの復元 `gameDidRestoreFinished` から呼ぶ）。
    public func gameDidFinish(gameID: String) {
        finishedGameIDs.insert(gameID)
    }

    /// 新しいプレイを始めた・1手指した（`GameServices.gameDidStart` / `gameDidRestart` /
    /// `gameDidProgress` から呼ぶ）。決着後に続けて遊ぶ局（2048 の「続ける」等）もここを通る。
    public func gameDidBeginPlay(gameID: String) {
        finishedGameIDs.remove(gameID)
    }

    /// そのゲームを開いた（`GameServices.gameDidOpen` から呼ぶ）。
    public func gameDidOpen(gameID: String) {
        withdraw(gameID)
    }

    /// そのゲームの中断データが消えた（終局・やり直し・設定の切り替え）。
    public func snapshotDidClear(gameID: String) {
        withdraw(gameID)
    }

    /// 設定でオフにした。予約済みのものもすべて取り消す。
    public func cancelAll() {
        globalEpoch += 1
        scheduler.cancelAll()
    }

    /// 通知がタップされた。対象外の ID（アプリの更新で外れたゲーム等）は無視する。
    public func notificationTapped(gameID: String) {
        guard reminderTitle(gameID) != nil else { return }
        requestedGameID = gameID
    }

    private func withdraw(_ gameID: String) {
        epochs[gameID, default: 0] += 1
        scheduler.cancel(gameIDs: [gameID])
    }

    private func schedule(gameID: String, title: String, leftAt: Date, token: Int, global: Int) async {
        var status = await scheduler.authorization()
        if status == .notDetermined {
            status = await scheduler.requestProvisionalAuthorization()
        }
        guard status.allowsScheduling else { return }
        let pending = await scheduler.pendingReminders()
        // 問い合わせを待つ間に開き直された・中断データが消えた・設定を切られたなら予約しない。
        guard epochs[gameID, default: 0] == token, globalEpoch == global, isEnabled() else { return }

        let evicted = ResumeReminderPolicy.evictions(pending: pending, adding: gameID)
        if !evicted.isEmpty {
            scheduler.cancel(gameIDs: evicted)
        }
        let content = ResumeReminderPolicy.content(gameTitle: title)
        await scheduler.schedule(
            ResumeReminder(
                gameID: gameID,
                fireDate: ResumeReminderPolicy.fireDate(leftAt: leftAt, calendar: calendar)
            ),
            title: content.title,
            body: content.body
        )
    }
}
