import Testing
import Foundation
import GameKitTestSupport
@testable import GameMinesweeper

/// 最初のマスを開く前（`.idle`）も操作の段（「⋯」・ヒント）を出す（#2423）。
@MainActor
struct MinesweeperIdleControlsTests {
    @Test("操作の段は開始前（.idle）でも出す")
    func controlsShownWhileIdle() throws {
        let source = try SourceScan.packageSource("Sources/GameMinesweeper/MinesweeperView.swift")
        let start = try #require(source.range(of: "private var controlArea: some View {"),
                                 "controlArea が見つからない（走査が空振りしている）")
        let end = try #require(source.range(of: "gameControls", range: start.upperBound..<source.endIndex))
        let body = source[start.lowerBound..<end.upperBound]
        #expect(body.contains("model.gameState == .idle || model.gameState == .playing"),
                "開始前に「⋯」が出ず、拡大・旗モードが使えない")
    }

    @Test("開始前は諦めるを押せない")
    func giveUpDisabledWhileIdle() throws {
        let source = try SourceScan.packageSource("Sources/GameMinesweeper/MinesweeperView.swift")
        let start = try #require(source.range(of: "id: \"giveUp\""))
        let end = try #require(source.range(of: "showGiveUpConfirm = true", range: start.upperBound..<source.endIndex))
        #expect(source[start.lowerBound..<end.upperBound].contains("isEnabled: model.gameState == .playing"))
    }

    @Test("開始前はヒントを使えない")
    func hintUnavailableWhileIdle() {
        let model = MinesweeperModel()
        #expect(model.gameState == .idle)
        #expect(!model.canUseHint)
    }
}
