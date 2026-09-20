import Testing
import Foundation
@testable import GameBaccarat

/// ルール（点数・引き足し・配当）の固定（#1197）。
///
/// バカラは操作が「賭け先と額を選ぶ」だけで、勝敗は公式表が機械的に決める。
/// 表を1マスでも取り違えると誰も気づけないまま配当が狂うので、**表そのもの**を固定する。
@Suite("バカラのルール")
struct BaccaratRulesTests {

    /// ランクの並びから手を組む。id は判定に使われないので通し番号でよい。
    private func hand(_ ranks: [Int]) -> [BaccaratCard] {
        ranks.enumerated().map { BaccaratCard(id: $0.offset, suit: .spades, rank: $0.element) }
    }

    private func card(_ rank: Int, id: Int = 99) -> BaccaratCard {
        BaccaratCard(id: id, suit: .hearts, rank: rank)
    }

    // MARK: - 点数と合計

    @Test("A=1・2〜9 は数字どおり・10 と絵札は 0")
    func cardPoints() {
        #expect(card(1).points == 1)
        for rank in 2...9 { #expect(card(rank).points == rank) }
        for rank in 10...13 { #expect(card(rank).points == 0, "\(rank) は 0 点") }
    }

    @Test("合計は下 1 桁だけを見る")
    func totalUsesLastDigit() {
        #expect(baccaratTotal(hand([7, 8])) == 5, "15 → 5")
        #expect(baccaratTotal(hand([9, 9])) == 8, "18 → 8")
        #expect(baccaratTotal(hand([10, 13])) == 0, "絵札だけなら 0")
        #expect(baccaratTotal(hand([1, 13])) == 1, "ブラックジャックと違い A+K は 1")
        #expect(baccaratTotal(hand([6, 7, 8])) == 1, "21 → 1（3 枚でも同じ）")
    }

    @Test("ナチュラルは最初の 2 枚で 8 か 9 のときだけ")
    func naturalRequiresTwoCards() {
        #expect(isNatural(hand([5, 3])))
        #expect(isNatural(hand([4, 5])))
        #expect(!isNatural(hand([3, 4])), "7 はナチュラルではない")
        #expect(!isNatural(hand([2, 3, 4])), "3 枚の 9 はナチュラルではない")
    }

    // MARK: - プレイヤーの引き足し

    @Test("プレイヤーは 0〜5 で引き、6〜7 はスタンド")
    func playerDrawTable() {
        for total in 0...5 { #expect(playerDrawsThird(total: total), "\(total) は引く") }
        for total in 6...7 { #expect(!playerDrawsThird(total: total), "\(total) はスタンド") }
    }

    // MARK: - バンカーの引き足し（公式表）

    @Test("プレイヤーが引かなかったら、バンカーも 0〜5 で引く")
    func bankerDrawsWithoutPlayerThird() {
        for total in 0...5 { #expect(bankerDrawsThird(total: total, playerThird: nil), "\(total) は引く") }
        for total in 6...7 { #expect(!bankerDrawsThird(total: total, playerThird: nil), "\(total) はスタンド") }
    }

    /// 公式表を**そのまま**書き下す。`true` の並びが1つでもずれたらここが赤くなる。
    @Test("プレイヤーが引いたときのバンカーの表（0〜9 の 3 枚目すべて）")
    func bankerDrawTable() {
        // 行 = バンカーの 2 枚合計（0...7）、列 = プレイヤーの 3 枚目の点数（0...9）
        let expected: [[Bool]] = [
            //     0     1     2     3     4     5     6     7     8     9
            [true, true, true, true, true, true, true, true, true, true],    // 0
            [true, true, true, true, true, true, true, true, true, true],    // 1
            [true, true, true, true, true, true, true, true, true, true],    // 2
            [true, true, true, true, true, true, true, true, false, true],   // 3（8 以外）
            [false, false, true, true, true, true, true, true, false, false], // 4（2〜7）
            [false, false, false, false, true, true, true, true, false, false], // 5（4〜7）
            [false, false, false, false, false, false, true, true, false, false], // 6（6・7）
            [false, false, false, false, false, false, false, false, false, false], // 7（スタンド）
        ]
        for (total, row) in expected.enumerated() {
            for (third, shouldDraw) in row.enumerated() {
                #expect(bankerDrawsThird(total: total, playerThird: third) == shouldDraw,
                        "バンカー \(total) × プレイヤーの3枚目 \(third) は \(shouldDraw ? "引く" : "スタンド")")
            }
        }
    }

    // MARK: - 通しの引き足し

    @Test("ナチュラルが出たら、どちらの手も 3 枚目を引かない")
    func naturalStopsBothHands() {
        // プレイヤー 9（ナチュラル）× バンカー 2（本来なら引く手）
        let natural = baccaratPlayOut(player: hand([4, 5]), banker: hand([1, 1]),
                                      thirdCards: [card(7), card(7)])
        #expect(natural.player.count == 2)
        #expect(natural.banker.count == 2, "プレイヤーのナチュラルでバンカーも止まる")

        // バンカーだけナチュラル 8 × プレイヤー 0（本来なら引く手）
        let bankerNatural = baccaratPlayOut(player: hand([10, 13]), banker: hand([5, 3]),
                                            thirdCards: [card(7), card(7)])
        #expect(bankerNatural.player.count == 2)
        #expect(bankerNatural.banker.count == 2)
    }

    @Test("プレイヤーだけが引いたら、3 枚目は山の先頭の 1 枚")
    func playerTakesTheFirstThirdCard() {
        // プレイヤー 4（引く）× バンカー 7（スタンド）
        let result = baccaratPlayOut(player: hand([2, 2]), banker: hand([3, 4]),
                                     thirdCards: [card(5, id: 1), card(6, id: 2)])
        #expect(result.player.count == 3)
        #expect(result.player.last?.rank == 5, "先頭の 1 枚を使う（2 枚目は捨て札）")
        #expect(result.banker.count == 2)
    }

    @Test("プレイヤーが引かずバンカーだけ引くときも、使うのは山の先頭の 1 枚")
    func bankerTakesTheFirstThirdCardWhenPlayerStands() {
        // プレイヤー 6（スタンド）× バンカー 3（プレイヤーが引かないので 0〜5 で引く）
        let result = baccaratPlayOut(player: hand([3, 3]), banker: hand([1, 2]),
                                     thirdCards: [card(9, id: 1), card(2, id: 2)])
        #expect(result.player.count == 2)
        #expect(result.banker.count == 3)
        #expect(result.banker.last?.rank == 9, "捨て札を飛ばして 2 枚目を使っていない")
    }

    @Test("プレイヤーの 3 枚目がバンカーの判断に効く（同じ手でも結果が割れる）")
    func bankerDecisionDependsOnPlayerThird() {
        // バンカー 3。プレイヤーの 3 枚目が 8 のときだけスタンドする。
        let stands = baccaratPlayOut(player: hand([2, 2]), banker: hand([1, 2]),
                                     thirdCards: [card(8), card(5)])
        #expect(stands.banker.count == 2, "プレイヤーの 3 枚目が 8 ならバンカーは引かない")

        let draws = baccaratPlayOut(player: hand([2, 2]), banker: hand([1, 2]),
                                    thirdCards: [card(7), card(5)])
        #expect(draws.banker.count == 3, "8 以外なら引く")
    }

    // MARK: - 決着

    @Test("9 に近いほうが勝ち、同じならタイ")
    func outcomeByTotal() {
        #expect(baccaratOutcome(player: hand([4, 5]), banker: hand([4, 4])) == .player)
        #expect(baccaratOutcome(player: hand([4, 4]), banker: hand([4, 5])) == .banker)
        #expect(baccaratOutcome(player: hand([4, 4]), banker: hand([1, 7])) == .tie)
        // 下 1 桁で比べる（15 → 5 は 8 に負ける）
        #expect(baccaratOutcome(player: hand([7, 8]), banker: hand([4, 4])) == .banker)
    }

    // MARK: - 配当

    @Test("プレイヤー的中は 1 倍")
    func playerBetPaysEven() {
        #expect(baccaratChipDelta(bet: .player, outcome: .player, amount: 100) == 100)
    }

    @Test("バンカー的中は手数料 5% を引いた 0.95 倍（端数は切り捨て）")
    func bankerBetPaysWithCommission() {
        #expect(baccaratChipDelta(bet: .banker, outcome: .banker, amount: 100) == 95)
        #expect(baccaratChipDelta(bet: .banker, outcome: .banker, amount: 200) == 190)
        #expect(baccaratChipDelta(bet: .banker, outcome: .banker, amount: 50) == 47, "47.5 は切り捨て")
    }

    @Test("タイ的中は 8 倍")
    func tieBetPaysEight() {
        #expect(baccaratChipDelta(bet: .tie, outcome: .tie, amount: 100) == 800)
    }

    @Test("タイのとき、プレイヤー／バンカーへの賭けは引き分け（賭け金が戻る）")
    func tiePushesSideBets() {
        #expect(baccaratChipDelta(bet: .player, outcome: .tie, amount: 100) == 0)
        #expect(baccaratChipDelta(bet: .banker, outcome: .tie, amount: 100) == 0)
    }

    @Test("外れは賭け金を失う")
    func missedBetsLoseTheStake() {
        #expect(baccaratChipDelta(bet: .player, outcome: .banker, amount: 100) == -100)
        #expect(baccaratChipDelta(bet: .banker, outcome: .player, amount: 100) == -100)
        #expect(baccaratChipDelta(bet: .tie, outcome: .player, amount: 100) == -100)
        #expect(baccaratChipDelta(bet: .tie, outcome: .banker, amount: 100) == -100)
    }

    /// 手数料はバンカー側の期待値を下げるためのもの（ハウスエッジの原資）。
    /// 5% を落とすと、プレイヤーより当たりやすいバンカーが完全な上位互換になる。
    @Test("バンカーの配当はプレイヤーより必ず少ない")
    func bankerPaysLessThanPlayer() {
        for amount in [50, 100, 200, 500] {
            let banker = baccaratChipDelta(bet: .banker, outcome: .banker, amount: amount)
            let player = baccaratChipDelta(bet: .player, outcome: .player, amount: amount)
            #expect(banker < player, "\(amount) 枚: バンカー \(banker) / プレイヤー \(player)")
        }
    }
}
