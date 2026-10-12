import Testing
import Core
import GameKitTestSupport
@testable import GameOjisanPuzzle

/// 図入りの遊び方（#2044 の先駆け・会長決定 2026-10-12）。「？」は遊んでいるモードに合わせて
/// 出し分ける（会長指示 2026-10-12）。
@Suite("おじさんの荷物運びパズルの遊び方")
@MainActor
struct OjisanPuzzleHowToTests {
    @Test("荷運びモードは項目ごとに図が 1 つずつある（文と図の数がずれない）")
    func everyBackpainItemHasFigure() {
        #expect(OjisanPuzzleHowToFigures.backpain.count == HowToPlayGuide.ojisanPuzzleBackpain.items.count)
        let guide = HowToPlayGuide.ojisanPuzzleBackpain.illustrated(OjisanPuzzleHowToFigures.backpain)
        #expect(guide.items.allSatisfy { $0.figure != nil })
        // 図を差し込んでも文言は変わらない。
        #expect(guide.items.map(\.text) == HowToPlayGuide.ojisanPuzzleBackpain.items.map(\.text))
        #expect(guide.notes == HowToPlayGuide.ojisanPuzzleBackpain.notes)
    }

    @Test("パズルモードは項目ごとに図が 1 つずつあり、腰痛ゲージの項目が無い")
    func everyPuzzleItemHasFigure() {
        #expect(OjisanPuzzleHowToFigures.puzzle.count == HowToPlayGuide.ojisanPuzzlePuzzle.items.count)
        let guide = HowToPlayGuide.ojisanPuzzlePuzzle.illustrated(OjisanPuzzleHowToFigures.puzzle)
        #expect(guide.items.allSatisfy { $0.figure != nil })
        #expect(guide.items.map(\.text) == HowToPlayGuide.ojisanPuzzlePuzzle.items.map(\.text))
        #expect(guide.notes == HowToPlayGuide.ojisanPuzzlePuzzle.notes)
        // 腰痛ゲージ・入院・クリアライン・せり上がりはパズルモードの「？」に出さない。
        #expect(guide.items.count < HowToPlayGuide.ojisanPuzzleBackpain.items.count)
        #expect(guide.items.allSatisfy { !$0.text.contains("腰痛ゲージ") && !$0.text.contains("入院") })
    }

    @Test("画面のヘッダーに図入りの遊び方をつなぎ、読んでいるあいだは止める")
    func viewWiresHowToPlay() throws {
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleView.swift"))
        #expect(code.contains(".howToPlay(howToPlayGuide,"))
        #expect(code.contains("model.mode.howToPlayGuide"))
        #expect(code.contains("onPresent: { model.pause() }"))
    }

    @Test("モードごとの遊び方は、そのモード用の図入りの文言になる")
    func modeGuideMatchesMode() {
        let backpain = OjisanPuzzleMode.backpain.howToPlayGuide
        #expect(backpain.items.map(\.text) == HowToPlayGuide.ojisanPuzzleBackpain.items.map(\.text))
        #expect(backpain.items.allSatisfy { $0.figure != nil })
        let puzzle = OjisanPuzzleMode.puzzle.howToPlayGuide
        #expect(puzzle.items.map(\.text) == HowToPlayGuide.ojisanPuzzlePuzzle.items.map(\.text))
        #expect(puzzle.items.allSatisfy { $0.figure != nil })
    }

    @Test("開始シートから、選んでいるモードの遊び方を開ける（会長指示 2026-10-12）")
    func setupSheetOpensModeGuide() throws {
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleSetupSheet.swift"))
        #expect(code.contains("GameSetupSheet(kind: .solo, howToPlay: howToPlay,"))
        #expect(code.contains("GameSetupHowToPlay(mode.howToPlayGuide, label: \"\\(mode.title)の遊び方を見る\")"))
        #expect(code.contains(".ojisanPuzzleBackpain.illustrated(OjisanPuzzleHowToFigures.backpain)"))
        #expect(code.contains(".ojisanPuzzlePuzzle.illustrated(OjisanPuzzleHowToFigures.puzzle)"))
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
