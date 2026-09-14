import Testing
@testable import GameSudoku

/// 広告のヒントを、広告を出す前に控えた局にだけ入れる（#815。コンティニューの #729 と同じ形）。
@MainActor
@Suite("数独 広告のヒントの局ガード（#815）")
struct SudokuRewardedHintTests {

    @Test("広告のあいだに新規ゲームを始めたら、前の局のヒントは新しい局に入らず回数も減らない")
    func hintForReplacedGameIsRejected() async throws {
        let model = SudokuModel(services: nil, seed: 2026)
        await model.newGame(difficulty: .easy)
        let game = model.gameSerial
        await model.newGame(difficulty: .easy)
        // 新しい局でもヒントを入れられるマスを選び、「入れられないマスだった」では弾けない形にする。
        let target = try #require((0..<81).first { model.canHint(at: $0) })
        let boardBefore = model.board

        #expect(!model.applyHint(forGame: game, at: target), "入れ替わった局へヒントを入れている")
        #expect(model.board == boardBefore)
        #expect(model.hintsUsed == 0)
        #expect(model.applyHint(forGame: model.gameSerial, at: target), "今の局に対する広告なら入れられる")
        #expect(model.hintsUsed == 1)
    }
}
