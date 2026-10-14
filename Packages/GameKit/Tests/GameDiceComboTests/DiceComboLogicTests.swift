import Testing
import CoreEngine
@testable import GameDiceCombo

@Suite("サイコロ役づくり: 役の判定と得点")
struct DiceComboLogicTests {

    @Test("1〜6 の目は、その目の個数 × 目")
    func upperCategories() {
        let dice = [3, 3, 5, 3, 1]
        #expect(DiceComboLogic.score(.ones, dice: dice) == 1)
        #expect(DiceComboLogic.score(.twos, dice: dice) == 0)
        #expect(DiceComboLogic.score(.threes, dice: dice) == 9)
        #expect(DiceComboLogic.score(.fives, dice: dice) == 5)
        #expect(DiceComboLogic.score(.sixes, dice: dice) == 0)
    }

    @Test("チョイスは条件なしで 5 個の合計")
    func choice() {
        #expect(DiceComboLogic.score(.choice, dice: [1, 2, 3, 4, 6]) == 16)
        #expect(DiceComboLogic.score(.choice, dice: [6, 6, 6, 6, 6]) == 30)
    }

    @Test("フォーダイスは同じ目 4 個以上で 5 個の合計、3 個までは 0 点")
    func fourDice() {
        #expect(DiceComboLogic.score(.fourDice, dice: [6, 6, 6, 6, 1]) == 25)
        #expect(DiceComboLogic.score(.fourDice, dice: [2, 2, 2, 2, 2]) == 10)
        #expect(DiceComboLogic.score(.fourDice, dice: [6, 6, 6, 1, 1]) == 0)
    }

    @Test("フルハウスは 3 個 + 2 個（5 個とも同じも含む）で 5 個の合計")
    func fullHouse() {
        #expect(DiceComboLogic.score(.fullHouse, dice: [2, 3, 2, 3, 3]) == 13)
        #expect(DiceComboLogic.score(.fullHouse, dice: [4, 4, 4, 4, 4]) == 20)
        #expect(DiceComboLogic.score(.fullHouse, dice: [4, 4, 4, 4, 1]) == 0)
        #expect(DiceComboLogic.score(.fullHouse, dice: [4, 4, 1, 1, 2]) == 0)
    }

    @Test("S ストレートは 4 つ続きで 15 点。並び順と残り 1 個は問わない")
    func smallStraight() {
        #expect(DiceComboLogic.score(.smallStraight, dice: [4, 1, 3, 2, 6]) == 15)
        #expect(DiceComboLogic.score(.smallStraight, dice: [3, 4, 5, 6, 6]) == 15)
        #expect(DiceComboLogic.score(.smallStraight, dice: [1, 2, 3, 4, 5]) == 15, "5 つ続きも 4 つ続きを含む")
        #expect(DiceComboLogic.score(.smallStraight, dice: [1, 2, 3, 5, 6]) == 0)
    }

    @Test("B ストレートは 5 つ続き（1〜5 か 2〜6）で 30 点")
    func bigStraight() {
        #expect(DiceComboLogic.score(.bigStraight, dice: [5, 4, 3, 2, 1]) == 30)
        #expect(DiceComboLogic.score(.bigStraight, dice: [2, 3, 4, 5, 6]) == 30)
        #expect(DiceComboLogic.score(.bigStraight, dice: [1, 2, 3, 4, 6]) == 0)
        #expect(DiceComboLogic.score(.bigStraight, dice: [1, 2, 3, 4, 4]) == 0)
    }

    @Test("ファイブダイスは 5 個とも同じ目で 50 点")
    func fiveDice() {
        #expect(DiceComboLogic.score(.fiveDice, dice: [1, 1, 1, 1, 1]) == 50)
        #expect(DiceComboLogic.score(.fiveDice, dice: [1, 1, 1, 1, 2]) == 0)
    }

    @Test("壊れた出目（個数違い・範囲外）はどの役も 0 点")
    func invalidDice() {
        for category in DiceComboCategory.allCases {
            #expect(DiceComboLogic.score(category, dice: [1, 2, 3, 4]) == 0)
            #expect(DiceComboLogic.score(category, dice: [0, 7, 3, 3, 3]) == 0)
        }
    }

