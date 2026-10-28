import Testing
import Foundation
@testable import GameCatPuzzle

/// 前もって作った 9×9 の問題（#3055）が、いま実行時に作る問題と同じで、ステージの条件を満たしていることを確かめる。
@Suite("ねこさがしの同梱ステージ")
struct CatPuzzleStageBankTests {
    private static let stages = CatPuzzleStageBank.firstStage..<(CatPuzzleStageBank.firstStage + CatPuzzleStageBank.entries.count)

    @Test("同梱は 31 面目（9×9 の最初）から 300 問で、その外は nil")
    func coversNinebyNine() {
        #expect(CatPuzzleStageBank.firstStage == 31)
        #expect(CatPuzzleStage(CatPuzzleStageBank.firstStage).size == .expert)
        #expect(CatPuzzleStageBank.entries.count == 300)
        #expect(CatPuzzleStageBank.puzzle(for: 30) == nil)
        #expect(CatPuzzleStageBank.puzzle(for: 331) == nil)
    }

    @Test("同梱の問題はどれも正しい形で、解が 1 つで、その面の段の範囲に入る")
    func everyEntryIsValid() throws {
        for number in Self.stages {
            let puzzle = try #require(CatPuzzleStageBank.puzzle(for: number), "\(number) 面目が読めない")
            #expect(puzzle.side == 9 && CatPuzzleLogic.isWellFormed(puzzle), "\(number) 面目の形が正しくない")
            #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 2) == 1, "\(number) 面目の解が 1 つでない")
            let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: 4)
            #expect(difficulty.solved && CatPuzzleStage(number).tiers.contains(difficulty.tier), "\(number) 面目の段が範囲外")
        }
    }

    @Test("同梱の問題は、実行時に作る問題と同じ（生成の手順を変えたら作り直す）")
    func matchesGeneratedPuzzle() {
        // 作るのが速い面だけ（全部は数十秒かかる）。
        for number in [33, 42, 45, 60] {
            #expect(CatPuzzleStage(number).makePuzzle() == CatPuzzleStage(number).generatePuzzle(), "\(number) 面目")
        }
    }

    @Test("同梱の外の面（1〜30 面目と 331 面目〜）は従来どおりその場で作る")
    func outsideTheBankIsGenerated() {
        let stage = CatPuzzleStage(1)
        #expect(stage.makePuzzle() == stage.generatePuzzle())
    }

    /// 同梱の行を書き出す（作り直し用）。`CAT_PUZZLE_BANK_OUT` に出力先を渡したときだけ動く。
    @Test("同梱の行の書き出し（作り直し用）")
    func exportBank() throws {
        guard let path = ProcessInfo.processInfo.environment["CAT_PUZZLE_BANK_OUT"], !path.isEmpty else { return }
        let lines = Self.stages.map { number -> String in
            let puzzle = CatPuzzleStage(number).generatePuzzle()
            return puzzle.rooms.map(String.init).joined() + "|" + puzzle.solution.map(String.init).joined()
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
