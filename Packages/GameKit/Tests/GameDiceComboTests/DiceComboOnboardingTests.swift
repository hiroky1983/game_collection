import Testing
import Core
@testable import GameDiceCombo

/// 図で見る「はじめての遊び方」（#2826）の図と文言が、実装のルールのとおりになっていること。
@MainActor
@Suite("サイコロ役づくり: はじめての遊び方")
struct DiceComboOnboardingTests {
    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(DiceComboOnboarding.guide.isWellFormed)
        #expect(DiceComboOnboarding.guide.gameID == DiceComboModel.gameID)
        #expect(DiceComboOnboarding.guide.gameID == DiceComboModule().id)
    }

    @Test("振る: サイコロは 5 個、1 ターンに 3 回まで。1 回も振る前はキープできない")
    func rollUpToThreeTimes() {
        #expect(DiceComboLogic.diceCount == 5)
        #expect(DiceComboLogic.maxRolls == 3)
        #expect(DiceComboHowToFigures.rolled.count == DiceComboLogic.diceCount)
        let model = DiceComboModel(seed: 2826)
        #expect(!model.canHold)
        for _ in 0..<3 {
            #expect(model.canRoll)
            model.roll()
            #expect(model.dice.count == DiceComboLogic.diceCount)
        }
        #expect(!model.canRoll, "4 回目は振れない")
        #expect(!model.canHold, "振り切ったあとはキープを変えられない")
    }

    @Test("キープの図: キープした位置の目は振り直しても同じ（図の振り直し後の目もそうなっている）")
    func keptDiceStay() {
        let rolled = DiceComboHowToFigures.rolled
        let rerolled = DiceComboHowToFigures.rerolled
        let kept = DiceComboHowToFigures.keptIndices
        #expect(DiceComboLogic.isValidDice(rolled) && DiceComboLogic.isValidDice(rerolled))
        for index in kept { #expect(rerolled[index] == rolled[index], "図の \(index) 番目") }
        let held = (0..<DiceComboLogic.diceCount).map { kept.contains($0) }
        for seed in UInt64(0)..<50 {
            var generator = SplitMix64(seed: seed)
            let result = DiceComboLogic.roll(rolled, held: held, using: &generator)
            for index in kept { #expect(result[index] == rolled[index]) }
        }
        // 画面の操作でも同じ: 振る → タップでキープ → 振り直す。
        let model = DiceComboModel(seed: 7)
        model.roll()
        let first = model.dice
        for index in kept { model.toggleHold(index) }
        model.roll()
        for index in kept { #expect(model.dice[index] == first[index]) }
    }

    @Test("記入の図: フルハウスは 5 個の合計、条件に合わない S ストレートは 0 点。0 点でも入れられてターンが終わる")
    func chooseScoresOrZero() {
        let dice = DiceComboHowToFigures.fullHouseDice
        #expect(DiceComboLogic.score(.fullHouse, dice: dice) == dice.reduce(0, +))
        #expect(DiceComboLogic.score(.fullHouse, dice: dice) == 24)
        #expect(DiceComboLogic.score(.smallStraight, dice: dice) == 0)

        let model = DiceComboModel(seed: 2826)
        model.roll()
        // 5 個とも同じ目でない限り、ファイブダイスの条件には合わない。
        let category: DiceComboCategory = Set(model.dice).count == 1 ? .smallStraight : .fiveDice
        let expected = DiceComboLogic.score(category, dice: model.dice)
        #expect(expected == 0)
        #expect(model.canChoose(category))
        model.choose(category)
        #expect(model.scores[category] == 0, "0 点で記入される")
        #expect(model.rollsUsed == 0 && model.dice.isEmpty, "ターンが終わって次の振りから")
        #expect(model.turn == 2)
    }

    @Test("役の例の図: B ストレート 30 点・ファイブダイス 50 点")
    func comboExamples() {
        #expect(DiceComboLogic.score(.bigStraight, dice: DiceComboHowToFigures.bigStraightDice) == DiceComboLogic.bigStraightScore)
        #expect(DiceComboLogic.bigStraightScore == 30)
        #expect(DiceComboLogic.score(.fiveDice, dice: DiceComboHowToFigures.fiveDiceDice) == DiceComboLogic.fiveDiceScore)
        #expect(DiceComboLogic.fiveDiceScore == 50)
        #expect(DiceComboCategory.allCases.count == 12)
    }

    @Test("ボーナス: 1〜6 の目はその目の合計。小計 63 点以上で +35 点（62 点なら付かない）")
    func upperBonus() {
        #expect(DiceComboLogic.score(.sixes, dice: DiceComboHowToFigures.rolled) == 12, "6 が 2 個で 12 点")
        #expect(DiceComboLogic.score(.threes, dice: DiceComboHowToFigures.rolled) == 3)
        #expect(DiceComboLogic.upperBonusThreshold == 63)
        #expect(DiceComboLogic.upperBonus == 35)
        let scores = DiceComboOnboarding.finishedScores
        #expect(DiceComboLogic.upperSubtotal(scores) == 63)
        #expect(DiceComboLogic.bonus(scores) == 35)
        var short = scores
        short[.ones] = 2
        #expect(DiceComboLogic.bonus(short) == 0)
    }

    @Test("終わりの図: 12 役ぜんぶ埋まった得点表は取りうる点だけで、合計はボーナス込み。モデルも 12 役目で決着する")
    func finishAfterTwelve() {
        let scores = DiceComboOnboarding.finishedScores
        #expect(DiceComboLogic.isComplete(scores))
        for (category, value) in scores {
            #expect(DiceComboLogic.isPossibleScore(value, for: category), "\(category) の \(value) 点は取れない")
        }
        #expect(DiceComboLogic.total(scores) == scores.values.reduce(0, +) + 35)

        let model = DiceComboModel(seed: 2826)
        for (index, category) in DiceComboCategory.allCases.enumerated() {
            #expect(!model.isFinished, "\(index) 役目の前に終わった")
            model.roll()
            model.choose(category)
        }
        #expect(model.isFinished)
        #expect(model.total == DiceComboLogic.total(model.scores))
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        let figureTexts = ["12 役を埋めたら終わり", "ターン", "合計", "振る", "3回まで", "キープした目は残る",
                           "フルハウス", "3個と2個で5個の合計", "Sストレート", "4つ続きで15点",
                           "Bストレート", "ファイブダイス", "1〜6の目の小計"]
        for text in DiceComboOnboarding.guide.texts + figureTexts {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
