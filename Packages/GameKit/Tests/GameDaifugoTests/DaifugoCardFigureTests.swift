import Testing
import Core
@testable import GameDaifugo

/// 大富豪のカードをトランプ共通基盤（#397）の面へ写す変換を固定する。
///
/// 54枚のうちジョーカー2枚を持つのは現状このゲームだけで、**新しい道化帽の図案を
/// 実際に描画するのも大富豪だけ**（#397 の受け入れ条件「大富豪のジョーカーが新デザインになる」）。
struct DaifugoCardFigureTests {

    @Test("ジョーカーは共通基盤のジョーカーへ写る")
    func jokerMapsToJoker() {
        let jokers = DaifugoCard.makeDeck().filter(\.isJoker)
        #expect(jokers.count == 2)
        for joker in jokers {
            #expect(joker.figure == .joker)
            #expect(joker.figure.rankLabel == "JOKER")
        }
    }

    @Test("実カード52枚はスートとランクを保って写る")
    func realCardsKeepSuitAndRank() {
        let cards = DaifugoCard.makeDeck().filter { !$0.isJoker }
        #expect(cards.count == 52)
        for card in cards {
            #expect(card.figure == .pip(suit: card.suit!.playing, rank: card.rank))
            #expect(card.figure.rankLabel == card.rankLabel)
        }
    }

    @Test("スートは共通基盤の同じスートへ写る")
    func suitsMapOneToOne() {
        let pairs: [(DaifugoSuit, PlayingCardSuit)] = [
            (.spades, .spade), (.hearts, .heart), (.diamonds, .diamond), (.clubs, .club),
        ]
        for (daifugo, playing) in pairs {
            #expect(daifugo.playing == playing)
            #expect(daifugo.symbol == playing.symbol)
            #expect(daifugo.isRed == playing.isRed)
        }
    }
}
