import UIKit
import Core

/// ホーム画面アイコン長押し（Quick Actions・#1642）。
///
/// 項目の中身（件数・並び・非表示の除外）は `QuickActions` / `RecentGames` が決める。ここは
/// それを `UIApplicationShortcutItem` へ写すことと、タップされた項目をハブへ渡すことだけを持つ。
/// 新しく保存するものは無い（項目は毎回、中断データと `PlayLog` から組み立て直す）。
@MainActor
@Observable
final class QuickActionService {
    /// タップされて開くよう求められたゲーム。ハブが読んで遷移し、nil に戻す
    /// （`ResumeReminderService.requestedGameID` と同じ受け渡し）。
    var requestedGameID: String?

    /// 項目のタップを受ける。自分の項目でなければ false。
    @discardableResult
    func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let gameID = QuickActions.gameID(fromType: item.type) else { return false }
        requestedGameID = gameID
        return true
    }

    /// 項目を最新の状態に組み直す。バックグラウンドへ入るたびに呼ぶ（長押しできるのはアプリの外だけ）。
    /// 撮影モードでは設定しない（撮影端末のアイコンに項目を残さない）。
    func refresh(
        registry: GameRegistry,
        settings: GameSettings,
        snapshots: SnapshotStore,
        playLog: PlayLog
    ) {
        guard !AppEnvironment.isScreenshotMode else { return }
        let visible = settings.visibleModules(from: registry).map(\.id)
        let resuming = visible.filter { registry.hasResumableSnapshot(gameID: $0, in: snapshots) }
        let candidates = RecentGames.candidates(
            visibleGameIDs: visible,
            resumingGameIDs: Set(resuming),
            resumeUpdatedAt: resuming.reduce(into: [:]) { result, id in
                if let date = snapshots.modifiedAt(for: id) { result[id] = date }
            },
            lastPlayedAt: playLog.lastPlayedAtByGame
        )
        let items = QuickActions.items(candidates: candidates, title: { registry.module(id: $0)?.title })
        UIApplication.shared.shortcutItems = items.map { item in
            UIApplicationShortcutItem(
                type: item.type,
                localizedTitle: item.title,
                localizedSubtitle: item.subtitle,
                icon: UIApplicationShortcutIcon(type: item.subtitle == nil ? .time : .play)
            )
        }
    }
}

/// 起動中・バックグラウンドからのタップを受ける。
/// アプリが終了していた状態から起動を起こした項目は、ここへ来ず `AppDelegate` が受ける。
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(MainActor.assumeIsolated { AppEnvironment.quickActions.handle(shortcutItem) })
    }
}
