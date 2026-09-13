import Testing
import Core
@testable import GameGomoku

/// 広告の待ったを、広告を出す前に控えた局面（対局の通し番号 × 手数）にだけ適用する（#729）。
@MainActor
@Suite("五目並べ 広告の待ったの局ガード（#729）")
struct GomokuRewardedUndoTests {

    /// 空いている交点に人間が 1 手打ち、CPU の応手まで進める。
    private func playExchange(_ model: GomokuModel) async throws {
        let before = model.moveCount
        let point = try #require((0..<15).lazy.flatMap { r in (0..<15).map { (r, $0) } }
            .first { model.board[$0.0, $0.1] == nil })
        model.tap(row: point.0, col: point.1)
        await model.performAIMoveIfNeeded()
        try #require(model.moveCount == before + 2, "前提: 人間の手と CPU の応手が打てている")
    }

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = GomokuModel(services: nil)
        let turn = model.aiTurnKey
        model.newGame()
        // 新しい対局でも 1 往復打ち、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        try await playExchange(model)
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "入れ替わった対局で待ったを適用している")
        #expect(model.moveCount == 2)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey), "今の局面に対する広告なら戻せる")
        #expect(model.moveCount == 0)
    }

    @Test("広告のあいだに同じ対局で 1 往復進めたら、広告を出したときとは別の 1 往復を戻さない")
    func undoForAdvancedPositionIsRejected() async throws {
        let model = GomokuModel(services: nil)
        try await playExchange(model)
        let turn = model.aiTurnKey
        try await playExchange(model)
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "打ち進めた局面へ待ったを適用している")
        #expect(model.moveCount == 4)
    }
}
