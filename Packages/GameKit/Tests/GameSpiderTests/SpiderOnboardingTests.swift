import Testing
import Core
@testable import GameSpider

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("スパイダー: はじめての遊び方")
struct SpiderOnboardingTests {
    private func card(_ suit: SpiderSuit, _ rank: Int, id: Int? = nil) -> SpiderCard {
        SpiderCard(id: id ?? (suit.rawValue * 13 + rank - 1), suit: suit, rank: rank)
    }

    private func board(_ piles: [[SpiderCard]], stock: [[SpiderCard]] = [], completed: [SpiderSuit] = []) -> SpiderBoard {
        var columns = piles.map { SpiderPile(cards: $0, faceDownCount: 0) }
        while columns.count < SpiderBoard.pileCount { columns.append(SpiderPile(cards: [])) }
        return SpiderBoard(piles: columns, stock: stock, completed: completed)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(SpiderOnboarding.guide.isWellFormed)
        #expect(SpiderOnboarding.guide.gameID == "spider")
    }

    @Test("置き方の図: 1 つ小さい札ならスートを問わず置け、2 つ小さい札は置けない。空いた列にはどの札でも置ける")
    func stacking() {
        let b = board([[card(.spade, 8)]])
        #expect(b.canPlace([card(.heart, 7)], onPile: 0))
        #expect(b.canPlace([card(.spade, 7, id: 99)], onPile: 0))
        #expect(!b.canPlace([card(.spade, 6)], onPile: 0))
        #expect(b.canPlace([card(.diamond, 5)], onPile: 1))
    }

    @Test("まとめて動かせるのは、同じスートで降順の並びだけ")
    func movableRun() {
        let b = board([[card(.spade, 8), card(.spade, 7), card(.spade, 6)],
                       [card(.spade, 8, id: 90), card(.heart, 7), card(.spade, 6, id: 91)]])
        #expect(b.isMovableRun(pile: 0, from: 0))
        #expect(!b.isMovableRun(pile: 1, from: 0))
        #expect(b.isMovableRun(pile: 1, from: 2))
    }

    @Test("山札は各列に 1 枚ずつ配る。空いた列があるあいだは配れない")
    func deal() {
        #expect(SpiderBoard.dealSize == SpiderBoard.pileCount)
        let stock = [(0..<SpiderBoard.pileCount).map { card(.spade, 2, id: 200 + $0) }]
        let full = board((0..<SpiderBoard.pileCount).map { [card(.heart, 9, id: 300 + $0)] }, stock: stock)
        #expect(full.canDeal)
        var dealt = full
        let ok = dealt.apply(.deal)
        #expect(ok)
        #expect(dealt.piles.allSatisfy { $0.cards.count == 2 })
        let blocked = board([[card(.heart, 9)]], stock: stock)
        #expect(!blocked.canDeal && blocked.isDealBlockedByEmptyPile)
    }

    @Test("K から A の 13 枚がそろうと取り除かれ、8 組でクリア")
    func completeAndWin() {
        #expect(SpiderBoard.sequenceLength == 13 && SpiderBoard.sequenceGoal == 8)
        // K〜2 の 12 枚に A を載せて 13 枚そろえると、その並びは自動で取り除かれる。
        let almost = (2...13).reversed().map { card(.spade, $0) }
        var b = board([almost, [card(.spade, 1)]])
        let moved = b.apply(.move(from: 1, cardIndex: 0, to: 0))
        #expect(moved)
        #expect(b.completed == [.spade] && b.piles[0].isEmpty)
        #expect(!board([], completed: Array(repeating: .spade, count: 7)).isWon)
        #expect(board([], completed: Array(repeating: .spade, count: 8)).isWon)
    }

    @Test("スートの数は 1・2・4。1 スートは ♠ だけ、2 スートは ♠♥、4 スートは 4 種すべて")
    func suitCounts() {
        #expect(SpiderSuitCount.allCases.map(\.rawValue) == [1, 2, 4])
        #expect(SpiderSuitCount.one.suits.map(\.symbol) == ["♠"])
        #expect(SpiderSuitCount.two.suits.map(\.symbol) == ["♠", "♥"])
        #expect(SpiderSuitCount.four.suits.count == 4)
    }

    @Test("文言の数字（取り除く組の数）が実装の値から作られ、全部の文言に英語の訳がある")
    func numbersAndEnglish() {
        let key = "%lld 組すべて取り除いたら、クリアです。"
        let lines = SpiderOnboarding.guide.pages.flatMap(\.lines)
        #expect(lines.contains("\(SpiderBoard.sequenceGoal) 組すべて取り除いたら、クリアです。"))
        #expect(tr.hasTranslation(key, language: .english))
        let filled = tr(key, SpiderBoard.sequenceGoal)
        for text in SpiderOnboarding.guide.texts where text != filled {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
