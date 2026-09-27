import SwiftUI
import simd
import HomerunCore

/// 外野カメラの静止ショット（README §3.2）の置き方。**軌道の連続アニメーションはここでは作らない**
/// （段 2 の続き。当たり以上でカメラが切り替わり、方向の柵・外野手・打球の落下点/フェンス直撃/柵越えの位置が
/// 見える 1 枚の静止ショットまで）。乱数なし・同じ `HomerunBattedBall` は同じ `Shot` になる。
enum HomerunOutfieldLayout {
    struct Shot: Equatable {
        var ballPosition: SIMD3<Float>
        var fielderPosition: SIMD3<Float>
        var fielderYaw: Float
        var cameraPosition: SIMD3<Float>
        var cameraTarget: SIMD3<Float>
    }

    static let characterScale = HomerunAtBatLayout.characterScale
    static let verticalFieldOfView: Float = 32

    /// フェンスより奥（カメラ側）に取る、カメラ・注視点のオフセット（m。`mock3d.swift` の `outfieldShot()` の写し）。
    private static let cameraBehindFence: Double = 50
    private static let cameraHeight: Double = 9
    private static let targetHeight: Double = 5.5
    /// 外野手はフェンスの少し手前（フェンス側へ寄り過ぎない下限も設ける）。
    private static let fielderInFrontOfFence: Double = 4
    private static let fielderMinDistance: Double = 20
    /// カメラは打球より本塁側（手前）にこの距離だけ離す（近距離の inPlay がカメラの死角に入らないように）。
    private static let cameraInFrontOfBall: Double = 10

    /// 本塁を原点・+z をセンターとする世界座標（`HomerunStadium3D.stadium()` と同じ座標系）。
    static func point(direction degrees: Double, distance: Double, height: Double = 0) -> SIMD3<Float> {
        let radians = degrees * .pi / 180
        return [Float(distance * sin(radians)), Float(height), Float(distance * cos(radians))]
    }

    /// 打球の結果から静止ショットを組み立てる。`ball.kind` は `.inPlay` / `.fenceHit` / `.homer` のいずれかを渡すこと
    /// （空振り・ファウルは外野へ切り替わらない。呼び出し側の `HomerunAtBatView` が判定する）。
    static func shot(for ball: HomerunBattedBall) -> Shot {
        let fence = ball.fence
        // 描画上の落下距離: 深い柵越えでもフェンスの少し奥までに収める（カメラの画角に収まるように）。
        let renderDistance = min(max(ball.distance, 0), fence + 10)
        let ballHeight: Double = switch ball.kind {
        case .fenceHit: 3.0   // フェンスの上端で跳ね返る高さ。
        case .homer: 4.6      // フェンスを越えた高さ。
        default: 0.3          // 地面（フェアゾーンに落ちた高さ）。
        }
        let ballPosition = point(direction: ball.direction, distance: renderDistance, height: ballHeight)
        let fielderDistance = max(min(renderDistance - 8, fence - fielderInFrontOfFence), fielderMinDistance)
        let fielderPosition = point(direction: ball.direction, distance: fielderDistance)
        // 本塁の方（打球が飛んできた側）を向く = 外向き（`point` と同じ回転）から180°回す。
        let fielderYaw = Float(ball.direction * .pi / 180) + .pi
        // 柵の 50m 手前を基本の位置にしつつ、近距離の inPlay（弱いゴロ等）ではそれより本塁側に寄せて
        // 打球がカメラの死角（後方）に入らないようにする（PR #1484 CodeRabbit 指摘）。
        let cameraDistance = min(fence - cameraBehindFence, max(renderDistance - cameraInFrontOfBall, 0))
        let cameraPosition = point(direction: ball.direction, distance: cameraDistance, height: cameraHeight)
        let cameraTarget = point(direction: ball.direction, distance: fence, height: targetHeight)
        return Shot(ballPosition: ballPosition, fielderPosition: fielderPosition, fielderYaw: fielderYaw,
                    cameraPosition: cameraPosition, cameraTarget: cameraTarget)
    }
}

/// 外野カメラの静止ショット（球場 + 外野手 + 打球）。RealityKit の描画は iOS だけ
/// （macOS の `swift test` では空色の背景だけ・`HomerunAtBatScene3DView` と同じ扱い）。
struct HomerunOutfieldScene3DView: View {
    var ball: HomerunBattedBall

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.64, blue: 0.90), Color(red: 0.60, green: 0.82, blue: 0.96), Color(red: 0.85, green: 0.93, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            #if os(iOS) && canImport(RealityKit)
            HomerunOutfieldSceneView(ball: ball)
            #endif
        }
        .accessibilityHidden(true)
    }
}

#if os(iOS) && canImport(RealityKit)
import RealityKit

private struct HomerunOutfieldSceneView: UIViewRepresentable {
    let ball: HomerunBattedBall

    final class Coordinator {
        var shot: HomerunOutfieldLayout.Shot?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableHDR, .disableGroundingShadows,
                                      .disableCameraGrain, .disableAREnvironmentLighting])
        build(in: view, context: context)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        guard context.coordinator.shot != HomerunOutfieldLayout.shot(for: ball) else { return }
        uiView.scene.anchors.removeAll()
        build(in: uiView, context: context)
    }

    private func build(in view: ARView, context: Context) {
        let shot = HomerunOutfieldLayout.shot(for: ball)
        context.coordinator.shot = shot
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(HomerunToonScene.entity(for: .stadium()))
        let fielder = HomerunToonScene.entity(for: .ojisan(.outfielder, outfit: .pitcher), scale: HomerunOutfieldLayout.characterScale)
        fielder.position = shot.fielderPosition
        fielder.orientation = simd_quatf(angle: shot.fielderYaw, axis: [0, 1, 0])
        anchor.addChild(fielder)
        if ball.distance > 0 {
            let sphere = HomerunToonScene.entity(for: HomerunToonModel().withBall())
            sphere.position = shot.ballPosition
            anchor.addChild(sphere)
        }
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = HomerunOutfieldLayout.verticalFieldOfView
        anchor.addChild(cam)
        cam.look(at: shot.cameraTarget, from: shot.cameraPosition, relativeTo: nil)
        view.scene.addAnchor(anchor)
    }
}

private extension HomerunToonModel {
    /// 打球の実体（白い球）。
    func withBall() -> HomerunToonModel {
        var m = self
        m.sphere(0.36, HomerunToonPalette.white, at: .zero, outline: 0.05)
        return m
    }
}
#endif
