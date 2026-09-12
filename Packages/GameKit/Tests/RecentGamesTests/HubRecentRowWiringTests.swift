import Foundation
import Testing

/// 「つづき・最近」の行（#660）の**結線**。行は App ターゲットにあり GameKit のテストから
/// import できないため、`GameCenterEntryPointTests`（#334）と同じくソースを走査して固定する。
///
/// 読み口は単一ファイル名ではなく **`App/` のディレクトリ一式**。View をファイルへ割っただけで
/// 走査が空振りする形にしないため。走査前に行コメントを落とすのも同じ理由で、説明文の言及が
/// `contains` に当たって「実装が消えても緑」になるのを防ぐ。
@Suite("つづき・最近の行の結線")
struct HubRecentRowWiringTests {
    private static func appSources() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RecentGamesTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // GameKit/
            .deletingLastPathComponent()   // Packages/
            .deletingLastPathComponent()   // リポジトリのルート
        let appDir = repoRoot.appendingPathComponent("App")
        let files = try FileManager.default
            .contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        #expect(!files.isEmpty, "App/ の走査に失敗している")
        let joined = try files
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        return stripLineComments(joined)
    }

    /// 行頭から始まる `//` の行を落とす。文字列リテラル内の `//` は本アプリの App/ には無い。
    private static func stripLineComments(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    @Test("候補は Core の規則（RecentGames）から来ていて、ハブが自前で並べていない")
    func candidatesComeFromCore() throws {
        let source = try Self.appSources()
        #expect(source.contains("RecentGames.candidates("),
                "ハブが RecentGames を使わずに候補を組んでいる（並び順がテストで固定されなくなる）")
        // 非表示にしたゲームを行から外す担保は「visibleModules を通してから渡す」の1点。
        #expect(
            source.range(
                of: #"let visible = settings\.visibleModules\(from: registry\)\.map\(\\\.id\)"#,
                options: .regularExpression
            ) != nil,
            "候補の元が visibleModules を通っていない（設定で非表示にしたゲームが行に出る）"
        )
        #expect(source.contains("visibleGameIDs: visible"),
                "visibleModules 由来の並びが RecentGames へ渡っていない")
    }

    @Test("候補が無ければ行そのものを描かない")
    func rowIsNotDrawnWhenEmpty() throws {
        let source = try Self.appSources()
        // 「空でないときだけ `HubRecentRow` を置く」という**結線**まで見る。片方だけの
        // contains だと、条件を外して常に描く形にしても緑のまま素通りする。
        #expect(
            source.range(
                of: #"if !recent\.isEmpty \{\s*HubRecentRow\("#,
                options: .regularExpression
            ) != nil,
            "候補ゼロでも行を描く形になっている（初回ユーザーのハブでグリッドの位置が動く）"
        )
    }

    @Test("行のカードはグリッドと同じ NavigationLink(value:) で遷移する")
    func rowUsesSameNavigationLink() throws {
        let source = try Self.appSources()
        // 自前で path を書き換える形にすると `gameDidLeave`（#158）の発火点が増え、
        // 1 プレイの数え方が狂う。
        #expect(
            source.range(
                of: #"NavigationLink\(value: candidate\.gameID\) \{\s*HubRecentCard\("#,
                options: .regularExpression
            ) != nil,
            "行のカードが NavigationLink(value:) で遷移していない"
        )
    }

    @Test("行の見出しが VoiceOver で見出しとして読まれる")
    func headingIsExposedToVoiceOver() throws {
        let source = try Self.appSources()
        guard let heading = source.range(of: #"Text("つづき・最近")"#) else {
            Issue.record("行の見出しが見つからない（走査のパターンが壊れている可能性）")
            return
        }
        // 見出しの装飾が続く範囲だけを見る。ファイル全体を contains で見ると、別の場所に
        // ある `.isHeader` に当たって緑になる。
        let tail = source[heading.upperBound...].prefix(400)
        #expect(tail.contains("accessibilityAddTraits(.isHeader)"),
                "「つづき・最近」に見出しの特性が付いていない")
    }
}
