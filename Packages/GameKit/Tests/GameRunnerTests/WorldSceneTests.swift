import Foundation
import SpriteKit
import Testing
@testable import GameRunner

/// 里山・港町（#1009）の着せ替えと遠景を、`RunnerScene` を画面に出さずに組んで確かめる。
/// 色と格子は `WorldTests` / `RunnerPixelArtTests` の純データで固定しているので、ここで見るのは
/// **描画経路が実際に通ること**——19・25 面のコースを組んで自動操縦で走らせても落ちず、着せ替えの
/// テクスチャが岩の数だけ貼られ、遠景のタイルに丘以外の部品が載っていること。
/// 1 面（朝）では着せ替えのテクスチャが 1 枚も使われない（元の岩塊の経路に戻る）ことも固定する。
@Suite("チャリンコおじさん: 里山・港町の描画")
@MainActor
struct RunnerWorldSceneTests {
    private func makeScene(stage: Int, suite: String) -> (RunnerModel, RunnerScene) {
        let model = RunnerModel(startingAt: stage, preference: makePreference("world-scene-\(suite)"))
        let scene = RunnerScene(model: model)
        scene.rebuildCourse()
        scene.sync()
        return (model, scene)
    }

    /// 子孫まで含めて、`texture` を貼ったスプライトの数。
    private func spriteCount(in node: SKNode, texture: SKTexture) -> Int {
        node.children.reduce(0) { total, child in
            let own = (child as? SKSpriteNode)?.texture === texture ? 1 : 0
            return total + own + spriteCount(in: child, texture: texture)
        }
    }

    @Test("19・25 面は着せ替えのテクスチャが岩の数だけ貼られ（里山の高い岩は岩塊のまま）、遠景のタイルに丘以外が載り、走らせても落ちない", arguments: [
        (19, RunnerWorld.satoyama), (25, RunnerWorld.harbor),
    ])
    func dressedStagesBuild(number: Int, world: RunnerWorld) throws {
        let (model, scene) = makeScene(stage: number, suite: "\(number)")
        #expect(scene.world == world)
        let stage = model.field.stage
        let lows = stage.hazards.filter { $0.kind == .lowBlock }.count
        let talls = stage.hazards.filter { $0.kind == .tallBlock }.count
        #expect(lows > 0 && talls > 0, "\(number) 面に岩が無い（空振り防止）")
        let dressing = world.dressing
        for (style, texture) in scene.blockTextures {
            let expected = (style == dressing.lowBlock ? lows : 0) + (style == dressing.tallBlock ? talls : 0)
            #expect(spriteCount(in: scene.courseLayer, texture: texture) == expected, "\(number) 面の \(style)")
        }
        // 遠景: 丘 3 つだけのタイルは無い（田んぼ・海の帯は全タイルに載る）。
        #expect(!scene.hillTiles.isEmpty)
        for tile in scene.hillTiles {
            #expect(tile.children.count > 3, "\(number) 面の遠景のタイルに丘しか無い")
        }
        // 犬の枠・イノシシの枠のテクスチャがその世界の絵になっている（港町は猫・フォークリフト）。
        let dogTextures = try #require(scene.dogTextures[world])
        #expect(dogTextures.count == RunnerPixelArt.WalkFrame.allCases.count)
        let walker = RunnerPixelArt.walker(.walk0, world: world)
        #expect(Int(dogTextures[0].size().width) == walker.width && Int(dogTextures[0].size().height) == walker.height)

        // 自動操縦で 10 秒ぶん走らせて反映しても落ちない（用水路・台座・加速床・動く障害の経路を通る）。
        model.press()
        model.release()
        for _ in 0..<600 {
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
        }
        #expect(model.phase.isRunning, "\(number) 面で 10 秒以内にミスした")
    }

    @Test("1 面（朝）では着せ替えのテクスチャは 1 枚も貼られず、岩は元の岩塊のまま")
    func originalWorldsUseTheOriginalParts() {
        let (model, scene) = makeScene(stage: 1, suite: "morning")
        #expect(scene.world == .morning)
        for (style, texture) in scene.blockTextures {
            #expect(spriteCount(in: scene.courseLayer, texture: texture) == 0, "1 面に \(style) が貼られている")
        }
        // `makeBlock` は岩塊（`makeRock`）と同じ部品を返す（塗りの図形だけで、スプライトは無い）。
        let rock = model.field.stage.hazards.first { $0.kind.isRock }!
        let viaBlock = scene.makeBlock(rock), viaRock = scene.makeRock(rock)
        #expect(viaBlock.children.count == viaRock.children.count)
        #expect(viaBlock.children.allSatisfy { !($0 is SKSpriteNode) })
    }
}
