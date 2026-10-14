import Testing
import Core
@testable import GameGo

/// 広告の待ったを、広告を出す前に控えた局面（対局の通し番号 × 手数）にだけ適用する（#729）。
@MainActor
@Suite("囲碁 広告の待ったの局ガード（#729）")
struct GoRewardedUndoTests {

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() throws {
        let model = GoModel(services: nil)
        model.newGame(humanSide: .black, level: .easy)
        let turn = model.aiTurnKey
        model.newGame(humanSide: .black, level: .easy)
        // 新しい対局でも 1 往復打ち、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        model.applyMoveForTesting(.play(row: 4, col: 4))   // 黒（人間）
        model.applyMoveForTesting(.play(row: 2, col: 2))   // 白（CPU）
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "入れ替わった対局で待ったを適用している")
        #expect(model.moveCount == 2)
        #expect(model.undoLastExchange(forTurn: model.aiTurnKey), "今の局面に対する広告なら戻せる")
        #expect(model.moveCount == 0)
    }

    @Test("広告のあいだに同じ対局で 1 往復進めたら、広告を出したときとは別の 1 往復を戻さない")
    func undoForAdvancedPositionIsRejected() throws {
        let model = GoModel(services: nil)
        model.newGame(humanSide: .black, level: .easy)
        model.applyMoveForTesting(.play(row: 4, col: 4))   // 黒（人間）
        model.applyMoveForTesting(.play(row: 2, col: 2))   // 白（CPU）
        let turn = model.aiTurnKey
        model.applyMoveForTesting(.play(row: 6, col: 6))   // 黒（人間）
        model.applyMoveForTesting(.play(row: 2, col: 6))   // 白（CPU）
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forTurn: turn), "打ち進めた局面へ待ったを適用している")
        #expect(model.moveCount == 4)
    }
}
