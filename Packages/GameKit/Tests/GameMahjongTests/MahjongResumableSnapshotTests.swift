import Testing
import Core
import CoreTestSupport
@testable import GameMahjong

/// 配牌のまま 1 枚も切っていない 1 局目は「続きから」に出さない（#2542）。
@Suite("麻雀の「続きから」判定（#2542）")
@MainActor
struct MahjongResumableSnapshotTests {
    private func started(store: MemorySnapshotStore, length: MahjongGameLength = .tonpuu) -> MahjongModel {
        let model = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            cpuDelay: .zero,
            seed: 2026
        )
        model.startGame(length: length)
        return model
    }

    @Test("配牌直後は保存されるが続きではなく、同じ配牌のまま開き直せる")
    func dealtHandIsUntouched() {
        let store = MemorySnapshotStore()
        let module = MahjongModule()
        let model = started(store: store)
        #expect(store.exists(for: module.id), "配った直後に保存はされる（前提）")
        #expect(!module.hasResumableSnapshot(in: store))
        #expect(module.hasUntouchedSnapshot(in: store))

        let reopened = MahjongModel(
            services: GameServices(snapshots: store, ads: NoopAdService()), cpuDelay: .zero, seed: 1
        )
        #expect(reopened.hands == model.hands, "保存は残っているので同じ配牌に戻る")
    }

    @Test("一局戦でも配牌直後は続きではない")
    func singleHandIsUntouched() {
        let store = MemorySnapshotStore()
        _ = started(store: store, length: .singleHand)
        #expect(!MahjongModule().hasResumableSnapshot(in: store))
        #expect(MahjongModule().hasUntouchedSnapshot(in: store))
    }

    @Test("1 枚切ると続きになる")
    func afterDiscardIsResumable() throws {
        let store = MemorySnapshotStore()
        let module = MahjongModule()
        let model = started(store: store)
        let tile = try #require(model.discardableTiles.first)
        model.discard(tile)
        #expect(module.hasResumableSnapshot(in: store))
        #expect(!module.hasUntouchedSnapshot(in: store))
    }
}
