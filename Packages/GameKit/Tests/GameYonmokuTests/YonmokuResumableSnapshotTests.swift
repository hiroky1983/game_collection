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
