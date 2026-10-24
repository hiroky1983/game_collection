import Testing
import Core
@testable import GameOjisanPuzzle

/// 英語の表示（多言語 #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("おじさんの荷物運びパズル: 英語の文言")
struct OjisanPuzzleLocalizationTests {

    @Test("表示名・モード・腰痛ゲージに英語の訳がある")
    func englishTerms() {
        #expect(GameOjisanPuzzle.tr("おじさんの荷物運びパズル", language: .english) == "Ojisan's Box Puzzle")
        #expect(GameOjisanPuzzle.tr("荷運びモード", language: .english) == "Moving Mode")
        #expect(GameOjisanPuzzle.tr("腰痛ゲージ %1$lld、%2$@", 42, "Back's aching", language: .english)
                == "Back pain 42, Back's aching")
    }

    @Test("記録に保存する区分名は表示言語によらず日本語のまま")
    func recordLabelStaysJapanese() {
        #expect(OjisanPuzzleMode.backpain.recordVariantLabel == "荷運びモード")
        #expect(OjisanPuzzleMode.puzzle.recordVariantLabel == "パズルモード")
        // 日本語の表示名と記録の区分名は同じ文字列（既存の記録と食い違わない）。
        for mode in OjisanPuzzleMode.allCases {
            #expect(mode.title == mode.recordVariantLabel)
        }
    }

    @Test("荷物の名前は 5 種とも英語の訳がある")
    func luggageNames() {
        #expect(GameOjisanPuzzle.tr("スイカ", language: .english) == "Watermelon")
        #expect(OjisanPuzzleLuggage.all.map(\.name) == ["座布団の山", "スイカ", "クーラーボックス", "灯油のポリタンク", "ビールケース"])
    }

    @Test("最大連鎖と一気落としの案内に英語の訳がある（#2810）")
    func maxChainAndFlickGuide() {
        #expect(GameOjisanPuzzle.tr("最大 %lld連鎖", 3, language: .english) == "Best chain: 3")
        #expect(GameOjisanPuzzle.tr("速く下に払うと一気に落とせるようになりました", language: .english)
                == "Flick down fast to drop it all at once")
    }
}
