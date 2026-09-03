import Testing
@testable import GamePoker

// カード生成ヘルパー
private func card(_ rank: Int, _ suit: PokerSuit) -> PokerCard {
    PokerCard(id: rank * 10 + suit.rawValue, suit: suit, rank: rank)
}

// MARK: - 役判定

@Suite("役判定")
struct HandRankTests {

    @Test func royalFlush() {
        let hand = [card(14, .spades), card(13, .spades), card(12, .spades),
                    card(11, .spades), card(10, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .royalFlush)
    }

    @Test func straightFlush() {
        let hand = [card(9, .hearts), card(8, .hearts), card(7, .hearts),
                    card(6, .hearts), card(5, .hearts)]
        #expect(HandEvaluator.evaluate(hand).rank == .straightFlush)
    }

    @Test func fourOfAKind() {
        let hand = [card(7, .spades), card(7, .hearts), card(7, .diamonds),
                    card(7, .clubs), card(3, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .fourOfAKind)
    }

    @Test func fullHouse() {
        let hand = [card(10, .spades), card(10, .hearts), card(10, .diamonds),
                    card(5, .spades), card(5, .hearts)]
        #expect(HandEvaluator.evaluate(hand).rank == .fullHouse)
    }

    @Test func flush() {
        let hand = [card(14, .clubs), card(10, .clubs), card(7, .clubs),
                    card(4, .clubs), card(2, .clubs)]
        #expect(HandEvaluator.evaluate(hand).rank == .flush)
    }

    @Test func straight() {
        let hand = [card(9, .spades), card(8, .hearts), card(7, .diamonds),
                    card(6, .clubs), card(5, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .straight)
    }

    @Test func straightWheel() {
        // A-2-3-4-5（ホイール）
        let hand = [card(14, .spades), card(2, .hearts), card(3, .diamonds),
                    card(4, .clubs), card(5, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .straight)
    }

    @Test func threeOfAKind() {
        let hand = [card(8, .spades), card(8, .hearts), card(8, .diamonds),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .threeOfAKind)
    }

    @Test func twoPair() {
        let hand = [card(13, .spades), card(13, .hearts), card(9, .diamonds),
                    card(9, .clubs), card(5, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .twoPair)
    }

    @Test func onePair() {
        let hand = [card(11, .spades), card(11, .hearts), card(8, .diamonds),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .onePair)
    }

    @Test func highCard() {
        let hand = [card(14, .spades), card(10, .hearts), card(7, .diamonds),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .highCard)
    }
}

// MARK: - 役の強さ順

@Suite("役の強さ順")
struct HandRankOrderTests {

    @Test func rankOrder() {
        let order: [PokerHandRank] = [
            .highCard, .onePair, .twoPair, .threeOfAKind,
            .straight, .flush, .fullHouse, .fourOfAKind,
            .straightFlush, .royalFlush
        ]
        for i in 0..<order.count - 1 {
            #expect(order[i] < order[i + 1])
        }
    }
}

// MARK: - 同役のタイブレーカー

@Suite("タイブレーカー")
struct TieBreakerTests {

    @Test func higherPairWins() {
        let kk = [card(13, .spades), card(13, .hearts), card(9, .diamonds),
                  card(4, .clubs), card(2, .spades)]
        let qq = [card(12, .spades), card(12, .hearts), card(9, .diamonds),
                  card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.compare(kk, qq) == 1)
    }

    @Test func sameOnePairHigherKickerWins() {
        // ペアAAで残り: K > Q
        let withK = [card(14, .spades), card(14, .hearts), card(13, .diamonds),
                     card(4, .clubs), card(2, .spades)]
        let withQ = [card(14, .spades), card(14, .hearts), card(12, .diamonds),
                     card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.compare(withK, withQ) == 1)
    }

    @Test func higherTwoPairWins() {
        let kkJJ = [card(13, .spades), card(13, .hearts), card(11, .diamonds),
                    card(11, .clubs), card(5, .spades)]
        let qqJJ = [card(12, .spades), card(12, .hearts), card(11, .diamonds),
                    card(11, .clubs), card(5, .spades)]
        #expect(HandEvaluator.compare(kkJJ, qqJJ) == 1)
    }

    @Test func higherStraightWins() {
        let tenHigh = [card(10, .spades), card(9, .hearts), card(8, .diamonds),
                       card(7, .clubs), card(6, .spades)]
        let nineHigh = [card(9, .spades), card(8, .hearts), card(7, .diamonds),
                        card(6, .clubs), card(5, .spades)]
        #expect(HandEvaluator.compare(tenHigh, nineHigh) == 1)
    }

    @Test func higherFlushWins() {
        let aceHigh = [card(14, .hearts), card(10, .hearts), card(7, .hearts),
                       card(4, .hearts), card(2, .hearts)]
        let kingHigh = [card(13, .hearts), card(10, .hearts), card(7, .hearts),
                        card(4, .hearts), card(2, .hearts)]
        #expect(HandEvaluator.compare(aceHigh, kingHigh) == 1)
    }

    @Test func exactTieIsDraw() {
        let a = [card(14, .spades), card(13, .hearts), card(9, .diamonds),
                 card(5, .clubs), card(2, .spades)]
        let b = [card(14, .hearts), card(13, .diamonds), card(9, .clubs),
                 card(5, .spades), card(2, .hearts)]
        #expect(HandEvaluator.compare(a, b) == 0)
    }

    @Test func aceHighBeatsKingHigh() {
        let aceHigh = [card(14, .spades), card(10, .hearts), card(7, .diamonds),
                       card(4, .clubs), card(2, .spades)]
        let kingHigh = [card(13, .spades), card(10, .hearts), card(7, .diamonds),
                        card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.compare(aceHigh, kingHigh) == 1)
    }

    @Test func wheelStraightLosesToSixHigh() {
        // A-2-3-4-5 はポーカー最弱のストレート。6ハイに負けるべき
        let wheel = [card(14, .spades), card(2, .hearts), card(3, .diamonds),
                     card(4, .clubs), card(5, .spades)]
        let sixHigh = [card(2, .hearts), card(3, .diamonds), card(4, .clubs),
                       card(5, .spades), card(6, .hearts)]
        #expect(HandEvaluator.compare(wheel, sixHigh) == -1)
    }

    @Test func wheelStraightLosesToSevenHigh() {
        let wheel = [card(14, .spades), card(2, .hearts), card(3, .diamonds),
                     card(4, .clubs), card(5, .spades)]
        let sevenHigh = [card(3, .hearts), card(4, .diamonds), card(5, .clubs),
                         card(6, .spades), card(7, .hearts)]
        #expect(HandEvaluator.compare(wheel, sevenHigh) == -1)
    }
}

// MARK: - CPU の交換判断

/// `cpuKeepIndices` は #443 の調査時点でテストが1件も無かった。
/// **現行の挙動を固定する**目的の Suite で、#443 が提案している変更
/// （ワンペアを崩してドローを狙う・ホイール方向 A-2-3-4 を拾う）は
/// 400万〜600万局の実測でいずれもチップ収支を悪化させたため入れていない（決裁待ち）。
@Suite("CPU の交換判断")
struct CPUKeepTests {

    // MARK: 完成役はそのまま持つ

    @Test func madeHandsKeepAllFive() {
        let flush = [card(14, .clubs), card(10, .clubs), card(7, .clubs),
                     card(4, .clubs), card(2, .clubs)]
        #expect(HandEvaluator.cpuKeepIndices(from: flush) == Set(0..<5))

        let straight = [card(9, .spades), card(8, .hearts), card(7, .diamonds),
                        card(6, .clubs), card(5, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: straight) == Set(0..<5))
    }

    @Test func threeOfAKindKeepsOnlyTheTrip() {
        let hand = [card(8, .spades), card(8, .hearts), card(8, .diamonds),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1, 2])
    }

    @Test func twoPairKeepsBothPairs() {
        let hand = [card(9, .spades), card(9, .hearts), card(4, .diamonds),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1, 2, 3])
    }

    // MARK: ワンペアはドローがあっても崩さない（#443 の決裁待ち）

    @Test func onePairKeepsThePair() {
        let hand = [card(9, .spades), card(9, .hearts), card(13, .diamonds),
                    card(5, .clubs), card(2, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1])
    }

    @Test func onePairKeepsThePairEvenWithFlushDraw() {
        // ♥4枚 + オフスートのペア。ペアを崩すとショーダウンの勝率が 58% → 35% に落ちる実測
        let hand = [card(9, .hearts), card(9, .spades), card(5, .hearts),
                    card(3, .hearts), card(2, .hearts)]
        #expect(HandEvaluator.evaluate(hand).rank == .onePair)
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1])
    }

    @Test func onePairKeepsThePairEvenWithOpenEndedStraightDraw() {
        // 5-6-7-8 + 余りの 8
        let hand = [card(8, .spades), card(8, .hearts), card(7, .diamonds),
                    card(6, .clubs), card(5, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .onePair)
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1])
    }

