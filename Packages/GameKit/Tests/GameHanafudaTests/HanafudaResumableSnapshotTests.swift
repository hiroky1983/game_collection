import Testing
import Core
import CoreTestSupport
@testable import GameHanafuda

/// 配っただけで一枚も出していない対局は「続きから」に出さない（#1912）。
@Suite("花札の「続きから」判定（#1912）")
@MainActor
struct HanafudaResumableSnapshotTests {
    private func started(dealer: HanafudaPlayer, store: MemorySnapshotStore) throws -> HanafudaModel {
        for seed in UInt64(1)...200 {
            let model = HanafudaModel(services: makeServices(store: store), cpuDelay: .zero, seed: seed)
            model.startMatch(options: HanafudaOptions())
            if model.dealer == dealer { return model }
            store.clear(for: HanafudaModel.gameID)
        }
        throw HanafudaSeedNotFound()
    }

    private struct HanafudaSeedNotFound: Error {}

    @Test("親が人間: 配っただけでは続きではなく、1 枚出すと続きになる")
    func humanDealerUntouched() throws {
        let store = MemorySnapshotStore()
        let module = HanafudaModule()
        let model = try started(dealer: .human, store: store)
        #expect(store.exists(for: module.id), "配った直後に保存はされる（前提）")
        #expect(!module.hasResumableSnapshot(in: store), "配っただけ")

        let card = try #require(model.humanHand.first { model.canPlay($0) })
        model.play(card)
        #expect(module.hasResumableSnapshot(in: store), "出した盤（対照）")
    }

    @Test("親が CPU: CPU が出す前の盤は続きではない")
    func cpuDealerUntouched() throws {
        let store = MemorySnapshotStore()
        _ = try started(dealer: .cpu, store: store)
        #expect(!HanafudaModule().hasResumableSnapshot(in: store))
    }
}
