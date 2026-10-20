import Testing
import Core
@testable import GameBlackjack

/// 英語の表示（多言語⑥ #2169）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
@Suite("ブラックジャック: 英語の文言")
struct BlackjackLocalizationTests {

    @Test("操作と結果の文言に英語の訳がある")
    func englishTerms() {
        #expect(GameBlackjack.tr("ヒット", language: .english) == "Hit")
        #expect(GameBlackjack.tr("スタンド", language: .english) == "Stand")
        #expect(GameBlackjack.tr("引き分け", language: .english) == "Push")
        #expect(GameBlackjack.tr("あなた%1$lld 対 ディーラー%2$lld", 19, 17, language: .english) == "You 19 vs. dealer 17")
        #expect(GameBlackjack.tr("%1$lld回目 / %2$lld", 3, 10, language: .english) == "Round 3 / 10")
        #expect(GameBlackjack.tr("勝ち %lld点", 7, language: .english) == "Points: 7")
        #expect(GameBlackjack.tr("連勝 %lld", 2, language: .english) == "Streak: 2")
    }

    @Test("日本語ではキーがそのまま出る")
    func japaneseIsUnchanged() {
        #expect(GameBlackjack.tr("あなた%1$lld 対 ディーラー%2$lld", 19, 17, language: .japanese) == "あなた19 対 ディーラー17")
    }
}
