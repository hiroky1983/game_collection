import Testing
@testable import GameBlockPuzzle

/// 広告のコンティニューを、広告を出す前に控えた局にだけ適用する（#729）。
@MainActor
@Suite("ブロックならべ 広告のコンティニューの局ガード（#729）")
struct BlockPuzzleRewardedContinueTests {

    @Test("新規ゲームで局の通し番号が変わり、前の局に対するコンティニューは適用しない")
    func continueForReplacedGameIsRejected() {
        let model = BlockPuzzleModel(services: nil, seed: 1)
        let game = model.gameSerial
        model.newGame()

        #expect(model.gameSerial != game, "新規ゲームで通し番号が変わっていない")
        #expect(!model.continueAfterAd(forGame: game), "入れ替わった局へコンティニューを適用している")
        #expect(!model.continueUsed, "新しい局のコンティニュー権が前の局の広告で消えている")
        #expect(!model.gameOver)
    }
}
