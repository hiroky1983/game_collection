import Foundation
import Testing
import GameKitTestSupport

/// 設定の「プレイ記録を消去」（#2936）の完了通知の**結線**。
///
/// 設定は App ターゲットにあり GameKit のテストから import できないため、ソースを走査して固定する。
@Suite("設定のプレイ記録の消去")
struct SettingsClearPlayLogWiringTests {
    @Test("消去の確定で、消す処理のあとに触覚と VoiceOver のアナウンスを出す")
    func clearAnnouncesCompletion() throws {
        let source = try SourceScan.appSources()
        #expect(
            source.range(
                of: #"playLog\.clear\(\)[\s\S]{0,400}?AppEnvironment\.reengagement\.cancelAll\(\)[\s\S]{0,300}?feedback\.notify\(\.success\)\s*AccessibilityNotification\.Announcement\(tr\("プレイ記録を消去しました"\)\)\.post\(\)"#,
                options: .regularExpression
            ) != nil,
            "プレイ記録の消去の完了が触覚・VoiceOver に伝わらない（#2936）"
        )
        #expect(source.contains("feedback: services.feedback"), "設定シートに feedback が注入されていない")
    }
}
