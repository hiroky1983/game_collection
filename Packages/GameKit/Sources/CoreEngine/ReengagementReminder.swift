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

/// お知らせの予約先。**複数ゲームのスレッドが並行しうる**（会長決裁 2026-09-21・#1229）ため、
/// どのスレッドがアクティブかは `ReengagementReminderStore` が持ち、ここはゲーム単位の
/// 予約の出し入れだけを担う（#663 の `ResumeReminderScheduler` と同じ「OS は予約の実体だけを持つ」設計）。
@MainActor
public protocol ReengagementReminderScheduler: AnyObject {
    func authorization() async -> ReminderAuthorization
    /// 標準の許可ダイアログを出して求める。**`.provisional` は含めない**
    /// （会長決裁 2026-09-21。#663 の `requestProvisionalAuthorization` とは異なる）。
    func requestExplicitAuthorization() async -> ReminderAuthorization
    /// 対象ゲームの予約を `fireDates` ぶん入れる（既存の同ゲームの予約があれば置き換える）。
    /// `fireDates` が空なら、そのゲームの予約をすべて取り消すのと同じ効果になる。
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
    /// 新しいスレッドを追加してよい間隔（会長決裁 2026-09-21）。直近の追加からこの日数が
    /// 経つまでは、新しい対象が選ばれてもスレッド化を見送る（通知が増えすぎるのを防ぐ）。
    public static let newThreadCooldownDays = 3

    /// `minimumIdleDays` 日以上遊んでいないゲームのうち、プレイ回数が最も多いもの 1 件を選ぶ。
    /// 同率は `availableIDs`（ハブの並び順）の先頭を採る（会長決裁 2026-09-20）。
    ///
    /// - Parameters:
    ///   - games: 全ゲームの入力（登録ゲームぶん）。
    ///   - availableIDs: ハブに並んでいるゲーム（非表示を除く、ハブの並び順）。
    public static func candidate(
        games: [ReengagementCandidateInput],
        availableIDs: [String],
        now: Date,
        calendar: Calendar = .current
    ) -> String? {
        let available = Set(availableIDs)
        let eligible = games.filter { input in
            guard available.contains(input.gameID), input.plays > 0, let last = input.lastPlayedAt else { return false }
            guard let eligibleAt = calendar.date(byAdding: .day, value: minimumIdleDays, to: last) else { return false }
            return now >= eligibleAt
        }
        guard let maxPlays = eligible.map(\.plays).max() else { return nil }
        let topGameIDs = Set(eligible.filter { $0.plays == maxPlays }.map(\.gameID))
        return availableIDs.first { topGameIDs.contains($0) }
    }

    /// 最終プレイ日時から `offsetDays` ぶんの発火時刻。既に過去に落ちるものは含めない
    /// （例: 40日ぶりに評価すると7日後・30日後は既に過去なので60日後だけになる）。
    public static func fireDates(lastPlayedAt: Date, now: Date, calendar: Calendar) -> [Date] {
        fireSchedule(lastPlayedAt: lastPlayedAt, now: now, calendar: calendar).map(\.date)
    }

    /// `fireDates` と同じ規則だが、発火までの日数（7 / 30 / 60）も一緒に返す。
    /// 複数スレッドの発火日が同日に重なったときの優劣判定（`resolvingCollisions`）に使う。
    public static func fireSchedule(lastPlayedAt: Date, now: Date, calendar: Calendar) -> [(days: Int, date: Date)] {
        offsetDays.compactMap { days in
            guard let base = calendar.date(byAdding: .day, value: days, to: lastPlayedAt) else { return nil }
            let atHour = calendar.date(bySettingHour: deliveryHour, minute: 0, second: 0, of: base) ?? base
            return atHour > now ? (days, atHour) : nil
        }
    }

    /// 60日後の発火予定時刻。**過去でも計算する**（`isUnresponsiveAfterSixtyDays` の判定に使うため、
    /// `fireSchedule` と違って「既に過去なら除外」しない）。
    public static func sixtyDayFireDate(lastPlayedAt: Date, calendar: Calendar) -> Date? {
        guard let sixty = offsetDays.last,
              let base = calendar.date(byAdding: .day, value: sixty, to: lastPlayedAt)
        else { return nil }
        return calendar.date(bySettingHour: deliveryHour, minute: 0, second: 0, of: base) ?? base
    }

