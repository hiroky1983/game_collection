import Foundation
import Testing
import GameKitTestSupport

/// 再エンゲージメント通知（#1193）の**結線**。OS へ渡す部分・バックグラウンド遷移・通知のタップは
/// App ターゲットにあり GameKit のテストから import できないため、`ResumeReminderWiringTests`
/// （#663）と同じくソースを走査して固定する。
@Suite("再エンゲージメント通知の結線（#1193）")
struct ReengagementReminderWiringTests {
    private static func matches(_ pattern: String, in source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }

    @Test("ReengagementReminderService が GameServices に渡り、開いたら取り消しが届く")
    func servicesAreWired() throws {
        let source = try SourceScan.appSources()
        #expect(Self.matches(#"reminders: reminders,\s*reengagement: reengagement\s*\)"#, in: source),
                "ReengagementReminderService が GameServices に渡っていない")
    }

    @Test("バックグラウンドに入るたびに対象を判定し直す")
    func scheduledOnBackgroundTransition() throws {
        let source = try SourceScan.appSources()
        #expect(Self.matches(#"if newPhase == \.background \{\s*AppEnvironment\.reengagement\.applicationDidEnterBackground\("#, in: source),
                "バックグラウンド遷移で対象の再判定が呼ばれていない")
    }

    @Test("撮影モードと DEBUG ビルドでは予約しない")
    func suppressedInScreenshotAndDebug() throws {
        let source = try SourceScan.appSources()
        guard let range = source.range(of: "let reengagement = ReengagementReminderService(") else {
            Issue.record("reengagement の組み立てが見つからない")
            return
        }
        let body = source[range.upperBound...].prefix(400)
        #expect(Self.matches(#"isSuppressed: isScreenshotMode \|\| isDebugBuild"#, in: String(body)),
                "撮影モードまたは DEBUG ビルドで予約が止まっていない")
    }

    @Test("許可は標準ダイアログの出る明示的な許可でだけ求める（provisional を含めない）")
    func authorizationIsExplicitOnly() throws {
        let source = try SourceScan.appSources()
        guard let range = source.range(of: "final class UserNotificationReengagementScheduler") else {
            Issue.record("UserNotificationReengagementScheduler が見つからない（走査のパターンが壊れている可能性）")
            return
        }
        let body = source[range.upperBound...]
        let classBody = body.range(of: "\nfinal class ").map { body[body.startIndex..<$0.lowerBound] } ?? body
        let requests = classBody.split(separator: "\n").filter { $0.contains("requestAuthorization(options:") }
        #expect(requests.count == 1, "許可を求める箇所が \(requests.count) か所ある")
        #expect(requests.allSatisfy { !$0.contains(".provisional") },
                "provisional を含む許可の要求がある（ダイアログの出ない仮の許可になってしまう）")
    }

    @Test("通知のタップを起動時から受け取り、そのゲームを notification の導線で開く")
    func tapOpensGame() throws {
        let source = try SourceScan.appSources()
        #expect(source.contains("AppEnvironment.reengagement.notificationTapped(gameID: gameID)"),
                "タップがサービスへ届いていない")
        guard let handler = source.range(of: ".onChange(of: services.reengagement?.requestedGameID, initial: true)") else {
            Issue.record("ハブがタップされたゲームを受け取っていない（走査のパターンが壊れている可能性）")
            return
        }
        let bodyText = source[handler.upperBound...].prefix(600)
        #expect(Self.matches(#"openFromOutside\(HubRoute\(\s*gameID: id, source: \.notification,"#, in: String(bodyText)),
                "ハブがタップされたゲームを notification の導線で開いていない")
    }

    @Test("設定のトグルで止められ、オフにすると予約済みも取り消す")
    func settingToggleStopsReminders() throws {
        let source = try SourceScan.appSources()
        #expect(Self.matches(#"get: \{ settings\.reengagementRemindersEnabled \},\s*set: \{ settings\.reengagementRemindersEnabled = \$0 \}"#, in: source),
                "設定画面に久しぶり通知のトグルが無い")
        #expect(Self.matches(#"isEnabled: \{ settings\.reengagementRemindersEnabled \}"#, in: source),
                "設定のオン / オフが判定に届いていない")
        #expect(Self.matches(#"if !reengagementRemindersEnabled \{\s*AppEnvironment\.reengagement\.cancelAll\(\)"#, in: source),
                "オフにしても予約済みのお知らせが残る")
    }

    @Test("識別子の名前空間が #663 と分かれている")
    func identifierNamespaceIsSeparateFromResumeReminder() throws {
        let source = try SourceScan.appSources()
        #expect(source.contains(#"static let identifierPrefix = "reengagement-reminder.""#),
                "識別子の接頭辞が見つからない、または #663 と同じになっている")
    }
}
