import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameChess

/// 開始シートを出す局の `game_start` は 1 局につき 1 回（#1372）。
/// `init` の数え込みと、シートで「開始」を押した `newGame` の数え込みが二重にならないこと。
@MainActor
@Suite("チェス game_start の回数（#1372）")
struct ChessStartCountTests {

    private func makeModel() -> (ChessGameModel, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["chess"])
        let services = GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService(), analytics: analytics)
        return (ChessGameModel(services: services), spy)
    }

    @Test("開いただけでは数えず、シートで開始すると 1 回だけ数える")
    func sheetStartCountsOnce() {
        let (model, spy) = makeModel()
        #expect(spy.starts.isEmpty)
        model.newGame()
        #expect(spy.starts.count == 1)
        model.startPlayIfPending()
        #expect(spy.starts.count == 1)
    }

    @Test("シートを閉じて遊んだ局は 1 回だけ数える（強さは載らない）")
    func dismissedSheetCountsOnce() {
        let (model, spy) = makeModel()
        model.startPlayIfPending()
        model.startPlayIfPending()
        #expect(spy.starts.count == 1)
        #expect(spy.startLevels.first.map { $0 == nil } == true)
    }

    @Test("シートを閉じずに最初の 1 手を指しても、game_start は 1 回だけ")
    func firstMoveWithoutClosingSheetCountsOnce() throws {
        let (model, spy) = makeModel()
        model.tapSquare(try #require(ChessSquare.fromName("e2")))
        model.tapSquare(try #require(ChessSquare.fromName("e4")))
        #expect(spy.starts.count == 1)
        model.startPlayIfPending()
        #expect(spy.starts.count == 1)
    }
}
