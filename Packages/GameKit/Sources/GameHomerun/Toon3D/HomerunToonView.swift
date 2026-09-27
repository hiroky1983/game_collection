import SwiftUI
import Core

/// 3D のおじさん（正面）を SwiftUI に置く。RealityKit の描画は iOS だけ（macOS の `swift test` では 2D の絵に落ちる）。
struct HomerunOjisan3DView: View {
    var pose: HomerunOjisanPose3 = .stance

    var body: some View {
        #if os(iOS)
        HomerunToonSceneView(model: .ojisan(pose), camera: .init(target: [0, 2.7, 0], distance: 14, fieldOfView: 26))
            .accessibilityHidden(true)
        #else
        OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
        #endif
    }
}

#if os(iOS) && canImport(RealityKit)
import RealityKit

/// 正面から見るカメラ（`target` を `distance` 離れた +z 側から見る）。
struct HomerunToonCamera: Equatable {
    var target: SIMD3<Float>
    var distance: Float
    var fieldOfView: Float
}

/// `ARView(cameraMode: .nonAR)` を包んだもの（`RealityView` は iOS 18 から。配備対象は iOS 17 のまま）。AR セッションは使わない。
struct HomerunToonSceneView: UIViewRepresentable {
    let model: HomerunToonModel
    let camera: HomerunToonCamera

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableHDR, .disableGroundingShadows,
                                      .disableCameraGrain, .disableAREnvironmentLighting])
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(HomerunToonScene.entity(for: model))
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = camera.fieldOfView
        anchor.addChild(cam)
        cam.look(at: camera.target, from: camera.target + SIMD3(0, 0, camera.distance), relativeTo: nil)
        view.scene.addAnchor(anchor)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif
