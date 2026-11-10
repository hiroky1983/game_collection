import Testing
import Core
@testable import GameChess

/// 「チェック」の札を固定待ちより早く畳む契機（将棋 #519 の取りこぼし。#3402）。
@MainActor
@Suite("チェス 札を畳む契機（#3402）")
struct ChessCheckBannerDismissTests {

    private func playExchange(_ model: ChessGameModel, _ uci: String) async throws {
        let move = try #require(ChessMove.fromUCI(uci))
        model.tapSquare(move.from)
        model.tapSquare(move.to)
        await model.performAIMoveIfNeeded()
    }

    @Test("待ったで契機が進み、着手・検討ナビでは進まない")
    func undoDismissesButMovesDoNot() async throws {
        let model = ChessGameModel(services: nil)
        model.hintThinkingScaleForTesting = 0.05
        model.newGame()
        let base = model.checkBannerDismissID
        try await playExchange(model, "e2e4")
        #expect(model.checkBannerDismissID == base, "着手で札を畳んでいる")

        try #require(model.canUndo)
        model.undoLastExchange()
        #expect(model.checkBannerDismissID == base + 1, "待ったで札を畳む契機が増えていない")

        try await playExchange(model, "d2d4")
        model.reviewGoTo(ply: 0)
        #expect(model.checkBannerDismissID == base + 1, "検討ナビで札を畳んでいる")
    }

    @Test("投了・新規対局で契機が進み、巻き戻らない")
    func resignAndNewGameDismissMonotonically() async throws {
        let model = ChessGameModel(services: nil)
        model.hintThinkingScaleForTesting = 0.05
        model.newGame()
        let base = model.checkBannerDismissID
        model.resign()
        #expect(model.checkBannerDismissID == base + 1, "投了で札を畳む契機が増えていない")
        model.newGame()
        #expect(model.checkBannerDismissID == base + 2, "新規対局で札を畳む契機が増えていない")
    }
}
