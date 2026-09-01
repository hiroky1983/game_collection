import Testing
import Foundation
@testable import GameSolitaire

/// 場札1列を組み立てる短縮記法。
private func pile(down: [SolitaireCard] = [], up: [SolitaireCard]) -> SolitairePile {
    SolitairePile(faceDown: down, faceUp: up)
}

private func board(
    _ piles: [SolitairePile],
    foundations: [Int] = [0, 0, 0, 0],
    stock: [SolitaireCard] = [],
    waste: [SolitaireCard] = [],
    joker: Bool = false
) -> SolitaireBoard {
    var piles = piles
    while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
    return SolitaireBoard(tableau: piles, foundations: foundations,
                          stock: stock, waste: waste, jokerAvailable: joker)
}

private let s = SolitaireSuit.spade
private let h = SolitaireSuit.heart
private let d = SolitaireSuit.diamond
private let c = SolitaireSuit.club

@Suite("クロンダイクのルール")
struct SolitaireBoardRuleTests {

    @Test("場札は降順・交互色にだけ積める")
    func tableauStacking() {
        let b = board([pile(up: [SolitaireCard(s, 8)]), pile(up: [SolitaireCard(h, 7)]),
                       pile(up: [SolitaireCard(c, 7)])])
        #expect(b.canPlace([SolitaireCard(h, 7)], onPile: 0))       // 黒8 に 赤7
        #expect(!b.canPlace([SolitaireCard(c, 7)], onPile: 0))      // 同色は不可
        #expect(!b.canPlace([SolitaireCard(h, 6)], onPile: 0))      // ランクが飛ぶのは不可
    }

    @Test("空列には K だけ置ける")
    func emptyColumnTakesOnlyKing() {
        let b = board([pile(up: [SolitaireCard(s, 5)])])
        #expect(b.canPlace([SolitaireCard(h, 13)], onPile: 1))
        #expect(!b.canPlace([SolitaireCard(h, 12)], onPile: 1))
    }

    @Test("組札は同スートで A から昇順にだけ積める")
    func foundationOrder() {
        var b = board([pile(up: [SolitaireCard(s, 1)])])
        #expect(b.canSendToFoundation(SolitaireCard(s, 1)))
        #expect(!b.canSendToFoundation(SolitaireCard(s, 2)))
        b.apply(.tableauToFoundation(pile: 0))
        #expect(b.foundations[s.rawValue] == 1)
        #expect(b.canSendToFoundation(SolitaireCard(s, 2)))
        #expect(!b.canSendToFoundation(SolitaireCard(h, 2)))
    }

    @Test("表向きが無くなった列は伏せ札を1枚めくる")
    func flipsFaceDownCard() {
        var b = board([pile(down: [SolitaireCard(d, 4)], up: [SolitaireCard(s, 1)])])
        b.apply(.tableauToFoundation(pile: 0))
        #expect(b.tableau[0].faceDown.isEmpty)
        #expect(b.tableau[0].top == SolitaireCard(d, 4))
    }

    @Test("正規の連続列は丸ごと動かせる")
    func movesWholeRun() {
        var b = board([
            pile(down: [SolitaireCard(d, 4)],
                 up: [SolitaireCard(s, 9), SolitaireCard(h, 8), SolitaireCard(c, 7)]),
            pile(up: [SolitaireCard(d, 10)]),
        ])
        #expect(b.isMovableRun(pile: 0, from: 0))
        b.apply(.tableauToTableau(from: 0, cardIndex: 0, to: 1))
        #expect(b.tableau[1].faceUp.count == 4)
        #expect(b.tableau[0].top == SolitaireCard(d, 4))   // 伏せ札がめくれる
    }

    @Test("山札は1枚ずつめくり、尽きたら捨て札が戻って循環する")
    func stockRecycles() {
        var b = board([pile(up: [SolitaireCard(s, 5)])],
                      stock: [SolitaireCard(h, 2), SolitaireCard(d, 3)])   // last = ♦3 が先
        b.apply(.draw)
        #expect(b.waste.last == SolitaireCard(d, 3))
        b.apply(.draw)
        #expect(b.waste.last == SolitaireCard(h, 2))
        #expect(b.stock.isEmpty)
        b.apply(.draw)                                   // 捨て札を戻してから1枚めくる
        #expect(b.waste.last == SolitaireCard(d, 3))
    }

    @Test("循環で到達できる札を、必要なめくり回数つきで列挙する")
    func enumeratesReachableStockCards() {
        let b = board([pile(up: [SolitaireCard(s, 5)])],
                      stock: [SolitaireCard(h, 2), SolitaireCard(d, 3)],
                      waste: [SolitaireCard(c, 9), SolitaireCard(s, 4)])
        let reachable = b.reachableStockCards()
        #expect(reachable.map(\.card) == [
            SolitaireCard(s, 4),   // 0 回（いま表を向いている）
            SolitaireCard(d, 3),   // 1 回
            SolitaireCard(h, 2),   // 2 回
            SolitaireCard(c, 9),   // 3 回（捨て札を戻してから）
        ])
        #expect(reachable.map(\.draws) == [0, 1, 2, 3])
        // 山札 + 捨て札の全枚数がちょうど1周で出てくる（重複も取りこぼしも無い）。
        #expect(Set(reachable.map(\.card.id)).count == b.stock.count + b.waste.count)
    }
}

