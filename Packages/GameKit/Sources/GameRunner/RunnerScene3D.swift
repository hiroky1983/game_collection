import Foundation
import SceneKit
import SpriteKit

/// チャリンコおじさんの 3D 描画プロトタイプ（v1.1.4 会長指示「一回3Dにしてみてほしい」）。
///
/// `RunnerField` は SpriteKit にも SwiftUI にも依存しない値型なので、ここでは**見た目だけ**を
/// SceneKit に差し替える。物理・当たり判定・ステージ定義・15 ステージの安全網
/// （`RunnerStageTests` / `RunnerPlaythroughTests`）は 2D 版の `RunnerScene` と完全に共有し、
/// いっさい変更していない——3D 化を試すコストを「新しい描画層 1 本」まで抑えるための設計。
///
/// **範囲を割り切った試作**: 漕ぐ脚のリグ（`RunnerRider`）はまだ 3D 化していない。まずは
/// 「地面・障害物・光と影のある空間として成立するか」を見るための最小構成（車輪・車体・
/// 胴・頭の単純な立体）。3D 方向で進める判断が出たら作り込む。
///
/// ワールド座標は X = 走行距離（`RunnerField.distance` と同じ単位）、Y = 高さ（`footY` と同じ）、
/// Z = 奥行き（新設、画面には映る幅だけを与える固定値）。走者はワールド上を実際に動き、
/// カメラがそれを追う（2D 版は逆に走者を画面固定してコースを流している。3D では
/// カメラを動かすほうが立体感が素直に出る）。
@MainActor
final class RunnerScene3D {
    private typealias Metrics = RunnerField.Metrics

    /// 奥行き（Z 方向）の厚み。地面・障害物・走者をこの範囲に収める。
    private static let depth: Double = 10

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let model: RunnerModel
    private var lastUpdate: TimeInterval?
    private var renderedGeneration = -1

    private let courseNode = SCNNode()
    private let player = SCNNode()
    private let frontWheel: SCNNode
    private let rearWheel: SCNNode

    init(model: RunnerModel) {
        self.model = model
        frontWheel = RunnerScene3D.makeWheel()
        rearWheel = RunnerScene3D.makeWheel()

        setupEnvironment()
        buildPlayer()
        scene.rootNode.addChildNode(courseNode)
        scene.rootNode.addChildNode(player)
        rebuildCourse()
        sync()
    }

    /// メインスレッドの `CADisplayLink` から毎フレーム呼ぶ（`SCNSceneRendererDelegate` は
    /// 描画専用スレッドで呼ばれ `@MainActor` の `RunnerModel` に触れないため、あえて使わない）。
    func tick(currentTime: TimeInterval) {
        defer { lastUpdate = currentTime }
        guard let last = lastUpdate, currentTime > last else { return }
        model.tick(dt: currentTime - last)
        sync()
    }

    // MARK: - 環境

