import Testing
import Foundation
import Core
import GameKitTestSupport

/// 差し色（yellow / teal / coral）を文字色に直接使うのを止める（#2282）。
///
/// 元の差し色は明るい地（クリーム・白）の上で 1.5〜2.6:1 しか取れず、ベット額・ポット額のような数字が
/// ライトモードで読めなかった。文字には `Theme.yellowText` / `tealText` / `coralText` を使う。
/// 暗い面の上など直接使ってよい箇所は、行末に `// accent-text-ok: 理由` を付ける。
struct AccentTextScanTests {

    private static let pattern = #"foregroundStyle\(\s*Theme\.(yellow|teal|coral)\b"#

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
        guard SourceScan.matchCount(of: pattern, in: String(line)) > 0 else { return false }
        return !line.contains("accent-text-ok")
    }

    @Test("差し色を foregroundStyle に直接使わない（文字用の色を使う）")
    func noDirectAccentForText() throws {
        var offenders: [String] = []
        for file in try Self.scannedSources() {
            for (index, line) in file.lines.enumerated() where Self.isOffending(line) {
                offenders.append("\(file.path):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, """
            foregroundStyle(Theme.yellow / teal / coral) は明るい地で読めない。Theme.yellowText / tealText / coralText を使う（#2282）。
            暗い面の上などで意図的に使うなら行末に `// accent-text-ok: 理由` を付ける。
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// 対照: 免除の印が実際に使われていること（検査が空振りしていないことも兼ねる）。
    @Test("判定は直接の差し色を落とし、文字用の色と免除の印は通す")
    func detectionRules() {
        #expect(Self.isOffending("    .foregroundStyle(Theme.yellow)"))
        #expect(Self.isOffending("    .foregroundStyle( Theme.coral)"))
        #expect(!Self.isOffending("    .foregroundStyle(Theme.yellowText)"))
        #expect(!Self.isOffending("    .foregroundStyle(Theme.teal) // accent-text-ok: 暗い面"))
        #expect(!Self.isOffending("    .foregroundStyle(Theme.Fill.yellow)"))
    }
}
