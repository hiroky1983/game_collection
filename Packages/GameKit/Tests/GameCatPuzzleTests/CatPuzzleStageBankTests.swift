import Testing
import Foundation
import GameKitTestSupport
@testable import GameCatPuzzle

/// 前もって作った 9×9 以上の問題（#3055・#3201・#3223）が、いま実行時に作る問題と同じで、ステージの条件を満たしていることを確かめる。
@Suite("ねこさがしの同梱ステージ")
struct CatPuzzleStageBankTests {
    private static let stages = CatPuzzleStageBank.firstStage..<(CatPuzzleStageBank.firstStage + CatPuzzleStageBank.entries.count)

    @Test("同梱は 46 面目（9×9 の最初）から 1,000 面目まで続き、45 面目以前は nil")
    func coversLargeBoards() {
        let bank = CatPuzzleStageBank.self
        #expect(bank.firstStage == 46)
        #expect(CatPuzzleStage(bank.firstStage).size == .expert)
        #expect(bank.entries.count == 1000 - 46 + 1)
        #expect(bank.lastStage == 1000)
        #expect(bank.puzzle(for: 45) == nil)
        #expect([46, 70, 71, 100, 101, 140, 141, 500, 501, 1000].map { bank.puzzle(for: $0)?.side } == [9, 9, 10, 10, 11, 11, 12, 12, 12, 12])
    }

    @Test("1,001 面目からは同梱の 12×12 を面番号の順に繰り返す。鍵の面は鍵の面同士")
    func repeatsLargeBoardsInOrder() {
        let bank = CatPuzzleStageBank.self
        // 非鍵: 1001→141, 1002→142 … 1009→149, 1011→151（鍵の 150 は飛ばす）。
        #expect([1001, 1002, 1009, 1011, 1019, 1021].map { bank.sourceNumber(for: $0) } == [141, 142, 149, 151, 159, 161])
        // 鍵: 1010→150, 1020→160 … 1000 の次は 150 に戻る（鍵は 150〜1000 の 86 面）。
        #expect([1010, 1020, 1030, 1860, 1870].map { bank.sourceNumber(for: $0) } == [150, 160, 170, 1000, 150])
        // 非鍵は 141〜1000 のうち鍵でない 774 面を一巡して戻る（1,001 + 774 + 86 = 1,861）。
        #expect(bank.sourceNumber(for: 1859) == 999 && bank.sourceNumber(for: 1861) == 141)
        for number in [1001, 1010, 1234, 1500, 2000, 5555, 12345] {
            let source = bank.sourceNumber(for: number)
            #expect((141...1000).contains(source), "\(number) 面目")
            #expect(CatPuzzleStage(source).isKey == CatPuzzleStage(number).isKey, "\(number) 面目")
            #expect(bank.puzzle(for: number) == bank.puzzle(for: source), "\(number) 面目")
            #expect(CatPuzzleStage(number).makePuzzle() == bank.puzzle(for: source), "\(number) 面目")
        }
        // 範囲の中の面は写し先が自分自身。
        #expect([46, 500, 1000].map { bank.sourceNumber(for: $0) } == [46, 500, 1000])
    }

    @Test("繰り返しの面でも、同梱の面と同じく段の範囲（前半・後半）と鍵の猫が合う")
    func repeatedStagesKeepShape() {
        for number in [1001, 1003, 1005, 1006, 1008, 1010, 1015, 1100, 2000] {
            let stage = CatPuzzleStage(number)
            let puzzle = stage.makePuzzle()
            #expect(puzzle.side == stage.size.side && CatPuzzleLogic.isWellFormed(puzzle), "\(number) 面目")
            #expect(CatPuzzleLogic.countSolutions(side: puzzle.side, rooms: puzzle.rooms, limit: 2) == 1, "\(number) 面目")
            #expect(stage.tiers.contains(CatPuzzleSolver.rate(puzzle, maxTier: 4).tier), "\(number) 面目")
            if stage.isKey { #expect(CatPuzzleSolver.keyCat(puzzle) != nil, "\(number) 面目") }
        }
    }

    /// CI では盤の境目と 7 面おき、夜間は全面。
    static let checkedStages: [Int] = NightlyScale.value(
        ci: Array(Set([46, 70, 71, 100, 101, 140, 141, 142, 143, 145, 148, 150, 155].filter(stages.contains) + stages.filter { $0 % 7 == 0 } + [stages.upperBound - 1])).sorted(),
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

    @Test("同梱の外の面（1〜45 面目）は従来どおりその場で作る")
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
