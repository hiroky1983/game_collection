import Testing
import Core
@testable import GameOthello

/// 広告の待ったを、広告を出す前に控えた局面（対局の通し番号 × 手番の通し番号）にだけ適用する（#729）。
@MainActor
@Suite("オセロ 広告の待ったの局ガード（#729）")
struct OthelloRewardedUndoTests {

    /// 人間が打てる最初の手を打ち、CPU の応手まで進める。
    private func playExchange(_ model: OthelloModel) async throws {
        let move = try #require(model.board.validMoves(for: model.humanSide).first)
        model.tap(row: move.0, col: move.1)
        await model.performAIMoveIfNeeded()
        try #require(!model.isAITurn && !model.mustPass, "前提: CPU が応手して人間の手番に戻っている")
    }

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        let turn = model.aiTurnKey
        model.newGame()
        // 新しい対局でも 1 往復打ち、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        try await playExchange(model)
        try #require(model.canUndo)
        let board = model.board

        #expect(!model.undoLastExchange(forTurn: turn), "入れ替わった対局で待ったを適用している")
        #expect(model.board == board)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey), "今の局面に対する広告なら戻せる")
        #expect(model.board != board)
    }

    @Test("広告のあいだに同じ対局で 1 往復進めたら、広告を出したときとは別の 1 往復を戻さない")
    func undoForAdvancedPositionIsRejected() async throws {
        let model = OthelloModel(services: nil, flipSettleDelay: .zero)
        try await playExchange(model)
        let turn = model.aiTurnKey
        try await playExchange(model)
        try #require(model.canUndo)
        let board = model.board

        #expect(!model.undoLastExchange(forTurn: turn), "打ち進めた局面へ待ったを適用している")
        #expect(model.board == board)
    }
}
