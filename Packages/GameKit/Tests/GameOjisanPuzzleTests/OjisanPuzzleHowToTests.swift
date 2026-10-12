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

    @Test("開始シートで常に見せる要点は、目的・腰痛ゲージ（荷運びのみ）・おわり方")
    func setupKeyItemsShowModeDifference() {
        let backpain = OjisanPuzzleMode.backpain
        #expect(backpain.setupKeyItems.map(\.text) == backpain.setupKeyItemIndices.map {
            HowToPlayGuide.ojisanPuzzleBackpain.items[$0].text
        })
        #expect(backpain.setupKeyItems.first?.text.contains("クリア") == true)
        #expect(backpain.setupKeyItems.contains { $0.text.contains("腰痛ゲージ") })
        #expect(backpain.setupKeyItems.last?.text.contains("終わり") == true)

        let puzzle = OjisanPuzzleMode.puzzle
        #expect(puzzle.setupKeyItems.first?.text.contains("得点") == true)
        #expect(puzzle.setupKeyItems.allSatisfy { !$0.text.contains("腰痛ゲージ") })
        #expect(puzzle.setupKeyItems.last?.text.contains("終わり") == true)

        for mode in OjisanPuzzleMode.allCases {
            // 要点と折りたたみで、遊び方の項目を過不足なく分けている（図も付いたまま）。
            #expect(mode.setupKeyItems.count + mode.setupDetailItems.count == mode.howToPlayGuide.items.count)
            #expect(Set(mode.setupKeyItems.map(\.text)).isDisjoint(with: mode.setupDetailItems.map(\.text)))
            #expect((mode.setupKeyItems + mode.setupDetailItems).allSatisfy { $0.figure != nil })
            // 操作・れんさは折りたたみ側。
            #expect(mode.setupDetailItems.contains { $0.text.contains("スワイプ") })
            #expect(mode.setupDetailItems.contains { $0.text.contains("れんさ") })
        }
    }

    @Test("開始シートの中に選んでいるモードの遊び方を図つきで並べ、別画面へ遷移しない（会長指示 2026-10-12）")
    func setupSheetShowsModeGuideInline() throws {
        let code = SourceScan.strippingComments(
            try SourceScan.packageSource("Sources/GameOjisanPuzzle/OjisanPuzzleSetupSheet.swift"))
        #expect(code.contains("GameSetupSheet(kind: .solo, onStart: onStart, onCancel: onCancel)"))
        #expect(code.contains("HowToPlayItemCard(item)"), "遊び方シートと同じカード部品で並べていない")
        #expect(code.contains("mode.setupKeyItems"))
        #expect(code.contains("if showsDetails {"), "操作・れんさの説明を折りたたんでいない")
        #expect(!code.contains("HowToPlaySheet("), "別画面の遊び方シートへ遷移している")
        #expect(!code.contains(".sheet("), "開始シートの上に別のシートを重ねている")
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
