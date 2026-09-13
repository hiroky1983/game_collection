import Testing
import Core
@testable import GameGo

/// 広告の待ったを、広告を出す前に控えた対局にだけ適用する（#729）。
@MainActor
@Suite("囲碁 広告の待ったの局ガード（#729）")
struct GoRewardedUndoTests {

    @Test("広告のあいだに新規対局を始めたら、前の対局の待ったは新しい対局に乗らない")
    func undoForReplacedGameIsRejected() throws {
        let model = GoModel(services: nil)
        model.newGame(humanSide: .black, level: .easy)
        let game = model.gameSerial
        model.newGame(humanSide: .black, level: .easy)
        // 新しい対局でも 1 往復打ち、「戻せる手が無い」という状態の確認だけでは弾けない形にする。
        model.applyMoveForTesting(.play(row: 4, col: 4))   // 黒（人間）
        model.applyMoveForTesting(.play(row: 2, col: 2))   // 白（CPU）
        try #require(model.canUndo)

        #expect(!model.undoLastExchange(forGame: game), "入れ替わった対局で待ったを適用している")
        #expect(model.moveCount == 2)
        #expect(model.undoLastExchange(forGame: model.gameSerial), "今の対局に対する広告なら戻せる")
        #expect(model.moveCount == 0)
    }
}
