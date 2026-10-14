import Testing
@testable import Core
@testable import GameHearts

/// 英語の表示（多言語⑥ #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("ハーツ: 英語の文言")
struct HeartsLocalizationTests {
    @Test("表示名・操作・点の文言に英語の訳がある")
    func englishTerms() {
        #expect(GameHearts.tr("ハーツ", language: .english) == "Hearts")
        #expect(GameHearts.tr("CPU1へ3枚渡す", language: .english) == "Pass 3 cards to CPU1")
        #expect(GameHearts.tr("%lld点", 1, language: .english) == "1 pt")
        #expect(GameHearts.tr("%lld点", 13, language: .english) == "13 pts")
        #expect(GameHearts.tr("%@の番", "CPU2", language: .english) == "CPU2's turn")
        #expect(GameHearts.tr("%1$@、この手%2$lld点、合計%3$lld点", "CPU1", 3, 12, language: .english)
                == "CPU1, this hand 3 pts, total 12 pts")
    }

    @Test("遊び方（Core の表）にも英語の訳がある")
    func howToPlayInEnglish() {
        #expect(Core.tr("ハーツの遊び方", language: .english) == "How to Play Hearts")
        for line in ["だれかが 50 点に届いたら終わり。合計の少ない人が勝ちです。", "ハートとスペードのQを取らないように"] {
            #expect(Core.tr(line, language: .english) != line, "「\(line)」に英語が無い")
        }
    }
}
