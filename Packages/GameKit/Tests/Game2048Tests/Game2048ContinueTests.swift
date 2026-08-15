import Testing
@testable import Game2048

/// #122: 広告視聴後のコンティニューが「盤面を動かせないまま戻される」不具合の回帰テスト。
/// 復活処理が決定的（乱数なし）になったので、盤面そのものを厳密な期待値で表明できる。
@Suite("2048 コンティニュー（#122）")
@MainActor
struct Game2048ContinueTests {
    /// 終局盤面（空きマス 0・合体可能な隣接 0）。
    static let deadBoard = [
        [2, 4, 8, 4],
        [16, 8, 32, 16],
        [4, 64, 128, 32],
        [16, 8, 4, 8],
    ]

    private func makeFinishedModel(score: Int = 1234) -> Game2048Model {
        let model = Game2048Model(board: Self.deadBoard, score: score)
        #expect(model.gameOver, "前提: 終局している盤面から始める")
        return model
    }

    @Test("コンティニュー直後に必ず動かせる（空きマス4・新タイルは沸かない）")
    func continueLeavesPlayableBoard() {
        let model = makeFinishedModel()
        model.continueAfterAd()

        #expect(!model.gameOver)
        #expect(model.continueUsed)
        #expect(Game2048Logic.emptyCells(model.board).count == 4, "新タイルを置かないので空きは4のまま")
        #expect(Direction.allCases.contains { Game2048Logic.slide(model.board, $0).moved })
    }

    @Test("スコアはコンティニュー前から引き継がれる")
    func continueKeepsScore() {
        let model = makeFinishedModel(score: 4321)
        model.continueAfterAd()
        #expect(model.score == 4321)
    }

    @Test("最大タイルはコンティニューで失われない")
    func continueKeepsHighestTile() {
        let model = makeFinishedModel()
        model.continueAfterAd()
        #expect(model.board.flatMap { $0 }.max() == 128)
    }

    @Test("コンティニューは1回だけ。2回目は盤面もフラグも変えない")
    func continueIsAllowedOnlyOnce() {
        let model = makeFinishedModel()
        model.continueAfterAd()
        let boardAfterFirst = model.board

        // 続きを遊んで再び終局させる。
        playUntilGameOver(model)
        #expect(model.gameOver)
        let boardAtSecondGameOver = model.board

        model.continueAfterAd()
        #expect(model.gameOver, "2回目のコンティニューは成立しない")
        #expect(model.board == boardAtSecondGameOver, "2回目では盤面に手を加えない")
        #expect(boardAfterFirst != boardAtSecondGameOver, "前提: 1回目の後に実際に遊べている")
    }

    @Test("コンティニュー後は最低4手動かせ、そのまま終局まで遊びきれる")
    func continuedGameCanBePlayedToTheEnd() {
        let model = makeFinishedModel()
        model.continueAfterAd()

        let moves = playUntilGameOver(model)
        #expect(moves >= 4, "空きマス4を確保しているので最低4手は保証される（実際は \(moves) 手）")
        #expect(model.gameOver, "終局まで到達できる（無限ループにも詰まりにもならない）")
    }

    /// 動かせる方向が無くなるまで動かし続け、実際に動いた手数を返す。
    /// 新タイルの生成は乱数なので、手数は実行ごとに変わる。
    @discardableResult
    private func playUntilGameOver(_ model: Game2048Model, limit: Int = 10_000) -> Int {
        var moves = 0
        while !model.gameOver, moves < limit {
            guard let direction = Direction.allCases.first(where: {
                Game2048Logic.slide(model.board, $0).moved
            }) else {
                Issue.record("終局していないのに動かせる方向が無い: \(model.board)")
                break
            }
            model.move(direction)
            moves += 1
        }
        #expect(moves < limit, "上限に達した = 終局に到達できていない")
        return moves
    }
}
