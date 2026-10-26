import Testing
import Foundation
import GameKitTestSupport
@testable import GameCatPuzzle

/// 盤の文字（部屋の札・「！」・電球）は `Canvas` の中で描かない（#2945）。
/// 描き直しのたびに和文の組版が主スレッドで走り、固まって監視（0x8BADF00D）に落とされる（花札 #2905 と同じ形）。
struct CatPuzzleCanvasTextTests {
    @Test("盤の絵は Canvas の中で Text を描かない")
    func boardDoesNotDrawTextInCanvas() throws {
        let code = try SourceScan.packageSource("Sources/GameCatPuzzle/CatPuzzleBoardCanvas.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!code.contains(".draw(text"), "文字を GraphicsContext に描いている")
        #expect(!code.contains("resolve(\n                Text"), "Canvas の中で Text を resolve している")
        #expect(!code.contains("context.resolve("), "Canvas の中で resolve している")
    }

    @Test("札の文字の大きさは文字サイズに比例する")
    func labelMetricsScaleWithFontSize() {
        let small = CatPuzzleLabelMetrics.size(of: "居間", fontSize: 10)
        let large = CatPuzzleLabelMetrics.size(of: "居間", fontSize: 20)
        #expect(small.width > 0)
        #expect(abs(large.width - small.width * 2) < 0.01)
    }
}
