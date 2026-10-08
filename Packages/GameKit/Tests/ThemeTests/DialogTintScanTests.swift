import Testing
import Foundation
import GameKitTestSupport

/// 標準ダイアログ（`.alert` / `.confirmationDialog`）が `View.dialogs(_:)` の外に付くのを止める（#1874）。
///
/// ダイアログのボタンの文字色は付けた位置の `tint` で決まる。View に直接付けると画面の部品と同じ
/// `coral` になり、OS のすりガラスの上で沈む。`.dialogs { anchor in anchor.alert(...) }` の形だけ通す。
struct DialogTintScanTests {

    private static func swiftFiles(under root: URL) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// 走査対象は本体のソース（`Packages/GameKit/Sources` と `App`）。テストコードは対象外。
    private static func scannedSources() throws -> [(path: String, source: String)] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [(String, String)] = []
        for root in roots {
            for file in try swiftFiles(under: root) {
                result.append((file.path, try String(contentsOf: file, encoding: .utf8)))
            }
        }
        // 空振り防止。パスの導出が外れて 0 件になると「見つからない」が緑になる。
        #expect(result.count > 100)
        return result
    }

    /// 行コメントと文字列リテラルの中身を落とす（文言に含まれる括弧や `alert` の語を数えないため）。
    static func strippingCommentsAndStrings(_ source: String) -> String {
        let withoutComments = SourceScan.strippingComments(source)
        guard let regex = try? NSRegularExpression(pattern: #""(\\.|[^"\\])*""#) else { return withoutComments }
        return regex.stringByReplacingMatches(
            in: withoutComments, range: NSRange(withoutComments.startIndex..., in: withoutComments),
            withTemplate: "\"\""
        )
    }

    /// `source` 内のダイアログ呼び出しのうち、`.dialogs { anchor in` の塊の外にあるものの行番号。
    static func offendingLines(in source: String) -> [Int] {
        let cleaned = strippingCommentsAndStrings(source)
        let ns = cleaned as NSString
        // メンバー呼び出し（`x.alert(`・連結の `.alert(`）と、`self` を省いた呼び出し（`alert(`）の両方。
        let pattern = #"(?:\.|(?<![\w.]))(alert|confirmationDialog)\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let start = match.range.location
            let line = ns.substring(to: start).components(separatedBy: "\n").count
            return isInsideDialogsBlock(cleaned, at: start) ? nil : line
        }
    }

    /// `position` を直接囲む `{` を後ろ向きに探し、それが `.dialogs { anchor in` の開き括弧か。
    private static func isInsideDialogsBlock(_ source: String, at position: Int) -> Bool {
        let chars = Array(source.utf16)
        let open = "{".utf16.first!
        let close = "}".utf16.first!
        var depth = 0
        var index = position - 1
        while index >= 0 {
            let c = chars[index]
            if c == close {
                depth += 1
            } else if c == open {
                if depth == 0 {
                    let lineStart = source.utf16.index(source.utf16.startIndex, offsetBy: index)
                    let head = String(source[..<lineStart]).split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
                    let tail = String(source[lineStart...]).split(separator: "\n", omittingEmptySubsequences: false).first ?? ""
                    // `.dialogs { anchor in`（修飾子チェーン）と `dialogs { anchor in`（`self` を省いた形）の両方。
                    let receiver = head.trimmingCharacters(in: .whitespaces)
                    return (receiver.hasSuffix(".dialogs") || receiver == "dialogs") && tail.hasPrefix("{ anchor in")
                }
                depth -= 1
            }
            index -= 1
        }
        return false
    }

    /// 対象の全呼び出し数（対照用）。
    static func dialogCallCount(in source: String) -> Int {
        SourceScan.matchCount(of: #"(?:\.|(?<![\w.]))(alert|confirmationDialog)\("#, in: strippingCommentsAndStrings(source))
    }

    @Test("標準ダイアログは .dialogs { anchor in } の中にだけ付ける")
    func dialogsAreAttachedThroughAnchor() throws {
        let offenders = try Self.scannedSources().flatMap { file in
            Self.offendingLines(in: file.source).map { "\(file.path):\($0)" }
        }
        #expect(offenders.isEmpty, """
            .alert / .confirmationDialog は View に直接付けず、.dialogs { anchor in anchor.alert(...) } の形にする（#1874）。
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// 対照: 検査が呼び出しを実際に見つけていること（見つからない検査は何も止めない）。
    @Test("ダイアログの呼び出しを実際に数えている")
    func dialogCallsAreDetected() throws {
        let total = try Self.scannedSources().reduce(0) { $0 + Self.dialogCallCount(in: $1.source) }
        #expect(total >= 37)
    }

    @Test("判定は直接付けた呼び出しを落とし、anchor 経由・連結・コメント・文言中の語は通す")
    func detectionRules() {
        #expect(Self.offendingLines(in: """
            VStack {}
                .alert("x", isPresented: $a) { Button("OK") {} }
            """) == [2])
        #expect(Self.offendingLines(in: """
            func f() -> some View {
                confirmationDialog("x", isPresented: p) { Button("OK") {} }
            }
            """) == [2])
        #expect(Self.offendingLines(in: """
            func f() -> some View {
                dialogs { anchor in
                    anchor.confirmationDialog("x", isPresented: p) { Button("OK") {} }
                }
            }
            """).isEmpty)
        #expect(Self.offendingLines(in: """
            VStack {}
                .dialogs { anchor in
                    anchor.alert("x", isPresented: $a) { Button("OK") {} }
                    .confirmationDialog("y", isPresented: $b) {
                        Button("OK") {}
                    } message: {
                        Text("alert( を含む文言")
                    }
                }
                // .alert("コメント", isPresented: $c) {}
            """).isEmpty)
        // `.dialogs` の塊の中でも、入れ子の別の閉じ括弧の中に置かれていれば落とす（直接囲む括弧で見る）。
        #expect(Self.offendingLines(in: """
            VStack {}
                .dialogs { anchor in
                    VStack {
                        Color.clear.alert("x", isPresented: $a) { Button("OK") {} }
                    }
                }
            """) == [4])
    }
}
