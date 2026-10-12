import Testing
import Foundation
import GameKitTestSupport

/// 固定 pt の文字指定が新しく入るのを止める（#1858）。
///
/// `.font(.system(size:))` は文字サイズ設定（Dynamic Type）に追従しない。「文字が追従しない」の起票が
/// 画面ごとに繰り返されたので、追従しない指定は**行末に `// fixed-size: 理由` を付けたものだけ**通す。
/// 追従させるなら `.scaledFont(_:weight:design:maxScale:)` か `themeTitle/themeBody/themeCaption` を使う。
struct FixedFontSizeScanTests {

    private static func swiftFiles(under root: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// 走査対象は本体のソース（`Packages/GameKit/Sources` と `App`）。テストコードは対象外。
    private static func scannedLines() throws -> [(location: String, text: String)] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [(String, String)] = []
        var fileCount = 0
        for root in roots {
            for file in try swiftFiles(under: root) {
                fileCount += 1
                let source = try String(contentsOf: file, encoding: .utf8)
                for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    result.append(("\(file.path):\(index + 1)", String(line)))
                }
            }
        }
        // 空振り防止。パスの導出が外れて 0 件になると「見つからない」が緑になる。
        #expect(fileCount > 100)
        return result
    }

    private static func isSizedSystemFont(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return line.contains(".system(size:") && !trimmed.hasPrefix("//")
    }

    @Test("固定サイズの文字指定は fixed-size の理由コメントが付いたものだけ")
    func fixedSizeNeedsReasonMarker() throws {
        let lines = try Self.scannedLines()
        let offenders = lines
            .filter { Self.isSizedSystemFont($0.text) && !$0.text.contains("// fixed-size:") }
            .map { "\($0.location): \($0.text.trimmingCharacters(in: .whitespaces))" }
        #expect(offenders.isEmpty, """
            固定サイズの指定には追従しない理由が要る。追従させるなら .scaledFont(...) に。\n\(offenders.joined(separator: "\n"))
            """)
    }

    /// 対照: 検査が「印の付いた行」を実際に見つけていること（見つからない検査は何も止めない）。
    @Test("印の付いた固定サイズの行を実際に検出している")
    func markerLinesAreDetected() throws {
        let marked = try Self.scannedLines()
            .filter { Self.isSizedSystemFont($0.text) && $0.text.contains("// fixed-size:") }
        #expect(marked.count > 30)
    }

    @Test("判定は印の無い行を落とし、印の付いた行・コメント行は通す")
    func detectionRules() {
        #expect(Self.isSizedSystemFont("    .font(.system(size: 12, weight: .bold))"))
        #expect(!Self.isSizedSystemFont("    // .font(.system(size: 12))"))
        #expect(!Self.isSizedSystemFont("    .scaledFont(12, weight: .bold)"))
    }
}
