import Testing
import Core
@testable import GameShogi

/// 広告の待ったを、広告を出す前に控えた対局にだけ適用する（#729）。
@MainActor
@Suite("将棋 広告の待ったの局ガード（#729）")
struct ShogiRewardedUndoTests {

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = ShogiGameModel(services: nil)
        let game = model.gameSerial
        model.newGame()
        // 新しい対局でも 1 往復指し、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        model.tapSquare(try #require(Sq.fromUSI("7g")))
        model.tapSquare(try #require(Sq.fromUSI("7f")))
        await model.performAIMoveIfNeeded()
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forGame: game), "入れ替わった対局で待ったを適用している")
        #expect(model.moves.count == 2)
        #expect(model.undoLastExchange(forGame: model.gameSerial), "今の対局に対する広告なら戻せる")
        #expect(model.moves.isEmpty)
    }
}
