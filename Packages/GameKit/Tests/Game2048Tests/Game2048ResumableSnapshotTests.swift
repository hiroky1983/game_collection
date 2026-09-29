import Testing
import Core
import CoreTestSupport
@testable import Game2048

/// 一度も動かしていない盤は「続きから」に出さない（#1572）。
@Suite("2048 の「続きから」判定（#1572）")
@MainActor
struct Game2048ResumableSnapshotTests {
    @Test("開いただけの盤は続きではなく、一手動かすと続きになる")
    func untouchedBoardIsNotResumable() {
        let store = MemorySnapshotStore()
        let module = Game2048Module()
        let model = Game2048Model(services: GameServices(snapshots: store, ads: NoopAdService()))
        #expect(!module.hasResumableSnapshot(in: store), "手つかずの盤")
        let before = model.board
        for direction in [Direction.left, .up, .right, .down] where model.board == before {
            model.move(direction)
        }
        #expect(model.board != before)
        #expect(module.hasResumableSnapshot(in: store), "一手動かした盤（対照）")
    }

    @Test("得点があれば続き・中断データが無ければ続きではない")
    func scoredBoardAndMissingSnapshot() {
        let store = MemorySnapshotStore()
        let module = Game2048Module()
        #expect(!module.hasResumableSnapshot(in: store))
        _ = Game2048Model(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            board: [[2, 0, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 4)
        #expect(module.hasResumableSnapshot(in: store))
    }
}
