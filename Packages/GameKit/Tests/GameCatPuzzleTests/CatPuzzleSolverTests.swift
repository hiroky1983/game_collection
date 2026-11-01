import Testing
import GameKitTestSupport
import Foundation
import CoreEngine
@testable import GameCatPuzzle

/// 解き手（#3048）。推理の段で解き切れたら答えと一致し、段の上限を守ること。
@Suite("おじさんちのねこさがしの解き手")
struct CatPuzzleSolverTests {

    /// 6×6 の問題を種から作る。
    private func easyPuzzle(seed: UInt64) -> CatPuzzle {
        var generator = SplitMix64(seed: seed)
        return CatPuzzleLogic.generate(size: .easy, using: &generator)
    }

    @Test("解き切れたときの猫の並びは答えと同じ（6×6）", arguments: 0..<30)
    func solvedCatsMatchSolution(seed: Int) {
        let puzzle = easyPuzzle(seed: UInt64(seed))
        let difficulty = CatPuzzleSolver.rate(puzzle)
        if difficulty.solved {
            #expect(CatPuzzleSolver.solve(puzzle) == puzzle.solutionCells)
        } else {
            #expect(CatPuzzleSolver.solve(puzzle) == nil)
        }
    }

    @Test("段の上限より上の段は使わない", arguments: 0..<30)
    func respectsMaxTier(seed: Int) {
        let puzzle = easyPuzzle(seed: UInt64(seed))
        for maxTier in 2...5 {
            let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: maxTier)
            #expect(difficulty.counts[maxTier...].allSatisfy { $0 == 0 })
            if difficulty.solved { #expect(difficulty.tier <= maxTier) }
        }
    }

    @Test("段 4 までで解けない問題は、当て推量（段 5）を使えば進む")
    func trialNeededPuzzleIsTierFive() throws {
        // 生成した 6×6 の多くは段 5 が要る（この割合の高さがステージで弾く理由）。最初に見つかった 1 問で確かめる。
        let puzzle = try #require((0..<50).lazy.map { easyPuzzle(seed: UInt64($0)) }
            .first { !CatPuzzleSolver.rate($0, maxTier: 4).solved })
        let difficulty = CatPuzzleSolver.rate(puzzle)
        #expect(difficulty.tier == 5)
        #expect(difficulty.counts[4] > 0)
    }

    @Test("段 1・2 だけで解ける形: 部屋が 1 マスずつ確定していく")
    func basicTiersSolveSmallPuzzle() {
        // 4×4・答えは行の順に列 1・3・0・2（`CatPuzzleLogicTests` と同じ盤）。
        let puzzle = CatPuzzle(
            side: 4,
            rooms: [
                0, 0, 1, 1,
                0, 0, 1, 1,
                2, 2, 3, 1,
                2, 2, 3, 3,
            ],
            solution: [1, 3, 0, 2]
        )
        #expect(CatPuzzleSolver.solve(puzzle) == puzzle.solutionCells)
    }

    @Test("点数は段ごとの回数 × 重みの合計")
    func scoreIsWeightedSum() {
        let difficulty = CatPuzzleDifficulty(tier: 4, counts: [6, 5, 2, 1, 0], solved: true)
        #expect(difficulty.score == 6 * 1 + 5 * 1 + 2 * 4 + 1 * 10)
    }

    @Test("組み合わせは辞書順で全部")
    func combinations() {
        #expect(CatPuzzleSolver.combinations([1, 2, 3, 4], 2) == [[1, 2], [1, 3], [1, 4], [2, 3], [2, 4], [3, 4]])
        #expect(CatPuzzleSolver.combinations([1, 2], 3).isEmpty)
    }
}

/// ステージモードの n 面目（#3048）。番号から盤の大きさ・段が決まり、同じ番号なら同じ問題になること。
@Suite("おじさんちのねこさがしのステージ")
struct CatPuzzleStageTests {

    @Test("10 面ごとに盤が 1 回り広がり、31 面目から 9×9、61 面目から 12×12")
    func sizeByStage() {
        #expect(CatPuzzleStage(1).size == .easy)
        #expect(CatPuzzleStage(10).size == .easy)
        #expect(CatPuzzleStage(11).size == .normal)
        #expect(CatPuzzleStage(21).size == .hard)
        #expect(CatPuzzleStage(30).size == .hard)
        #expect(CatPuzzleStage(31).size == .expert)
        #expect(CatPuzzleStage(40).size == .expert)
        #expect(CatPuzzleStage(41).size == .size10)
        #expect(CatPuzzleStage(50).size == .size10)
        #expect(CatPuzzleStage(51).size == .size11)
        #expect(CatPuzzleStage(60).size == .size11)
        #expect(CatPuzzleStage(61).size == .size12)
        #expect(CatPuzzleStage(500).size == .size12)
        #expect([6, 7, 8, 9, 10, 11, 12] == [1, 11, 21, 31, 41, 51, 61].map { CatPuzzleStage($0).size.side })
        #expect(CatPuzzleStage(0).number == 1, "0 以下は 1 面目に丸める")
    }

    @Test("各 10 面の前半は段 3 まで、後半は段 4 が要る問題（9×9 は段 4 までのどれでも）")
    func tiersByStage() {
        #expect(CatPuzzleStage(1).tiers == 1...3)
        #expect(CatPuzzleStage(5).tiers == 1...3)
        #expect(CatPuzzleStage(6).tiers == 4...4)
        #expect(CatPuzzleStage(10).tiers == 4...4)
        #expect(CatPuzzleStage(15).tiers == 1...3)
        #expect(CatPuzzleStage(26).tiers == 4...4)
        #expect(CatPuzzleStage(31).tiers == 1...4)
        #expect(CatPuzzleStage(41).tiers == 1...3)
        #expect(CatPuzzleStage(46).tiers == 4...4)
        #expect(CatPuzzleStage(65).tiers == 1...4, "12×12 の前半も段 4 までのどれでも")
        #expect(CatPuzzleStage(66).tiers == 4...4)
        #expect(CatPuzzleStage(70).tiers == 4...4)
    }

