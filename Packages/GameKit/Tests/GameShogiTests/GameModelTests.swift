import Testing
@testable import GameShogi

@MainActor
@Suite("対局モデル（人間→CPU の流れ）")
struct ShogiGameModelTests {
    @Test func humanMoveThenAIReplies() async {
        let model = ShogiGameModel(services: nil)
        // 既定は人間=先手 / CPU=後手。
        #expect(model.humanSide == .black)
        #expect(model.isAITurn == false)

        // 人間(先手)が 7g7f（選択→着手先タップ）。
        model.tapSquare(Sq.fromUSI("7g")!)
        #expect(model.selectedSquare == Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(model.moves.count == 1)
        #expect(model.moves.last?.usi == "7g7f")

        // 手番は後手(CPU)。AI が応手する。
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 2)
        #expect(model.gameOver == false)
        // 応手後は再び先手(人間)番。
        #expect(model.isAITurn == false)
    }

    @Test func humanCannotMoveDuringCPUTurn() {
        let model = ShogiGameModel(services: nil)
        // 人間(先手)が一手指すと CPU(後手)の手番。
        model.tapSquare(Sq.fromUSI("7g")!)
        model.tapSquare(Sq.fromUSI("7f")!)
        #expect(model.isAITurn)
        let movesBefore = model.moves.count
        // CPU の手番中に後手の駒を触っても何も起きない。
        model.tapSquare(Sq.fromUSI("3c")!) // 後手の歩
        #expect(model.selectedSquare == nil)
        model.tapSquare(Sq.fromUSI("3d")!)
        #expect(model.moves.count == movesBefore) // 手が増えない
    }

    @Test func newGameAsGoteMakesAIMoveFirst() async {
        let model = ShogiGameModel(services: nil)
        model.newGame(humanSide: .white) // 人間後手 → CPU が先手で初手を指す
        #expect(model.isAITurn)
        await model.performAIMoveIfNeeded()
        #expect(model.moves.count == 1)
    }
}
