import Testing
@testable import GameBlockPuzzle

/// 広告のコンティニューを、広告を出す前に控えた局にだけ適用する（#729）。
@MainActor
@Suite("ブロックならべ 広告のコンティニューの局ガード（#729）")
struct BlockPuzzleRewardedContinueTests {

    /// 1×1 しか置けない盤（`BlockPuzzleModelTests.makeAboutToLose` と同じ形）で、(0, 2) に置いて詰ませる。
    private func makeFinishedModel() throws -> BlockPuzzleModel {
        var board = Array(repeating: Array(repeating: 1, count: 10), count: 10)
        for i in 0..<10 { board[i][i] = 0 }
        board[0][2] = 0
        let square3 = BlockPuzzlePiece.catalog[10]
        let model = BlockPuzzleModel(
            services: nil, board: board,
            hand: [BlockPuzzlePiece.catalog[0], square3, square3], score: 500
        )
        #expect(model.place(pieceIndex: 0, row: 0, col: 2))
        try #require(model.gameOver, "前提: 置ける形が無くなって終局している")
        return model
    }

    @Test("新規ゲームで局の通し番号が変わる")
    func newGameAdvancesSerial() {
        let model = BlockPuzzleModel(services: nil, seed: 1)
        let game = model.gameSerial
        model.newGame()
        #expect(model.gameSerial != game, "新規ゲームで通し番号が変わっていない")
    }

    @Test("終局していても、控えた番号が今の局と違えばコンティニューを適用しない")
    func continueForAnotherGameIsRejected() throws {
        let model = try makeFinishedModel()
        // 新しい局を狙って詰ませる手段が無いので、終局した局に「別の局の番号」を渡して照合だけを検査する。
        #expect(!model.continueAfterAd(forGame: model.gameSerial + 1), "番号の違う局へコンティニューを適用している")
        #expect(model.gameOver)
        #expect(!model.continueUsed)
        #expect(model.continueAfterAd(forGame: model.gameSerial), "今の局に対する広告なら適用できる")
        #expect(!model.gameOver)
    }
}
