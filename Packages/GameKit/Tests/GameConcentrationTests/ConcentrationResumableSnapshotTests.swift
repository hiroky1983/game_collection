import Testing
import Core
import CoreTestSupport
@testable import GameConcentration

/// 一枚もめくっていない盤は「続きから」に出さない（#1847）。
@Suite("神経衰弱の「続きから」判定（#1847）")
@MainActor
struct ConcentrationResumableSnapshotTests {
    @Test("開いただけでは続きではなく、一枚めくると続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = ConcentrationModule()
        let model = ConcentrationModel(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "開いただけ")
        model.newGame(pairCount: .medium, cpuLevel: .normal)
        #expect(!module.hasResumableSnapshot(in: store), "新規対局を始めただけ")
        model.tap(index: 0)
        #expect(module.hasResumableSnapshot(in: store), "一枚めくった盤（対照）")
    }
}
