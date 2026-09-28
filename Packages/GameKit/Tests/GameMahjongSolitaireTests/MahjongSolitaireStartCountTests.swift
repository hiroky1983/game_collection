import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameMahjongSolitaire

/// 開始シートを出す初回の `game_start` は 1 プレイにつき 1 回（囲碁 #1372 と同じ契約）。
/// `init` の数え込みと、シートで別のかたちを選んだ `newGame` の数え込みが二重にならないこと。
@MainActor
@Suite("麻雀ソリティア game_start の回数（開始シート）")
struct MahjongSolitaireStartCountTests {

    private func makeModel(defers: Bool, store: MemorySnapshotStore = MemorySnapshotStore())
        -> (MahjongSolitaireModel, SpyAnalyticsService) {
        let spy = SpyAnalyticsService()
        let analytics = GameAnalytics(service: spy, allowedGameIDs: ["mahjong"])
        let services = GameServices(snapshots: store, ads: NoopAdService(), analytics: analytics)
        return (MahjongSolitaireModel(services: services, seed: 1, defersInitialStart: defers), spy)
    }

    @Test("開いただけでは数えず、シートで別のかたちを選んで始めると 1 回だけ数える")
    func sheetStartWithOtherLayoutCountsOnce() {
        let (model, spy) = makeModel(defers: true)
        #expect(spy.starts.isEmpty)
        model.newGame(layout: .pyramid)
        #expect(spy.starts.count == 1)
        // シートを閉じたときの呼び出しは何もしない。
        model.startPlayIfPending()
        #expect(spy.starts.count == 1)
    }

    @Test("シートを閉じて（または同じかたちで始めて）遊んだプレイは 1 回だけ数える")
    func dismissedSheetCountsOnce() {
        let (model, spy) = makeModel(defers: true)
        model.startPlayIfPending()
        model.startPlayIfPending()
        model.tap(0)
        #expect(spy.starts.count == 1)
    }

    @Test("シートを出さないとき（既定）は init で 1 回数える")
    func noSheetCountsInInit() {
        let (model, spy) = makeModel(defers: false)
        #expect(spy.starts.count == 1)
        model.startPlayIfPending()
        #expect(spy.starts.count == 1)
    }
}