    @Test("部屋の入り組み: 9×9 までは従来どおり 0、10×10 以上は前半 1・後半 2")
    func windingByStage() {
        #expect([1, 6, 11, 16, 21, 26, 31, 36, 40].allSatisfy { CatPuzzleStage($0).winding == 0 })
        #expect(CatPuzzleStage(41).winding == 1)
        #expect(CatPuzzleStage(45).winding == 1)
        #expect(CatPuzzleStage(46).winding == 2)
        #expect(CatPuzzleStage(61).winding == 1)
        #expect(CatPuzzleStage(70).winding == 2)
        #expect(CatPuzzleLogic.windingDenominator(0) == 4, "従来の確率は変えない")
        #expect(CatPuzzleLogic.windingDenominator(1) > CatPuzzleLogic.windingDenominator(2))
    }

    @Test("部屋の数は盤の大きさ（辺のマス数）と同じで、盤が広がるほど増える")
    func roomCountGrowsWithBoard() {
        let rooms = [1, 31, 41, 51, 61].map { CatPuzzleStage($0).makePuzzle() }
        #expect(rooms.map { Set($0.rooms).count } == rooms.map(\.side))
        #expect(rooms.map(\.side) == [6, 9, 10, 11, 12])
    }

    @Test("12×12 でも iPhone SE（幅 375pt・左右の余白 16pt）でマスが 26pt 以上")
    @MainActor
    func cellSideOnIPhoneSE() {
        let boardSide: CGFloat = 375 - 16 * 2
        #expect(CatPuzzleView.cellSide(boardSide: boardSide, side: 12) >= 26)
        #expect(CatPuzzleView.cellSide(boardSide: boardSide, side: 6) > CatPuzzleView.cellSide(boardSide: boardSide, side: 12))
    }

    @Test("スライドと決める動きは、小さいマスでも 14pt を下回らない")
    @MainActor
    func slideDistanceHasFloor() {
        #expect(CatPuzzleModel.slideDistance(cellSide: 27) == 14)
        #expect(abs(CatPuzzleModel.slideDistance(cellSide: 36) - 36 * CGFloat(CatPuzzleModel.slideThreshold)) < 0.001)
        #expect(abs(CatPuzzleModel.slideDistance(cellSide: 60) - 60 * CGFloat(CatPuzzleModel.slideThreshold)) < 0.001)
    }

    @Test("10×10 以上は自由に遊ぶの難易度に出ない（ステージ専用）")
    func largeSizesAreStageOnly() {
        #expect(CatPuzzleSize.allCases == [.easy, .normal, .hard, .expert])
        #expect(CatPuzzleSize(rawValue: "size12") == .size12)
    }

    @Test("種は番号ごとに違い、同じ番号なら同じ")
    func seeds() {
        let seeds = (1...200).map { CatPuzzleStage($0).seed }
        #expect(Set(seeds).count == seeds.count)
        #expect(CatPuzzleStage(7).seed == CatPuzzleStage(7).seed)
    }

    /// CI では各盤の前半・後半の端と 8×8・9×9 の代表（6×6・7×7 の全面は点数のテストが作る）、夜間は 50 面まで全部。
    static let checkedStages: [Int] = NightlyScale.value(ci: [1, 5, 6, 10, 11, 15, 16, 20, 21, 26, 31, 41, 46, 51, 56, 61, 66],
                                                         nightly: Array(1...50))

    @Test("どの面も解が 1 つで、段 5 が要らず、段が決まりの範囲に入る", arguments: checkedStages)
    func stagePuzzleIsFair(number: Int) {
        let stage = CatPuzzleStage(number)
        let puzzle = stage.makePuzzle()
        #expect(puzzle.side == stage.size.side)
        #expect(CatPuzzleLogic.isWellFormed(puzzle))
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 2) == 1)
        let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: 4)
        #expect(difficulty.solved, "段 4 までで解ける（当て推量は要らない）")
        #expect(stage.tiers.contains(difficulty.tier))
        #expect(CatPuzzleSolver.solve(puzzle, maxTier: 4) == puzzle.solutionCells)
    }

    @Test("同じ番号の面は何度作っても同じ問題（誰が遊んでも同じ）")
    func sameNumberSamePuzzle() {
        for number in [1, 6, 13] {
            #expect(CatPuzzleStage(number).makePuzzle() == CatPuzzleStage(number).makePuzzle())
        }
        #expect(CatPuzzleStage(1).makePuzzle() != CatPuzzleStage(2).makePuzzle())
    }

    @Test("難しさの点数はおおむね上がる: 各盤の後半（段 4）は前半（段 3 まで）より平均が高く、盤が広がると上がる")
    func scoresRoughlyIncrease() {
        func meanScore(_ range: ClosedRange<Int>) -> Double {
            let scores = range.map { CatPuzzleSolver.rate(CatPuzzleStage($0).makePuzzle(), maxTier: 4).score }
            return Double(scores.reduce(0, +)) / Double(scores.count)
        }
        let easyFirst = meanScore(1...5), easySecond = meanScore(6...10)
        let normalFirst = meanScore(11...15), normalSecond = meanScore(16...20)
        #expect(easyFirst < easySecond)
        #expect(normalFirst < normalSecond)
        #expect(easySecond < normalSecond)
    }
}