    /// 60日後通知の発火予定時刻から24時間経ったか（会長決裁 2026-09-21）。
    /// OS に「N時間後にコードを実行する」仕組みが無いため、既存の再評価タイミング
    /// （`applicationDidEnterBackground` 等）のたびにこの条件を受動的にチェックする。
    public static func isUnresponsiveAfterSixtyDays(fireDate: Date, now: Date) -> Bool {
        now >= fireDate.addingTimeInterval(24 * 60 * 60)
    }

    /// 直近のスレッド追加から `newThreadCooldownDays` 日以上経っているか（会長決裁 2026-09-21）。
    public static func canAddNewThread(lastThreadAddedAt: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastThreadAddedAt else { return true }
        guard let cooldownEnds = calendar.date(byAdding: .day, value: newThreadCooldownDays, to: lastThreadAddedAt) else {
            return true
        }
        return now >= cooldownEnds
    }

    /// 複数スレッドの発火予定が同じ暦日に重なったら、日数が大きい方（＝より切迫している方）だけを残す
    /// （会長決裁 2026-09-21）。小さい方はその回だけスキップされる（スレッド自体は他の予定日が残っていれば続く）。
    /// 日数まで同じ場合も 1 件だけ残す（`gameID` の昇順で先の方。Dictionary の反復順に依存させない）。
    public static func resolvingCollisions(
        threads: [String: [(days: Int, date: Date)]],
        calendar: Calendar
    ) -> [String: [Date]] {
        struct Entry { let gameID: String; let days: Int; let date: Date }
        let entries = threads.flatMap { gameID, schedule in
            schedule.map { Entry(gameID: gameID, days: $0.days, date: $0.date) }
        }
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.date) }
        var result: [String: [Date]] = [:]
        for (_, group) in grouped {
            guard let maxDays = group.map(\.days).max() else { continue }
            guard let winner = group.filter({ $0.days == maxDays }).min(by: { $0.gameID < $1.gameID }) else { continue }
            result[winner.gameID, default: []].append(winner.date)
        }
        for key in result.keys { result[key]?.sort() }
        return result
    }

    /// 通知の文言。
    public static func content(gameTitle: String) -> (title: String, body: String) {
        ("「\(gameTitle)」、久しぶりに遊んでみませんか？", "以前よく遊んでいたあそびです。")
    }
}

/// 複数スレッド化・永続停止のための永続状態（会長決裁 2026-09-21・#1229）。
///
/// **OS の予約一覧だけでは「60日後通知が発火した」という過去の事実を確定できない**
/// （発火後は通知センターに届いたものとして残るだけで、元の発火予定時刻を後から
/// 取り出せる保証が無い）ため、スレッドの起点（そのスレッドを作った時点の最終プレイ日時）を
/// ここに永続化する。保存先は端末内の `UserDefaults` のみ（サーバ送信なし）。
public struct ReengagementReminderStore {
    private let defaults: UserDefaults
    private static let activeThreadsKey = "reengagement_activeThreads_v1"
    private static let lastThreadAddedAtKey = "reengagement_lastThreadAddedAt_v1"
    private static let permanentlyStoppedKey = "reengagement_permanentlyStopped_v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// アクティブなスレッド。キー = gameID、値 = そのスレッドの起点になった最終プレイ日時
    /// （`ReengagementReminderPolicy.fireSchedule` に渡す基準値として使う）。
    public var activeThreads: [String: Date] {
        get {
            guard let data = defaults.data(forKey: Self.activeThreadsKey),
                  let raw = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return [:] }
            return raw.mapValues(Date.init(timeIntervalSince1970:))
        }
        nonmutating set {
            let raw = newValue.mapValues(\.timeIntervalSince1970)
            defaults.set(try? JSONEncoder().encode(raw), forKey: Self.activeThreadsKey)
        }
    }

    /// 最後に新しいスレッドを追加した日時（3日クールダウンの起点。会長決裁 2026-09-21）。
    /// ゲームごとではなく全体で 1 つ。
    public var lastThreadAddedAt: Date? {
        get { (defaults.object(forKey: Self.lastThreadAddedAtKey) as? Double).map(Date.init(timeIntervalSince1970:)) }
        nonmutating set { defaults.set(newValue?.timeIntervalSince1970, forKey: Self.lastThreadAddedAtKey) }
    }

    /// 60日後通知への無反応でユーザー全体が永続停止したか（会長決裁 2026-09-21）。
    public var isPermanentlyStopped: Bool {
        get { defaults.bool(forKey: Self.permanentlyStoppedKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.permanentlyStoppedKey) }
    }
}

