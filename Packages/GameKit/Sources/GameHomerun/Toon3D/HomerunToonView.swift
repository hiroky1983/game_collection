import SwiftUI
import ImageIO
import Core

/// 打席前・結果画面のおじさん（構えの正面）。3D（RealityKit）は描かず、書き出した透明 PNG を出す（#1772）。
/// 以前は画面を開くたびに `ARView` を作って USDZ を主スレッドで読んでいたため、表示までが遅かった。
///
/// 画像の撮り直し（打者の USDZ や構え・カメラを変えたとき）:
/// 1. DEBUG ビルドを iOS シミュレータ（3x の端末。iPhone 17 など）に入れ、起動引数 `-homerunExportOjisan` を付けて
///    柵越えの打席前の画面を開く（ハブでは非公開なので、手元で `HomerunModule()` のコメントを外して開く。コミットしない）。
/// 2. アプリのコンテナの Documents に `HomerunOjisanStance.png`（120pt 角・3x = 360px・背景透明）が書き出される。
///    `xcrun simctl get_app_container <UDID> <bundle id> data` で場所を取る。
/// 3. それを `Resources/HomerunOjisanStance.png` に置き換える。
struct HomerunOjisanImageView: View {
    var body: some View {
        Group {
            #if DEBUG && os(iOS) && canImport(RealityKit)
            if ProcessInfo.processInfo.arguments.contains("-homerunExportOjisan") {
                HomerunOjisanExporter()
            } else {
                art
            }
            #else
            art
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var art: some View {
        if let image = HomerunOjisanArt.image {
            Image(decorative: image, scale: HomerunOjisanArt.scale).resizable().scaledToFit()
        } else {
            OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
        }
    }
}

/// 書き出した画像。GameKit は macOS でもビルドされる（`swift test`）ので UIImage は使わず ImageIO で読む。
enum HomerunOjisanArt {
    /// 書き出し時の端末の倍率（3x）。
    static let scale: CGFloat = 3
    static let image: CGImage? = Bundle.module.url(forResource: "HomerunOjisanStance", withExtension: "png")
        .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
}

#if DEBUG && os(iOS) && canImport(RealityKit)
import Combine
import RealityKit

/// 正面から見るカメラ（`target` を `distance` 離れた +z 側から見る）。
struct HomerunToonCamera: Equatable {
    var target: SIMD3<Float>
    var distance: Float
    var fieldOfView: Float
}

/// 打席前のおじさんの向き（書き出し専用。画像は `HomerunOjisanArt`）（y 軸まわり）。構えの顔は +x（投手側）を向くので、回して顔とバットをカメラ（+z）へ向ける。
enum HomerunBatterPortrait {
    static let yaw: Float = -1.4
    /// 全身が枠に収まるカメラ。
    static let stillCamera = HomerunToonCamera(target: [0, 0.86, 0], distance: 4.3, fieldOfView: 26)
}

/// 画像の書き出し（`HomerunOjisanExporter`）だけが使う。
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
            coordinator.updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak view, weak coordinator] _ in
                guard let coordinator else { return }
                coordinator.frames += 1
                guard coordinator.frames >= Self.framesBeforeSnapshot, !coordinator.didSnapshot, let view else { return }
                coordinator.didSnapshot = true
                view.snapshot(saveToHDR: false) { [weak coordinator] image in
                    guard let coordinator else { return }
                    guard let image else { coordinator.didSnapshot = false; return }
                    coordinator.updates?.cancel()
                    onSnapshot(image)
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel()
    }
}

/// 起動引数 `-homerunExportOjisan` のときだけ、構えのおじさんを 3D で描いて透明 PNG に書き出す（DEBUG のみ）。
struct HomerunOjisanExporter: View {
    @State private var done = false

    var body: some View {
        HomerunToonSceneView(model: .ojisan(.stance), camera: .init(target: [0, 2.7, 0], distance: 14, fieldOfView: 26),
                             batterCamera: HomerunBatterPortrait.stillCamera) { image in
            guard !done, let data = image.pngData(),
                  let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            done = true
            try? data.write(to: dir.appendingPathComponent("HomerunOjisanStance.png"))
            print("HomerunOjisanExporter: wrote \(image.size) @\(image.scale)x to \(dir.path)")
        }
        .frame(width: 120, height: 120)
        .overlay(alignment: .bottom) { if done { Text(verbatim: "exported").font(.caption2) } }
    }
}
#endif
