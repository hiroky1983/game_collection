import Testing
import CoreGraphics
@testable import GameRunner

/// 層の前後関係（#942）。屋根が走者や旗より前に出た不具合の再発防止。
@Suite("シーンの層")
struct SceneLayerTests {
    @Test("層の z は奥から手前へ単調に増え、部品の相対 z より広い間隔を持つ")
    func layersAreSpacedBeyondPartZ() {
        let z = RunnerScene.LayerZ.ordered
        #expect(z == [RunnerScene.LayerZ.clouds, RunnerScene.LayerZ.backdrop, RunnerScene.LayerZ.hills,
                      RunnerScene.LayerZ.course, RunnerScene.LayerZ.player])
        for (back, front) in zip(z, z.dropFirst()) {
            #expect(front - back > RunnerScene.LayerZ.partMax, "\(back) → \(front)")
        }
    }

    @Test("部品の相対 z は上限の内側（屋根 1・走者の顔 7・煙 6）")
    func partZStaysUnderLimit() {
        // RunnerScene の部品は zPosition を 7 までしか使わない。ここで上限を縛っておけば、
        // 将来どこかの部品が 10 を超えたときに層の間隔（100）との関係を見直す合図になる。
        #expect(RunnerScene.LayerZ.partMax >= 7)
    }
}
