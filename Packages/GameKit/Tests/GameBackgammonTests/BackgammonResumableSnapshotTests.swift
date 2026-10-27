import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameBackgammon

/// CPU が先手で動いただけの局は「続きから」にも「途中離脱」にも数えない（#2934。#2508 のバックギャモン版）。
@Suite("バックギャモンの「続きから」判定（#2934）")
@MainActor
struct BackgammonResumableSnapshotTests {
    private let module = BackgammonModule()

    private func makeServices(store: SnapshotStore, spy: SpyAnalyticsService? = nil) -> GameServices {
        let analytics = spy.map { GameAnalytics(service: $0, allowedGameIDs: ["backgammon"]) }
        return GameServices(
            snapshots: store, ads: NoopAdService(), analytics: analytics,
            isResumable: { _, snapshots in BackgammonModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    /// CPU（黒）が先手で目を使い切り、人間の番になった局。
    private func cpuOpenedModel(_ services: GameServices) async -> BackgammonModel {
        let model = BackgammonModel(services: services, cpuDelay: .zero, seed: 3)
        model.configureForTesting(board: BackgammonBoard(), side: .black, roll: (6, 5))
        await model.performAIMoveIfNeeded()
        await model.performAIMoveIfNeeded()
        return model
    }

    /// 人間が動かせる駒を 1 手動かす。
    private func playHuman(_ model: BackgammonModel) {
        guard let move = model.legalMoves.first else { return }
        model.tap(move.from)
        model.tap(move.to)
    }

    @Test("CPU が先手で動いただけの局は続きではなく手つかず。人間が動かすと続きになる")
    func cpuOpeningOnlyIsUntouched() async {
        let store = MemorySnapshotStore()
        let model = await cpuOpenedModel(makeServices(store: store))
        #expect(!model.isAITurn && !model.legalMoves.isEmpty, "前提: CPU が動いて人間の番になった")
        #expect(store.exists(for: "backgammon"), "前提: CPU の手でも中断データは保存される")
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(module.hasUntouchedSnapshot(in: store))

        playHuman(model)
        #expect(module.hasResumableSnapshot(in: store), "人間が動かした局（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("人間が動かした後に CPU が応じた局は続き。鍵を持たない旧形式も続きとして読む")
    func humanMovedAndLegacySnapshot() throws {
        let store = MemorySnapshotStore()
        let model = BackgammonModel(services: makeServices(store: store), cpuDelay: .zero, seed: 1)
        model.configureForTesting(board: BackgammonBoard(), side: .white, roll: (3, 1))
        playHuman(model)
        #expect(module.hasResumableSnapshot(in: store))

        // `humanMoved` を持たない旧形式（鍵を消した JSON）。
        let data = try #require(store.rawData(for: "backgammon"))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "humanMoved")
        store.inject(try JSONSerialization.data(withJSONObject: json), for: "backgammon")
        #expect(module.hasResumableSnapshot(in: store), "旧形式は従来どおり続き")
    }

    @Test("CPU が先手で動いただけで離れても途中離脱に数えない")
    func leavingUntouchedIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = makeServices(store: store, spy: spy)
        services.gameDidStart(gameID: "backgammon")
        let model = await cpuOpenedModel(services)
        services.gameDidLeave(gameID: "backgammon")
        #expect(spy.quits.isEmpty, "CPU が動いただけでは離脱に数えない")
    }

    @Test("人間が動かした後に離れると進行済みの盤を再開できない形で離れると途中離脱に数える（対照・上のテストが空振りでない証拠）")
    func leavingAfterHumanMoveIsQuit() async {
        let spy = SpyAnalyticsService()
        let services = makeServices(store: MemorySnapshotStore(), spy: spy)
        services.gameDidStart(gameID: "backgammon")
        let model = await cpuOpenedModel(services)
        playHuman(model)
        // 再開できない盤として離れる（`game_end` quit は「進行済みで再開できない」ときだけ送られる）。
        services.analytics?.leaveGame(gameID: "backgammon", isResumable: false)
        #expect(spy.quits.map(\.gameID) == ["backgammon"])
    }
}
