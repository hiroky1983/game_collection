import Testing
import Core
@testable import GameOthello

/// 広告の待ったを、広告を出す前に控えた対局にだけ適用する（#729）。
@MainActor
@Suite("オセロ 広告の待ったの局ガード（#729）")
struct OthelloRewardedUndoTests {

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        let game = model.gameSerial
        model.newGame()
        // 新しい対局でも 1 往復打ち、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        model.tap(row: 2, col: 3)
        await model.performAIMoveIfNeeded()
        try #require(model.canUndo)
        let board = model.board

        #expect(!model.undoLastExchange(forGame: game), "入れ替わった対局で待ったを適用している")
        #expect(model.board == board)
        #expect(model.undoLastExchange(forGame: model.gameSerial), "今の対局に対する広告なら戻せる")
        #expect(model.board != board)
    }
}
