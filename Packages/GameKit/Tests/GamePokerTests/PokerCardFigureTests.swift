import Testing
import Core
@testable import GamePoker

/// ポーカーのカードをトランプ共通基盤（#397）の面へ写す変換を固定する。
///
/// ポーカーだけは A を **14** として持っている（強さの比較にそのまま使うため）。
/// 共通基盤は A=1 表記なので、ここで戻し損ねると A の札が「14」と表示される。
struct PokerCardFigureTests {

    @Test("A は 14 で持っているが面には A と出す")
    func aceIsShownAsAce() {
        let ace = PokerCard(id: 0, suit: .spades, rank: 14)
        #expect(ace.figure == .pip(suit: .spade, rank: 1))
        #expect(ace.figure.rankLabel == "A")
        #expect(ace.figure.rankLabel == ace.rankLabel)
    }

    @Test("A 以外のランクはそのまま面に出る")
    func otherRanksPassThrough() {
        for rank in 2...13 {
            let card = PokerCard(id: rank, suit: .hearts, rank: rank)
            #expect(card.figure == .pip(suit: .heart, rank: rank))
            #expect(card.figure.rankLabel == card.rankLabel)
        }
    }

    @Test("スートは共通基盤の同じスートへ写る")
    func suitsMapOneToOne() {
        let pairs: [(PokerSuit, PlayingCardSuit)] = [
            (.spades, .spade), (.hearts, .heart), (.diamonds, .diamond), (.clubs, .club),
        ]
        for (poker, playing) in pairs {
            #expect(poker.playing == playing)
            #expect(poker.symbol == playing.symbol)
            #expect(poker.isRed == playing.isRed)
        }
    }
}
