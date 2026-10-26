import Testing
import GameKitTestSupport

/// 盤（`CatPuzzleBoardCanvas`）は `Canvas` の中で文字を描かない（#2905 の花札の帯の文字と同じ形・#2945）。
///
/// `Canvas` の `GraphicsContext.resolve(Text)`/`draw(Text)` は描き直すたびに文字の組版をやり直すので、
/// 猫を置く・消す・ヒント・ミスのたびに盤を描き直すこのゲームで使うと、和文の代替フォント探しで
/// 主スレッドが詰まる危険がある。部屋の名前の札・矛盾の「！」・ヒントの電球は、Canvas の外（overlay の
/// `Text`/`Image`）に出してある。
@Suite("おじさんちのねこさがし: 盤の文字は Canvas で描かない")
struct CatPuzzleBoardCanvasTests {
    @Test("CatPuzzleBoardCanvas.swift は Canvas の中で文字を描いていない")
    func boardCanvasDoesNotDrawTextInCanvas() throws {
        let code = try SourceScan.packageSource("Sources/GameCatPuzzle/CatPuzzleBoardCanvas.swift")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        #expect(!code.contains(".draw(Text"), "Canvas の中で文字を描いている")
        #expect(!code.contains("resolve(Text"), "Canvas の中で文字を測っている・描いている")
        // 実際の描画が overlay の Text に移っていること（退行防止の素振り）。
        #expect(code.contains("Text(name)"))
        #expect(code.contains("Text(verbatim: \"!\")"))
        #expect(code.contains("lightbulb.fill"))
    }
}
