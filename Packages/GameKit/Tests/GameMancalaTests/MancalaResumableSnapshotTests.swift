import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameMancala

/// CPU が先に打っただけの局は「続きから」にも「途中離脱」にも数えない（#2934。#2508 のマンカラ版）。
@Suite("マンカラの「続きから」判定（#2934）")
@MainActor
struct MancalaResumableSnapshotTests {
    private let module = MancalaModule()

    private func makeServices(store: SnapshotStore, spy: SpyAnalyticsService? = nil) -> GameServices {
        let analytics = spy.map { GameAnalytics(service: $0, allowedGameIDs: ["mancala"]) }
        return GameServices(
            snapshots: store, ads: NoopAdService(), analytics: analytics,
            isResumable: { _, snapshots in MancalaModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    /// CPU が打つ手番が続くあいだ（もう一度を含む）進める。
    private func playCPUTurn(_ model: MancalaModel) async {
        var guardCount = 0
        while !model.gameOver, model.isAITurn, guardCount < 40 {
            guardCount += 1
            await model.performAIMoveIfNeeded()
        }
    }

    @Test("人間が後手のとき、CPU の初手だけでは続きではなく手つかず。自分が打つと続きになる")
    func secondAfterCPUOpeningIsNotResumable() async {
        let store = MemorySnapshotStore()
        let model = MancalaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 1)
        model.newGame(humanFirst: false)
        await playCPUTurn(model)
        #expect(!model.isAITurn && model.turnID > 0, "前提: CPU が打って人間の番になった")
        #expect(store.exists(for: "mancala"), "前提: CPU の手でも中断データは保存される")
        #expect(!module.hasResumableSnapshot(in: store), "CPU の初手だけ")
        #expect(module.hasUntouchedSnapshot(in: store))
        model.tap(pit: model.legalPits[0])
        #expect(module.hasResumableSnapshot(in: store), "自分が打った盤（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("人間が先手なら、自分の初手で続きになる")
    func firstIsResumableAfterFirstMove() {
        let store = MemorySnapshotStore()
        let model = MancalaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 1)
        model.newGame(humanFirst: true)
        #expect(!module.hasResumableSnapshot(in: store))
        model.tap(pit: 2)
        #expect(module.hasResumableSnapshot(in: store))
    }

    @Test("後手で一手打ってから「待った」で戻しても、使用済みの印が残るので続きとして残す")
    func undoKeepsItResumable() async {
        let store = MemorySnapshotStore()
        let model = MancalaModel(services: makeServices(store: store), cpuDelay: .zero, seed: 1)
        model.newGame(humanFirst: false)
        await playCPUTurn(model)
        model.tap(pit: model.legalPits[0])
        await playCPUTurn(model)
        #expect(model.canUndo)
        model.undoLastExchange()
        #expect(module.hasResumableSnapshot(in: store))
    }

    @Test("CPU の初手だけで離れても途中離脱に数えない")
    func leavingUntouchedIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = makeServices(store: store, spy: spy)
        services.gameDidStart(gameID: "mancala")
        let model = MancalaModel(services: services, cpuDelay: .zero, seed: 1)
        model.newGame(humanFirst: false)
        await playCPUTurn(model)
        services.gameDidLeave(gameID: "mancala")
        #expect(spy.quits.isEmpty, "CPU が打っただけでは離脱に数えない")
    }

    @Test("自分が打った後に離れると進行済みの盤を再開できない形で離れると途中離脱に数える（対照・上のテストが空振りでない証拠）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(store: MemorySnapshotStore(), spy: spy)
        services.gameDidStart(gameID: "mancala")
        let model = MancalaModel(services: services, cpuDelay: .zero, seed: 1)
        model.newGame(humanFirst: false)
        await playCPUTurn(model)
        model.tap(pit: model.legalPits[0])
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "mancala", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["mancala"])
    }
}
