import Testing
import Core
import GameKitTestSupport
import CoreTestSupport
@testable import GameSudoku

/// 図で見る「はじめての遊び方」（#2826）の中身が、実装のルールと食い違っていないこと。
@MainActor
@Suite("ナンプレ: はじめての遊び方")
struct SudokuOnboardingTests {
    private func makeModel() async -> SudokuModel {
        let model = SudokuModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), seed: 2826)
        await model.newGame(difficulty: .easy)
        return model
    }

    /// 空いているマスに答えと違う数字を入れる。
    private func enterWrong(_ model: SudokuModel, at index: Int) {
        if model.selected != index { model.select(index: index) }
        model.enter(digit: model.solution[index] % 9 + 1)
    }

    @Test("カードの型（4〜6 枚・各 2〜3 行）に収まっている")
    func wellFormed() {
        #expect(SudokuOnboarding.guide.isWellFormed)
        #expect(SudokuOnboarding.guide.gameID == SudokuModel(services: nil).gameID)
    }

    @Test("図の盤は、行・列・3×3 のどれにも 1〜9 が 1 つずつ入っている")
    func figureBoardFollowsRule() {
        let grid = SudokuHowToFigures.solved.flatMap { $0 }
        #expect(grid.count == SudokuEngine.cellCount)
        for unit in 0..<SudokuEngine.unitCount {
            #expect(Set(SudokuEngine.cells(ofUnit: unit).map { grid[$0] }) == Set(1...9), "ユニット \(unit) が 1〜9 でない")
        }
        // 同じ数字を同じ行・列・3×3 にもう 1 つ入れることは、ルール上できない。
        var erased = grid
        erased[0] = 0
        #expect(SudokuEngine.isValid(erased, at: 0, digit: grid[0]))
        #expect(!SudokuEngine.isValid(erased, at: 0, digit: grid[1]))
    }

    @Test("ミスの図: 入れた数字はそのマスの答えと違う")
    func mistakeFigureIsWrong() {
        let cell = SudokuOnboarding.mistakeCell
        #expect(SudokuHowToFigures.solved[cell.row][cell.col] != SudokuOnboarding.mistakeDigit)
    }

    @Test("答えと違う数字はミス。3 回で止まり、広告のコンティニューでミスが 0 に戻る")
    func mistakesUpToThree() async {
        #expect(SudokuModel.maxMistakes == 3)
        let model = await makeModel()
        let empties = (0..<SudokuEngine.cellCount).filter { model.board[$0] == 0 }
        enterWrong(model, at: empties[0])
        #expect(model.mistakes == 1)
        #expect(model.errorCells.contains(empties[0]))
        enterWrong(model, at: empties[1])
        #expect(model.state == .playing)
        enterWrong(model, at: empties[2])
        #expect(model.state == .failed)
        #expect(model.continueAfterAd())
        #expect(model.mistakes == 0)
        #expect(model.state == .playing)
    }

    @Test("空いているマスをすべて正しく埋めたらクリア")
    func clearsWhenFilled() async {
        let model = await makeModel()
        for index in 0..<SudokuEngine.cellCount where model.board[index] == 0 {
            if model.selected != index { model.select(index: index) }
            model.enter(digit: model.solution[index])
        }
        #expect(model.state == .cleared)
    }

    @Test("諦めると答えが表示され、クリアできなかった扱いになる")
    func giveUpShowsAnswer() async {
        let model = await makeModel()
        model.giveUp()
        #expect(model.state == .givenUp)
        #expect(model.board == model.solution)
    }

    @Test("全部の文言に英語の訳がある（訳し漏れ 0）")
    func everyTextHasEnglish() {
        for text in SudokuOnboarding.guide.texts + ["はじめ", "おわり"] {
            #expect(tr.hasTranslation(text, language: .english), "「\(text)」に英語の訳が無い")
        }
    }
}
