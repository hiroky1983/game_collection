import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameMahjongSolitaire

/// 「戻す」で全牌が戻ったら、離脱の印も戻す（#3458）。
@Suite("麻雀ソリティア 戻すと離脱の印（#3458）")
@MainActor
struct MahjongSolitaireUndoQuitTests {
    private func makeServices(_ spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(), feedback: SpyFeedbackService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: [MahjongSolitaireModel.snapshotID])
        )
    }

    private func take(_ model: MahjongSolitaireModel, pairs: Int) {
        for pair in model.solution.prefix(pairs) {
            model.tap(pair[0])
            model.tap(pair[1])
        }
    }

    @Test("1 組取って「戻す」で全牌が戻ったら、離れても離脱に数えない")
    func undoToFullBoardIsNotQuit() {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        services.gameDidStart(gameID: MahjongSolitaireModel.snapshotID)
        let model = MahjongSolitaireModel(services: services, seed: 3458)
        take(model, pairs: 1)
        #expect(model.undoLastTake())
        #expect(model.remainingCount == model.layout.count, "前提: 全牌が戻った")
        services.analytics?.leaveGame(gameID: MahjongSolitaireModel.snapshotID, isResumable: false)
        #expect(spy.quits.isEmpty)
    }

    @Test("2 組取って 1 組だけ戻したら、離れると離脱に数える（対照）")
    func partialUndoStaysQuit() {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy)
        services.gameDidStart(gameID: MahjongSolitaireModel.snapshotID)
        let model = MahjongSolitaireModel(services: services, seed: 3458)
        take(model, pairs: 2)
        #expect(model.undoLastTake())
        #expect(model.remainingCount < model.layout.count)
        services.analytics?.leaveGame(gameID: MahjongSolitaireModel.snapshotID, isResumable: false)
        #expect(spy.quits.map(\.gameID) == [MahjongSolitaireModel.snapshotID])
    }
}
