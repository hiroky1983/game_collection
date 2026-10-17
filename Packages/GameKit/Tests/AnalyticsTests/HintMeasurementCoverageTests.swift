import Testing
import Foundation
import GameKitTestSupport

/// ヒントを消費する Model が `gameDidUseHint` に繋がっていること（#2325）。
///
/// 呼び忘れると `game_end` の `hints_used` が常に 0 になる（ナンプレ #2323・麻雀ソリティア #2325）。
/// 実行では確かめにくい結線なので、ソースの形で守る。
@Suite("ヒントを持つゲームは gameDidUseHint を呼ぶ（#2325）")
struct HintMeasurementCoverageTests {

    /// ヒントを消費する関数の宣言。
    private static let hintConsumer = #"func (showHint|requestHint|requestAdHint|useHint|applyHint)\("#

    /// `BoardHintReader`（Core）は内部で `gameDidUseHint` を呼ぶので、これを使う Model も繋がっているとみなす。
    private static let wired = ["gameDidUseHint(", "BoardHintReader<"]

    /// 除外する module と理由。
    private static let exempt: [String: String] = [:]

    @Test("ヒントの消費関数を持つ module は gameDidUseHint（または BoardHintReader）を使っている")
    func everyHintModuleReportsUsage() throws {
        let sources = SourceScan.packageRoot.appendingPathComponent("Sources")
        let modules = try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasPrefix("Game") }.sorted()
        var checked = 0
        var missing: [String] = []
        for module in modules where Self.exempt[module] == nil {
            let source = SourceScan.strippingComments(try SourceScan.moduleSources(module))
            guard SourceScan.matchCount(of: Self.hintConsumer, in: source) > 0 else { continue }
            checked += 1
            if !Self.wired.contains(where: source.contains) { missing.append(module) }
        }
        #expect(checked >= 10, "走査が空振りしている（ヒントを持つ module を \(checked) 本しか見つけていない）")
        #expect(missing.isEmpty, "gameDidUseHint を呼んでいない: \(missing)")
    }
}
