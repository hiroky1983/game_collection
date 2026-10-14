import Testing
import CoreEngine
@testable import GameAkariKeshi

@Suite("明かり消しパズルの規則")
struct AkariKeshiLogicTests {
    @Test("押すと自分と上下左右が入れ替わる。端と角は盤の中の隣だけ")
    func toggledCells() {
        #expect(Set(AkariKeshiLogic.toggled(by: 12)) == [12, 7, 17, 11, 13], "真ん中は 5 マス")
        #expect(Set(AkariKeshiLogic.toggled(by: 0)) == [0, 1, 5], "左上の角は 3 マス")
        #expect(Set(AkariKeshiLogic.toggled(by: 24)) == [24, 23, 19], "右下の角は 3 マス")
        #expect(Set(AkariKeshiLogic.toggled(by: 2)) == [2, 1, 3, 7], "上の辺は 4 マス")
        #expect(Set(AkariKeshiLogic.toggled(by: 9)) == [9, 4, 14, 8], "右の辺は 4 マス（次の行の先頭へ回り込まない）")
        #expect(Set(AkariKeshiLogic.toggled(by: 10)) == [10, 5, 15, 11], "左の辺は 4 マス（前の行の末尾へ回り込まない）")
        #expect(AkariKeshiLogic.toggled(by: -1).isEmpty && AkariKeshiLogic.toggled(by: 25).isEmpty)
    }

    @Test("同じマスを 2 回押すと元に戻り、押す順番は結果に関係しない")
    func pressIsInvolutionAndCommutative() {
        let start = AkariKeshiLogic.board(pressing: [3, 8, 20])
        for index in 0..<AkariKeshiLogic.cellCount {
            #expect(AkariKeshiLogic.press(AkariKeshiLogic.press(start, at: index), at: index) == start)
        }
        let ab = AkariKeshiLogic.press(AkariKeshiLogic.press(start, at: 6), at: 18)
        let ba = AkariKeshiLogic.press(AkariKeshiLogic.press(start, at: 18), at: 6)
        #expect(ab == ba)
    }

    @Test("何も変えない押し方は 3 つ（重さ 12・12・16）で、全部消えた盤の解は 4 通り")
    func quietPatterns() {
        let quiet = AkariKeshiLogic.solutions(AkariKeshiLogic.cleared)
        #expect(quiet.count == 4)
        #expect(quiet.map(\.count).sorted() == [0, 12, 12, 16])
        for pattern in quiet {
            #expect(AkariKeshiLogic.board(pressing: pattern) == AkariKeshiLogic.cleared)
        }
    }

    @Test("求めた解はどれも本当に全部消える")
    func solutionsClearTheBoard() {
        let board = AkariKeshiLogic.board(pressing: [0, 7, 13, 24])
        let found = AkariKeshiLogic.solutions(board)
        #expect(found.count == 4)
        for solution in found {
            #expect(AkariKeshiLogic.isCleared(solution.reduce(board) { AkariKeshiLogic.press($0, at: $1) }))
        }
        #expect(AkariKeshiLogic.minimumPresses(board) == 4)
    }

    @Test("ランダムに点けた盤には解けないものがある（だから逆生成で作る）")
    func someBoardsAreUnsolvable() {
        var oneLit = AkariKeshiLogic.cleared
        oneLit[0] = true
        #expect(!AkariKeshiLogic.isSolvable(oneLit), "角 1 つだけ点いた盤は消せない")
        #expect(AkariKeshiLogic.minimumPresses(oneLit) == nil)
        #expect(AkariKeshiLogic.solutions([true, false]).isEmpty, "形の違う盤は解かない")
    }

    @Test("生成した盤は必ず解け、最短の押し方がただ 1 つで、それが生成で押したマスと一致する",
          arguments: [4, 7, 10])
    func generatedBoardsHaveUniqueShortestSolution(presses: Int) {
        var rng = SplitMix64(seed: UInt64(presses) * 1_000)
        for _ in 0..<60 {
            let puzzle = AkariKeshiLogic.generate(presses: presses, using: &rng)
            #expect(AkariKeshiLogic.isValid(puzzle.board))
            #expect(!AkariKeshiLogic.isCleared(puzzle.board), "最初から消えている盤は出さない")
            #expect(puzzle.solution.count == presses)
            #expect(AkariKeshiLogic.board(pressing: puzzle.solution) == puzzle.board)
            let found = AkariKeshiLogic.solutions(puzzle.board)
            #expect(!found.isEmpty, "解けない盤を出した")
            #expect(AkariKeshiLogic.minimumPresses(puzzle.board) == presses, "表示する最短の手数と食い違う")
            #expect(found.filter { $0.count == presses } == [puzzle.solution], "最短の押し方が 2 通り以上ある")
            #expect(AkariKeshiLogic.hasUniqueShortestSolution(puzzle.board))
        }
    }

    @Test("同じ種からは同じ問題、違う種からは違う問題")
    func generationIsDeterministicPerSeed() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        var c = SplitMix64(seed: 43)
        let first = AkariKeshiLogic.generate(presses: 7, using: &a)
        #expect(first.board == AkariKeshiLogic.generate(presses: 7, using: &b).board)
        #expect(first.board != AkariKeshiLogic.generate(presses: 7, using: &c).board)
    }

    @Test("難易度は押す数＝最短の手数で 3 段階、いちばん上は生成の上限")
    func difficulties() {
        #expect(AkariKeshiDifficulty.allCases.map(\.presses) == [4, 7, 10])
        #expect(AkariKeshiDifficulty.hard.presses == AkariKeshiLogic.maxPresses)
        #expect(AkariKeshiDifficulty.allCases.map(\.rawValue) == ["easy", "normal", "hard"], "記録・解析のキーは英字")
    }
}
