import Testing
import Foundation
import GameKitTestSupport

/// `Canvas` の中で文字を描くのを止める（#2946。#2905 の再発防止）。
///
/// `GraphicsContext.draw(Text)` / `resolve(Text)` は、`Canvas` が描き直されるたびに文字を組み直す。
/// 和文は代替フォント探しで重く、描き直しが続くと主スレッドが埋まって固まる（花札の札の帯で実機に出た）。
/// 位置の決まった文字は `Canvas` の外の `Text`（`.position`）で置く。どうしても中に残すものは、
/// 下の許可リストにファイルと理由を書く（1 件ずつ判断するため、ファイル単位・最大行数つき）。
struct CanvasTextScanTests {

    /// ファイル名（末尾一致）→ 残してよい行数と理由。
    private static let allowed: [String: (maxLines: Int, reason: String)] = [
        "GameHomerun/HomerunSprayChart.swift": (5, "打球の印（★ F ×）と番号は 1 文字・数字だけで和文を含まない。位置が球ごとに動く"),
        // 以下は v1.1.14 で直している途中のもの（#2905 花札・#2945 ねこさがし／柵越えの操作説明）。
        // v1.1.14 → v1.1.15 の同期で直った版が入ったら、この 3 行は消す（残っても害は無い）。
        "GameHanafuda/HanafudaCardFace.swift": (2, "v1.1.14 の #2905（PR #2943）で Text に直し済み。同期待ち"),
        "GameCatPuzzle/CatPuzzleBoardCanvas.swift": (1, "v1.1.14 の #2945 で直す。同期待ち"),
        "GameHomerun/HomerunTutorial.swift": (3, "v1.1.14 の #2945 で直す。同期待ち"),
    ]

    private static let pattern = try! NSRegularExpression(pattern: #"\.(draw|resolve)\(\s*(Text|text)\b"#)

    private static func hits(in line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//") else { return false }
        let code = line.components(separatedBy: "//").first ?? line
        return pattern.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    private static func offenders() throws -> [(file: String, line: Int)] {
        let roots = [
            SourceScan.packageRoot.appendingPathComponent("Sources"),
            SourceScan.repositoryRoot.appendingPathComponent("App"),
        ]
        var result: [(String, Int)] = []
        var fileCount = 0
        for root in roots {
            let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                fileCount += 1
                let source = try String(contentsOf: file, encoding: .utf8)
                for (index, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where hits(in: String(line)) {
                    result.append((file.path, index + 1))
                }
            }
        }
        #expect(fileCount > 100)   // パスの導出が外れて 0 件の緑にならないように
        return result
    }

    @Test("Canvas の中で文字を描くのは許可リストのファイルだけ・行数の上限内")
    func textInCanvasOnlyWhereAllowed() throws {
        let found = try Self.offenders()
        var problems: [String] = []
        for (suffix, rule) in Self.allowed {
            let n = found.filter { $0.file.hasSuffix(suffix) }.count
            if n > rule.maxLines { problems.append("\(suffix): \(n) 行（上限 \(rule.maxLines)）。\(rule.reason)") }
        }
        let others = found.filter { hit in !Self.allowed.keys.contains { hit.file.hasSuffix($0) } }
        problems += others.map { "\($0.file):\($0.line) Canvas の中で文字を描いている" }
        #expect(problems.isEmpty, """
            Canvas の中の文字は描き直すたびに組み直され、重い（#2905）。Canvas の外の Text に出す。\n\(problems.joined(separator: "\n"))
            """)
    }

    @Test("検査が許可リストの行を実際に見つけている（見つからない検査は何も止めない）")
    func allowedLinesAreDetected() throws {
        let found = try Self.offenders()
        #expect(found.contains { $0.file.hasSuffix("GameHomerun/HomerunSprayChart.swift") })
    }

    @Test("判定は draw(Text・resolve(Text を拾い、コメント行・Image は拾わない")
    func detectionRules() {
        #expect(Self.hits(in: "ctx.draw(Text(verbatim: \"a\"), at: p)"))
        #expect(Self.hits(in: "let t = ctx.resolve(Text(\"x\"))"))
        #expect(Self.hits(in: "ctx.draw(text, at: p)"))
        #expect(!Self.hits(in: "// ctx.draw(Text(\"x\"), at: p)"))
        #expect(!Self.hits(in: "ctx.draw(image, at: p)"))
    }
}
