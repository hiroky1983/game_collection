import Testing
import Core
@testable import GameCatPuzzle

/// 図で見る「はじめての遊び方」（#2826）の図が、実装のルールのとおりになっていること。
@MainActor
@Suite("おじさんちのねこさがし: はじめての遊び方")
struct CatPuzzleOnboardingTests {
    private var sample: CatPuzzle { CatPuzzleHowToFigures.sample }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(CatPuzzleOnboarding.guide.isWellFormed)
        #expect(CatPuzzleOnboarding.guide.gameID == CatPuzzleModel.gameID)
        #expect(CatPuzzleOnboarding.guide.gameID == CatPuzzleModule().id)
    }

    @Test("目的・1 匹ずつ・クリアの図: 猫は部屋の数だけいて、部屋・行・列に 1 匹ずつ。答えは 1 通り")
    func goalAndOnePerRoom() {
        let cats = sample.solutionCells
        #expect(cats.count == sample.side)
        #expect(Set(sample.rooms).count == sample.side, "部屋の数 = 猫の数")
        #expect(CatPuzzleLogic.isWellFormed(sample))
        #expect(CatPuzzleLogic.isSolved(puzzle: sample, cats: cats))
        #expect(Set(cats.map { $0 / sample.side }).count == sample.side)
        #expect(Set(cats.map { $0 % sample.side }).count == sample.side)
        #expect(Set(cats.map { sample.rooms[$0] }).count == sample.side)
        #expect(CatPuzzleLogic.countSolutions(side: sample.side, rooms: sample.rooms, limit: 2) == 1)
    }

    @Test("隣り合わない図: ななめに隣り合った 2 匹は決まり違反（隣り合い）")
    func notAdjacent() {
        let cats = CatPuzzleHowToFigures.adjacentCats
        let violations = CatPuzzleLogic.violations(puzzle: sample, cats: cats)
        #expect(violations.kinds == [.adjacent])
        #expect(cats[0] / sample.side != cats[1] / sample.side && cats[0] % sample.side != cats[1] % sample.side, "ななめ")
        // 答えの猫どうしは、ななめも含めて隣り合っていない。
        let solution = sample.solutionCells
        for a in solution {
            for b in solution where a < b {
                #expect(!CatPuzzleLogic.isAdjacent(a, b, side: sample.side))
            }
        }
    }

    @Test("操作の図: タップで × を付け外し（ミスにならない）、ダブルタップで猫を見つける")
    func tapControls() {
        let cell = CatPuzzleHowToFigures.tapCell
        #expect(sample.solutionCells.contains(cell))
        let model = CatPuzzleModel(puzzle: sample, size: .easy)
        model.toggleCross(cell: cell)
        #expect(model.marks[cell] == .cross)
        model.toggleCross(cell: cell)
        #expect(model.marks[cell] == .empty)
        #expect(model.mistakes == 0)
        model.findCat(cell: cell)
        #expect(model.marks[cell] == .cat)
    }

    @Test("ミスの図: 答えでないマスをダブルタップすると赤い × が付き、ミスが 1 つ増える。赤い × は消せない")
    func mistakeFigure() {
        let cell = CatPuzzleOnboarding.mistakeCell
        #expect(!sample.solutionCells.contains(cell))
        #expect(sample.solutionCells.contains(CatPuzzleOnboarding.foundCat))
        let model = CatPuzzleModel(puzzle: sample, size: .easy)
        model.findCat(cell: CatPuzzleOnboarding.foundCat)
        model.findCat(cell: cell)
        #expect(model.mistakes == 1)
        #expect(model.wrongCrosses == [cell])
        #expect(model.marks[cell] == .cross)
        #expect(!model.toggleCross(cell: cell))
        model.reset()
        #expect(model.marks[cell] == .cross, "やり直しても赤い × は残る")
    }

    @Test("勝ち負け: 全部見つけたらクリア。ミス 3 回で負け、その前に 1 回だけ広告で続けられる")
    func winAndLose() {
        #expect(CatPuzzleModel.maxMistakes == 3)
        let wrong = (0..<sample.cellCount).filter { !sample.solutionCells.contains($0) }

        let winner = CatPuzzleModel(puzzle: sample, size: .easy)
        for cell in sample.solutionCells { winner.findCat(cell: cell) }
        #expect(winner.isSolved)

        let model = CatPuzzleModel(puzzle: sample, size: .easy)
        for cell in wrong.prefix(3) { model.findCat(cell: cell) }
        #expect(model.isOfferingContinue)
        #expect(model.continueAfterAd())
        #expect(model.mistakes == CatPuzzleModel.maxMistakes - 1)
        model.findCat(cell: wrong[3])
        #expect(model.isFailed, "コンティニューは 1 回だけ")
        #expect(!model.isOfferingContinue)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in CatPuzzleOnboarding.guide.texts + ["はじめ", "おわり", "全部見つけたらクリア", "ミス %1$lld/%2$lld"] {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
