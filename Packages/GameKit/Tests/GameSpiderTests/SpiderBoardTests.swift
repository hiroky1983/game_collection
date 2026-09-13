import Testing
import Foundation
@testable import GameSpider

/// 盤面を手で組むための道具。
private func card(_ suit: SpiderSuit, _ rank: Int, id: Int? = nil) -> SpiderCard {
    SpiderCard(id: id ?? (suit.rawValue * 13 + rank - 1), suit: suit, rank: rank)
}

private func board(_ piles: [[SpiderCard]], faceDown: [Int]? = nil,
                   stock: [[SpiderCard]] = [], completed: [SpiderSuit] = []) -> SpiderBoard {
    var columns = piles.map { SpiderPile(cards: $0, faceDownCount: 0) }
    while columns.count < SpiderBoard.pileCount { columns.append(SpiderPile(cards: [])) }
    if let faceDown {
        for (index, count) in faceDown.enumerated() where index < columns.count {
            columns[index].faceDownCount = min(count, columns[index].cards.count)
        }
    }
    return SpiderBoard(piles: columns, stock: stock, completed: completed)
}

@Suite("スパイダーの盤面")
struct SpiderBoardTests {

    // MARK: - 並びと置き方

    @Test("同じスートで降順の並びだけがまとめて動かせる")
    func movableRunRequiresSameSuitDescending() {
        let b = board([
            [card(.spade, 9), card(.spade, 8), card(.spade, 7)],
            [card(.spade, 9), card(.heart, 8), card(.heart, 7)],
            [card(.spade, 9), card(.spade, 7)],
        ])
        #expect(b.isMovableRun(pile: 0, from: 0))
        #expect(b.isMovableRun(pile: 0, from: 1))
        #expect(!b.isMovableRun(pile: 1, from: 0), "スートが変わる並びは動かせない")
        #expect(b.isMovableRun(pile: 1, from: 1), "♥8♥7 の部分だけなら動かせる")
        #expect(!b.isMovableRun(pile: 2, from: 0), "降順が飛んでいる")
    }

    @Test("伏せ札を含む位置からは動かせない")
    func faceDownCardsAreNotMovable() {
        let b = board([[card(.spade, 9), card(.spade, 8), card(.spade, 7)]], faceDown: [1])
        #expect(!b.isMovableRun(pile: 0, from: 0))
        #expect(b.isMovableRun(pile: 0, from: 1))
    }

    @Test("置けるのは 1 つ大きい札の上（スート不問）か空いた列")
    func placementIgnoresSuit() {
        let b = board([
            [card(.spade, 8)],
            [card(.heart, 8)],
            [card(.spade, 6)],
            [],
        ])
        let seven = [card(.club, 7)]
        #expect(b.canPlace(seven, onPile: 0))
        #expect(b.canPlace(seven, onPile: 1))
        #expect(!b.canPlace(seven, onPile: 2))
        #expect(b.canPlace(seven, onPile: 3), "空いた列にはどの札でも置ける")
        #expect(b.canPlace([card(.diamond, 13)], onPile: 3))
    }

    @Test("非合法な手は適用されず false を返す")
    func illegalMoveIsRejected() {
        var b = board([[card(.spade, 8)], [card(.spade, 6)]])
        let before = b
        let applied1 = b.apply(.move(from: 0, cardIndex: 0, to: 1))
        #expect(!applied1)
        let applied2 = b.apply(.move(from: 0, cardIndex: 0, to: 0))
        #expect(!applied2)
        let applied3 = b.apply(.move(from: 5, cardIndex: 0, to: 1))
        #expect(!applied3, "範囲外の列")
        let applied4 = b.apply(.deal)
        #expect(!applied4, "山札が無い")
        #expect(b == before)
    }

    // MARK: - めくりと取り除き

    @Test("動かして空いた下の伏せ札は自動で表になる")
    func exposedCardFlips() {
        var b = board([[card(.heart, 3), card(.spade, 7)], [card(.spade, 8)]], faceDown: [1, 0])
        let applied5 = b.apply(.move(from: 0, cardIndex: 1, to: 1))
        #expect(applied5)
        #expect(b.piles[0].faceDownCount == 0)
        #expect(b.piles[0].cards == [card(.heart, 3)])
        #expect(b.piles[1].cards.map(\.rank) == [8, 7])
    }

    @Test("同じスートの K〜A が揃うと自動で取り除かれ、下の伏せ札がめくれる")
    func completedSequenceIsRemoved() {
        let run = (2...13).reversed().map { card(.spade, $0) }   // K〜2
        var b = board([
            [card(.heart, 5)] + run,
            [card(.spade, 1)],
        ], faceDown: [1, 0])
        let applied6 = b.apply(.move(from: 1, cardIndex: 0, to: 0))
        #expect(applied6)
        #expect(b.completed == [.spade])
        #expect(b.piles[0].cards == [card(.heart, 5)])
        #expect(b.piles[0].faceDownCount == 0, "取り除いたあとに残った伏せ札は表になる")
        #expect(b.piles[1].isEmpty)
    }

