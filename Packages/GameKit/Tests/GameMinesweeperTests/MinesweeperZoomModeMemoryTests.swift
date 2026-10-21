import Testing
import GameKitTestSupport

/// 拡大モードの ON/OFF をゲームごとに覚える（#2616）。ナンプレと同じ仕組みで揃える。
@Suite("マインスイーパーの拡大モードの記憶")
struct MinesweeperZoomModeMemoryTests {

    @Test("拡大モードは @AppStorage で覚え、画面側から OFF に戻す書き込みが無い")
    func zoomModeIsRemembered() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameMinesweeper"))
        #expect(source.contains(#"@AppStorage("minesweeperZoomMode")"#), "拡大モードが保存されていない")
        #expect(SourceScan.matchCount(of: #"(?m)^\s*zoom(Mode|Preference)\s*=\s*false"#, in: source) == 0,
                "どこかで拡大モードを OFF に戻している（新規ゲームで前回の選択が消える）")
    }
}
