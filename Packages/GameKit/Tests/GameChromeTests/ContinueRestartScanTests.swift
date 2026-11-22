import Testing
import Foundation
import GameKitTestSupport

/// 広告コンティニューで「負け」を取り消す（`cancelLoss`）関数は、同じ関数の中で `gameDidRestart` も呼ぶ（#3446）。
///
/// 呼ばないと、ミス上限で出した `game_end(loss)` で解析上の 1 プレイが `.finished` になったまま続きが遊ばれ、
/// 続きの局の `game_end`（win / quit）が全部弾かれる。ナンプレ・ねこさがしでこの取りこぼしが出ていた
/// （2048・ブロック崩し等の #1953 と同じ症状）。実行では確かめにくいので呼び出しの形で守る。
/// 意図して呼ばない関数は、`cancelLoss(` の行の末尾に `// 例外: <理由>` を書く。
@Suite("コンティニューの解析の呼び出し走査（#3446）")
struct ContinueRestartScanTests {
    /// `Sources/<module>/*.swift` を全部読む。
    private func allSources() throws -> [(file: String, lines: [String])] {
        let dir = SourceScan.packageRoot.appendingPathComponent("Sources")
        let modules = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        var result: [(String, [String])] = []
        for module in modules.sorted() {
            let moduleDir = dir.appendingPathComponent(module)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: moduleDir.path)) ?? []
            for name in files.sorted() where name.hasSuffix(".swift") {
                let text = try String(contentsOf: moduleDir.appendingPathComponent(name), encoding: .utf8)
                result.append(("\(module)/\(name)", text.components(separatedBy: "\n")))
            }
        }
        return result
    }

    private func isFuncDeclaration(_ line: String) -> Bool {
        line.range(of: #"\bfunc\s"#, options: .regularExpression) != nil
    }

    @Test("cancelLoss を呼ぶ関数は同じ関数内で gameDidRestart も呼ぶ")
    func cancelLossFunctionsAlsoRestart() throws {
        var found = 0
        var violations: [String] = []
        for (file, lines) in try allSources() {
            for (i, line) in lines.enumerated() where line.contains("cancelLoss(") && !isFuncDeclaration(line) {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") { continue }
                found += 1
                if line.contains("// 例外:") { continue }
                var start = i
                while start > 0, !isFuncDeclaration(lines[start]) { start -= 1 }
                var end = i + 1
                while end < lines.count, !isFuncDeclaration(lines[end]) { end += 1 }
                let body = lines[start..<end].filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                if !body.contains(where: { $0.contains("gameDidRestart(") }) {
                    violations.append("\(file):\(i + 1) \(lines[start].trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        // 空振り防止。走査がソースを読めていないと「違反なし」で素通りする（調査時点で 10 箇所）。
        #expect(found >= 10, "cancelLoss の呼び出しを \(found) 箇所しか見つけられない（走査の空振り）")
        #expect(violations.isEmpty, "gameDidRestart を呼んでいない: \(violations)")
    }
}
