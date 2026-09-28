import SwiftUI
import Core

/// 3D のおじさん（正面）を SwiftUI に置く。RealityKit の描画は iOS だけ（macOS の `swift test` では 2D の絵に落ちる）。
/// 試作: Meshy の打者おじさん（`HomerunBatterAsset`）の構えを見せる。読めなければプリミティブで組んだ旧モデル。
struct HomerunOjisan3DView: View {
    var pose: HomerunOjisanPose3 = .stance

    var body: some View {
        #if os(iOS)
        HomerunToonSceneView(model: .ojisan(pose), camera: .init(target: [0, 2.7, 0], distance: 14, fieldOfView: 26),
                             batterCamera: HomerunBatterPortrait.stillCamera,
                             // 結果画面の 1 枚絵（`HomerunOjisan3DStillView`）を、すでに描いているこの画面のうちに作っておく。
                             onSnapshot: HomerunOjisanStillCache.image == nil ? { HomerunOjisanStillCache.image = $0 } : nil)
            // 3D（ARView）に当たり判定を残さない（スクロールや手前の操作を吸わせない）。
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #else
        OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
        #endif
    }
}

/// 結果画面用の 3D おじさん（構えの 1 枚絵）。小さな枠のために RealityKit を回し続けず、画像を出す。
/// 画像は打席前のおじさん（`HomerunOjisan3DView`）が描いたついでに作っておく（結果画面を開くときに ARView を作ると
/// 主スレッドが止まるため）。作られていなければ（打席前を通らずに結果へ来たとき）ここで 1 枚描いてから画像にする。
/// macOS の `swift test` では 2D の絵に落ちる。
struct HomerunOjisan3DStillView: View {
    #if os(iOS) && canImport(RealityKit)
    @State private var still = HomerunOjisanStillCache.image

    var body: some View {
        Group {
            if let still {
                Image(uiImage: still).resizable().scaledToFit()
            } else {
                HomerunToonSceneView(model: .ojisan(.stance), camera: HomerunBatterPortrait.stillCamera,
                                     batterCamera: HomerunBatterPortrait.stillCamera) { image in
                    HomerunOjisanStillCache.image = image
                    still = image
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    #else
    var body: some View {
        OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
    }
    #endif
}

#if os(iOS) && canImport(RealityKit)
import Combine
import RealityKit

/// 結果画面のおじさんの 1 枚絵の置き場（プロセスの間だけ持つ）。
@MainActor
enum HomerunOjisanStillCache {
    static var image: UIImage?
}

/// 正面から見るカメラ（`target` を `distance` 離れた +z 側から見る）。
struct HomerunToonCamera: Equatable {
    var target: SIMD3<Float>
    var distance: Float
    var fieldOfView: Float
}

/// 打席前のおじさんの向き（y 軸まわり）。構えの顔は +x（投手側）を向くので、回して顔とバットをカメラ（+z）へ向ける。
enum HomerunBatterPortrait {
    static let yaw: Float = -1.4
    /// 打席前・結果画面で使う、全身が枠に収まるカメラ。
    static let stillCamera = HomerunToonCamera(target: [0, 0.86, 0], distance: 4.3, fieldOfView: 26)
}

/// `ARView(cameraMode: .nonAR)` を包んだもの（`RealityView` は iOS 18 から。配備対象は iOS 17 のまま）。AR セッションは使わない。
struct HomerunToonSceneView: UIViewRepresentable {
    let model: HomerunToonModel
    let camera: HomerunToonCamera
    /// Meshy の打者おじさんを置くときのカメラ（nil なら常に `model` を置く）。
    var batterCamera: HomerunToonCamera?
    /// 渡すと、数フレーム描いたところで 1 枚の画像にして返す（ARView を外すかは呼び出し側が決める）。
    var onSnapshot: ((UIImage) -> Void)?

    /// 画像にする前に描く枚数（Meshy の実体の読み込み・骨の構え・テクスチャの反映を待つ）。
    static let framesBeforeSnapshot = 8

    final class Coordinator {
        var batterRig: HomerunBatterRig?
        var updates: (any Cancellable)?
        var frames = 0
        var didSnapshot = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.isUserInteractionEnabled = false
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableHDR, .disableGroundingShadows,
                                      .disableCameraGrain, .disableAREnvironmentLighting])
        let anchor = AnchorEntity(world: .zero)
        var camera = camera
        if let batterCamera, let rig = HomerunBatterRig() {
            rig.entity.orientation = simd_quatf(angle: HomerunBatterPortrait.yaw, axis: [0, 1, 0])
            anchor.addChild(rig.entity)
            context.coordinator.batterRig = rig
            camera = batterCamera
        } else {
            anchor.addChild(HomerunToonScene.entity(for: model))
        }
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = camera.fieldOfView
        anchor.addChild(cam)
        cam.look(at: camera.target, from: camera.target + SIMD3(0, 0, camera.distance), relativeTo: nil)
        view.scene.addAnchor(anchor)
        if let onSnapshot {
            let coordinator = context.coordinator
            coordinator.updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak view] _ in
                coordinator.frames += 1
                guard coordinator.frames >= Self.framesBeforeSnapshot, !coordinator.didSnapshot, let view else { return }
                coordinator.didSnapshot = true
                view.snapshot(saveToHDR: false) { image in
                    guard let image else { coordinator.didSnapshot = false; return }
                    coordinator.updates?.cancel()
                    onSnapshot(image)
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
#endif
