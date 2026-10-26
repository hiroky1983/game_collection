import Testing
import Core
import CoreTestSupport
@testable import GameBlackjack

/// ハブのタイルに出す進み具合（#2870）。
@Suite("ブラックジャックの中断データの進み具合（#2870）")
@MainActor
struct BlackjackResumeProgressTests {
    @Test("10 回勝負は「n/10回目」、単発戦は出さない")
    func tenRoundsOnly() {
        let store = MemorySnapshotStore()
        let module = BlackjackModule()
        try? store.save(blackjackSnapshot(player: [5, 6], dealer: [10], deck: [2, 3], completedRounds: 2), for: module.id)
        #expect(module.resumeProgress(in: store) == "3/10回目")
        try? store.save(blackjackSnapshot(player: [5, 6], dealer: [10], deck: [2, 3], format: .single), for: module.id)
        #expect(module.resumeProgress(in: store) == nil)
    }
}