    @Test("役は 12 種類で、上段は 1〜6 の目の 6 種類")
    func twelveCategories() {
        #expect(DiceComboCategory.allCases.count == 12)
        #expect(DiceComboCategory.upper.map(\.face) == [1, 2, 3, 4, 5, 6])
        // 中断データの鍵は英字のまま変えない。
        #expect(DiceComboCategory.allCases.map(\.rawValue) == [
            "ones", "twos", "threes", "fours", "fives", "sixes",
            "choice", "fourDice", "fullHouse", "smallStraight", "bigStraight", "fiveDice",
        ])
    }

    @Test("上段の小計 63 点以上でボーナス 35 点、未満は 0 点")
    func upperBonus() {
        // 各目 3 個ずつで小計ちょうど 63。
        var scores: [DiceComboCategory: Int] = [.ones: 3, .twos: 6, .threes: 9, .fours: 12, .fives: 15, .sixes: 18]
        #expect(DiceComboLogic.upperSubtotal(scores) == 63)
        #expect(DiceComboLogic.bonus(scores) == 35)
        #expect(DiceComboLogic.total(scores) == 98)
        scores[.ones] = 2
        #expect(DiceComboLogic.bonus(scores) == 0)
        // 下段の点は小計に入らない。
        scores[.choice] = 30
        #expect(DiceComboLogic.upperSubtotal(scores) == 62)
        #expect(DiceComboLogic.total(scores) == 62 + 30)
    }

    @Test("各役の最高点を全通りの出目から求めると、合計の最高は 325 点")
    func bestPossibleTotal() {
        let everyDice = DiceComboLogic.allDice
        #expect(everyDice.count == 7776)
        #expect(Set(everyDice).count == 7776, "全通りに重複が無い")
        var best: [DiceComboCategory: Int] = [:]
        for category in DiceComboCategory.allCases {
            best[category] = everyDice.map { DiceComboLogic.score(category, dice: $0) }.max()
        }
        #expect(best[.fiveDice] == 50)
        #expect(best[.bigStraight] == 30)
        #expect(best[.smallStraight] == 15)
        #expect(best[.fullHouse] == 30)
        #expect(DiceComboLogic.total(best) == DiceComboLogic.maxTotal)
        #expect(DiceComboLogic.isComplete(best))
    }

    @Test("中断データの検証は、その役で取りうる点だけを通す")
    func possibleScores() {
        #expect(DiceComboLogic.isPossibleScore(12, for: .threes))
        #expect(!DiceComboLogic.isPossibleScore(13, for: .threes))
        #expect(!DiceComboLogic.isPossibleScore(18, for: .threes))
        #expect(DiceComboLogic.isPossibleScore(0, for: .fiveDice))
        #expect(DiceComboLogic.isPossibleScore(50, for: .fiveDice))
        #expect(!DiceComboLogic.isPossibleScore(49, for: .fiveDice))
        #expect(!DiceComboLogic.isPossibleScore(-1, for: .choice))
        #expect(!DiceComboLogic.isPossibleScore(4, for: .choice), "チョイスは 5 点未満にならない")
    }

    @Test("振り直しはキープした目を残し、残りは 1〜6 の目になる")
    func rollKeepsHeldDice() {
        var generator = SplitMix64(seed: 42)
        let before = [6, 6, 1, 6, 2]
        for _ in 0..<200 {
            let after = DiceComboLogic.roll(before, held: [true, true, false, true, false], using: &generator)
            #expect(after.count == 5)
            #expect(after[0] == 6 && after[1] == 6 && after[3] == 6)
            #expect(DiceComboLogic.isValidDice(after))
        }
    }

    @Test("最初の 1 投（出目なし・キープなし）でも 5 個そろう。目は 6 種類とも出る")
    func firstRoll() {
        var generator = SplitMix64(seed: 7)
        var seen: Set<Int> = []
        for _ in 0..<100 {
            let dice = DiceComboLogic.roll([], held: [], using: &generator)
            #expect(DiceComboLogic.isValidDice(dice))
            seen.formUnion(dice)
        }
        #expect(seen == [1, 2, 3, 4, 5, 6])
    }
}
