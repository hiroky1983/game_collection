import Foundation
import Testing
import GameKitTestSupport

/// 「つづき・最近」の行（#660）の**結線**。行は App ターゲットにあり GameKit のテストから
/// import できないため、`GameCenterEntryPointTests`（#334）と同じくソースを走査して固定する。
///
/// 読み口は単一ファイル名ではなく **`App/` のディレクトリ一式**。View をファイルへ割っただけで
/// 走査が空振りする形にしないため。走査前に行コメントを落とすのも同じ理由で、説明文の言及が
/// `contains` に当たって「実装が消えても緑」になるのを防ぐ。
@Suite("つづき・最近の行の結線")
struct HubRecentRowWiringTests {
    @Test("候補は Core の規則（RecentGames）から来ていて、ハブが自前で並べていない")
    func candidatesComeFromCore() throws {
        let source = try SourceScan.appSources()
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

    @Test("「続きから」の判定は GameModule に聞き、中断データの有無を直接見ない（#809）")
    func resumeJudgementGoesThroughModule() throws {
        let source = try SourceScan.appSources()
        // 行・グリッドのバッジ・`game_open` の `resume` のどれか 1 か所でも `exists` に戻ると、
        // チャリンコおじさん・終局した将棋とチェスが「つづきから」に戻り、`resume = 1` で送られる。
        #expect(!source.contains("snapshots.exists("),
                "ハブが中断データの有無だけで「続きから」を決めている箇所がある")
        #expect(
            source.range(
                of: #"func isResumable\(_ gameID: String\) -> Bool \{\s*registry\.hasResumableSnapshot\(gameID: gameID, in: services\.snapshots\)"#,
                options: .regularExpression
            ) != nil,
            "ハブの判定が GameModule.hasResumableSnapshot を通っていない"
        )
        #expect(source.contains("let resuming = visible.filter { isResumable($0) }"),
                "「つづき・最近」の行の中断判定が isResumable を通っていない")
        #expect(source.contains("let hasResume = isResumable(module.id)"),
                "グリッドの「続きから」バッジが isResumable を通っていない")
        // 起動引数で直接開く経路は init の中なので、インスタンスメソッドを呼べずレジストリへ直接聞く。
        #expect(source.contains("resume: registry.hasResumableSnapshot(gameID: $0, in: services.snapshots)"),
                "起動引数で開く経路の resume が同じ判定を通っていない")
        let routes = source.components(separatedBy: "HubRoute(").count - 1
        let judged = source.components(separatedBy: "resume: isResumable(").count - 1
        // HubRoute を作る箇所: 起動引数・はじめの1本・グリッド・行・レコメンド・通知と、型の定義。
        // グリッドは hasResume、行は candidate.hasResume、起動引数はレジストリを経由するので、
        // isResumable を直接渡すのは、はじめの1本・レコメンド・通知の 3 か所。
        #expect(judged == 3, "resume: isResumable( が \(judged) か所（HubRoute は \(routes) か所）")
    }

    @Test("候補が無ければ行そのものを描かない")
    func rowIsNotDrawnWhenEmpty() throws {
        let source = try SourceScan.appSources()
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
        let source = try SourceScan.appSources()
        // 自前で path を書き換える形にすると `gameDidLeave`（#158）の発火点が増え、
        // 1 プレイの数え方が狂う。
        #expect(
            source.range(
                of: #"NavigationLink\(value: HubRoute\(\s*gameID: candidate\.gameID, source: \.recent,[^)]*\)\) \{\s*HubRecentCard\("#,
                options: .regularExpression
            ) != nil,
            "行のカードが NavigationLink(value:) で遷移していない"
        )
    }

    @Test("行の見出しが VoiceOver で見出しとして読まれる")
    func headingIsExposedToVoiceOver() throws {
        let source = try SourceScan.appSources()
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
