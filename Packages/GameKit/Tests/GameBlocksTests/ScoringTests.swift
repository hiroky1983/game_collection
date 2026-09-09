import Foundation
import Testing
@testable import GameBlocks

/// 配点（#463）。式と値をここで固定し、調整したくなったときに影響範囲が見えるようにする。
@Suite("ブロック崩しの配点")
struct ScoringTests {

    @Test("ステージ倍率は3面ごとに1段上がり、最終面でも4倍で頭打ち")
    func stageMultiplierSteps() {
        let expected: [Int: Int] = [
            1: 1, 2: 1, 3: 1,
            4: 2, 5: 2, 6: 2,
            7: 3, 8: 3, 9: 3,
            10: 4, 11: 4, 12: 4,
        ]
        for (stage, multiplier) in expected {
            #expect(
                BlocksScoring.stageMultiplier(stage: stage) == multiplier,
                "ステージ\(stage) の倍率が \(BlocksScoring.stageMultiplier(stage: stage))"
            )
        }
        #expect(BlocksScoring.stageMultiplier(stage: 0) == 1, "不正な値でも 1 を下回らない")
        #expect(BlocksScoring.stageMultiplier(stage: -5) == 1)
    }

    @Test("通常ブロックは壊したときだけ点が入る")
    func normalBlockPoints() {
        #expect(BlocksScoring.blockPoints(kind: .normal, destroyed: true, stage: 1) == 10)
        #expect(BlocksScoring.blockPoints(kind: .normal, destroyed: false, stage: 1) == 0)
        #expect(BlocksScoring.blockPoints(kind: .normal, destroyed: true, stage: 12) == 40)
    }

    @Test("硬いブロックは当てた時点でも点が入り、壊すとさらに入る")
    func hardBlockPoints() {
        #expect(BlocksScoring.blockPoints(kind: .hard, destroyed: false, stage: 1) == 5)
        #expect(BlocksScoring.blockPoints(kind: .hard, destroyed: true, stage: 1) == 30)
        // 硬いブロック 1 個を壊し切るまでの合計（1 回目 + 2 回目）。
        let total = BlocksScoring.blockPoints(kind: .hard, destroyed: false, stage: 4)
            + BlocksScoring.blockPoints(kind: .hard, destroyed: true, stage: 4)
        #expect(total == 70)
    }

    @Test("壊れないブロックは何度当てても0点（当て続けて稼げない）")
    func solidBlockGivesNothing() {
        for stage in 1...BlocksRules.stageCount {
            #expect(BlocksScoring.blockPoints(kind: .solid, destroyed: false, stage: stage) == 0)
            #expect(BlocksScoring.blockPoints(kind: .solid, destroyed: true, stage: stage) == 0)
        }
    }

    @Test("ステージクリアのボーナスは番号と残機で増える")
    func stageClearBonus() {
        #expect(BlocksScoring.stageClearBonus(stage: 1, remainingLives: 3) == 100 + 150)
        #expect(BlocksScoring.stageClearBonus(stage: 12, remainingLives: 0) == 1_200)
        #expect(
            BlocksScoring.stageClearBonus(stage: 5, remainingLives: 2)
                > BlocksScoring.stageClearBonus(stage: 5, remainingLives: 1),
            "残機が多いほど高い"
        )
        #expect(BlocksScoring.stageClearBonus(stage: 3, remainingLives: -1) == 300,
                "残機が負でも減点しない")
    }
}