    private func setupEnvironment() {
        scene.background.contents = RunnerPalette.color(RunnerPalette.sky)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.castsShadow = true
        sun.light?.shadowRadius = 3
        sun.light?.shadowColor = SKColor.black.withAlphaComponent(0.4)
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = SKColor(white: 0.55, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let camera = SCNCamera()
        camera.fieldOfView = 50
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - 走者

    /// 2D 版の丸と長方形だけの意匠を踏襲した最小構成（球・カプセル・円柱・箱のみ）。
    private func buildPlayer() {
        let frame = SCNNode()
        // 位置そのものは毎フレーム `player.position`（world の distance/footY）で決める。
        // ここで `groundY` を足すと `sync()` の footY と二重に積み上がり、走者が空へ消える
        // （最初のシミュレータ確認で判明）。

        frontWheel.position = SCNVector3(2.6, 2.6, 0)
        rearWheel.position = SCNVector3(-2.6, 2.6, 0)
        frame.addChildNode(frontWheel)
        frame.addChildNode(rearWheel)

        let body = SCNNode(geometry: SCNCapsule(capRadius: 1.4, height: 6))
        body.geometry?.firstMaterial?.diffuse.contents = RunnerPalette.color(RunnerPalette.shirt)
        body.position = SCNVector3(-0.6, 6.5, 0)
        body.eulerAngles = SCNVector3(0, 0, Float.pi / 10)
        frame.addChildNode(body)

        let head = SCNNode(geometry: SCNSphere(radius: 1.6))
        head.geometry?.firstMaterial?.diffuse.contents = RunnerPalette.color(RunnerPalette.skin)
        head.position = SCNVector3(0.6, 9.8, 0)
        frame.addChildNode(head)

        let bike = SCNNode(geometry: SCNBox(width: 6.6, height: 0.5, length: 0.5, chamferRadius: 0.1))
        bike.geometry?.firstMaterial?.diffuse.contents = RunnerPalette.color(RunnerPalette.bike)
        bike.position = SCNVector3(0, 3.6, 0)
        bike.eulerAngles = SCNVector3(0, 0, Float.pi / 14)
        frame.addChildNode(bike)

        player.addChildNode(frame)
    }

    private static func makeWheel() -> SCNNode {
        let geometry = SCNCylinder(radius: 2.6, height: 0.6)
        geometry.firstMaterial?.diffuse.contents = RunnerPalette.color(RunnerPalette.wheel)
        let node = SCNNode(geometry: geometry)
        // 既定の円柱は Y 軸方向に高さを持つ（断面が XZ 面）。X 軸まわりに 90° 回して
        // 断面を XY 面へ倒すと、横から見たカメラに「円」として映る。
        node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        return node
    }

    // MARK: - コース

    private func rebuildCourse() {
        renderedGeneration = model.runGeneration
        courseNode.childNodes.forEach { $0.removeFromParentNode() }

        let stage = model.field.stage
        let pits = stage.hazards.filter { $0.kind == .pit }.sorted { $0.start < $1.start }

        var cursor: Double = 0
        for pit in pits {
            if pit.start > cursor { addGround(from: cursor, to: pit.start) }
            addPitVoid(from: pit.start, to: pit.end)
            cursor = pit.end
        }
        if cursor < stage.length { addGround(from: cursor, to: stage.length) }

        for hazard in stage.hazards where hazard.kind != .pit {
            addObstacle(hazard)
        }

        addMarker(at: stage.checkpoint, color: RunnerPalette.checkpoint, height: 5)
        addMarker(at: stage.length, color: RunnerPalette.goal, height: 7)
    }

    private func addGround(from start: Double, to end: Double) {
        let length = end - start
        guard length > 0 else { return }
        let thickness: Double = 14
        let geometry = SCNBox(
            width: length, height: thickness, length: RunnerScene3D.depth, chamferRadius: 0
        )
        geometry.materials = groundMaterials()
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(
            Float(start + length / 2), Float(Metrics.groundY - thickness / 2), 0
        )
        courseNode.addChildNode(node)
    }

    /// 穴の中身（奈落）。地面より一段低い暗い面を敷いて、幅の実感を出す（2D 版と同じ狙い）。
    private func addPitVoid(from start: Double, to end: Double) {
        let length = end - start
        guard length > 0 else { return }
        let geometry = SCNBox(width: length, height: 2, length: RunnerScene3D.depth, chamferRadius: 0)
        geometry.firstMaterial?.diffuse.contents = RunnerPalette.color(RunnerPalette.pitVoid)
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(Float(start + length / 2), Float(Metrics.groundY - 10), 0)
        courseNode.addChildNode(node)
    }

    private func addObstacle(_ hazard: RunnerHazard) {
        let geometry = SCNBox(
            width: hazard.length, height: hazard.height, length: RunnerScene3D.depth * 0.7,
            chamferRadius: 0.15
        )
        geometry.materials = rockMaterials()
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(
            Float(hazard.start + hazard.length / 2), Float(Metrics.groundY + hazard.height / 2), 0
        )
        courseNode.addChildNode(node)
    }

    private func addMarker(at x: Double, color: UInt32, height: Double) {
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.25, height: height))
        pole.geometry?.firstMaterial?.diffuse.contents = SKColor(white: 0.85, alpha: 1)
        pole.position = SCNVector3(Float(x), Float(Metrics.groundY + height / 2), 0)
        courseNode.addChildNode(pole)

        let flag = SCNNode(geometry: SCNBox(width: 1.6, height: 1.1, length: 0.1, chamferRadius: 0))
        flag.geometry?.firstMaterial?.diffuse.contents = RunnerPalette.color(color)
        flag.position = SCNVector3(Float(x + 0.9), Float(Metrics.groundY + height - 0.7), 0.3)
        courseNode.addChildNode(flag)
    }

