import Testing
import Core
@testable import GameSolitaire

/// 図で見る「はじめての遊び方」（#2824）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("ソリティア: はじめての遊び方")
struct SolitaireOnboardingTests {
    private func board(piles: [SolitairePile], foundations: [Int] = [0, 0, 0, 0],
                       stock: [SolitaireCard] = [], waste: [SolitaireCard] = []) -> SolitaireBoard {
        var piles = piles
        while piles.count < SolitaireBoard.pileCount { piles.append(SolitairePile()) }
        return SolitaireBoard(tableau: piles, foundations: foundations, stock: stock, waste: waste)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(SolitaireOnboarding.guide.isWellFormed)
        #expect(SolitaireOnboarding.guide.gameID == "solitaire")
    }

    @Test("重ね方の図: 黒の 8 の上に赤の 7 は置け、同色の 7・飛んだ 6 は置けない")
    func stackingFigure() {
        let b = board(piles: [SolitairePile(faceDown: [], faceUp: [SolitaireCard(.spade, 8)])])
        #expect(b.canPlace([SolitaireCard(.heart, 7)], onPile: 0))
        #expect(!b.canPlace([SolitaireCard(.club, 7)], onPile: 0))
        #expect(!b.canPlace([SolitaireCard(.heart, 6)], onPile: 0))
    }

    @Test("そろった並び（降順・交互色）は、まとめて動かして置ける")
    func runMoves() {
        let run = [SolitaireCard(.heart, 7), SolitaireCard(.club, 6)]
        let b = board(piles: [SolitairePile(faceDown: [], faceUp: [SolitaireCard(.spade, 8)]),
                              SolitairePile(faceDown: [], faceUp: run)])
        #expect(b.isMovableRun(pile: 1, from: 0))
        #expect(b.canPlace(run, onPile: 0))
    }

    @Test("空いた列には K だけ置け、K から始まる並びはまとめて置ける")
    func emptyColumn() {
        let b = board(piles: [])
        #expect(b.canPlace([SolitaireCard(.heart, 13)], onPile: 0))
        #expect(b.canPlace([SolitaireCard(.heart, 13), SolitaireCard(.club, 12)], onPile: 0))
        #expect(!b.canPlace([SolitaireCard(.heart, 12)], onPile: 0))
    }

    @Test("組札は同じスートで A から順。4 つとも K まで積めたらクリア")
    func foundationAndWin() {
        let b = board(piles: [], foundations: [0, 0, 0, 0])
        #expect(b.canSendToFoundation(SolitaireCard(.spade, 1)))
        #expect(!b.canSendToFoundation(SolitaireCard(.spade, 2)))
        #expect(!b.isWon)
        #expect(board(piles: [], foundations: [12, 13, 13, 13]).isWon == false)
        #expect(board(piles: [], foundations: [13, 13, 13, 13]).isWon)
    }

    @Test("山札: 1 枚めくりは 1 枚ずつ・3 枚めくりは 3 枚ずつ。最後までめくったあとのタップで最初からめくれる")
    func stock() {
        #expect(SolitaireDrawMode.one.drawCount == 1)
        #expect(SolitaireDrawMode.three.drawCount == 3)
        let stock = (1...4).map { SolitaireCard(.spade, $0) }
        var b = board(piles: [], stock: stock)
        let drew = b.apply(.draw)
        #expect(drew)
        #expect(b.waste.count == 1 && b.stock.count == 3)
        var empty = board(piles: [], stock: [], waste: stock)
        let recycled = empty.apply(.draw)
        #expect(recycled)
        // 捨て札が山札に戻り、そのまま 1 枚めくれる（先頭から）。
        #expect(empty.stock.count == 3 && empty.waste.count == 1)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in SolitaireOnboarding.guide.texts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
