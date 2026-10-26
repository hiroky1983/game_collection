import Testing
import Core
import CoreTestSupport
@testable import GamePoker

/// ハブのタイルに出す進み具合（#2870）。
@Suite("ポーカーの中断データの進み具合（#2870）")
@MainActor
struct PokerResumeProgressTests {
    @Test("10 回勝負は「n/10回目」、単発戦は出さない")
    func tenRoundsOnly() {
        let store = MemorySnapshotStore()
        let module = PokerModule()
        let model = PokerModel(services: GameServices(snapshots: store, ads: PokerStubAdService()))
        model.startGame()
        #expect(module.resumeProgress(in: store) == "1/10回目")
        let singleStore = MemorySnapshotStore()
        let single = PokerModel(services: GameServices(snapshots: singleStore, ads: PokerStubAdService()))
        single.startGame(format: .single)
        #expect(module.resumeProgress(in: singleStore) == nil)
    }
}