@Suite("ジョーカー（中継札）")
struct SolitaireJokerTests {

    @Test("ジョーカーは場札の上にだけ置ける（空列・組札には置けない）")
    func jokerPlacement() {
        let b = board([pile(up: [SolitaireCard(s, 5)])], joker: true)
        #expect(b.canPlaceJoker(onPile: 0))
        #expect(!b.canPlaceJoker(onPile: 1))                       // 空列は不可（吟味1の確定）
        #expect(!b.canPlace([SolitaireCard.joker], onPile: 0))     // 通常の積み手としても置けない
        #expect(!b.canSendToFoundation(SolitaireCard.joker))
    }

    @Test("所持していなければ置けず、置くと所持は空になる")
    func jokerIsConsumed() {
        var b = board([pile(up: [SolitaireCard(s, 5)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        #expect(!b.jokerAvailable)
        #expect(!b.canPlaceJoker(onPile: 0))
    }

    @Test("ジョーカーの上には任意のカードを1枚だけ置け、その先は通常ルールに戻る")
    func jokerAcceptsAnySingleCard() {
        var b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(d, 3)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        // 色もランクも無関係に1枚だけ乗る。
        #expect(b.canPlace([SolitaireCard(d, 3)], onPile: 0))
        // 2枚以上の連続列は乗らない。
        #expect(!b.canPlace([SolitaireCard(d, 3), SolitaireCard(s, 2)], onPile: 0))
        b.apply(.tableauToTableau(from: 1, cardIndex: 0, to: 0))
        #expect(b.tableau[0].faceUp.map(\.label) == ["♠5", "JOKER", "♦3"])
        // その先は通常ルール（♦3 の上は黒2 のみ）。
        #expect(b.canPlace([SolitaireCard(s, 2)], onPile: 0))
        #expect(!b.canPlace([SolitaireCard(h, 2)], onPile: 0))
    }

    @Test("ジョーカーを含む並びは動かせない（置いたジョーカーは動かない）")
    func jokerCannotBeMoved() {
        var b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(d, 4)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        b.apply(.tableauToTableau(from: 1, cardIndex: 0, to: 0))    // ♠5, JOKER, ♦4
        #expect(!b.isMovableRun(pile: 0, from: 1))                  // JOKER から下は動かせない
        #expect(b.isMovableRun(pile: 0, from: 2))                   // その上の ♦4 だけなら動かせる
    }

    @Test("受け取り済みのジョーカーは露出した瞬間に消え、下の札が使えるようになる")
    func consumedJokerVanishesWhenExposed() {
        var b = board([pile(up: [SolitaireCard(s, 5)]),
                       pile(up: [SolitaireCard(d, 4)]),
                       pile(up: [SolitaireCard(c, 5)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        b.apply(.tableauToTableau(from: 1, cardIndex: 0, to: 0))    // ♠5, JOKER, ♦4
        #expect(b.tableau[0].faceUp.count == 3)
        b.apply(.tableauToTableau(from: 0, cardIndex: 2, to: 2))    // ♦4 を ♣5 の上へ退かす
        #expect(b.tableau[0].faceUp.map(\.label) == ["♠5"])         // JOKER は消滅
        #expect(b.tableau[0].top == SolitaireCard(s, 5))            // 下の札が再び使える
    }

    @Test("まだ何も受け取っていないジョーカーは露出したままでも消えない")
    func pendingJokerStays() {
        var b = board([pile(up: [SolitaireCard(s, 5)])], joker: true)
        b.apply(.placeJoker(pile: 0))
        #expect(b.tableau[0].top?.isJoker == true)
    }
}

@Suite("詰み検知")
struct SolitaireDeadEndTests {

    @Test("動かせる手が1つも無ければ詰み")
    func detectsDeadEnd() {
        // 山札も捨て札も空、場札は互いに積めない2列だけ。
        let b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(c, 9)])])
        #expect(b.isDeadEnd)
    }

    @Test("山札に使える札があれば詰みではない")
    func stockKeepsGameAlive() {
        let b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(c, 9)])],
                      stock: [SolitaireCard(h, 4)])
        #expect(!b.isDeadEnd)
    }

    @Test("空列どうしの入れ替えしか無い状態は詰みとみなす")
    func emptyColumnShuffleIsNotProgress() {
        let b = board([pile(up: [SolitaireCard(s, 13)])])   // ♠K 単独 + 空列6本
        #expect(b.isDeadEnd)
    }

    @Test("ジョーカーを所持していても詰みの判定は変わらない")
    func jokerIsExcludedFromDeadEndCheck() {
        let b = board([pile(up: [SolitaireCard(s, 5)]), pile(up: [SolitaireCard(c, 9)])], joker: true)
        #expect(b.isDeadEnd)
    }

    @Test("クリア済みの盤面は詰みではない")
    func wonBoardIsNotDeadEnd() {
        let b = board([], foundations: [13, 13, 13, 13])
        #expect(b.isWon)
        #expect(!b.isDeadEnd)
    }
}
