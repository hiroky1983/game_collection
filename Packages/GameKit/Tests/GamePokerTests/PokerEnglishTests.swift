import Testing
import CoreEngine
@testable import GamePoker

/// ポーカーの英語の文言（#2166）。`swift test` は日本語で動くので、英語は `language: .english` を明示して引く。
/// `AppLanguageStore.shared` は書き換えない（並列のテストが巻き込まれる）。
@Suite("ポーカーの英語の文言（#2166）")
struct PokerEnglishTests {

    @Test("役名は英語の標準の呼び名になる")
    func handRanks() {
        #expect(GamePoker.tr("ハイカード", language: .english) == "High Card")
        #expect(GamePoker.tr("ワンペア", language: .english) == "One Pair")
        #expect(GamePoker.tr("ツーペア", language: .english) == "Two Pair")
        #expect(GamePoker.tr("スリーカード", language: .english) == "Three of a Kind")
        #expect(GamePoker.tr("ストレート", language: .english) == "Straight")
        #expect(GamePoker.tr("フラッシュ", language: .english) == "Flush")
        #expect(GamePoker.tr("フルハウス", language: .english) == "Full House")
        #expect(GamePoker.tr("フォーカード", language: .english) == "Four of a Kind")
        #expect(GamePoker.tr("ストレートフラッシュ", language: .english) == "Straight Flush")
        #expect(GamePoker.tr("ロイヤルフラッシュ", language: .english) == "Royal Flush")
    }

    @Test("日本語では役名は従来どおり")
    func handRanksInJapanese() {
        #expect(PokerHandRank.fullHouse.description == "フルハウス")
        #expect(GamePoker.tr("フルハウス", language: .japanese) == "フルハウス")
    }

    @Test("操作の用語")
    func actions() {
        #expect(GamePoker.tr("ポーカー", language: .english) == "Poker")
        #expect(GamePoker.tr("交換しない", language: .english) == "Stand Pat")
        #expect(GamePoker.tr("勝負する", language: .english) == "Showdown")
        #expect(GamePoker.tr("%lld枚を交換", 1, language: .english) == "Draw 1 Card")
        #expect(GamePoker.tr("%lld枚を交換", 3, language: .english) == "Draw 3 Cards")
    }

    @Test("点は単数と複数で言い分ける（#2551）")
    func pointPlurals() {
        #expect(GamePoker.tr("合計 %lld点", 1, language: .english) == "Total 1 pt")
        #expect(GamePoker.tr("合計 %lld点", 12, language: .english) == "Total 12 pts")
        #expect(GamePoker.tr("+%lld点", 18, language: .english) == "+18 pts")
        #expect(GamePoker.tr("%1$lld回目 / %2$lld", 3, 10, language: .english) == "Round 3 / 10")
        #expect(GamePoker.tr("合計 %lld点", 12) == "合計 12点")
    }

    @Test("上の帯の読み上げ文も点を単数と複数で言い分ける（#2574）")
    func scoreboardLabelPlurals() {
        let en = { (total: Int, cpu: Int) in
            GamePoker.tr("%1$lld回目 / %2$lld、合計%3$@、CPU %4$@", 3, 10,
                         GamePoker.tr("%lld点", total, language: .english),
                         GamePoker.tr("%lld点", cpu, language: .english), language: .english)
        }
        #expect(en(1, 1) == "Round 3 of 10, total 1 pt, CPU 1 pt")
        #expect(en(12, 0) == "Round 3 of 10, total 12 pts, CPU 0 pts")
        #expect(PokerAccessibility.scoreboardLabel(round: 3, playerPoints: 1, cpuPoints: 8) == "3回目 / 10、合計1点、CPU 8点")
    }

    @Test("CPU の行動は中断データに原文で残し、表示の境目で訳す")
    func cpuActionKeys() {
        #expect(GamePoker.tr.hasTranslation("カード交換なし", language: .english))
        #expect(GamePoker.tr("%lld枚交換", 2, language: .english) == "Drew 2 cards")
    }

    @Test("決着の理由は語順を英語に合わせる")
    func resultReason() {
        #expect(GamePoker.tr("%1$@ 対 %2$@・+%3$lld点", "Flush", "Two Pair", 12, language: .english)
                == "Flush vs. Two Pair · +12 pts")
        #expect(GamePoker.tr("どちらも%@", "One Pair", language: .english) == "Both have One Pair")
    }
}
