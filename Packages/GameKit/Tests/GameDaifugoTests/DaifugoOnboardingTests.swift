import Testing
import Core
@testable import GameDaifugo

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("大富豪: はじめての遊び方")
struct DaifugoOnboardingTests {
    private func card(_ rank: Int, _ suit: DaifugoSuit? = .spades) -> DaifugoCard {
        DaifugoCard(id: rank * 10 + (suit?.rawValue ?? 9), suit: rank == DaifugoRules.jokerRank ? nil : suit, rank: rank)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(DaifugoOnboarding.guide.isWellFormed)
        #expect(DaifugoOnboarding.guide.gameID == "daifugo")
    }

    @Test("強さ: 3 が最弱・A・2・ジョーカーの順。図の並び（3 7 J A 2 JK）は弱い順に並んでいる")
    func strengthOrder() {
        let order = DaifugoReference.strengthOrder(isRevolution: false)
        #expect(order.first == 3 && order.last == DaifugoRules.jokerRank)
        let figure = [3, 7, 11, 1, 2, DaifugoRules.jokerRank]
        let strengths = figure.map { DaifugoRules.strength(rank: $0, isRevolution: false) }
        #expect(strengths == strengths.sorted())
    }

    @Test("出し方: 同じ枚数で強い組だけが出せる。場が空なら組として成立していれば何枚でも出せる")
    func playRules() {
        #expect(DaifugoRules.isValidPlay([card(11)], field: [card(7)], isRevolution: false))
        #expect(!DaifugoRules.isValidPlay([card(7)], field: [card(11)], isRevolution: false))
        #expect(!DaifugoRules.isValidPlay([card(11), card(11, .hearts)], field: [card(7)], isRevolution: false))
        #expect(DaifugoRules.isValidPlay([card(5), card(5, .hearts), card(5, .clubs)], field: [], isRevolution: false))
        // ジョーカーは最強で、どの数字の代わりにもなる。
        #expect(DaifugoRules.isValidPlay([card(DaifugoRules.jokerRank)], field: [card(2)], isRevolution: false))
        #expect(DaifugoRules.playRank([card(5), card(DaifugoRules.jokerRank)]) == 5)
    }

    @Test("革命: 同じ数字 4 枚で強さが逆になる。8 を含む組は場を流す。反則上がりは 2・8・ジョーカー")
    func specialRules() {
        #expect(DaifugoRules.revolutionCount == 4)
        let four = DaifugoSuit.allCases.map { card(5, $0) }
        #expect(DaifugoRules.triggersRevolution(four))
        #expect(DaifugoRules.strength(rank: 3, isRevolution: true) > DaifugoRules.strength(rank: 2, isRevolution: true))
        #expect(DaifugoRules.clearsField([card(8), card(8, .hearts)]))
        #expect(DaifugoRules.isFoulFinish([card(2)]) && DaifugoRules.isFoulFinish([card(8)])
                && DaifugoRules.isFoulFinish([card(DaifugoRules.jokerRank)]))
        #expect(!DaifugoRules.isFoulFinish([card(9)]))
    }

    @Test("階級: 上がった順に 大富豪・富豪・貧民・大貧民。反則上がりは末尾へ回る")
    func titlesAndFoul() {
        #expect(DaifugoRules.titles == ["大富豪", "富豪", "貧民", "大貧民"])
        #expect(DaifugoRules.ranking(finishOrder: [2, 0, 1, 3], fouls: [2]) == [0, 1, 3, 2])
        #expect(DaifugoModel.playerCount == DaifugoRules.titles.count)
    }

    @Test("文言の数字（革命の枚数）が実装の値から作られる")
    func numbersComeFromRules() {
        let lines = DaifugoOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("同じ数字を \(DaifugoRules.revolutionCount) 枚以上まとめて出すと「革命」。強さが逆になります。"))
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let key = "同じ数字を %lld 枚以上まとめて出すと「革命」。強さが逆になります。"
        #expect(tr.hasTranslation(key, language: .english), "「\(key)」に英語の訳が無い")
        let filled = tr(key, DaifugoRules.revolutionCount)
        for text in DaifugoOnboarding.guide.texts where text != filled {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
