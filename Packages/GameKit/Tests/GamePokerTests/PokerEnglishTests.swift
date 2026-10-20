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
        #expect(GamePoker.tr("勝負！", language: .english) == "Showdown!")
        #expect(GamePoker.tr("%lld枚を交換", 1, language: .english) == "Draw 1 Card")
        #expect(GamePoker.tr("%lld枚を交換", 3, language: .english) == "Draw 3 Cards")
    }

    @Test("点は単数と複数で言い分ける")
    func pointPlurals() {
        #expect(GamePoker.tr("%lld点", 1, language: .english) == "1 pt")
        #expect(GamePoker.tr("%lld点", 12, language: .english) == "12 pts")
        #expect(GamePoker.tr("合計 %@点", "42", language: .english) == "Total: 42 pts")
        #expect(GamePoker.tr("合計 %@点", "1", language: .english) == "Total: 1 pt")
        #expect(GamePoker.tr("合計 %@点", "1,000") == "合計 1,000点")
    }

    @Test("チップ・ベット・ポット・賭けの語は英訳に残らない")
    func noGamblingWordsInEnglish() {
        let keys = [
            "10回目", "%1$lld / %2$lld 回目", "%1$lld勝 %2$lld敗 %3$lld分", "勝負！", "次の回へ",
            "もう一度（10回勝負）", "広告を見てもう1回交換（1勝負に1回）", "役の点数表", "役の点数表を見る",
            "ポーカーの遊び方",
        ]
        for key in keys where GamePoker.tr.hasTranslation(key, language: .english) {
            let english = GamePoker.tr(key, 1, 2, 3, language: .english).lowercased()
            for word in ["chip", "bet", "pot ", "gambl", "wager", "earn"] {
                #expect(!english.contains(word), "\(key) → \(english)")
            }
        }
    }

    @Test("CPU の行動は中断データに原文で残し、表示の境目で訳す")
    func cpuActionKeys() {
        #expect(GamePoker.tr.hasTranslation("カード交換なし", language: .english))
        #expect(GamePoker.tr("%lld枚交換", 2, language: .english) == "Drew 2 cards")
    }

    @Test("決着の理由は語順を英語に合わせる")
    func resultReason() {
        #expect(GamePoker.tr("%1$@ 対 %2$@", "Flush", "Two Pair", language: .english) == "Flush vs. Two Pair")
        #expect(GamePoker.tr("どちらも%@", "One Pair", language: .english) == "Both have One Pair")
    }
}
