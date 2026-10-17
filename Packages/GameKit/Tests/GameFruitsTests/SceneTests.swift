import Core
import Foundation
import SpriteKit
import Testing
@testable import GameFruits
import CoreTestSupport

/// 描画ループ（`FruitsScene.update`）の計時だけを見るテスト（ブロック崩し #522 と同じ）。
///
/// ルール層のテスト（`FieldTests` / `ModelTests`）と違い、ここでは `SKScene` を生成する。
/// 終局の幕の裏で**描画ループごと止める**ため、再開の 1 フレーム目に渡る `dt` が止めていた時間そのものになり、
/// これはシーンにしか現れないため。ビューには載せないので `didMove(to:)` は走らず、確認するのはモデルの進み方だけ。
@Suite("おじさんの盆栽の描画")
@MainActor
struct SceneTests {
    private func makeModel() -> FruitsModel {
        FruitsModel(services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()), seed: 1)
    }

    @Test("普通のフレームは経過したぶんだけ進む")
    func normalFrameAdvances() {
        let model = makeModel()
        let scene = FruitsScene(model: model)
        model.drop()
        let y0 = model.field.fruits[0].y

        scene.update(100)
        #expect(model.field.fruits[0].y == y0, "初回フレームは経過時間が測れないので進めない")
        scene.update(100 + 1.0 / 60)
        #expect(model.field.fruits[0].y < y0, "2 フレーム目から落ち始める")
    }

    @Test("止めていたあいだの時間はまとめて入らない（#522）")
    func resumeAfterPausedLoopDoesNotWarp() {
        let model = makeModel()
        let scene = FruitsScene(model: model)
        model.drop()
        scene.update(100)
        scene.update(100 + 1.0 / 60)
        let beforePause = model.field.fruits[0].y

        // 描画ループが止まっていて update がまったく来ない 10 秒。
        scene.update(110)
        #expect(model.field.fruits[0].y == beforePause, "止めていた時間で果物が進んではいけない")

        // 時計は合わせ直されているので、次のフレームからは普通に進む。
        scene.update(110 + 1.0 / 60)
        #expect(model.field.fruits[0].y < beforePause)
    }

    @Test("描画ループを止めてよいのは 1 フレーム描いたあと（暗い矩形のまま止めない）")
    func rendersOnceBeforeAllowingPause() {
        let model = makeModel()
        let scene = FruitsScene(model: model)
        #expect(!scene.hasRenderedFrame)
        var notified = 0
        scene.onFrameRendered = { notified += 1 }
        scene.didFinishUpdate()
        #expect(scene.hasRenderedFrame)
        #expect(notified == 1)
    }

    @Test("危険線は開いた直後から通常色で塗られ、果物が掛かると警告色に変わる")
    func deadlineIsStyledFromTheStart() {
        let model = makeModel()
        let scene = FruitsScene(model: model)
        #expect(scene.isDeadlineWarning == nil, "まだ塗っていない")
        // ビューに載せずに `didMove` を呼ぶ（SKView は作らない）。
        scene.didMove(to: SKView())
        #expect(scene.isDeadlineWarning == false, "既定の白のままにしない（地と見分けが付かない）")
    }

    @Test("盆栽は回転させず、鉢の底を円の下端に置く（#2361 案 B）")
    func bonsaiDoesNotRotate() throws {
        let model = makeModel()
        model.moveCursor(to: 20)
        model.drop()
        let scene = FruitsScene(model: model)
        scene.didMove(to: SKView())
        // 転がるまで進める（落ちて床で跳ね、横へ転がる手応えのある時間）。
        model.moveCursor(to: 23)
        var time = 100.0
        scene.update(time)
        for _ in 0..<240 {
            if model.canDrop {
                model.moveCursor(to: Double(Int(time * 7) % 60) + 20)
                model.drop()
            }
            time += 1.0 / 60
            scene.update(time)
        }
        #expect(model.field.fruits.contains { abs($0.angle) > 0.01 }, "物理の円は転がっている（前提）")
        for fruit in model.field.fruits {
            let node = try #require(scene.node(forFruit: fruit.id))
            #expect(node.zRotation == 0, "\(fruit.kind.name) が傾いている")
            #expect(node.anchorPoint == CGPoint(x: 0.5, y: 0))
            #expect(abs(Double(node.position.x) - fruit.x) < 1e-3, "SpriteKit は位置を単精度で持つ")
            #expect(abs(Double(node.position.y) - (fruit.y - fruit.radius)) < 1e-3, "鉢の底が円の下端に無い")
            // 合体で生まれた直後の「膨らむ」演出（`setScale(0.7)` → 1）はビューに載せないと進まないので、倍率を割り戻して比べる。
            let expected = BonsaiArt.spriteSize(for: fruit.kind)
            #expect(abs(Double(node.size.width / node.xScale) - expected.width) < 1e-3)
            #expect(abs(Double(node.size.height / node.yScale) - expected.height) < 1e-3)
        }
    }

    @Test("小さい盆栽ほど前に重ね、大きい盆栽の木の陰に隠れない（#2388）")
    func smallerBonsaiIsInFront() {
        // 大きい盆栽の上に小さい盆栽が載った（小さいほうの鉢の底が高い）場面でも、小さいほうが前。
        let top = FruitField.Metrics.height
        for (small, large) in zip(FruitKind.allCases, FruitKind.allCases.dropFirst()) {
            #expect(FruitsScene.zPosition(for: small, bottomY: top) > FruitsScene.zPosition(for: large, bottomY: 0),
                    "\(small.name) が \(large.name) の後ろ")
        }
        #expect(FruitsScene.zPosition(for: .sakura, bottomY: top) > FruitsScene.zPosition(for: .kinmatsu, bottomY: 0))
        // 同じ段どうしは手前（下）が前。
        for kind in FruitKind.allCases {
            #expect(FruitsScene.zPosition(for: kind, bottomY: 0) > FruitsScene.zPosition(for: kind, bottomY: 30))
        }
        // 危険線（1）より前・合体の輪（4）より奥。
        #expect(FruitsScene.zPosition(for: .sakura, bottomY: 0) < 3)
        #expect(FruitsScene.zPosition(for: .kinmatsu, bottomY: top) >= 2)
    }

    @Test("1 フレームの進みには上限がある")
    func frameIsCapped() {
        let model = makeModel()
        model.drop()
        let y0 = model.field.fruits[0].y
        model.tick(dt: 0.4)
        // 1/30 秒ぶんしか落ちない（自由落下で 0.4 秒なら 25 単位以上落ちる）。
        #expect(y0 - model.field.fruits[0].y < 2)
    }
}