    @Test("スートが混ざった K〜A は取り除かれない")
    func mixedSequenceIsNotRemoved() {
        var run = (2...13).reversed().map { card(.spade, $0) }
        run[5] = card(.heart, run[5].rank)
        var b = board([run, [card(.spade, 1)]])
        let applied7 = b.apply(.move(from: 1, cardIndex: 0, to: 0))
        #expect(applied7)
        #expect(b.completed.isEmpty)
        #expect(b.piles[0].cards.count == 13)
    }

    @Test("8 組取り除いたらクリア")
    func winRequiresEightSequences() {
        let run = (2...13).reversed().map { card(.spade, $0) }
        var b = board([run, [card(.spade, 1)]], completed: Array(repeating: .spade, count: 7))
        #expect(!b.isWon)
        let applied8 = b.apply(.move(from: 1, cardIndex: 0, to: 0))
        #expect(applied8)
        #expect(b.isWon)
    }

    // MARK: - 配り

    @Test("配ると各列に 1 枚ずつ載り、山札が 1 回ぶん減る")
    func dealAddsOneCardToEveryPile() {
        let piles = (0..<10).map { [card(.spade, 5, id: $0)] }
        let deal = (0..<10).map { card(.heart, 9, id: 20 + $0) }
        var b = board(piles, stock: [deal])
        #expect(b.canDeal)
        let applied9 = b.apply(.deal)
        #expect(applied9)
        #expect(b.dealsRemaining == 0)
        #expect(b.piles.allSatisfy { $0.cards.count == 2 && $0.top?.rank == 9 })
        #expect(!b.canDeal)
    }

    @Test("空いた列があると配れない")
    func dealIsBlockedByEmptyPile() {
        var piles = (0..<10).map { [card(.spade, 5, id: $0)] }
        piles[3] = []
        let deal = (0..<10).map { card(.heart, 9, id: 20 + $0) }
        let b = board(piles, stock: [deal])
        #expect(!b.canDeal)
        #expect(b.isDealBlockedByEmptyPile)
        #expect(!b.isLegal(.deal))
    }

    @Test("配った札で K〜A が揃えばその場で取り除かれる")
    func dealCanCompleteSequence() {
        var piles = (0..<10).map { [card(.spade, 5, id: $0)] }
        piles[0] = (2...13).reversed().map { card(.heart, $0, id: 40 + $0) }
        var deal = (0..<10).map { card(.club, 4, id: 20 + $0) }
        deal[0] = card(.heart, 1, id: 99)
        var b = board(piles, stock: [deal])
        let applied10 = b.apply(.deal)
        #expect(applied10)
        #expect(b.completed == [.heart])
        #expect(b.piles[0].isEmpty)
    }

    // MARK: - 詰み

    @Test("置き先も配りも無ければ行き止まり")
    func deadEndWhenNothingMoves() {
        let kings = (0..<10).map { card(.spade, 13, id: $0) }.map { [$0] }
        let b = board(kings)
        #expect(b.legalMoves.isEmpty)
        #expect(b.isDeadEnd)
        // 山札が残っていれば配れるので行き止まりではない。
        let withStock = board(kings, stock: [(0..<10).map { card(.heart, 2, id: 20 + $0) }])
        #expect(!withStock.isDeadEnd)
        #expect(withStock.legalMoves == [.deal])
    }

    @Test("合法手の一覧はすべて適用できる")
    func legalMovesAreApplicable() {
        let b = SpiderDealer.deal(seed: 3, suits: .two)
        let moves = b.legalMoves
        #expect(!moves.isEmpty)
        for move in moves {
            var copy = b
            let applied11 = copy.apply(move)
            #expect(applied11, "\(move)")
        }
    }

    // MARK: - キー

    @Test("同じスート・ランクの札を入れ替えただけの局面は同じキーになる")
    func stateKeyIgnoresCardIdentity() {
        let a = board([[card(.spade, 5, id: 0)], [card(.spade, 5, id: 1)]])
        let b = board([[card(.spade, 5, id: 1)], [card(.spade, 5, id: 0)]])
        #expect(a.stateKey == b.stateKey)
        let c = board([[card(.spade, 5, id: 0)], [card(.heart, 5, id: 1)]])
        #expect(a.stateKey != c.stateKey)
    }

    @Test("山札が尽きたあとは伏せ札の無い列の並べ替えを同一視し、残っているあいだは区別する")
    func stateKeyCanonicalizesOnlyAfterStockIsExhausted() {
        let x = [card(.spade, 5, id: 0)], y = [card(.heart, 9, id: 1)]
        let a = board([x, y])
        let b = board([y, x])
        #expect(a.stateKey == b.stateKey)
        let deal = (0..<10).map { card(.club, 4, id: 20 + $0) }
        let withStockA = board([x, y], stock: [deal])
        let withStockB = board([y, x], stock: [deal])
        #expect(withStockA.stateKey != withStockB.stateKey, "次の配りで載る札が列ごとに違う")
    }
}
