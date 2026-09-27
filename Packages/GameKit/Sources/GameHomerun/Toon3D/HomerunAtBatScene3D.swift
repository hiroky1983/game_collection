import SwiftUI
import simd

/// センターカメラの打席シーンの置き方（`mock3d.swift` の `atBatShot()` の写し・メートル）。純粋な値なのでテストで固定する。
enum HomerunAtBatLayout {
    struct Placement: Equatable {
        var position: SIMD3<Float>
        var yaw: Float
    }

    /// 頭の半径 1 → 0.354m（全身 4.8 → 1.7m）。
    static let characterScale: Float = 0.354

    /// 打者（右打席・胸を少し一塁側に開く）。
    static let batter = Placement(position: [-1.0, 0, 0.15], yaw: 0.35)
    /// 審判は捕手の後ろ（ほとんど隠れる）。捕手は本塁の少し一塁側・奥で、リングとストライクゾーンの周りを空ける。
    static let umpire = Placement(position: [0.75, 0, -3.2], yaw: 0)
    static let catcher = Placement(position: [0.6, 0, -2.2], yaw: 0)
    /// 投手はマウンドの上・本塁に向く（カメラに背中）。
    static let pitcher = Placement(position: [0, 0.3, 17.4], yaw: .pi)

    /// センター側の遠くからの望遠（投手と打者の大きさの差を縮め、投手は腰から上だけ映す = 中継のセンターカメラ）。
    static let cameraPosition: SIMD3<Float> = [0, 6, 43]
    static let cameraTarget: SIMD3<Float> = [0, 1.35, 0.3]
    static let verticalFieldOfView: Float = 9.6
}

/// 3D の打席シーン（球場 + 打者・投手・捕手・審判）を SwiftUI に置く。RealityKit の描画は iOS だけ（macOS の `swift test` では空色の背景だけ）。
struct HomerunAtBatScene3DView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.64, blue: 0.90), Color(red: 0.60, green: 0.82, blue: 0.96), Color(red: 0.85, green: 0.93, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            #if os(iOS) && canImport(RealityKit)
            HomerunAtBatSceneView()
            #endif
        }
        .accessibilityHidden(true)
    }
}

#if os(iOS) && canImport(RealityKit)
import RealityKit

private struct HomerunAtBatSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableHDR, .disableGroundingShadows,
                                      .disableCameraGrain, .disableAREnvironmentLighting])
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(HomerunToonScene.entity(for: .stadium()))
        func place(_ model: HomerunToonModel, _ p: HomerunAtBatLayout.Placement) {
            let e = HomerunToonScene.entity(for: model, scale: HomerunAtBatLayout.characterScale)
            e.position = p.position
            e.orientation = simd_quatf(angle: p.yaw, axis: [0, 1, 0])
            anchor.addChild(e)
        }
        place(.ojisan(.stance), HomerunAtBatLayout.batter)
        place(.ojisan(.pitch, outfit: .pitcher), HomerunAtBatLayout.pitcher)
        place(.catcher(), HomerunAtBatLayout.catcher)
        place(.umpire(), HomerunAtBatLayout.umpire)
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = HomerunAtBatLayout.verticalFieldOfView
        anchor.addChild(cam)
        cam.look(at: HomerunAtBatLayout.cameraTarget, from: HomerunAtBatLayout.cameraPosition, relativeTo: nil)
        view.scene.addAnchor(anchor)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif
