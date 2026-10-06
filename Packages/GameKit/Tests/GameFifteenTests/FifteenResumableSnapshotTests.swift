import Testing
import Core
import CoreTestSupport
@testable import GameFifteen

/// 一手も動かしていない盤は「続きから」に出さない（#1847）。
@Suite("15パズルの「続きから」判定（#1847）")
@MainActor
struct FifteenResumableSnapshotTests {
    @Test("開いただけでは続きではなく、タイルを動かすと続きになる")
    func untouchedBoardIsNotResumable() throws {
        let store = MemorySnapshotStore()
        let module = FifteenModule()
        let model = FifteenModel(services: GameServices(snapshots: store, ads: NoopAdService()), seed: 7)
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        let index = try #require(model.tiles.indices.first { FifteenLogic.slide(model.tiles, at: $0) != nil })
        model.tap(at: index)
        #expect(module.hasResumableSnapshot(in: store), "動かした盤（対照）")
    }
}
