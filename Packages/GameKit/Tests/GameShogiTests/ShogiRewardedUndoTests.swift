import Testing
import Core
@testable import GameShogi

/// 広告の待ったを、広告を出す前に控えた局面（対局の通し番号 × 手数）にだけ適用する（#729）。
@MainActor
@Suite("将棋 広告の待ったの局ガード（#729）")
struct ShogiRewardedUndoTests {

    /// 人間の 1 手を指し、CPU の応手まで進める。
    private func playExchange(_ model: ShogiGameModel, from: String, to: String) async throws {
        let before = model.moves.count
        model.tapSquare(try #require(Sq.fromUSI(Substring(from))))
        model.tapSquare(try #require(Sq.fromUSI(Substring(to))))
        await model.performAIMoveIfNeeded()
        try #require(model.moves.count == before + 2, "前提: \(from)→\(to) と CPU の応手が指せている")
    }

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() async throws {
        let model = ShogiGameModel(services: nil)
        let turn = model.aiTurnKey
        model.newGame()
        // 新しい対局でも 1 往復指し、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        try await playExchange(model, from: "7g", to: "7f")
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "入れ替わった対局で待ったを適用している")
        #expect(model.moves.count == 2)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey), "今の局面に対する広告なら戻せる")
        #expect(model.moves.isEmpty)
    }

    @Test("広告のあいだに同じ対局で 1 往復進めたら、広告を出したときとは別の 1 往復を戻さない")
    func undoForAdvancedPositionIsRejected() async throws {
        let model = ShogiGameModel(services: nil)
        try await playExchange(model, from: "7g", to: "7f")
        let turn = model.aiTurnKey
        try await playExchange(model, from: "2g", to: "2f")
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "指し進めた局面へ待ったを適用している")
        #expect(model.moves.count == 4)
    }
}
