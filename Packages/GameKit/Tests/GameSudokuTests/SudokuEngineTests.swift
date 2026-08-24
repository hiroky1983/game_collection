import Testing
import Foundation
@testable import GameSudoku

/// 生成アルゴリズムの検証（#262 の受け入れ条件「難易度3段階それぞれで唯一解のパズルが生成できる」）。
///
/// 乱数は種を渡して固定する。種を変えた複数回ぶんを回すことで、
/// 「たまたま 1 盤面だけ通った」を防ぎつつ実行時間を数百 ms に収める。
@Suite("数独の生成エンジン")
struct SudokuEngineTests {

    private func makePuzzle(_ difficulty: SudokuDifficulty, seed: UInt64) -> SudokuEngine.Puzzle {
        var rng = SudokuSeededGenerator(seed: seed)
        return SudokuEngine.generate(difficulty: difficulty, using: &rng)
    }

    @Test("難易度3段階それぞれで、解が1通りしかないパズルが出来る", arguments: SudokuDifficulty.allCases)
    func generatesUniqueSolution(_ difficulty: SudokuDifficulty) {
        for seed in UInt64(1)...3 {
            let puzzle = makePuzzle(difficulty, seed: seed)
            #expect(
                SudokuEngine.solutionCount(puzzle.board, limit: 2) == 1,
                "\(difficulty) / seed \(seed): 解が唯一でない"
            )
        }
    }

    @Test("正解グリッドは数独として正しい（行・列・ブロックに1〜9が1つずつ）",
          arguments: SudokuDifficulty.allCases)
    func solutionIsWellFormed(_ difficulty: SudokuDifficulty) {
        let solution = makePuzzle(difficulty, seed: 42).solution
        #expect(solution.count == 81)
        for i in 0..<9 {
            let row = Set((0..<9).map { solution[i * 9 + $0] })
            let col = Set((0..<9).map { solution[$0 * 9 + i] })
            let block = Set((0..<9).map { d -> Int in
                let br = (i / 3) * 3 + d / 3, bc = (i % 3) * 3 + d % 3
                return solution[br * 9 + bc]
            })
            #expect(row == Set(1...9), "\(i + 1)行目に重複か欠けがある")
            #expect(col == Set(1...9), "\(i + 1)列目に重複か欠けがある")
            #expect(block == Set(1...9), "\(i + 1)番目のブロックに重複か欠けがある")
        }
    }

    @Test("出題は正解の部分集合（消えているマス以外は正解と一致する）",
          arguments: SudokuDifficulty.allCases)
    func boardIsSubsetOfSolution(_ difficulty: SudokuDifficulty) {
        let puzzle = makePuzzle(difficulty, seed: 7)
        for index in 0..<81 where puzzle.board[index] != 0 {
            #expect(puzzle.board[index] == puzzle.solution[index])
        }
    }

    @Test("難易度が上がるほど空きマスが増える")
    func blanksIncreaseWithDifficulty() {
        // 種ごとのばらつきを均すため、同じ種の組で3難易度を比べる。
        for seed in UInt64(1)...3 {
            let easy = makePuzzle(.easy, seed: seed).blankCount
            let normal = makePuzzle(.normal, seed: seed).blankCount
            let hard = makePuzzle(.hard, seed: seed).blankCount
            #expect(easy < normal, "seed \(seed): かんたん(\(easy)) < ふつう(\(normal))")
            #expect(normal <= hard, "seed \(seed): ふつう(\(normal)) <= むずかしい(\(hard))")
        }
    }

    @Test("空きマス数は難易度の指定範囲を超えない", arguments: SudokuDifficulty.allCases)
    func blankCountWithinRange(_ difficulty: SudokuDifficulty) {
        let puzzle = makePuzzle(difficulty, seed: 99)
        // 唯一解を保てないマスは削れずに戻すため下限は割りうるが、上限は必ず守られる。
        #expect(puzzle.blankCount <= difficulty.removalRange.upperBound)
        #expect(puzzle.blankCount > 0)
    }

    @Test("同じ種からは同じ盤面が出る（テストが盤面を固定できる）")
    func generationIsDeterministic() {
        #expect(makePuzzle(.normal, seed: 12345) == makePuzzle(.normal, seed: 12345))
    }

    @Test("解が複数ある盤は唯一解と判定しない")
    func detectsMultipleSolutions() {
        // 空の盤は解が大量にあるので、limit で打ち切っても 1 にはならない。
        let empty = [Int](repeating: 0, count: 81)
        #expect(SudokuEngine.solutionCount(empty, limit: 2) >= 2)
    }

    @Test("peers は自分を含まない 20 マス（行8 + 列8 + ブロックの残り4）")
    func peersAreTwenty() {
        let peers = SudokuEngine.peers(of: 40)   // 5行5列
        #expect(peers.count == 20)
        #expect(!peers.contains(40))
        #expect(peers.contains(36))   // 同じ行
        #expect(peers.contains(4))    // 同じ列
        #expect(peers.contains(30))   // 同じブロック
        #expect(!peers.contains(0))   // 無関係なマス
    }

    @Test("isValid は行・列・ブロックの衝突を見る")
    func validityChecksAllThreeConstraints() {
        var grid = [Int](repeating: 0, count: 81)
        grid[0] = 5
        #expect(!SudokuEngine.isValid(grid, at: 8, digit: 5), "同じ行はだめ")
        #expect(!SudokuEngine.isValid(grid, at: 72, digit: 5), "同じ列はだめ")
        #expect(!SudokuEngine.isValid(grid, at: 10, digit: 5), "同じブロックはだめ")
        #expect(SudokuEngine.isValid(grid, at: 40, digit: 5), "無関係なマスは置ける")
    }
}
