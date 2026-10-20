import Testing
import Foundation
@testable import GameBlackjack

/// 勝敗判定表の回帰テスト（#413）。
///
/// 監査で見つかった欠陥は「**ディーラーのみナチュラル（2枚21）× プレイヤーの3枚以上21** が
/// プッシュになる」というもので、判定表にディーラー側のナチュラルが無かったのが原因。
/// 直したのは1分岐だけだが、他の組み合わせを巻き添えで壊していないことまで固定する。
@Suite("ブラックジャックの勝敗判定")
struct BlackjackSettlementTests {

    /// 手札を組み立てる。id は判定に使われないので通し番号でよい。
    private func hand(_ ranks: [Int]) -> [BlackjackCard] {
        ranks.enumerated().map { BlackjackCard(id: $0.offset, suit: .spades, rank: $0.element) }
    }

    private func settle(player: [Int], dealer: [Int]) -> (outcome: BlackjackOutcome, points: Int) {
        let outcome = blackjackSettlement(player: hand(player), dealer: hand(dealer))
        return (outcome, outcome.points)
    }

    // MARK: - 受け入れ条件1: ディーラーのみナチュラル

    @Test("ディーラーのみナチュラル × プレイヤーの3枚21 はディーラーの勝ち（#413 の欠陥）")
    func dealerNaturalBeatsThreeCardTwentyOne() {
        let result = settle(player: [7, 7, 7], dealer: [1, 13])
        #expect(result.outcome == .lose)
        #expect(result.points == 0)
    }

    @Test("ディーラーのみナチュラル × プレイヤーの4枚21 もディーラーの勝ち")
    func dealerNaturalBeatsFourCardTwentyOne() {
        let result = settle(player: [5, 6, 4, 6], dealer: [11, 1])
        #expect(result.outcome == .lose)
        #expect(result.points == 0)
    }

    @Test("ディーラーのみナチュラル × プレイヤー20 は従来どおり敗北")
    func dealerNaturalBeatsTwenty() {
        let result = settle(player: [10, 10], dealer: [1, 12])
        #expect(result.outcome == .lose)
        #expect(result.points == 0)
    }

    // MARK: - 受け入れ条件2: 既存の正しい挙動が変わらない

    @Test("両者ナチュラルはプッシュ")
    func bothNaturalIsPush() {
        let result = settle(player: [1, 10], dealer: [13, 1])
        #expect(result.outcome == .push)
        #expect(result.points == 0)
    }

    @Test("プレイヤーのみナチュラルは 2 点")
    func playerNaturalScoresTwo() {
        let result = settle(player: [1, 11], dealer: [7, 7, 7])
        #expect(result.outcome == .playerBlackjack)
        #expect(result.points == 2)
    }

    @Test("ディーラーがバストしたらプレイヤーの勝ち")
    func dealerBustIsWin() {
        let result = settle(player: [5, 6], dealer: [10, 9, 5])
        #expect(result.outcome == .win)
        #expect(result.points == 1)
    }

    @Test("バストしていない同士は数字の大きい方が勝つ")
    func higherValueWins() {
        #expect(settle(player: [10, 9], dealer: [10, 8]).outcome == .win)
        #expect(settle(player: [10, 7], dealer: [10, 8]).outcome == .lose)
    }

    @Test("ナチュラルが絡まない同値はプッシュ")
    func equalValueIsPush() {
        #expect(settle(player: [10, 10], dealer: [11, 12]).outcome == .push)
        // 3枚21 同士。どちらもナチュラルではないのでプッシュのまま
        #expect(settle(player: [7, 7, 7], dealer: [5, 6, 10]).outcome == .push)
    }

    @Test("ディーラーだけが3枚21ならプレイヤーの20は負け")
    func dealerThreeCardTwentyOneBeatsTwenty() {
        let result = settle(player: [10, 10], dealer: [7, 7, 7])
        #expect(result.outcome == .lose)
        #expect(result.points == 0)
    }

    @Test("点は 勝ち 1・ブラックジャック 2・それ以外 0（#2552）")
    func pointsPerOutcome() {
        #expect(BlackjackOutcome.win.points == 1)
        #expect(BlackjackOutcome.playerBlackjack.points == 2)
        #expect(BlackjackOutcome.push.points == 0)
        #expect(BlackjackOutcome.lose.points == 0)
        #expect(BlackjackOutcome.bust.points == 0)
    }

    @Test("スプリットで作った 2 枚 21 はナチュラルにならず、ふつうの勝ち（1 点）")
    func splitTwentyOneIsNotNatural() {
        let outcome = blackjackSettlement(player: hand([1, 13]), dealer: hand([10, 7]), allowsPlayerNatural: false)
        #expect(outcome == .win)
        #expect(outcome.points == 1)
    }

    // MARK: - 判定の土台（A の柔軟評価とナチュラルの定義）

    @Test("A はバストするときだけ 1 に下がる")
    func aceSoftensOnlyWhenBusting() {
        #expect(handValue(hand([1, 10])) == 21)
        #expect(handValue(hand([1, 1])) == 12)
        #expect(handValue(hand([1, 10, 10])) == 21)
        #expect(handValue(hand([1, 1, 9])) == 21)
    }

    @Test("ナチュラルは2枚のときだけ成立する")
    func naturalRequiresExactlyTwoCards() {
        #expect(isBlackjack(hand([1, 13])))
        #expect(!isBlackjack(hand([7, 7, 7])))
        #expect(!isBlackjack(hand([10, 10])))
    }

    // MARK: - モデル経由

    // 「ディーラーのナチュラル × プレイヤーの3枚以上の21」をモデル経由で確かめるテストは置かない。
    // ディーラーがナチュラルの局は配った時点で精算されプレイヤーの手番に入らなくなった（#1377）ため、
    // 3枚以上の21に到達する局面が作れない。判定表そのものは上の純関数のテストが担保し、
    // 配札時に決着することは `BlackjackDealerNaturalTests` が担保する。
}
