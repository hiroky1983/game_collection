import Testing
import GameKitTestSupport

/// 拡大モードの ON/OFF をゲームごとに覚える（#2616）。iPhone SE では 44pt を満たす唯一の手段なので、
/// 新規ゲーム・階段・もう一回のたびに等倍へ戻してはならない。
@Suite("ナンプレの拡大モードの記憶")
struct SudokuZoomModeMemoryTests {

    @Test("拡大モードは @AppStorage で覚え、画面側から OFF に戻す書き込みが無い")
    func zoomModeIsRemembered() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameSudoku"))
        #expect(source.contains(#"@AppStorage("sudokuZoomMode")"#), "拡大モードが保存されていない")
        #expect(SourceScan.matchCount(of: #"(?m)^\s*zoomMode\s*=\s*false"#, in: source) == 0,
                "どこかで拡大モードを OFF に戻している（新規ゲームで前回の選択が消える）")
    }
}
