import Testing
import Core
@testable import GameBlackjack

/// ブラックジャックのカードをトランプ共通基盤（#397）の面へ写す変換を固定する。
///
/// ランクは既に A=1 表記なので素通しでよいが、**A の点数は 11（`value`）** という別の数値が
/// 同居しているため、面の表記にそちらが漏れていないことを押さえておく。
struct BlackjackCardFigureTests {

    @Test("A は点数 11 でも面には A と出す")
    func aceShowsAceNotItsValue() {
        let ace = BlackjackCard(id: 0, suit: .spades, rank: 1)
        #expect(ace.value == 11)
        #expect(ace.figure == .pip(suit: .spade, rank: 1))
        #expect(ace.figure.rankLabel == "A")
    }

    @Test("絵札は点数 10 でも J / Q / K と出す")
    func courtCardsShowLetters() {
        for (rank, label) in [(11, "J"), (12, "Q"), (13, "K")] {
            let card = BlackjackCard(id: rank, suit: .clubs, rank: rank)
            #expect(card.value == 10)
            #expect(card.figure.rankLabel == label)
            #expect(card.figure.rankLabel == card.rankLabel)
        }
    }

    @Test("スートは共通基盤の同じスートへ写る")
    func suitsMapOneToOne() {
        let pairs: [(BlackjackSuit, PlayingCardSuit)] = [
            (.spades, .spade), (.hearts, .heart), (.diamonds, .diamond), (.clubs, .club),
        ]
        for (blackjack, playing) in pairs {
            #expect(blackjack.playing == playing)
            #expect(blackjack.symbol == playing.symbol)
            #expect(blackjack.isRed == playing.isRed)
        }
    }
}
