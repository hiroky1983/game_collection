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
@Suite("くっつきフルーツの描画ループ")
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
