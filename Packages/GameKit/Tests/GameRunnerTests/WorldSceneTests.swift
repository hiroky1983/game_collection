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

    /// 着せ替えだけが使う色（着せ替えの部品を通ったことの目印）。白や黒のような共通の色は
    /// 入れない——路面の白線や縁取りに使われていて、元の部品でも出てくる。
    private static let dressingSignatureColors: [String: UInt32] = [
        "ditchWater": RunnerWorld.DressingPalette.ditchWater,
        "gapSea": RunnerWorld.DressingPalette.gapSea,
        "ditchWall": RunnerWorld.DressingPalette.ditchWall,
        "fender": RunnerWorld.DressingPalette.fender,
        "strawBody": RunnerWorld.DressingPalette.strawBody,
        "strawTop": RunnerWorld.DressingPalette.strawTop,
        "crateWood": RunnerWorld.DressingPalette.crateWood,
        "crateTop": RunnerWorld.DressingPalette.crateTop,
        "pavedAsphalt": RunnerWorld.DressingPalette.pavedAsphalt,
        "conveyorBelt": RunnerWorld.DressingPalette.conveyorBelt,
    ]

    /// 子孫まで含めて、その色で塗られたノード（スプライトの色・図形の塗り）を数える。
    ///
    /// 色は `SKColor` どうしの `==` では比べない——同じ値でも色空間が違うと一致せず、
    /// **何も数えないまま緑になる**（最初にこの形で書いて対照が 0 件になった）。sRGB の成分に
    /// 直して 1/255 の幅で見る。
    private func fillCount(in node: SKNode, color hex: UInt32) -> Int {
        node.children.reduce(0) { total, child in
            var own = 0
            if let sprite = child as? SKSpriteNode, sprite.texture == nil, isSame(sprite.color, hex) { own = 1 }
            if let shape = child as? SKShapeNode, isSame(shape.fillColor, hex) { own = 1 }
            return total + own + fillCount(in: child, color: hex)
        }
    }

    private func isSame(_ color: SKColor, _ hex: UInt32) -> Bool {
        guard let lhs = rgb(color), let rhs = rgb(RunnerPalette.color(hex)) else { return false }
        return abs(lhs.0 - rhs.0) < 0.004 && abs(lhs.1 - rhs.1) < 0.004 && abs(lhs.2 - rhs.2) < 0.004
    }

    private func rgb(_ color: SKColor) -> (Double, Double, Double)? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let c = converted.components, c.count >= 3 else { return nil }
        return (Double(c[0]), Double(c[1]), Double(c[2]))
    }

    /// 穴・台座・加速床は、旧世界（朝・夕方・夜）では**着せ替えの部品を一切通らない**。
    ///
    /// `makeBlock` 側は `originalWorldsUseTheOriginalParts` が部品の構成で見ているが、
    /// 穴・台座・床は分岐を旧世界側へ倒しても 353 件が全部緑だった（#1100 の敵対的検証）。
    /// 分岐そのものを縛るため、元の部品が返すノードに着せ替え専用の色が 1 つも無いことを固定する。
    /// その世界の面から、穴・台座・加速床を 1 つずつ拾って元の部品で組んだノード。
    /// 3 つが同じ面に揃うとは限らない（朝・夕方には揃う面が無い）ので、面をまたいで集める。
    private func partsOfWorld(_ world: RunnerWorld, suite: String) -> (node: SKNode, found: Set<String>) {
        let node = SKNode()
        var found: Set<String> = []
        for number in world.stageRange {
            let (model, scene) = makeScene(stage: number, suite: "\(suite)-\(number)")
            let stage = model.field.stage
            if !found.contains("pit"), let pit = stage.hazards.first(where: { $0.kind == .pit }) {
                scene.addPitVoid(pit, into: node)
                scene.addPitEdgeMarkers(pit, into: node)
                found.insert("pit")
            }
            if !found.contains("platform"), let platform = stage.platforms.first {
                node.addChild(scene.makePlatform(platform))
                found.insert("platform")
            }
            if !found.contains("floor"), let floor = stage.boostFloors.first {
                node.addChild(scene.makeBoostFloor(floor))
                found.insert("floor")
            }
            if found.count == 3 { break }
        }
        return (node, found)
    }

    @Test("朝・夕方・夜の穴・台座・加速床には着せ替えの色が 1 つも出ない")
    func originalWorldsDrawPitsPlatformsAndFloorsThemselves() {
        let oldWorlds: [RunnerWorld] = [.morning, .evening, .night]
        var covered: Set<String> = []
        for world in oldWorlds {
            #expect(world.dressing == RunnerWorld.originalDressing)
            let (sample, found) = partsOfWorld(world, suite: "original-\(world)")
            covered.formUnion(found)
            for (name, hex) in Self.dressingSignatureColors {
                #expect(fillCount(in: sample, color: hex) == 0, "\(world) の穴・台座・床に \(name) が出ている")
            }
        }
        // 台座（`P`）と加速床（`=`）は 16 面から登場するので、朝・夕方の面には構造上載っていない
        // （`RunnerStage.patterns`）。3 つとも一度は通したことを世界をまたいで確かめる（空振り防止）。
        #expect(covered == ["pit", "platform", "floor"], "旧世界で穴・台座・床を全部は通していない")

        // 対照: 同じ数え方で、着せ替えの世界（里山）ではちゃんと色が出る（数え方の空振り防止）。
        let (control, controlFound) = partsOfWorld(.satoyama, suite: "control")
        #expect(controlFound == ["pit", "platform", "floor"])
        #expect(fillCount(in: control, color: RunnerWorld.DressingPalette.ditchWater) > 0)
        #expect(fillCount(in: control, color: RunnerWorld.DressingPalette.strawTop) > 0)
        #expect(fillCount(in: control, color: RunnerWorld.DressingPalette.pavedAsphalt) > 0)
    }
}
