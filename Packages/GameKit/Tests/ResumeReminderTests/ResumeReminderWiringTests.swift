import Foundation
import Testing

/// 中断したゲームのお知らせ（#663）の**結線**。OS へ渡す部分と通知のタップは App ターゲットにあり
/// GameKit のテストから import できないため、`HubRecentRowWiringTests`（#660）と同じくソースを走査して固定する。
///
/// 読み口は `App/` のディレクトリ一式で、行コメントを落としてから走査する（説明文の言及に当たって
/// 「実装が消えても緑」になるのを防ぐ）。
@Suite("中断のお知らせの結線（#663）")
struct ResumeReminderWiringTests {
    private static var appDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ResumeReminderTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // GameKit/
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // リポジトリのルート
            .appendingPathComponent("App")
    }

    private static func appSources() throws -> String {
        let files = try FileManager.default
            .contentsOfDirectory(at: appDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        #expect(!files.isEmpty, "App/ の走査に失敗している")
        return try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func matches(_ pattern: String, in source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }

    @Test("中断データの消去が取り消しに届き、サービスが GameServices に渡っている")
    func servicesAreWired() throws {
        let source = try Self.appSources()
        #expect(
            Self.matches(#"snapshots: ClearObservingSnapshotStore\(base: FileSnapshotStore\(\)\) \{[^}]*reminders\.snapshotDidClear\(gameID: gameID\)"#, in: source),
            "中断データの消去（終局・やり直し）がお知らせの取り消しに届いていない"
        )
        #expect(Self.matches(#"gameCenter: gameCenter,\s*reminders: reminders\s*\)"#, in: source),
                "ResumeReminderService が GameServices に渡っていない（離脱・開いたの両方が届かない）")
    }

    @Test("撮影モードと DEBUG ビルドでは予約しない")
    func suppressedInScreenshotAndDebug() throws {
        let source = try Self.appSources()
        #expect(Self.matches(#"isSuppressed: isScreenshotMode \|\| isDebugBuild"#, in: source),
                "撮影モードまたは DEBUG ビルドで予約が止まっていない")
        #expect(Self.matches(#"static var isDebugBuild: Bool \{\s*#if DEBUG\s*return true\s*#else\s*return false\s*#endif"#, in: source),
                "isDebugBuild が DEBUG 構成を見ていない")
    }

    @Test("中断データから局を復元しないゲームは対象外")
    func unresumableGamesAreExcluded() throws {
        let source = try Self.appSources()
        #expect(Self.matches(#"reminderTitle: \{ gameID in\s*guard let module = registry\.module\(id: gameID\), module\.resumesFromSnapshot else \{ return nil \}"#, in: source),
                "resumesFromSnapshot を見ずに通知の対象を決めている")
    }

    @Test("許可はダイアログの出ない provisional でだけ求める")
    func authorizationIsProvisionalOnly() throws {
        let source = try Self.appSources()
        let requests = source.split(separator: "\n").filter { $0.contains("requestAuthorization(options:") }
        #expect(requests.count == 1, "許可を求める箇所が \(requests.count) か所ある")
        #expect(requests.allSatisfy { $0.contains(".provisional") },
                "provisional を含まない許可の要求がある（起動直後などに許可ダイアログが出る）")
    }

    @Test("通知のタップを起動時から受け取り、そのゲームを notification の導線で開く")
    func tapOpensGame() throws {
        let source = try Self.appSources()
        #expect(source.contains("@UIApplicationDelegateAdaptor(AppDelegate.self)"),
                "AppDelegate が登録されていない（通知のタップを受け取れない）")
        #expect(Self.matches(#"didFinishLaunchingWithOptions[^{]*\{\s*UNUserNotificationCenter\.current\(\)\.delegate = self"#, in: source),
                "起動処理の中で通知の delegate を立てていない（終了中のアプリへのタップを取りこぼす）")
        #expect(source.contains("AppEnvironment.reminders.notificationTapped(gameID: gameID)"),
                "タップがサービスへ届いていない")
        guard let handler = source.range(of: ".onChange(of: services.reminders?.requestedGameID, initial: true)") else {
            Issue.record("ハブがタップされたゲームを受け取っていない（走査のパターンが壊れている可能性）")
            return
        }
        // 受け取った直後の範囲だけを見る。ファイル全体の contains だと、別の場所の `.notification` に当たる。
        let body = source[handler.upperBound...].prefix(600)
        #expect(Self.matches(#"openFromOutside\(HubRoute\(\s*gameID: id, source: \.notification,"#, in: String(body)),
                "ハブがタップされたゲームを notification の導線で開いていない")
    }

    @Test("設定の「通知」トグルで止められ、オフにすると予約済みも取り消す")
    func settingToggleStopsReminders() throws {
        let source = try Self.appSources()
        #expect(Self.matches(#"get: \{ settings\.notificationsEnabled \},\s*set: \{ settings\.notificationsEnabled = \$0 \}"#, in: source),
                "設定画面に通知のトグルが無い")
        #expect(Self.matches(#"isEnabled: \{ settings\.notificationsEnabled \}"#, in: source),
                "設定のオン / オフが予約の判定に届いていない")
        #expect(Self.matches(#"if !notificationsEnabled \{\s*AppEnvironment\.reminders\.cancelAll\(\)"#, in: source),
                "オフにしても予約済みのお知らせが残る")
    }
}
