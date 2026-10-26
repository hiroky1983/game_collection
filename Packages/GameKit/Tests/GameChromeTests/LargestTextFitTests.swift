import Foundation
import Testing
import GameKitTestSupport

/// 文字を最大の大きさにしたとき、結果カードと「はじめての遊び方」が切れない仕組みを残す（#2858）。
///
/// macOS の `ImageRenderer` は `dynamicTypeSize` を反映しない（#1601）ので、ソースで固定する。
@Suite("最大の文字サイズで切れない（#2858）")
struct LargestTextFitTests {
    @Test("結果カードは盤より背が高いときにスクロールへ切り替わる", arguments: ["BoardGameResultCard", "GameClearCard"])
    func resultCardScrollsWhenTall(file: String) throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/\(file).swift"))
        #expect(source.contains(".resultCardScrollsWhenTall()"), "\(file) が縦スクロールへの切り替えを通っていない")
    }

    @Test("はじめての遊び方は最大サイズで見出しを縦に積み、カードをスクロールさせる")
    func onboardingHandlesAccessibilitySizes() throws {
        let source = SourceScan.strippingComments(try SourceScan.packageSource("Sources/Core/OnboardingGuide.swift"))
        #expect(source.components(separatedBy: "dynamicTypeSize.isAccessibilitySize").count - 1 >= 2,
                "見出しとカードの両方が isAccessibilitySize で分岐していない")
        #expect(source.contains("ScrollView {"), "最大サイズのカードがスクロールしない")
    }
}
