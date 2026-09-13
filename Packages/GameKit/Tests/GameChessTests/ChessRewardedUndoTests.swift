import Testing
import Core
@testable import GameChess

/// 広告の待ったを、広告を出す前に控えた対局にだけ適用する（#729）。
@MainActor
@Suite("チェス 広告の待ったの局ガード（#729）")
struct ChessRewardedUndoTests {

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = ChessGameModel(services: nil)
        let game = model.gameSerial
        model.newGame()
        // 新しい対局でも 1 往復指し、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        let move = try #require(ChessMove.fromUCI("e2e4"))
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        await model.performAIMoveIfNeeded()
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forGame: game), "入れ替わった対局で待ったを適用している")
        #expect(model.moves.count == 2)
        #expect(model.undoLastExchange(forGame: model.gameSerial), "今の対局に対する広告なら戻せる")
        #expect(model.moves.isEmpty)
    }

    @Test("広告のあいだに投了したら、同じ対局でも待ったを適用しない")
    func undoAfterResignIsRejected() async throws {
        let model = ChessGameModel(services: nil)
        let move = try #require(ChessMove.fromUCI("e2e4"))
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        await model.performAIMoveIfNeeded()
        try #require(model.canUndo)
        let game = model.gameSerial

        model.resign()
        #expect(!model.undoLastExchange(forGame: game))
        #expect(model.moves.count == 2)
    }
}