/// よく遊んでいたのに最近開いていないゲームへの再エンゲージメント通知（#1193）。
///
/// - アプリがバックグラウンドに入るたびに対象を判定し直す（`applicationDidEnterBackground`）。
///   **対象は常に高々1ゲームではなく、複数ゲームのスレッドが並行しうる**
///   （会長決裁 2026-09-21・#1229）。新しい対象が選ばれても、既存のアクティブなスレッドは
///   キャンセルしない。同じゲームが再度選ばれても、既にアクティブなスレッドがあれば何もしない
/// - 新しいスレッドの追加は、直近の追加から `ReengagementReminderPolicy.newThreadCooldownDays`
///   日以上空ける（通知が増えすぎるのを防ぐ）
/// - 複数スレッドの発火日が同じ暦日に重なったら、日数が大きい方だけ送り、小さい方はその回だけスキップする
/// - 60日後通知が発火してから24時間経っても未反応（`lastPlayedAt` が不変）なら、
///   そのユーザー全体でこの機能を永続的に停止する
/// - そのゲームを開くと、そのゲームのスレッドだけ止める（1回でも開いたら以降は停止・会長決裁 2026-09-20）
/// - 許諾が未決定なら、標準の許可ダイアログ（明示的な許可）を求めてから予約する。**#663 とは異なり
///   `.provisional` は使わない**（会長決裁 2026-09-21）
/// - 撮影モード・DEBUG ビルドでは予約しない
@MainActor
@Observable
public final class ReengagementReminderService {
    /// 通知がタップされて開くよう求められたゲーム。ハブが読んで遷移し、nil に戻す。
    public var requestedGameID: String?

