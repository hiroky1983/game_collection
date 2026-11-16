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

    /// `game_start` / `game_end` に載った `mode`（#3517）。
    private func modes(_ spy: SpyAnalyticsService) -> (starts: [AnalyticsMode?], ends: [AnalyticsMode?]) {
        var starts: [AnalyticsMode?] = [], ends: [AnalyticsMode?] = []
        for event in spy.events {
            switch event {
            case let .gameStart(_, _, mode, _, _): starts.append(mode)
            case let .gameEnd(_, _, _, mode, _, _, _, _, _, _, _, _): ends.append(mode)
            default: break
            }
        }
        return (starts, ends)
    }

    @Test("かたちを替えて始めると game_start の mode が変わり、game_end には開始時の mode が載る（#3517）")
    func modeFollowsChosenLayout() {
        let (model, spy) = makeModel(defers: true)
        model.newGame(layout: .cross)
        // 取れる 1 組を取って「始めたプレイ」にする（取れない牌は拒否されるだけで手に数えない）。
        let pair = MahjongSolitaireRules.availablePairs(faces: model.faces, layout: model.layout)[0]
        model.tap(pair.0)
        model.tap(pair.1)
        model.newGame(layout: .pyramid)
        let result = modes(spy)
        #expect(result.starts == [.some(.cross), .some(.pyramid)])
        // 捨てた 1 つ目のプレイは開始時の値（十字）のまま game_end(quit) になる。
        #expect(result.ends.first == .some(.cross))
    }

    @Test("シートを経ない初回開始は既定の亀甲を mode に載せ、シートを閉じたときの開始も同じ値（#3517）")
    func initialStartCarriesDefaultLayout() {
        let (direct, directSpy) = makeModel(defers: false)
        _ = direct
        #expect(modes(directSpy).starts == [.some(.turtle)])
        let (deferred, deferredSpy) = makeModel(defers: true)
        deferred.startPlayIfPending()
        #expect(modes(deferredSpy).starts == [.some(.turtle)])
    }
}
