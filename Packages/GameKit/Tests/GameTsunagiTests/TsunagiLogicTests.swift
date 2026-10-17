import Testing
import Foundation
import CoreEngine
@testable import GameTsunagi

@Suite("線つなぎのロジック")
struct TsunagiLogicTests {

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（5×5）", arguments: 0..<30)
    func smallPuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(seed))
        let puzzle = TsunagiLogic.generate(size: .small, using: &generator)
        #expect(puzzle.side == 5)
        #expect(TsunagiSize.small.pairRange.contains(puzzle.pairCount))
        #expect(TsunagiLogic.isWellFormed(puzzle))
        #expect(TsunagiLogic.isSolved(puzzle: puzzle, paths: puzzle.solution), "持っている解が正しい")
        // 2 つ目の解を探しに行っても見つからない（上限を 3 にして数え切る）。
        #expect(TsunagiLogic.countSolutions(puzzle, limit: 3) == 1)
    }

    @Test("生成した問題は形が正しく、解がちょうど 1 つ（7×7）", arguments: 0..<8)
    func largePuzzlesHaveUniqueSolution(seed: Int) {
        var generator = SplitMix64(seed: UInt64(1000 + seed))
        let puzzle = TsunagiLogic.generate(size: .large, using: &generator)
        #expect(puzzle.side == 7)
        #expect(TsunagiSize.large.pairRange.contains(puzzle.pairCount))
        #expect(TsunagiLogic.isWellFormed(puzzle))
        #expect(TsunagiLogic.isSolved(puzzle: puzzle, paths: puzzle.solution))
        #expect(TsunagiLogic.countSolutions(puzzle, limit: 3) == 1)
    }

    @Test("同じ種からは同じ問題ができる")
    func deterministicForSeed() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        #expect(TsunagiLogic.generate(size: .small, using: &a) == TsunagiLogic.generate(size: .small, using: &b))
    }

    @Test("各線は 3 マス以上で、点どうしが隣り合っていない")
    func segmentsAreLongEnough() {
        var generator = SplitMix64(seed: 7)
        for _ in 0..<10 {
            let puzzle = TsunagiLogic.generate(size: .small, using: &generator)
            for path in puzzle.solution { #expect(path.count >= 3) }
        }
    }

    @Test("数え上げ: 解が 2 つある問題は 2、解の無い問題は 0 と数える（数え上げそのものの対照）")
    func solverCountsAlternatives() {
        // 2×2 で 1 が対角の 2 マス → 0-1-3 も 0-2-3 も 1 マス残るので解なし。
        let diagonal = TsunagiPuzzle(side: 2, endpoints: [[0, 3]], solution: [[0, 1, 3]])
        #expect(TsunagiLogic.countSolutions(diagonal, limit: 5) == 0)
        // 2×2 で 1 が上の 2 マス、2 が下の 2 マス → 1 通り。
        let unique = TsunagiPuzzle(side: 2, endpoints: [[0, 1], [2, 3]], solution: [[0, 1], [2, 3]])
        #expect(TsunagiLogic.countSolutions(unique, limit: 5) == 1)
        // 3×3 で 1 が左上と右下だけ → 全マスを通る道は複数ある。
        let open = TsunagiPuzzle(side: 3, endpoints: [[0, 8]], solution: [[0, 1, 2, 5, 4, 3, 6, 7, 8]])
        #expect(TsunagiLogic.isWellFormed(open))
        #expect(TsunagiLogic.countSolutions(open, limit: 5) >= 2)
        // 交差しないと結べない配置 → 0。
        let crossing = TsunagiPuzzle(side: 3, endpoints: [[1, 7], [3, 5]], solution: [[1, 4, 7], [3, 4, 5]])
        #expect(TsunagiLogic.countSolutions(crossing, limit: 5) == 0)
    }

    @Test("後ろ噛みで作る道は全マスを 1 回ずつ、隣どうしで通る")
    func hamiltonianPathIsValid() {
        var generator = SplitMix64(seed: 99)
        for side in [3, 5, 7] {
            let path = TsunagiLogic.randomHamiltonianPath(side: side, using: &generator)
            #expect(Set(path) == Set(0..<(side * side)))
            for i in 1..<path.count { #expect(TsunagiLogic.isAdjacent(path[i - 1], path[i], side: side)) }
        }
    }

    @Test("形の検査: 解が重なる・抜ける・飛ぶ問題を弾く")
    func wellFormedRejectsBrokenPuzzles() {
        let good = TsunagiPuzzle(side: 2, endpoints: [[0, 1], [2, 3]], solution: [[0, 1], [2, 3]])
        #expect(TsunagiLogic.isWellFormed(good))
        #expect(!TsunagiLogic.isWellFormed(TsunagiPuzzle(side: 2, endpoints: [[0, 1]], solution: [[0, 1]])), "マスが余る")
        #expect(!TsunagiLogic.isWellFormed(TsunagiPuzzle(side: 2, endpoints: [[0, 3], [1, 2]], solution: [[0, 3], [1, 2]])), "隣でない")
        #expect(!TsunagiLogic.isWellFormed(TsunagiPuzzle(side: 2, endpoints: [[0, 1], [1, 3]], solution: [[0, 1], [1, 3]])), "重なる")
    }

    @Test("クリアの判定: 全部つながっていても空きがあればクリアでない")
    func solvedNeedsEveryCell() {
        let puzzle = TsunagiPuzzle(side: 2, endpoints: [[0, 2]], solution: [[0, 1, 3, 2]])
        #expect(TsunagiLogic.isSolved(puzzle: puzzle, paths: [[0, 1, 3, 2]]))
        #expect(TsunagiLogic.isSolved(puzzle: puzzle, paths: [[2, 3, 1, 0]]), "逆向きに引いてもよい")
        #expect(!TsunagiLogic.isSolved(puzzle: puzzle, paths: [[0, 2]]), "つながっているが 2 マス空き")
        #expect(!TsunagiLogic.isSolved(puzzle: puzzle, paths: [[0, 1, 3]]), "つながっていない")
    }
}
