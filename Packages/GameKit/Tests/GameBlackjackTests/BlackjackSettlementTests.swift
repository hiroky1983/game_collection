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

    private let bet = 100

    private func settle(player: [Int], dealer: [Int]) -> (outcome: BlackjackOutcome, chipDelta: Int) {
        blackjackSettlement(player: hand(player), dealer: hand(dealer), bet: bet)
    }

    // MARK: - 受け入れ条件1: ディーラーのみナチュラル

    @Test("ディーラーのみナチュラル × プレイヤーの3枚21 はディーラーの勝ち（#413 の欠陥）")
    func dealerNaturalBeatsThreeCardTwentyOne() {
        let result = settle(player: [7, 7, 7], dealer: [1, 13])
        #expect(result.outcome == .lose)
        #expect(result.chipDelta == -bet)
    }

    @Test("ディーラーのみナチュラル × プレイヤーの4枚21 もディーラーの勝ち")
    func dealerNaturalBeatsFourCardTwentyOne() {
        let result = settle(player: [5, 6, 4, 6], dealer: [11, 1])
        #expect(result.outcome == .lose)
        #expect(result.chipDelta == -bet)
    }

    @Test("ディーラーのみナチュラル × プレイヤー20 は従来どおり敗北")
    func dealerNaturalBeatsTwenty() {
        let result = settle(player: [10, 10], dealer: [1, 12])
        #expect(result.outcome == .lose)
        #expect(result.chipDelta == -bet)
    }

    // MARK: - 受け入れ条件2: 既存の正しい挙動が変わらない

    @Test("両者ナチュラルはプッシュ")
    func bothNaturalIsPush() {
        let result = settle(player: [1, 10], dealer: [13, 1])
        #expect(result.outcome == .push)
        #expect(result.chipDelta == 0)
    }

    @Test("プレイヤーのみナチュラルは 1.5 倍払い")
    func playerNaturalPaysOneAndAHalf() {
        let result = settle(player: [1, 11], dealer: [7, 7, 7])
        #expect(result.outcome == .playerBlackjack)
        #expect(result.chipDelta == 150)
    }

    @Test("ディーラーがバストしたらプレイヤーの勝ち")
    func dealerBustIsWin() {
        let result = settle(player: [5, 6], dealer: [10, 9, 5])
        #expect(result.outcome == .win)
        #expect(result.chipDelta == bet)
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
        #expect(result.chipDelta == -bet)
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

    // MARK: - モデル経由（判定表が実際の対局結果に効いていること）

    @Test("モデルの対局でも、ディーラーのナチュラルは3枚以上の21に勝つ")
    @MainActor
    func modelAppliesDealerNaturalRule() {
        // 決定的な種を順に試し、「ディーラーがナチュラル・プレイヤーは非ナチュラルで
        // ヒットして 3 枚以上の 21 に到達する」局面を最初に作れた種で検証する。
        for seed in UInt64(1)...2000 {
            let model = BlackjackModel(seed: seed)
            model.placeBet(100)
            guard model.phase == .playerTurn,
                  isBlackjack(model.dealerHand) else { continue }

            while model.playerValue < 21 && model.phase == .playerTurn {
                model.hit()
            }
            guard model.phase == .playerTurn,
                  model.playerValue == 21,
                  model.playerHand.count >= 3 else { continue }

            model.stand()
            #expect(model.outcome == .lose)
            #expect(model.chips == 900)
            return
        }
        Issue.record("検証対象の局面を作れる種が 2000 件の中に無かった")
    }
}
