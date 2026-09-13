import Testing
@testable import GameGomoku

/// 広告の待ったを、広告を出す前に控えた対局にだけ適用する（#729）。
@MainActor
@Suite("五目並べ 広告の待ったの局ガード（#729）")
struct GomokuRewardedUndoTests {

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = GomokuModel(services: nil)
        let game = model.gameSerial
        model.newGame()
        // 新しい対局でも 1 往復打ち、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        model.tap(row: 7, col: 7)
        await model.performAIMoveIfNeeded()
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forGame: game), "入れ替わった対局で待ったを適用している")
        #expect(model.moveCount == 2)
        #expect(model.undoLastExchange(forGame: model.gameSerial), "今の対局に対する広告なら戻せる")
        #expect(model.moveCount == 0)
    }
}
