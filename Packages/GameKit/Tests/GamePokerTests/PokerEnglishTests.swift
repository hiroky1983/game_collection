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
        #expect(GamePoker.tr("チェック", language: .english) == "Check")
        #expect(GamePoker.tr("フォールド", language: .english) == "Fold")
        #expect(GamePoker.tr("コール %lld枚", 20, language: .english) == "Call 20")
        #expect(GamePoker.tr("ベット %lld枚", 20, language: .english) == "Bet 20")
        #expect(GamePoker.tr("交換しない", language: .english) == "Stand Pat")
        #expect(GamePoker.tr("ポット", language: .english) == "Pot")
    }

    @Test("チップの枚数は単数と複数で言い分ける")
    func chipPlurals() {
        // 枚数は桁区切り済みの文字列で渡し、単数・複数は後ろに足した整数で選ぶ（表示は 1,000 のまま）。
        #expect(GamePoker.tr("%@枚", "1", 1, language: .english) == "1 chip")
        #expect(GamePoker.tr("%@枚", "40", 40, language: .english) == "40 chips")
        #expect(GamePoker.tr("+%@枚", "1,000", 1000, language: .english) == "+1,000 chips")
        #expect(GamePoker.tr("%@枚", "1,000", 1000) == "1,000枚")
        #expect(GamePoker.tr("%lld枚を交換", 1, language: .english) == "Draw 1 Card")
        #expect(GamePoker.tr("%lld枚を交換", 3, language: .english) == "Draw 3 Cards")
    }

    @Test("CPU の行動は中断データに原文で残し、表示の境目で訳す")
    func cpuActionKeys() {
        // `PokerModel.cpuAction` に入りうる原文（`cpuActionLabel` が訳す先）は、どれも英訳を持つ。
        for key in ["チェック", "コール", "フォールド", "あなたがフォールド", "カード交換なし"] {
            #expect(GamePoker.tr.hasTranslation(key, language: .english), "\(key) に英訳が無い")
        }
        #expect(GamePoker.tr("ベット %lld", 20, language: .english) == "Bet 20")
        #expect(GamePoker.tr("%lld枚交換", 2, language: .english) == "Drew 2 cards")
    }

    @Test("決着の理由は語順を英語に合わせる")
    func resultReason() {
        #expect(GamePoker.tr("%1$@ 対 %2$@", "Flush", "Two Pair", language: .english) == "Flush vs. Two Pair")
        #expect(GamePoker.tr("どちらも%@", "One Pair", language: .english) == "Both have One Pair")
    }
}
