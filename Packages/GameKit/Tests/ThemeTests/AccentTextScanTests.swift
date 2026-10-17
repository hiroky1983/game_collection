import Testing
import Foundation
import Core
import GameKitTestSupport

/// 差し色（yellow / teal / coral）を前景（文字・アイコン・記号）に直接使うのを止める（#2282・#2377）。
///
/// 元の差し色は明るい地（クリーム・白）の上で 1.5〜2.6:1 しか取れず、ベット額・ポット額のような数字が
/// ライトモードで読めなかった。文字・アイコン・記号には `Theme.yellowText` / `tealText` / `coralText` を使う。
/// 面（塗り）・枠線・影は元の差し色のままでよい（検査しない）。
/// 暗い面の上など前景に直接使ってよい箇所と、`.tint` が面（トグルのトラック・進捗バー）になる箇所は、
/// 行末に `// accent-text-ok: 理由` を付ける。
///
/// 見るのは行単位の書き方だけ: `foregroundStyle(` の引数・`.tint(`・文字ラベル部品（`RuleFigureLabel` /
/// `GameOverflowCaption`）の `color:`・帯のキャプションの `captionColor:`・その `color:` だけを折り返した行。`-> Color` を返す関数経由の色は
/// 検査できないので、前景に使う色を返す関数は最初から `...Text` を返すこと。
struct AccentTextScanTests {

    private static let accent = #"\bTheme\.(yellow|teal|coral)\b"#
    private static let patterns = [
        #"foregroundStyle\(.*"# + accent,
        #"\.tint\(\s*"# + accent,
        #"(RuleFigureLabel|GameOverflowCaption)\(.*\bcolor:.*"# + accent,
        #"\bcaptionColor:\s*"# + accent,
        // 折り返した `color:` 行（線の色を渡す `color: ..., lineWidth:` は前景ではないので除く）
        #"^\s*color:(?!.*(lineWidth|dash)).*"# + accent,
    ]

    private static func scannedSources() throws -> [(path: String, lines: [Substring])] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [(String, [Substring])] = []
        for root in roots {
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                result.append((file.path, try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)))
            }
        }
        // 空振り防止。パスの導出が外れて 0 件になると「見つからない」が緑になる。
        #expect(result.count > 100)
        return result
    }

    /// 検査対象の行（直接の差し色で、`accent-text-ok` の免除が無いもの）。
    static func isOffending(_ line: Substring) -> Bool {
        guard !line.contains("accent-text-ok") else { return false }
        return patterns.contains { SourceScan.matchCount(of: $0, in: String(line)) > 0 }
    }

    @Test("差し色を前景（文字・アイコン・記号）に直接使わない（文字用の色を使う）")
    func noDirectAccentForText() throws {
        var offenders: [String] = []
        for file in try Self.scannedSources() {
            for (index, line) in file.lines.enumerated() where Self.isOffending(line) {
                offenders.append("\(file.path):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, """
            前景（foregroundStyle・.tint・文字ラベルの color:）に Theme.yellow / teal / coral を使うと明るい地で読めない。
            Theme.yellowText / tealText / coralText を使う（#2282・#2377）。面・枠・影は対象外。
            暗い面の上や .tint が面になる箇所などで意図的に使うなら行末に `// accent-text-ok: 理由` を付ける。
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// 対照: 免除の印が実際に使われていること（検査が空振りしていないことも兼ねる）。
    @Test("判定は直接の差し色を落とし、文字用の色と免除の印は通す")
    func detectionRules() {
        #expect(Self.isOffending("    .foregroundStyle(Theme.yellow)"))
        #expect(Self.isOffending("    .foregroundStyle( Theme.coral)"))
        #expect(Self.isOffending("    .foregroundStyle(isWin ? Theme.yellow : Theme.coral)"))
        #expect(Self.isOffending("    .tint(Theme.coral)"))
        #expect(Self.isOffending("    .init(c, share: 0.2, color: Theme.Fill.coral, captionColor: Theme.coral)"))
        #expect(!Self.isOffending("    .init(c, share: 0.2, color: Theme.Fill.coral, captionColor: Theme.coralText)"))
        #expect(Self.isOffending("    RuleFigureLabel(tr(\"あ\"), color: Theme.teal)"))
        #expect(Self.isOffending("                                    color: index == 0 ? Theme.coral : Theme.inkSub)"))
        #expect(!Self.isOffending("                   to: p, color: Theme.yellow, lineWidth: 4)"))
        #expect(!Self.isOffending("    .foregroundStyle(isWin ? Theme.yellowText : Theme.coralText)"))
        #expect(!Self.isOffending("    .tint(Theme.coralText)"))
        #expect(!Self.isOffending("    Capsule().fill(Theme.coral)"))
        #expect(!Self.isOffending("    .tint(Theme.coral) // accent-text-ok: トグルのトラック（面）"))
        #expect(!Self.isOffending("    .foregroundStyle(Theme.yellowText)"))
        #expect(!Self.isOffending("    .foregroundStyle(Theme.teal) // accent-text-ok: 暗い面"))
        #expect(!Self.isOffending("    .foregroundStyle(Theme.Fill.yellow)"))
    }
}
