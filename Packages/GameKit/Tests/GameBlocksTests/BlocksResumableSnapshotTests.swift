import Testing
import Foundation
import Core
import CoreTestSupport
@testable import GameBlocks

/// 1 面の頭の手つかずの状態は「続きから」に出さない（#1912）。2 面以降・残機減・得点ありは進行。
@Suite("ブロック崩しの「続きから」判定（#1912）")
@MainActor
struct BlocksResumableSnapshotTests {
    private func resumable(stage: Int, score: Int = 0, lives: Int = BlocksRules.initialLives) -> Bool {
        let store = MemorySnapshotStore()
        let defaults = UserDefaults(suiteName: "asobiba.blocks.tests.resumable")!
        defaults.removePersistentDomain(forName: "asobiba.blocks.tests.resumable")
        let preference = FeedbackPreference(key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false)
        _ = BlocksModel(
            services: GameServices(snapshots: store, ads: NoopAdService()),
            startingAt: stage, score: score, lives: lives, preference: preference
        )
        return BlocksModule().hasResumableSnapshot(in: store)
    }

    @Test("1 面の頭は続きではない")
    func firstStageUntouched() {
        #expect(!resumable(stage: 1))
    }

    @Test("2 面以降・残機が減った・得点がある状態は続き（対照）")
    func progressIsResumable() {
        #expect(resumable(stage: 2))
        #expect(resumable(stage: 1, lives: BlocksRules.initialLives - 1))
        #expect(resumable(stage: 1, score: 100))
    }
}
