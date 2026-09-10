import Core
import Foundation
import SpriteKit
import Testing
@testable import GameBlocks

/// 描画ループ（`BlocksScene.update`）の計時だけを見るテスト（#522）。
///
/// ルール層のテスト（`FieldTests` / `ModelTests`）と違い、ここでは `SKScene` を生成する。
/// 一時停止で**描画ループごと止める**ようにしたことで、再開の 1 フレーム目に渡る `dt` が
/// 止めていた時間そのものになり、これはシーンにしか現れないため。
/// ビューには載せないので `didMove(to:)` は走らず、確認するのはモデルの進み方だけ。
@Suite("ブロック崩しの描画ループ")
@MainActor
struct SceneTests {
    private func makeModel(_ suite: String) -> BlocksModel {
        let name = "asobiba.blocks.scene.tests.\(suite)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return BlocksModel(
            services: GameServices(snapshots: MemorySnapshotStore(), ads: NoopAdService()),
            preference: FeedbackPreference(
                key: "blocksSlowMode_v1", defaults: defaults, defaultValue: false
            )
        )
    }

    /// 発射後、まっすぐ上へ飛んでいる球を作る（左右の反射を挟まず y だけで進みを測れる）。
    private func launchStraightUp(_ model: BlocksModel) {
        model.launch()
        model.placeBallForTesting(x: 50, y: 40, vx: 0, vy: 60)
    }

    @Test("普通のフレームは経過したぶんだけ進む")
    func normalFrameAdvances() {
        let model = makeModel("normal")
        let scene = BlocksScene(model: model)
        launchStraightUp(model)

        scene.update(100)
        #expect(model.field.ball.y == 40, "初回フレームは経過時間が測れないので進めない")
        scene.update(100 + 1.0 / 60)
        #expect(abs(model.field.ball.y - (40 + 60.0 / 60)) < 0.001)
    }

    @Test("止めていたあいだの時間はまとめて入らない（#522）")
    func resumeAfterPausedLoopDoesNotWarp() {
        let model = makeModel("resume")
        let scene = BlocksScene(model: model)
        launchStraightUp(model)
        scene.update(100)
        scene.update(100 + 1.0 / 60)
        let beforePause = model.field.ball.y

        // 一時停止のあいだ `SpriteView` の描画ループが止まり、update がまったく来ない。
        model.pause()
        model.resume()
        // 再開の 1 フレーム目。`currentTime` は止めていた 10 秒ぶん飛んでいる。
        scene.update(110)
        #expect(model.field.ball.y == beforePause, "止めていた時間で球が進んではいけない")

        // 時計は合わせ直されているので、次のフレームからは普通に進む。
        scene.update(110 + 1.0 / 60)
        #expect(abs(model.field.ball.y - (beforePause + 60.0 / 60)) < 0.001)
    }
}

private final class MemorySnapshotStore: SnapshotStore, @unchecked Sendable {
    private var store: [String: Data] = [:]
    func save<T: Codable>(_ snapshot: T, for gameID: String) throws {
        store[gameID] = try JSONEncoder().encode(snapshot)
    }
    func load<T: Codable>(_ type: T.Type, for gameID: String) -> T? {
        guard let data = store[gameID] else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    func clear(for gameID: String) { store.removeValue(forKey: gameID) }
    func exists(for gameID: String) -> Bool { store[gameID] != nil }
}