    // MARK: ハイカードのドロー

    @Test func highCardKeepsFlushDraw() {
        let hand = [card(13, .clubs), card(10, .clubs), card(7, .clubs),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1, 2, 3])
    }

    @Test func flushDrawWinsOverStraightDrawWhenBothExist() {
        // ♥4枚（5-6-7-K）と、♠8 を使う 5-6-7-8 の4連続が同時に立つ手。
        // 拾う4枚が食い違うので、フラッシュを優先していることを実際に区別できる
        let hand = [card(8, .spades), card(5, .hearts), card(6, .hearts),
                    card(7, .hearts), card(13, .hearts)]
        #expect(HandEvaluator.evaluate(hand).rank == .highCard)
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [1, 2, 3, 4])
    }

    @Test func highCardKeepsOpenEndedStraightDraw() {
        let hand = [card(9, .spades), card(8, .hearts), card(7, .diamonds),
                    card(6, .clubs), card(2, .spades)]
        #expect(HandEvaluator.evaluate(hand).rank == .highCard)
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1, 2, 3])
    }

    @Test func highCardKeepsBroadwayStraightDraw() {
        // J-Q-K-A。A を 14 として数える筋なので現行の実装でも拾える
        let hand = [card(14, .spades), card(13, .hearts), card(12, .diamonds),
                    card(11, .clubs), card(3, .hearts)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0, 1, 2, 3])
    }

    @Test func insideStraightIsNotDrawn() {
        // 9-8-6-5 は間が抜けている（ガットショット）。狙わず A だけ残す
        let hand = [card(14, .spades), card(9, .hearts), card(8, .diamonds),
                    card(6, .clubs), card(5, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0])
    }

    @Test func wheelStraightDrawIsNotDrawn() {
        // A-2-3-4。当てても最弱のストレートにしかならず、外すと 4 ハイになる。
        // 実測でも A だけ残すほうが収支が良い（-0.52 対 -2.79）ので狙わない（#443）
        let hand = [card(14, .spades), card(2, .hearts), card(3, .diamonds),
                    card(4, .clubs), card(9, .hearts)]
        #expect(HandEvaluator.evaluate(hand).rank == .highCard)
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0])
    }

    @Test func aceDoesNotBridgeKingAndTwo() {
        // K-A-2-3 は連続していない。ドロー扱いしてはいけない
        let hand = [card(13, .spades), card(14, .hearts), card(2, .diamonds),
                    card(3, .clubs), card(9, .hearts)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [1])
    }

    // MARK: 何も無いとき

    @Test func highCardWithNothingKeepsAceOnly() {
        let hand = [card(14, .spades), card(10, .hearts), card(7, .diamonds),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0])
    }

    @Test func highCardWithoutAceKeepsHighestCard() {
        let hand = [card(13, .spades), card(10, .hearts), card(7, .diamonds),
                    card(4, .clubs), card(2, .spades)]
        #expect(HandEvaluator.cpuKeepIndices(from: hand) == [0])
    }
}
