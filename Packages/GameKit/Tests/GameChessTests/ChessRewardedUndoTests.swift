import Testing
import Core
@testable import GameChess

/// 広告の待ったを、広告を出す前に控えた局面（対局の通し番号 × 手数）にだけ適用する（#729）。
@MainActor
@Suite("チェス 広告の待ったの局ガード（#729）")
struct ChessRewardedUndoTests {

    /// 人間の 1 手を指し、CPU の応手まで進める。
    private func playExchange(_ model: ChessGameModel, _ uci: String) async throws {
        let before = model.moves.count
        let move = try #require(ChessMove.fromUCI(uci))
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        await model.performAIMoveIfNeeded()
        try #require(model.moves.count == before + 2, "前提: \(uci) と CPU の応手が指せている")
    }

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = ChessGameModel(services: nil)
        let turn = model.aiTurnKey
        model.newGame()
        // 新しい対局でも 1 往復指し、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        try await playExchange(model, "e2e4")
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "入れ替わった対局で待ったを適用している")
        #expect(model.moves.count == 2)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey), "今の局面に対する広告なら戻せる")
        #expect(model.moves.isEmpty)
    }

    @Test("広告のあいだに同じ対局で 1 往復進めたら、広告を出したときとは別の 1 往復を戻さない")
    func undoForAdvancedPositionIsRejected() async throws {
        let model = ChessGameModel(services: nil)
        try await playExchange(model, "e2e4")
        let turn = model.aiTurnKey
        try await playExchange(model, "g1f3")
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "指し進めた局面へ待ったを適用している")
        #expect(model.moves.count == 4)
    }

    @Test("広告のあいだに投了したら、同じ対局でも待ったを適用しない")
    func undoAfterResignIsRejected() async throws {
        let model = ChessGameModel(services: nil)
        try await playExchange(model, "e2e4")
        try #require(model.canUndo)
        let turn = model.aiTurnKey

        model.resign()
        #expect(!model.undoLastExchange(forTurn: turn))
        #expect(model.moves.count == 2)
    }
}