    private func groundMaterials() -> [SCNMaterial] {
        let top = SCNMaterial()
        top.diffuse.contents = RunnerPalette.color(RunnerPalette.groundTop)
        let side = SCNMaterial()
        side.diffuse.contents = RunnerPalette.color(RunnerPalette.groundBody)
        // SCNBox の面順: front, right, back, left, top, bottom
        return [side, side, side, side, top, side]
    }

    private func rockMaterials() -> [SCNMaterial] {
        let light = SCNMaterial()
        light.diffuse.contents = RunnerPalette.color(RunnerPalette.rockLight)
        let dark = SCNMaterial()
        dark.diffuse.contents = RunnerPalette.color(RunnerPalette.rockDark)
        return [light, dark, dark, dark, light, dark]
    }

    // MARK: - 毎フレーム反映

    private func sync() {
        if renderedGeneration != model.runGeneration { rebuildCourse() }

        let field = model.field
        player.position = SCNVector3(Float(field.distance), Float(field.footY), 0)

        let spin = Float(field.distance) * 1.2
        frontWheel.eulerAngles = SCNVector3(Float.pi / 2, 0, -spin)
        rearWheel.eulerAngles = SCNVector3(Float.pi / 2, 0, -spin)

        // カメラは走者の後ろに構え、2D 版と同じく「先の地形が見える」よう進行方向を見る。
        // （走者より前に出すと走者自身がカメラの後ろに回り込み、画面から消える——最初の
        // シミュレータ確認で判明。)
        let camX = field.distance - 20
        cameraNode.position = SCNVector3(Float(camX), Float(Metrics.groundY + 20), -42)
        cameraNode.look(at: SCNVector3(Float(field.distance + 8), Float(Metrics.groundY + 4), 0))
    }
}

#if os(iOS) && DEBUG
import SwiftUI
import UIKit

/// `RunnerScene3D` を SwiftUI から使うための橋渡し（試作専用。`-runner3D` のときだけ生成される）。
///
/// `SCNSceneRendererDelegate` はレンダリング専用スレッドで呼ばれるため使わず、
/// 代わりにメインスレッドの `CADisplayLink` で `RunnerScene3D.tick(currentTime:)` を毎フレーム叩く。
struct RunnerSceneKitView: UIViewRepresentable {
    let scene3D: RunnerScene3D

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene3D.scene
        view.pointOfView = scene3D.cameraNode
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        context.coordinator.start(driving: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(scene3D: scene3D) }

    /// SwiftUI がビューを手放すタイミングで確実に呼ばれる。`deinit` は non-isolated で
    /// `CADisplayLink`（非 Sendable）に触れないため、ここで止める。
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let scene3D: RunnerScene3D
        private var displayLink: CADisplayLink?

        init(scene3D: RunnerScene3D) { self.scene3D = scene3D }

        func start(driving view: SCNView) {
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func step(_ link: CADisplayLink) {
            scene3D.tick(currentTime: link.timestamp)
        }
    }
}
#endif
