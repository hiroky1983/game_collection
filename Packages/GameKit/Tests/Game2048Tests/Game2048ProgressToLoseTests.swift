import Testing
import Core
@testable import Game2048

/// 「リセット」の確認を出すかの境目（#1011）。
@MainActor
@Suite("2048 リセットで失われる進行（#1011）")
struct Game2048ProgressToLoseTests {

    @Test("開始直後（2 枚・得点 0）は失うものが無い")
    func freshBoardHasNothingToLose() {
        let model = Game2048Model(board: [
            [2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
        ])
        #expect(!model.hasProgressToLose)
    }

    @Test("1 手動かして枚数が増えたら失う進行がある")
    func moreTilesMeansProgress() {
        let model = Game2048Model(board: [
            [2, 2, 4, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
        ])
        #expect(model.hasProgressToLose)
    }

    @Test("合体して得点が入っていれば、枚数が 2 枚でも失う進行がある")
    func scoreMeansProgress() {
        let model = Game2048Model(board: [
            [8, 4, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
        ], score: 12)
        #expect(model.hasProgressToLose)
    }

    @Test("詰んだ盤（終局後）は失うものが無い")
    func gameOverHasNothingToLose() throws {
        let model = Game2048Model(board: [
            [2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2],
        ], score: 100)
        try #require(model.gameOver)
        #expect(!model.hasProgressToLose)
    }

    @Test("新規ゲームで開始直後に戻れば、また失うものは無い")
    func newGameResetsProgress() {
        let model = Game2048Model(board: [
            [2, 2, 4, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0],
        ], score: 8)
        model.newGame()
        #expect(!model.hasProgressToLose)
    }
}
