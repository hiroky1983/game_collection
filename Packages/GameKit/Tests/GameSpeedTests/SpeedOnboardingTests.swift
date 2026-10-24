import Testing
import Core
import CoreTestSupport
import GameKitTestSupport
@testable import GameSpeed

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("スピード: はじめての遊び方")
struct SpeedOnboardingTests {
    private func card(_ suit: SpeedSuit, _ rank: Int) -> SpeedCard {
        SpeedCard(id: suit.rawValue * 13 + rank - 1, suit: suit, rank: rank)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(SpeedOnboarding.guide.isWellFormed)
        #expect(SpeedOnboarding.guide.gameID == "speed")
    }

    @Test("出せる札: 台札と 1 つ違い。マークは関係なく、同じ数字・2 つ違いは出せない")
    func adjacent() {
        let seven = card(.spades, 7)
        #expect(SpeedRules.canPlay(card(.hearts, 6), onto: seven))
        #expect(SpeedRules.canPlay(card(.diamonds, 8), onto: seven))
        #expect(!SpeedRules.canPlay(card(.hearts, 9), onto: seven))
        #expect(!SpeedRules.canPlay(card(.hearts, 7), onto: seven))
    }

    @Test("A と K もつながる（K の上に A、A の上に K）")
    func wrap() {
        #expect(SpeedRules.canPlay(card(.hearts, 1), onto: card(.clubs, 13)))
        #expect(SpeedRules.canPlay(card(.diamonds, 13), onto: card(.spades, 1)))
    }

    @Test("始めると手札は 4 枚で、出すと山札から 1 枚補充される")
    func handAndRefill() {
        let model = SpeedModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), seed: 2)
        model.start(.standard)
        #expect(SpeedRules.handSize == 4)
        #expect(model.humanHand.count == SpeedRules.handSize && model.cpuHand.count == SpeedRules.handSize)
        // 手札と山札の合計が、出し切るまでの残り枚数。
        #expect(model.remaining(of: .human) == model.humanHand.count + model.humanStock.count)
    }

    @Test("めくるだけが続いて場が動かないときの上限が決まっている（引き分けの根拠）")
    func flipLimit() {
        #expect(SpeedRules.maxConsecutiveFlips > 0)
    }

    @Test("文言の数字（手札の枚数）が実装の値から作られ、全部の文言に英語の訳がある")
    func numbersAndEnglish() {
        let key = "手札はいつも %lld 枚です。"
        let lines = SpeedOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("手札はいつも \(SpeedRules.handSize) 枚です。"))
        #expect(tr.hasTranslation(key, language: .english))
        let filled = tr(key, SpeedRules.handSize)
        for text in SpeedOnboarding.guide.texts where text != filled {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