    @ObservationIgnored private let scheduler: ReengagementReminderScheduler
    @ObservationIgnored private let store: ReengagementReminderStore
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
        store: ReengagementReminderStore = ReengagementReminderStore(),
        isEnabled: @escaping @MainActor () -> Bool,
        isSuppressed: Bool,
        reminderTitle: @escaping @MainActor (String) -> String?,
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.scheduler = scheduler
        self.store = store
        self.isEnabled = isEnabled
        self.isSuppressed = isSuppressed
        self.reminderTitle = reminderTitle
        self.now = now
        self.calendar = calendar
    }

    /// アプリがバックグラウンドに入った（`GameCollectionApp` の `scenePhase` から呼ぶ）。
    public func applicationDidEnterBackground(games: [ReengagementCandidateInput], availableIDs: [String]) {
        guard !isSuppressed, isEnabled(), !store.isPermanentlyStopped else { return }
        let target = ReengagementReminderPolicy.candidate(games: games, availableIDs: availableIDs, now: now(), calendar: calendar)
        epoch += 1
        let token = epoch
        let previous = pendingWork
        pendingWork = Task { [weak self] in
            await previous?.value
            await self?.apply(target: target, games: games, token: token)
        }
    }

    /// そのゲームを開いた。予約が残っていれば消す（識別子はゲーム単位で決まるので、
    /// 予約が無いゲームに対して呼んでも何も起きない）。
    public func gameDidOpen(gameID: String) {
        // 進行中の判定〜予約タスクが後から追加してしまわないよう、世代を進めてから取り消す
        // （#663 と同じ設計。CodeRabbit 指摘・PR #1223）。
        epoch += 1
        store.activeThreads.removeValue(forKey: gameID)
        scheduler.cancel(gameID: gameID)
    }

    /// 設定でオフにした。予約済み・アクティブなスレッドの記録もすべて取り消す
    /// （オンに戻したとき、古いスレッドの状態を引きずらない）。
    public func cancelAll() {
        epoch += 1
        store.activeThreads = [:]
        store.lastThreadAddedAt = nil
        scheduler.cancelAll()
    }

    /// 通知がタップされた。対象外の ID（アプリの更新で外れたゲーム等）は無視する。
    public func notificationTapped(gameID: String) {
        guard reminderTitle(gameID) != nil else { return }
        requestedGameID = gameID
    }

    private func apply(target: String?, games: [ReengagementCandidateInput], token: Int) async {
        guard epoch == token else { return }
        let currentLastPlayed = Dictionary(uniqueKeysWithValues: games.map { ($0.gameID, $0.lastPlayedAt) })

        // 1. 60日後通知が発火してから24時間経っても未反応（lastPlayedAt が不変）なら、
        //    ユーザー全体を永続停止する（会長決裁 2026-09-21）。反応があった・確認できないスレッドは
        //    役目を終えたものとして外すだけにする。これらは OS への問い合わせを伴わないので、
        //    許諾の確認より前に済ませてよい。
        var activeThreads = store.activeThreads
        for (gameID, baseline) in store.activeThreads {
            guard let fireDate = ReengagementReminderPolicy.sixtyDayFireDate(lastPlayedAt: baseline, calendar: calendar),
                  ReengagementReminderPolicy.isUnresponsiveAfterSixtyDays(fireDate: fireDate, now: now())
            else { continue }
            if let current = currentLastPlayed[gameID] ?? nil, current == baseline {
                store.isPermanentlyStopped = true
                store.activeThreads = [:]
                store.lastThreadAddedAt = nil
                scheduler.cancelAll()
                return
            }
            activeThreads.removeValue(forKey: gameID)
        }
        // 非表示にした・アプリの更新で外れたゲームのスレッドは、新しい対象の有無に関係なくここで後始末する
        // （後段は新しい対象があるときにしか届かず、開けない通知が残りうる。CodeRabbit 指摘・PR #1234）。
        for gameID in activeThreads.keys.filter({ reminderTitle($0) == nil }) {
            scheduler.cancel(gameID: gameID)
            activeThreads.removeValue(forKey: gameID)
        }
        store.activeThreads = activeThreads
        guard epoch == token, !store.isPermanentlyStopped else { return }

        // 2. 新しい対象は、既にアクティブなスレッドが無く・クールダウンが明けていれば新規スレッドの
        //    「候補」にする。**ここではまだ永続化しない**: 許諾確認は OS への問い合わせを挟むため、
        //    待っている間に中断されると記録だけが残って実体の予約が無い状態になってしまう
        //    （PR #697・#1223 と同型の競合）。実際に記録するのは許諾が確認できてから（4）。
        guard let target, activeThreads[target] == nil,
              let newLastPlayedAt = currentLastPlayed[target] ?? nil,
              ReengagementReminderPolicy.canAddNewThread(lastThreadAddedAt: store.lastThreadAddedAt, now: now(), calendar: calendar)
        else { return }

        // 3. 許諾確認。
        var status = await scheduler.authorization()
        if status == .notDetermined {
            status = await scheduler.requestExplicitAuthorization()
        }
        guard status.allowsScheduling, epoch == token, isEnabled(), !store.isPermanentlyStopped else { return }

        // 4. 許諾が確認できたので新しいスレッドとして記録し、既存スレッドとあわせて発火予定を
        //    組み直す。同じ暦日に重なったら日数の大きい方だけ残してから反映する。
        let previousLastThreadAddedAt = store.lastThreadAddedAt
        let addedAt = now()
        activeThreads[target] = newLastPlayedAt
        store.lastThreadAddedAt = addedAt
        store.activeThreads = activeThreads

        var perThreadSchedule: [String: [(days: Int, date: Date)]] = [:]
        for (gameID, baseline) in activeThreads {
            perThreadSchedule[gameID] = ReengagementReminderPolicy.fireSchedule(lastPlayedAt: baseline, now: now(), calendar: calendar)
        }
        let resolved = ReengagementReminderPolicy.resolvingCollisions(threads: perThreadSchedule, calendar: calendar)

        for gameID in activeThreads.keys {
            guard let title = reminderTitle(gameID) else {
                scheduler.cancel(gameID: gameID)
                store.activeThreads.removeValue(forKey: gameID)
                continue
            }
            let content = ReengagementReminderPolicy.content(gameTitle: title)
            await scheduler.schedule(gameID: gameID, fireDates: resolved[gameID] ?? [], title: content.title, body: content.body)
            // 追加の完了を待つ間に判定がやり直された・設定を切られたなら、入った予約を取り消す
            // （取り消しが追加より先に処理されると残ってしまうため。PR #697 の CodeRabbit 指摘と同型）。
            guard epoch == token, isEnabled(), !store.isPermanentlyStopped else {
                scheduler.cancel(gameID: gameID)
                // 新規スレッドの記録だけが残ると、次の判定で「既にアクティブ」と見なされ永久に予約されない。
                // 巻き戻して次の判定でやり直せるようにする（記録が別の処理で書き換わっていれば触らない）。
                scheduler.cancel(gameID: target)
                store.activeThreads.removeValue(forKey: target)
                if store.lastThreadAddedAt == addedAt { store.lastThreadAddedAt = previousLastThreadAddedAt }
                return
            }
        }
    }
}
