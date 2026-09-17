import Testing
import CoreGraphics
import GameKitTestSupport
@testable import GameRunner

/// 層の前後関係（#942）。屋根が走者や旗より前に出た不具合の再発防止。
@Suite("シーンの層")
struct SceneLayerTests {
    @Test("層の z は奥から手前へ単調に増え、部品の相対 z より広い間隔を持つ")
    func layersAreSpacedBeyondPartZ() {
        let z = RunnerScene.LayerZ.ordered
        #expect(z == [RunnerScene.LayerZ.clouds, RunnerScene.LayerZ.backdrop, RunnerScene.LayerZ.hills,
                      RunnerScene.LayerZ.course, RunnerScene.LayerZ.player, RunnerScene.LayerZ.effects])
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

    /// 紙吹雪・激突の土煙がシーン直下（z = 6）に置かれ、遠景（100）の後ろに隠れていた（#1069）。
    /// 層は実行では確かめられないので、呼び出しがすべて層を渡していることをソースの形で固定する。
    @Test("土煙・紙吹雪は必ず層を指定して置き、画面固定の演出は走者より手前の層に出す")
    func dustIsPlacedInALayer() throws {
        let source = SourceScan.strippingComments(try SourceScan.moduleSources("GameRunner"))
        // 宣言 1 + 呼び出し 3（紙吹雪・激突・ジャスト着地）。増えたらここで気づく。
        #expect(SourceScan.matchCount(of: #"spawnDust\("#, in: source) == 4)
        // 置く層を省略できない（省略時にシーン直下へ落ちる形を残さない）。
        let dust = try #require(SourceScan.declaration(of: "private func spawnDust(", in: source))
        #expect(source.contains("in parent: SKNode,"))
        #expect(!source.contains("in parent: SKNode?"))
        #expect(!dust.contains("?? self"))
        #expect(dust.contains("parent.addChild(puff)"))

        let confetti = try #require(SourceScan.declaration(of: "private func spawnGoalConfetti()", in: source))
        #expect(confetti.contains("in: effectLayer"))
        let crash = try #require(SourceScan.declaration(of: "private func spawnCrashDust()", in: source))
        #expect(crash.contains("in: effectLayer"))
        let landing = try #require(SourceScan.declaration(of: "private func spawnJustLandingDust(", in: source))
        #expect(landing.contains("in: courseLayer"))

        // 演出層は走者より手前の z を持ち、シーンに載っている。
        #expect(RunnerScene.LayerZ.effects > RunnerScene.LayerZ.player)
        let didMove = try #require(SourceScan.declaration(of: "override func didMove(to view: SKView)", in: source))
        #expect(didMove.contains("effectLayer.zPosition = LayerZ.effects"))
        #expect(didMove.contains("addChild(effectLayer)"))
    }
}
