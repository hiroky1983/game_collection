import Testing
@testable import GameSudoku

/// 広告のコンティニューを、広告を出す前に控えた局にだけ適用する（#729）。
@MainActor
@Suite("数独 広告のコンティニューの局ガード（#729）")
struct SudokuRewardedContinueTests {

    @Test("広告のあいだに新規ゲームを始めたら、前の局のコンティニューは新しい局に乗らない")
    func continueForReplacedGameIsRejected() async {
        let model = SudokuModel(services: nil, seed: 2026)
        await model.newGame(difficulty: .easy)
        let game = model.gameSerial
        await model.newGame(difficulty: .easy)
        // 新しい局もミス上限にし、「ミス上限ではない」という状態の確認だけでは弾けない形にする。
        for _ in 0..<SudokuModel.maxMistakes { enterWrongDigit(model) }
        #expect(model.state == .failed, "前提: 新しい局もミス上限になっている")

        #expect(!model.continueAfterAd(forGame: game), "入れ替わった局へコンティニューを適用している")
        #expect(model.state == .failed)
        #expect(model.mistakes == SudokuModel.maxMistakes)
        #expect(model.continueAfterAd(forGame: model.gameSerial), "今の局に対する広告なら適用できる")
        #expect(model.state == .playing)
    }

    /// 空きマスを1つ選び、正解ではない数字を入れる。
    private func enterWrongDigit(_ model: SudokuModel) {
        guard let index = (0..<81).first(where: { !model.given[$0] && model.board[$0] == 0 }) else {
            Issue.record("空きマスが無い")
            return
        }
        if model.selected != index { model.select(index: index) }
        let wrong = (1...9).first { $0 != model.solution[index] }!
        model.enter(digit: wrong)
    }
}
