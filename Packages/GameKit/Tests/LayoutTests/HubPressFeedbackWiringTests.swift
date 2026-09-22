import Foundation
import Testing
import GameKitTestSupport

/// ハブのカードの押下フィードバックと、ツールバーの読み上げ（#716）。
///
/// ハブは App ターゲットにあり GameKit のテストから import できないため、`HubRecentRowWiringTests`（#660）
/// と同じくソースを走査して固定する。読み口は `App/` のディレクトリ一式で、行コメントは落としてから見る
/// （View をファイルへ割っただけで空振りする形・説明文の言及に当たって緑になる形を避けるため）。
@Suite("ハブの押下フィードバックと読み上げ")
struct HubPressFeedbackWiringTests {
    private static func count(_ pattern: String, in source: String) throws -> Int {
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source))
    }

    @Test("App/ に押下フィードバックを消す .plain が残っていない")
    func noPlainButtonStyle() throws {
        let source = try SourceScan.appSources()
        #expect(!source.contains("buttonStyle(.plain)"),
                "`.plain` は押下中の縮みも消す。自前で背景を描くボタンは `.pop` を使う（#195）")
    }

    @Test("ハブからゲームへ入るカードは、すべて .pop で押下中に沈む")
    func everyGameLinkUsesPopStyle() throws {
        let source = try SourceScan.appSources()
        // 導線の数（グリッド・つづき/最近の行・はじめの1本 #721）と、`.pop` まで結線された数が一致すること。
        // `.pop` の有無だけを contains で見ると、別のボタンに付いた `.pop` で緑になる。
        // 導線を足したら、そのカードの型名を下の選択肢に加える（加えないと .pop を付けても赤になる）。
        let links = try Self.count(#"NavigationLink\(value: HubRoute\("#, in: source)
        let popped = try Self.count(
            #"NavigationLink\(value: HubRoute\([^{}]*\)\) \{\s*(GameCard|HubRecentCard|HubFirstPickCard)\([^{}]*\)\s*\}\s*\.buttonStyle\(\.pop\)"#,
            in: source
        )
        #expect(links >= 2, "ハブの導線が見つからない（走査のパターンが壊れている可能性）")
        #expect(popped == links, "押下フィードバックの無いカードがある（\(popped)/\(links)）")
    }

    @Test("設定の歯車ボタンが VoiceOver で「設定」と読まれる")
    func settingsButtonHasAccessibilityLabel() throws {
        let source = try SourceScan.appSources()
        // アイコンだけのボタンは VoiceOver がシンボル名を読む。ボタンとラベルの**結線**まで見る。
        #expect(
            source.range(
                of: #"Button \{ showSettings = true \} label: \{\s*Image\(systemName: "gearshape\.fill"\)[^{}]*\}\s*\.accessibilityLabel\("設定"\)"#,
                options: .regularExpression
            ) != nil,
            "設定の歯車ボタンに読み上げラベルが付いていない"
        )
    }
}
