import Testing
@testable import Core
@testable import GameConcentration
@testable import GameOjisanPuzzle

/// 遊び方の英語（多言語② #2165）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("遊び方: 英語の文言")
struct HowToPlayLocalizationTests {
    /// `all` に入らない出し分け用の版（五目並べの禁じ手・ポーカーのボーナスルール・荷物運びパズルのパズルモード・麻雀の一局戦・チャリンコおじさんのエンドレス・カードしりとりのとことん）も含めた全部。
    static var guides: [HowToPlayGuide] {
        HowToPlayGuide.all + [.gomokuRenju, .ojisanPuzzlePuzzle, .mahjongSingleHand, .mahjongHanchan, .runnerEndless, .shiritoriEndless]
    }

    @Test("全部の遊び方の題名・本文・ミニガイド・項目・補足に英語の訳がある")
    func everyTextHasEnglish() {
        for guide in Self.guides {
            let texts = [guide.title, guide.hint] + guide.lines + guide.items.map(\.text) + guide.notes
            for text in texts {
                #expect(Core.tr.hasTranslation(text, language: .english), "\(guide.gameID): 「\(text)」に英語の訳が無い")
            }
        }
    }

    @Test("題名は How to Play の形で、ゲーム名は既存の訳に揃える（他社の商標名を使わない）")
    func titlesFollowExistingNames() {
        #expect(Core.tr("将棋の遊び方", language: .english) == "How to Play Shogi")
        #expect(Core.tr("オセロの遊び方", language: .english) == "How to Play Osero")
        #expect(Core.tr("ナンプレの遊び方", language: .english) == "How to Play Number Place")
        #expect(Core.tr("大富豪の遊び方", language: .english) == "How to Play Daifugo")
        #expect(Core.tr("おじさんの荷物運びパズルの遊び方", language: .english) == "How to Play Ojisan's Box Puzzle")
        #expect(Core.tr("くわしいルール", language: .english) == "Detailed Rules")
    }

    @Test("図の中の文字は各ゲームの表で引く（書式・複数形を含む）")
    func figureTexts() {
        #expect(GameConcentration.tr("%lld ペア", 1, language: .english) == "1 pair")
        #expect(GameConcentration.tr("%lld ペア", 5, language: .english) == "5 pairs")
        #expect(GameConcentration.tr("%@（勝ち）", "You", language: .english) == "You (wins)")
        #expect(GameOjisanPuzzle.tr("%@のルール", "Moving Mode", language: .english) == "Moving Mode Rules")
        // 日本語は従来のまま。
        #expect(GameConcentration.tr("%lld ペア", 5, language: .japanese) == "5 ペア")
    }
}
