import Testing
import Core
import GameKitTestSupport
@testable import GameOjisanPuzzle

/// 図入りの遊び方（#2044 の先駆け・会長決定 2026-10-12）。
@Suite("おじさんの荷物運びパズルの遊び方")
@MainActor
struct OjisanPuzzleHowToTests {
    @Test("項目ごとに図が 1 つずつある（文と図の数がずれない）")
    func everyItemHasFigure() {
        #expect(OjisanPuzzleHowToFigures.all.count == HowToPlayGuide.ojisanPuzzle.items.count)
        let guide = HowToPlayGuide.ojisanPuzzle.illustrated(OjisanPuzzleHowToFigures.all)
        #expect(guide.items.allSatisfy { $0.figure != nil })
        // 図を差し込んでも文言は変わらない。
        #expect(guide.items.map(\.text) == HowToPlayGuide.ojisanPuzzle.items.map(\.text))
        #expect(guide.notes == HowToPlayGuide.ojisanPuzzle.notes)
    }

    @Test("画面のヘッダーに図入りの遊び方をつなぎ、読んでいるあいだは止める")
    func viewWiresHowToPlay() throws {
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleView.swift"))
        #expect(code.contains(".howToPlay(.ojisanPuzzle.illustrated(OjisanPuzzleHowToFigures.all)"))
        #expect(code.contains("onPresent: { model.pause() }"))
    }

    @Test("図は本番の描画部品を使う（荷物・おじさんの絵を二重に持たない）")
    func figuresReuseProductionArt() throws {
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleHowToFigures.swift"))
        #expect(code.contains("OjisanPuzzleView.luggage("))
        #expect(code.contains("OjisanPuzzleArt.image("))
        #expect(!code.contains("Canvas"), "荷物を図の側で描き直さない")
        #expect(!code.contains("Bundle.module"), "絵の素材を図の側で読み直さない")
    }
}
