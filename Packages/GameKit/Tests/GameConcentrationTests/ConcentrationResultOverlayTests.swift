import Testing
import Foundation
import GameKitTestSupport

/// 決着後のレコメンド・階段の枠（#847）。
///
/// 神経衰弱の結果は全面の暗幕（`resultOverlay`）で出すため、枠が本体の VStack にあると
/// 暗幕の下になり、透けて見えるのに押せない。枠が暗幕の中にあることをソースから固定する。
/// コメント行は落としてから数える（言及に当たって空振りしないため）。
@Suite("神経衰弱の結果の暗幕")
struct ConcentrationResultOverlayTests {

    @Test("レコメンド・階段の枠は結果の暗幕の中にだけ置かれている")
    func recommendationSlotIsInsideResultOverlay() throws {
        let source = try SourceScan.packageSource("Sources/GameConcentration/ConcentrationView.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")

        #expect(SourceScan.matchCount(of: #"RecommendationSlot\("#, in: source) == 1,
                "枠が 1 か所だけに置かれていない")

        let overlay = try #require(source.range(of: "private var resultOverlay: some View {"))
        let card = try #require(source.range(of: "private var resultCard: some View {"))
        let slot = try #require(source.range(of: "RecommendationSlot("))
        #expect(overlay.upperBound <= slot.lowerBound && slot.upperBound <= card.lowerBound,
                "枠が resultOverlay の中に無い（本体に置くと暗幕の下で押せない）")
        #expect(source.contains("ladder: ladder"), "階段の提案を枠へ渡していない")
    }
}
