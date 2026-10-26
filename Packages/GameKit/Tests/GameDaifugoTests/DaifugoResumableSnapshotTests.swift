import Testing
import Foundation
import Core
import CoreEngine
@testable import GameDaifugo
import CoreTestSupport

/// CPU が親で先に出しただけの局は「続きから」にも「途中離脱」にも数えない（#2774。#2508 の大富豪版）。
@Suite("大富豪の「続きから」判定（#2774）")
@MainActor
struct DaifugoResumableSnapshotTests {
    private let module = DaifugoModule()

    private func makeServices(
        store: SnapshotStore, spy: SpyAnalyticsService? = nil
    ) -> GameServices {
        let analytics = spy.map { GameAnalytics(service: $0, allowedGameIDs: ["daifugo"]) }
        return GameServices(
            snapshots: store, ads: NoopAdService(), analytics: analytics,
            isResumable: { _, snapshots in DaifugoModule().hasResumableSnapshot(in: snapshots) }
        )
    }

    /// CPU1 が親で、CPU1〜3 が 1 巡して人間の手番になった局（人間はまだ何もしていない）。
    private func cpuOpenedModel(_ services: GameServices) async -> DaifugoModel {
        let model = DaifugoModel(services: services, cpuDelay: .zero, seed: 42)
        model.configureForTesting(
            hands: [[card(2), card(13)], [card(4), card(5)], [card(6), card(7)], [card(8), card(11)]],
            currentPlayer: 1
        )
        await model.runCPUTurnsIfNeeded()
        return model
    }

    /// 人間が出せる手を 1 つ出す（場に勝つ札のうち最も弱いもの）。
    private func playHuman(_ model: DaifugoModel) {
        guard let play = DaifugoRules.greedyPlay(
            hand: model.playerHand, field: model.field, isRevolution: model.isRevolution
        ) else { return }
        for card in play { model.toggleSelection(card) }
        model.playSelected()
    }

    @Test("CPU が親で先に出しただけの局は続きではなく手つかず。人間が出すと続きになる")
    func cpuOpeningOnlyIsUntouched() async {
        let store = MemorySnapshotStore()
        let model = await cpuOpenedModel(makeServices(store: store))
        #expect(model.isPlayerTurn, "前提: CPU が動いて人間の手番になった")
        #expect(model.field.isEmpty == false, "前提: CPU が出した札が場にある")
        #expect(store.exists(for: "daifugo"), "前提: CPU の手でも中断データは保存される")
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(module.hasUntouchedSnapshot(in: store))

        playHuman(model)
        #expect(module.hasResumableSnapshot(in: store), "人間が出した局（対照）")
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("CPU が先に出した後に人間がパスしても続きになる")
    func humanPassMakesItResumable() async {
        let store = MemorySnapshotStore()
        let model = await cpuOpenedModel(makeServices(store: store))
        #expect(model.canPass, "前提: 場に札があるのでパスできる")
        model.pass()
        #expect(module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("中断データが無ければ続きでも手つかずでもない")
    func noSnapshot() {
        let store = MemorySnapshotStore()
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
    }

    @Test("旧データ（lastActions が無い・壊れている）は従来どおり続きとして扱う")
    func legacySnapshotStaysResumable() {
        #expect(DaifugoSnapshot.humanHasActed(lastActions: nil))
        #expect(DaifugoSnapshot.humanHasActed(lastActions: ["", ""]))
        #expect(!DaifugoSnapshot.humanHasActed(lastActions: ["", "3", "", ""]))
        #expect(DaifugoSnapshot.humanHasActed(lastActions: ["パス", "3", "", ""]))
    }

    @Test("人間未着手のまま離れても途中離脱（game_end quit）に数えない。人間が出した後なら数える")
    func leavingUntouchedIsNotQuit() async {
        let spy = SpyAnalyticsService()
        let store = MemorySnapshotStore()
        let services = makeServices(store: store, spy: spy)
        services.gameDidStart(gameID: "daifugo")
        let model = await cpuOpenedModel(services)
        services.gameDidLeave(gameID: "daifugo")
        #expect(spy.quits.isEmpty, "CPU が出しただけでは離脱に数えない")

        // 手つかずの中断データを開き直すと game_start を数え直す（#2161）。
        services.gameScreenDidAppear(
            gameID: "daifugo", hasUntouchedSnapshot: module.hasUntouchedSnapshot(in: store))
        #expect(spy.starts == ["daifugo", "daifugo"])

        playHuman(model)
        #expect(module.hasResumableSnapshot(in: store))
    }

    @Test("持ち越し（献上免除）の局を CPU が先に出しても免除は消えない（#1103・#1146）")
    func carryOverStillSpentByFirstSave() async {
        let store = MemorySnapshotStore()
        let services = makeServices(store: store)
        let first = DaifugoModel(services: services, cpuDelay: .zero, seed: 42)
        first.configureForTesting(
            hands: [[card(3), card(4)], [card(5)], [card(9)], [card(10)]], currentPlayer: 0
        )
        first.resign()
        #expect(store.exists(for: "daifugo-carryover"), "前提: 決着の階級を持ち越した")

        let reopened = DaifugoModel(services: services, cpuDelay: .zero, seed: 42)
        reopened.startGame()
        #expect(!module.hasResumableSnapshot(in: store), "配ったばかりは続きではない")
        #expect(store.exists(for: "daifugo-carryover"), "1 手も保存されていないので持ち越しは残る")
    }
}
