import Core
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

    /// テクスチャ／ドット絵のドットを RGBA のバイト列として読み出す（絵が同じかを比べる用）。
    /// `SKTexture.cgImage()` は貼ってある画像をそのまま返すので、画面に出さずに比べられる。
    private static func pixels(of texture: SKTexture) -> [UInt8]? { bytes(of: texture.cgImage()) }
    private static func pixels(of sprite: PixelSprite) -> [UInt8]? { bytes(of: sprite.cgImage(scale: 1)) }

    private static func bytes(of image: CGImage?) -> [UInt8]? {
        guard let image else { return nil }
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
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

    /// 突き上げ（#1010）の描画経路。**絵の位置が当たり判定の上端から出ている**ことを、
    /// 実際に走らせて `sync` した結果で確かめる——ここがずれると「見えている高さと当たる高さが
    /// 違う」という理不尽な当たりになる。予告の揺れは伸び切ったら止める（`.stopped`）。
    ///
    /// **里山（19 面・竹の子）と港町（26 面・波しぶき）の両方で回す。** 片方だけだと、もう片方の
    /// テクスチャを取り違えても／作り忘れても緑のまま通る——`SKSpriteNode(texture:)` は nil を
    /// 受け取れるので、「絵の無い（＝見えない）突き上げ」が出荷されうる（2026-09-18 の敵対的検証で、
    /// 19 面だけ見ていたときに港町のテクスチャを消しても 368 件緑だったのを実測）。
    @Test("突き上げは本数ぶん組まれ、その世界の絵が貼られ、絵が当たり判定の伸びた高さに追従する", arguments: [
        (19, RunnerWorld.Dressing.Shoot.bambooShoot, 3),
        (26, RunnerWorld.Dressing.Shoot.seaSpray, 2),
    ])
    func shootsFollowTheHitBox(number: Int, style: RunnerWorld.Dressing.Shoot, count: Int) throws {
        let (model, scene) = makeScene(stage: number, suite: "shoot-\(number)")
        let stage = model.field.stage
        let shoots = stage.hazards.filter { $0.kind == .shoot }
        #expect(shoots.count == count, "\(number) 面の突き上げが \(shoots.count) 本（空振り防止）")
        #expect(scene.world.dressing.shoot == style)
        let views = scene.movingHazards.filter { $0.hazard.kind == .shoot }
        #expect(views.count == shoots.count, "突き上げのノードが本数ぶん無い")
        // 貼られている絵は、その世界の着せ替えのもの。**その世界のぶんしかテクスチャを作らない**
        // （#1010 の受け入れ条件「世界に入ったときに作ってキャッシュ」）。
        #expect(scene.cachedShootStyles == [style], "作ったテクスチャ: \(scene.cachedShootStyles)")
        let expected = scene.shootTexture(style)
        let other: RunnerWorld.Dressing.Shoot = style == .bambooShoot ? .seaSpray : .bambooShoot
        // **2 つの着せ替えのテクスチャが「絵として」違うこと**を先に言う。同じ画を 2 枚焼いても
        // インスタンスは別物になるので、`!==` では足りない——**ドットを読んで比べる**
        // （2026-09-18 の敵対的検証で、`shootTexture` が着せ替えを無視して 1 枚だけ焼く実装でも
        // 緑のまま通ったのを実測）。格子は 12×27 なので読み出しは軽い。
        #expect(
            Self.pixels(of: expected) != Self.pixels(of: scene.shootTexture(other)),
            "2 つの世界で同じ絵を貼っている"
        )
        // 貼った絵が `RunnerPixelArt` の着せ替えのものと一致する（焼き直したものと同じドット）。
        #expect(
            Self.pixels(of: expected) == Self.pixels(of: RunnerPixelArt.shootArt(for: style)),
            "貼られている絵が \(style) のドット絵と違う"
        )
        for view in views {
            #expect(spriteCount(in: view.node, texture: expected) == 1, "\(style) の絵が貼られていない")
            #expect(spriteCount(in: view.node, texture: scene.shootTexture(other)) == 0, "別の世界の絵が貼られている")
            #expect(view.riserHeight == RunnerHazardKind.shootTop)
        }

        // 伸びかけ・伸び切りの両方で、絵の底が「伸びた高さ − 箱の高さ」に置かれている。
        //
        // **走者を直接置いて反映する**（`placeForTesting` + `syncMovingHazard`）。自動操縦で
        // 区画 8 まで走らせても同じ経路を通るが、700 フレームぶんの `tick` + `sync` はこの
        // スイートだけで 20 秒以上増える（CI を延ばさない・#1039）。走らせて落ちないことは
        // 同じ 19 面を 10 秒走る `dressedStagesBuild` が見ている。
        let target = try #require(views.first)
        let full = RunnerHazardKind.shootTop
        var field = RunnerField(stage: stage)
        var rising = 0, risen = 0, worstOffset = 0.0, floatingCue = 0.0
        var shownBeforeCue = false, hiddenAfterCue = false, wrongState = 0
        for step in stride(from: -8.0, through: RunnerRules.shootRiseDistance + 8, by: 1.0) {
            field.placeForTesting(distance: target.hazard.shootCueDistance + step, altitude: 0, vy: 0)
            // 揺れの `SKAction` はシーンを回さないと進まないので、**揺れの上端に居る状態を手で作る**
            // ——そのうえで反映したとき、伸び切っていれば地面へ戻ることを見る。
            target.cue?.position.y = 0.35
            scene.syncMovingHazard(target, field: field)
            guard let frame = target.hazard.frame(atRunnerDistance: field.distance) else {
                if !target.node.isHidden { shownBeforeCue = true }
                continue
            }
            if target.node.isHidden { hiddenAfterCue = true }
            worstOffset = max(worstOffset, abs(Double(target.riser?.position.y ?? 0) - (frame.top - full)))
            if target.state != (frame.top < full ? .moving : .stopped) { wrongState += 1 }
            if frame.top < full {
                rising += 1
            } else {
                risen += 1
                // 伸び切ったら予告の揺れを止め、**塚・泡を地面へ戻す**（浮いたまま固まらせない）。
                floatingCue = max(floatingCue, abs(Double(target.cue?.position.y ?? 0)))
            }
        }
        #expect(!shownBeforeCue, "予告の前なのに絵が見えている")
        #expect(!hiddenAfterCue, "予告の後なのに絵が隠れている")
        #expect(wrongState == 0, "予告の揺れの止め方が \(wrongState) 地点で違う")
        // SpriteKit は `position` を単精度で持つので、丸めのぶん（この大きさでは 1e-6 以下）を見込む。
        #expect(worstOffset < 1e-4, "絵の位置と当たり判定の上端のずれが最大 \(worstOffset)")
        #expect(floatingCue < 1e-4, "伸び切ったあとも予告が浮いている（y = \(floatingCue)）")
        #expect(rising > 10 && risen > 5, "伸びかけ \(rising) / 伸び切り \(risen) 地点しか見ていない")
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

    /// 沈む床（#1089）の描画経路。**里山と港町で別の絵になっている**ことを、
    /// 相手側の色が 1 つも出ないところまで見る——片方の分岐を落としても、
    /// 自分側の色を数えるだけなら緑のまま通る（`shootsFollowTheHitBox` と同じ空振りの形）。
    @Test("沈む床は世界ごとに別の絵で組まれ、相手の世界の色は出ない", arguments: [
        (21, RunnerWorld.satoyama), (29, RunnerWorld.harbor),
    ])
    func sinkFloorsAreDressedPerWorld(number: Int, world: RunnerWorld) throws {
        typealias P = RunnerWorld.DressingPalette
        let (model, scene) = makeScene(stage: number, suite: "sink-\(number)")
        #expect(scene.world == world)
        let floors = model.field.stage.sinkFloors
        #expect(!floors.isEmpty, "\(number) 面に沈む床が無い（空振り防止）")

        let paddy = world == .satoyama
        let node = scene.makeSinkFloor(try #require(floors.first))
        let container = SKNode()
        container.addChild(node)
        for (name, hex) in [("水面／泥", paddy ? P.paddyWater : P.tidelandMud),
                            ("底", paddy ? P.paddyDeep : P.tidelandDeep),
                            ("目印", paddy ? P.paddySeedling : P.tidelandHole)] {
            #expect(fillCount(in: container, color: hex) > 0, "\(world) の沈む床に\(name)が無い")
        }
        for (name, hex) in [("水面／泥", paddy ? P.tidelandMud : P.paddyWater),
                            ("底", paddy ? P.tidelandDeep : P.paddyDeep),
                            ("目印", paddy ? P.tidelandHole : P.paddySeedling)] {
            #expect(fillCount(in: container, color: hex) == 0, "\(world) の沈む床に別の世界の\(name)が出ている")
        }

        // コース層にも床の本数ぶん組まれていて、走らせても落ちない（沈み → 溺れの経路を通る）。
        #expect(fillCount(in: scene.courseLayer, color: paddy ? P.paddyWater : P.tidelandMud) >= floors.count)
        model.press()
        model.release()
        for _ in 0..<900 {
            if RunnerAutoPilot.shouldJump(field: model.field) { model.press() }
            if RunnerAutoPilot.shouldRelease(field: model.field) { model.release() }
            model.tick(dt: 1.0 / 60)
            scene.sync()
        }
        #expect(model.phase.isRunning || model.phase == .cleared, "\(number) 面で 15 秒以内にミスした")
    }
}
