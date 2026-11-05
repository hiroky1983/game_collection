import Testing
import Core
import CoreTestSupport
@testable import GameOldMaid

/// CPU が先に引いただけの局は「続きから」にも「途中離脱」にも数えない（#3000。#2508・#2774 のババ抜き版）。
@Suite("ババ抜きの「続きから」判定（#3000）")
@MainActor
struct OldMaidResumableSnapshotTests {
    private let module = OldMaidModule()

    private func makeServices(store: SnapshotStore, spy: SpyAnalyticsService? = nil) -> GameServices {
        let analytics = spy.map { GameAnalytics(service: $0, allowedGameIDs: [OldMaidModel.gameID]) }
        return GameServices(
            snapshots: store, ads: NoopAdService(), analytics: analytics,
            isResumable: { _, snapshots in OldMaidModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    /// 2 ゲーム目（先手は CPU1）を配り、CPU が 1 巡してあなたの番になった局。あなたはまだ何もしていない。
    private func cpuOpenedModel(_ services: GameServices) async -> OldMaidModel {
        let model = OldMaidModel(services: services, cpuDelay: .zero, seed: 42)
        model.startGame()
        model.startGame()
        await model.runCPUTurnsIfNeeded()
        return model
    }

    @Test("CPU が先に引いただけの局は続きではない。あなたが引くと続きになる")
    func cpuOpeningOnlyIsUntouched() async throws {
        let store = MemorySnapshotStore()
        let model = await cpuOpenedModel(makeServices(store: store))
        try #require(model.phase == .playing && model.isPlayerTurn)
        #expect(model.gameNumber == 2)
        #expect(store.exists(for: module.id), "CPU の手も保存はされる（前提）")
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(module.hasUntouchedSnapshot(in: store))

        let target = try #require(model.humanTarget)
        model.toggleSelection(model.hands[target][0].id)
        model.drawSelected()
        guard model.phase == .playing else { return }
        #expect(module.hasResumableSnapshot(in: store), "あなたが引いた盤（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("保存が無ければどちらも false")
    func noSnapshot() {
        let store = MemorySnapshotStore()
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("未着手のまま離れても途中離脱（game_end quit）に数えない")
    func leavingUntouchedIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(store: MemorySnapshotStore(), spy: spy)
        services.gameDidStart(gameID: OldMaidModel.gameID)
        _ = await cpuOpenedModel(services)
        services.gameDidLeave(gameID: OldMaidModel.gameID)
        #expect(spy.quits.isEmpty, "CPU が引いただけでは離脱に数えない（数えると離脱が休憩側に偏る）")
    }
}
