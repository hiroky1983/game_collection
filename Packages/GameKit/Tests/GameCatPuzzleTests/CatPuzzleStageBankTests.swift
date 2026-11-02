import Testing
import Foundation
import GameKitTestSupport
@testable import GameCatPuzzle

/// 前もって作った 9×9 以上の問題（#3055・#3201・#3223）が、いま実行時に作る問題と同じで、ステージの条件を満たしていることを確かめる。
@Suite("ねこさがしの同梱ステージ")
struct CatPuzzleStageBankTests {
    private static let stages = CatPuzzleStageBank.firstStage..<(CatPuzzleStageBank.firstStage + CatPuzzleStageBank.entries.count)

    @Test("同梱は 46 面目（9×9 の最初）から 500 面目まで続き、その外は nil")
    func coversLargeBoards() {
        let bank = CatPuzzleStageBank.self
        #expect(bank.firstStage == 46)
        #expect(CatPuzzleStage(bank.firstStage).size == .expert)
        #expect(bank.entries.count == 500 - 46 + 1)
        #expect(bank.puzzle(for: 45) == nil)
        #expect(bank.puzzle(for: 500) != nil)
        #expect(bank.puzzle(for: 501) == nil)
        #expect([46, 70, 71, 100, 101, 140, 141, 500].map { bank.puzzle(for: $0)?.side } == [9, 9, 10, 10, 11, 11, 12, 12])
    }

    /// CI では盤の境目と 7 面おき、夜間は全面。
    static let checkedStages: [Int] = NightlyScale.value(
        ci: Array(Set([46, 70, 71, 100, 101, 140, 141, 142, 150].filter(stages.contains) + stages.filter { $0 % 7 == 0 } + [stages.upperBound - 1])).sorted(),
        nightly: Array(stages))

    @Test("同梱の問題は正しい形で、盤の大きさが面と合い、解が 1 つで、その面の段の範囲に入る", arguments: checkedStages)
    func everyEntryIsValid(number: Int) throws {
        let puzzle = try #require(CatPuzzleStageBank.puzzle(for: number), "\(number) 面目が読めない")
        #expect(puzzle.side == CatPuzzleStage(number).size.side && CatPuzzleLogic.isWellFormed(puzzle), "\(number) 面目の形が正しくない")
        #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 2) == 1, "\(number) 面目の解が 1 つでない")
        let difficulty = CatPuzzleSolver.rate(puzzle, maxTier: 4)
        #expect(difficulty.solved && CatPuzzleStage(number).tiers.contains(difficulty.tier), "\(number) 面目の段が範囲外")
    }

    @Test("同梱の問題は、実行時に作る問題と同じ（生成の手順を変えたら作り直す）")
    func matchesGeneratedPuzzle() {
        // 作るのが速い面だけ（12×12 は debug ビルドだと 1 問に数分かかる。同梱の 12×12 は書き出し時に release の生成と同じ手順で作ったもの）。
        for number in [46, 49, 60] {
            #expect(CatPuzzleStage(number).makePuzzle() == CatPuzzleStage(number).generatePuzzle(), "\(number) 面目")
        }
    }

    @Test("同梱の外の面（1〜45 面目と 501 面目〜）は従来どおりその場で作る")
    func outsideTheBankIsGenerated() {
        let stage = CatPuzzleStage(1)
        #expect(stage.makePuzzle() == stage.generatePuzzle())
    }

    @Test("12×12 のステージから自由に遊ぶへ移っても、盤は 9×9 までの大きさで作る（選べない大きさで始めない）")
    @MainActor
    func freePlayAfterLargeStageUsesSelectableSize() {
        let model = CatPuzzleModel(puzzle: CatPuzzleStage(141).makePuzzle(), size: .size12, stage: 141)
        model.newGame()
        #expect(model.stage == nil)
        #expect(model.size == .expert && model.puzzle.side == 9)
    }

    /// 同梱の行を書き出す（作り直し用）。`CAT_PUZZLE_BANK_OUT` に出力先を渡したときだけ動く。
    @Test("同梱の行の書き出し（作り直し用）")
    func exportBank() throws {
        guard let path = ProcessInfo.processInfo.environment["CAT_PUZZLE_BANK_OUT"], !path.isEmpty else { return }
        let lines = Self.stages.map { number -> String in
            let puzzle = CatPuzzleStage(number).generatePuzzle()
            return puzzle.rooms.map { String($0, radix: 16) }.joined() + "|" + puzzle.solution.map { String($0, radix: 16) }.joined()
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}
