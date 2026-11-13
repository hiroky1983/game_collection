import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameYonmoku

/// CPU が先に打っただけの局は「続きから」にも「途中離脱」にも数えない（#2934。#2508 の四目並べ版）。
@Suite("四目並べの「続きから」判定（#2934）")
@MainActor
struct YonmokuResumableSnapshotTests {
    private let module = YonmokuModule()

    private func makeServices(store: SnapshotStore, spy: SpyAnalyticsService? = nil) -> GameServices {
        let analytics = spy.map { GameAnalytics(service: $0, allowedGameIDs: ["yonmoku"]) }
        return GameServices(
            snapshots: store, ads: NoopAdService(), analytics: analytics,
            isResumable: { _, snapshots in YonmokuModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    @Test("人間が白のとき、CPU の初手だけでは続きではなく手つかず。自分が打つと続きになる")
    func whiteAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let model = YonmokuModel(services: makeServices(store: store), cpuDelay: .zero, seed: 1)
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        #expect(!model.isAITurn && model.lastMove != nil, "前提: CPU が初手を打った")
        #expect(store.exists(for: "yonmoku"), "前提: CPU の手でも中断データは保存される")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store))
        model.tap(column: 0)
        #expect(module.hasResumableSnapshot(in: store), "自分が打った盤（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("人間が黒なら、自分の初手で続きになる")
    func blackIsResumableAfterFirstMove() {
        let store = MemorySnapshotStore()
        let model = YonmokuModel(services: makeServices(store: store), cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .black)
        #expect(!module.hasResumableSnapshot(in: store))
        model.tap(column: 3)
        #expect(module.hasResumableSnapshot(in: store))
    }

    @Test("CPU の初手だけで離れても途中離脱に数えない")
    func leavingUntouchedIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = makeServices(store: store, spy: spy)
        services.gameDidStart(gameID: "yonmoku")
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        services.gameDidLeave(gameID: "yonmoku")
        #expect(spy.quits.isEmpty, "CPU が打っただけでは離脱に数えない")
    }

    @Test("自分が打った後に離れると進行済みの盤を再開できない形で離れると途中離脱に数える（対照・上のテストが空振りでない証拠）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(store: MemorySnapshotStore(), spy: spy)
        services.gameDidStart(gameID: "yonmoku")
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        model.tap(column: 0)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "yonmoku", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["yonmoku"])
    }
}

/// 「待った」で開始局面まで戻したら離脱の印も戻す（#3398。#3133・#3200 で四目並べだけ取りこぼした）。
@Suite("四目並べの「待った」と離脱の印（#3398）")
@MainActor
struct YonmokuUndoToStartTests {
    private func makeServices(spy: SpyAnalyticsService) -> GameServices {
        GameServices(
            snapshots: MemorySnapshotStore(), ads: NoopAdService(),
            analytics: GameAnalytics(service: spy, allowedGameIDs: ["yonmoku"]),
            isResumable: { _, snapshots in YonmokuModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    @Test("黒で 1 手指して「待った」で 0 手に戻したら、離れても離脱に数えない")
    func blackUndoToStartIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy: spy)
        services.gameDidStart(gameID: "yonmoku")
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .black)
        model.tap(column: 3)
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo, "前提: 1 往復指して待ったを押せる")
        model.undoLastExchange()
        #expect(model.lastMove == nil, "前提: 開始局面まで戻った")
        services.analytics?.leaveGame(gameID: "yonmoku", isResumable: false)
        #expect(spy.quits.isEmpty, "指していない盤は離脱に数えない")
    }

    @Test("白で CPU の初手だけまで戻したら離脱に数えない。途中までの戻しなら印は残る")
    func whiteUndoToCPUOpeningClearsButMidGameKeeps() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy: spy)
        services.gameDidStart(gameID: "yonmoku")
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        model.tap(column: 0)
        await model.performAIMoveIfNeeded()
        model.tap(column: 1)
        await model.performAIMoveIfNeeded()
        // 5 手 → 3 手（自分の手が残る）。印は残る。
        model.undoLastExchange()
        services.analytics?.leaveGame(gameID: "yonmoku", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["yonmoku"], "途中までの戻しでは従来どおり数える（対照）")
    }

    @Test("白で 3 手から CPU の初手だけ（1 手）まで戻したら離脱に数えない")
    func whiteUndoToCPUOpeningIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(spy: spy)
        services.gameDidStart(gameID: "yonmoku")
        let model = YonmokuModel(services: services, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        model.tap(column: 0)
        await model.performAIMoveIfNeeded()
        #expect(model.canUndo, "前提: 3 手で待ったを押せる")
        model.undoLastExchange()
        #expect(model.lastMove != nil, "前提: CPU の初手だけが残っている")
        services.analytics?.leaveGame(gameID: "yonmoku", isResumable: false)
        #expect(spy.quits.isEmpty, "CPU の初手だけの盤は離脱に数えない")
    }
}

/// CPU 先手の局で、CPU の初手だけでは「新規」に確認を出さない（#3490）。
@Suite("四目並べ CPU 先手の局の新規対局確認（#3490）")
@MainActor
struct YonmokuCPUOpeningProgressTests {
    @Test("人間が白のとき、CPU の初手だけでは失う進行は無く、自分が打つと進行になる")
    func whiteAfterCPUOpening() async throws {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .white)
        await model.performAIMoveIfNeeded()
        try #require(!model.isAITurn && model.lastMove != nil, "前提: CPU が初手を打った")
        #expect(!model.hasProgressToLose)
        model.tap(column: 0)
        #expect(model.hasProgressToLose)
    }

    @Test("人間が黒のとき、1 手打つまでは無く、打つと進行になる（対照）")
    func blackFirst() {
        let model = YonmokuModel(services: nil, cpuDelay: .zero, seed: 1)
        model.newGame(humanSide: .black)
        #expect(!model.hasProgressToLose)
        model.tap(column: 3)
        #expect(model.hasProgressToLose)
    }
}
