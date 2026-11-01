import Testing
import Foundation
import GameKitTestSupport
@testable import GameCatPuzzle

/// 前もって作った 9×9 以上の問題（#3055・#3201）が、いま実行時に作る問題と同じで、ステージの条件を満たしていることを確かめる。
@Suite("ねこさがしの同梱ステージ")
struct CatPuzzleStageBankTests {
    private static let stages = CatPuzzleStageBank.firstStage..<(CatPuzzleStageBank.firstStage + CatPuzzleStageBank.entries.count)

    @Test("同梱は 31 面目（9×9 の最初）から続き、9×9・10×10・11×11 は全面、12×12 も途中まであり、その外は nil")
    func coversLargeBoards() {
        let bank = CatPuzzleStageBank.self
        #expect(bank.firstStage == 31)
        #expect(CatPuzzleStage(bank.firstStage).size == .expert)
        #expect(bank.entries.count >= 40, "31〜60 面（9×9 の 10 面・10×10・11×11 の各 10 面）と 12×12 の 10 面以上")
        #expect(bank.puzzle(for: 30) == nil)
        #expect(bank.puzzle(for: bank.firstStage + bank.entries.count) == nil)
        #expect([31, 40, 41, 50, 51, 60, 61].map { bank.puzzle(for: $0)?.side } == [9, 9, 10, 10, 11, 11, 12])
    }

    /// CI では盤の境目と 7 面おき、夜間は全面。
    static let checkedStages: [Int] = NightlyScale.value(
        ci: Array(Set([31, 40, 41, 50, 51, 60, 61, 62, 70].filter(stages.contains) + stages.filter { $0 % 7 == 0 } + [stages.upperBound - 1])).sorted(),
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
        for number in [33, 46, 49] {
            #expect(CatPuzzleStage(number).makePuzzle() == CatPuzzleStage(number).generatePuzzle(), "\(number) 面目")
        }
    }

    @Test("同梱の外の面（1〜30 面目と同梱の最後の次の面〜）は従来どおりその場で作る")
    func outsideTheBankIsGenerated() {
        let stage = CatPuzzleStage(1)
        #expect(stage.makePuzzle() == stage.generatePuzzle())
    }

    @Test("12×12 のステージから自由に遊ぶへ移っても、盤は 9×9 までの大きさで作る（選べない大きさで始めない）")
    @MainActor
    func freePlayAfterLargeStageUsesSelectableSize() {
        let model = CatPuzzleModel(puzzle: CatPuzzleStage(61).makePuzzle(), size: .size12, stage: 61)
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
