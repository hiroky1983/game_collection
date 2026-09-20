import Testing
import Foundation
@testable import GameSevens

/// 「出せる手の判定」（#1198）の固定。
///
/// 七並べは操作が「持ち札を出す」だけで、出せるかどうかは場の開通状況が機械的に決める。
/// 判定を1マスでも取り違えると気づけないまま進行が壊れるので、境界値をすべて固定する。
@Suite("七並べのルール")
struct SevensRulesTests {

    private func card(_ suit: SevensSuit, _ rank: Int, id: Int = 0) -> SevensCard {
        SevensCard(id: id, suit: suit, rank: rank)
    }

    // MARK: - 合法判定

    @Test("未着手のスートは 7 だけ出せる")
    func onlySevenOnUntouchedSuit() {
        let board = SevensRules.emptyBoard()
        #expect(SevensRules.canPlay(card(.spades, 7), board: board))
        for rank in 1...13 where rank != 7 {
            #expect(!SevensRules.canPlay(card(.spades, rank), board: board), "\(rank) は出せない")
        }
    }

    @Test("着手済みのスートは下限-1と上限+1だけ出せる")
    func extendsFromBothEnds() {
        var board = SevensRules.emptyBoard()
        board[SevensSuit.hearts.rawValue] = SevensSuitRange(low: 5, high: 8)
        #expect(SevensRules.canPlay(card(.hearts, 4), board: board), "下限の1つ下は出せる")
        #expect(SevensRules.canPlay(card(.hearts, 9), board: board), "上限の1つ上は出せる")
        #expect(!SevensRules.canPlay(card(.hearts, 3), board: board), "2つ飛ばしては出せない")
        #expect(!SevensRules.canPlay(card(.hearts, 10), board: board), "2つ飛ばしては出せない")
        #expect(!SevensRules.canPlay(card(.hearts, 6), board: board), "既に開通済みの数字は出せない")
    }

    @Test("端（A・K）まで埋まったらそれ以上出せない")
    func edgesStopExtending() {
        var board = SevensRules.emptyBoard()
        board[SevensSuit.clubs.rawValue] = SevensSuitRange(low: 1, high: 13)
        for rank in 1...13 {
            #expect(!SevensRules.canPlay(card(.clubs, rank), board: board), "\(rank) は既に埋まっている")
        }
    }

    @Test("他のスートには影響しない")
    func suitsAreIndependent() {
        var board = SevensRules.emptyBoard()
        board[SevensSuit.diamonds.rawValue] = SevensSuitRange(low: 7, high: 7)
        #expect(!SevensRules.canPlay(card(.spades, 6), board: board), "スペードはまだ未着手")
        #expect(SevensRules.canPlay(card(.spades, 7), board: board))
    }

    // MARK: - apply

    @Test("apply は下限側・上限側どちらの延長も正しく反映する")
    func applyExtendsRange() {
        let board = SevensRules.emptyBoard()
        let afterSeven = SevensRules.apply(card(.spades, 7), to: board)
        #expect(afterSeven[SevensSuit.spades.rawValue] == SevensSuitRange(low: 7, high: 7))

        let afterSix = SevensRules.apply(card(.spades, 6), to: afterSeven)
        #expect(afterSix[SevensSuit.spades.rawValue] == SevensSuitRange(low: 6, high: 7))

        let afterEight = SevensRules.apply(card(.spades, 8), to: afterSix)
        #expect(afterEight[SevensSuit.spades.rawValue] == SevensSuitRange(low: 6, high: 8))
    }

    @Test("出せない札を渡しても場は変わらない")
    func applyIgnoresIllegalCard() {
        let board = SevensRules.emptyBoard()
        let result = SevensRules.apply(card(.spades, 6), to: board)
        #expect(result == board)
    }

    // MARK: - playableCards

    @Test("手札の中で出せる札だけを返す")
    func playableCardsFiltersHand() {
        var board = SevensRules.emptyBoard()
        board[SevensSuit.hearts.rawValue] = SevensSuitRange(low: 7, high: 7)
        let hand = [card(.hearts, 6, id: 1), card(.hearts, 9, id: 2), card(.spades, 7, id: 3), card(.clubs, 2, id: 4)]
        let playable = Set(SevensRules.playableCards(hand: hand, board: board).map(\.id))
        #expect(playable == [1, 3], "ハートの6・スペードの7だけが出せる")
    }

    // MARK: - CPU の選択

    @Test("出せる手が無ければ nil")
    func greedyPlayReturnsNilWhenNothingPlayable() {
        let board = SevensRules.emptyBoard()
        let hand = [card(.hearts, 3, id: 1), card(.clubs, 5, id: 2)]
        #expect(SevensRules.greedyPlay(hand: hand, board: board) == nil)
    }

    @Test("7 から最も離れたランクを優先する")
    func greedyPlayPrefersFarthestFromSeven() {
        var board = SevensRules.emptyBoard()
        board[SevensSuit.spades.rawValue] = SevensSuitRange(low: 1, high: 13)
        board[SevensSuit.hearts.rawValue] = SevensSuitRange(low: 6, high: 8)
        // ハートは 5(距離2) と 9(距離2) が出せる、クラブは 7(距離0) が出せる。
        board[SevensSuit.clubs.rawValue] = SevensSuitRange()
        let hand = [
            card(.hearts, 5, id: 1),
            card(.hearts, 9, id: 2),
            card(.clubs, 7, id: 3),
        ]
        let chosen = SevensRules.greedyPlay(hand: hand, board: board)
        #expect(chosen?.id == 1, "距離が同じ 1 と 2 の中では id が小さい方（決定的なタイブレーク）")
    }

    @Test("距離が離れた札を距離が近い札より優先する")
    func greedyPlayPicksLargerDistance() {
        var board = SevensRules.emptyBoard()
        // スペードは 7 が出れば距離 0、ハートは既に 6〜8 まで開通していて 5/9 は距離 2。
        board[SevensSuit.spades.rawValue] = SevensSuitRange()
        board[SevensSuit.hearts.rawValue] = SevensSuitRange(low: 6, high: 8)
        let hand = [card(.spades, 7, id: 1), card(.hearts, 9, id: 2)]
        #expect(SevensRules.greedyPlay(hand: hand, board: board)?.id == 2, "距離2のハートの9を優先する")
    }

    @Test("距離が同着なら id の小さい方（決定的なタイブレーク）")
    func greedyPlayTieBreaksByID() {
        var board = SevensRules.emptyBoard()
        board[SevensSuit.spades.rawValue] = SevensSuitRange(low: 6, high: 8)
        let hand = [card(.spades, 5, id: 10), card(.spades, 9, id: 11)]
        // 5 の距離は 2、9 の距離は 2 で同着 → id 昇順。
        #expect(SevensRules.greedyPlay(hand: hand, board: board)?.id == 10)
    }

    // MARK: - 開始プレイヤー

    @Test("ダイヤの 7 を持つ人が開始プレイヤー")
    func openingPlayerHoldsDiamondSeven() {
        let hands: [[SevensCard]] = [
            [card(.spades, 1, id: 0)],
            [card(.diamonds, 7, id: 1)],
            [card(.clubs, 3, id: 2)],
            [card(.hearts, 5, id: 3)],
        ]
        #expect(SevensRules.openingPlayer(hands: hands) == 1)
    }
}
