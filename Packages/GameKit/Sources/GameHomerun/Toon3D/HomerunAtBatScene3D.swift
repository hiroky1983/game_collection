import SwiftUI
import simd
import HomerunCore

/// センターカメラの打席シーンの置き方（`mock3d.swift` の `atBatShot()` の写し・メートル）。純粋な値なのでテストで固定する。
enum HomerunAtBatLayout {
    struct Placement: Equatable {
        var position: SIMD3<Float>
        var yaw: Float
    }

    /// 頭の半径 1 → 0.354m（全身 4.8 → 1.7m）。
    static let characterScale: Float = 0.354

    /// 打者（右打席 = 三塁側 = センターカメラから見て右の +x）。Meshy の 3D モデル（`HomerunBatterAsset`）は構えで
    /// 胸が +z・左肩が +x を向いているので、y 軸で -90° 回して左肩を投手（+z）へ、胸を本塁（-x）へ向ける（試作）。
    static let batter = Placement(position: [0.95, 0, 0.1], yaw: -.pi / 2)
    /// 審判は捕手の後ろ（ほとんど隠れる）。捕手は本塁の少し一塁側（-x）・奥で、リングとストライクゾーンと打者の周りを空ける。
    static let umpire = Placement(position: [-0.75, 0, -3.2], yaw: 0)
    static let catcher = Placement(position: [-0.6, 0, -2.2], yaw: 0)
    /// 投手はマウンドの上・本塁に向く（カメラに背中）。
    static let pitcher = Placement(position: [0, 0.3, 17.4], yaw: .pi)

    /// カメラ（位置・注視点・垂直画角）。純粋な値なので、どの点が画面のどこに映るかをテストで固定できる。
    struct Camera: Equatable {
        var position: SIMD3<Float>
        var target: SIMD3<Float>
        var verticalFieldOfView: Float
        /// 描画を左右反転する。世界座標は +x が一塁側で、センターカメラ（本塁を向く）では +x が画面の右 = HUD の方向メーター・
        /// スプレーチャートの「右」と一致する。本塁の後ろから外野を向くカメラでは +x が画面の左に来て HUD と食い違うので反転して合わせる
        /// （右打席の打者も、後ろから見て左に立つ本来の見え方になる）。
        var mirrored = false

        /// 世界の点が画面のどこ（左上 = (0, 0)・右下 = (1, 1)）に映るか。`aspect` は画面の幅 / 高さ。透視投影・ロール無し。
        func screenPoint(of point: SIMD3<Float>, aspect: Double) -> (x: Double, y: Double) {
            let forward = simd_normalize(target - position)
            let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
            let up = simd_cross(right, forward)
            let v = point - position
            let depth = Double(simd_dot(v, forward))
            let halfTan = tan(Double(verticalFieldOfView) * .pi / 360)
            let x = 0.5 + 0.5 * Double(simd_dot(v, right)) / depth / (halfTan * aspect)
            return (mirrored ? 1 - x : x, 0.5 - 0.5 * Double(simd_dot(v, up)) / depth / halfTan)
        }

        /// 世界の点が画面の高さのどこ（上端 = 0・下端 = 1）に映るか。
        func screenFraction(of point: SIMD3<Float>) -> Double { screenPoint(of: point, aspect: 1).y }

        /// `anchor` が画面の横の中央・高さ `yFraction` に映るように注視点を決めたカメラ。
        /// 注視点は anchor を通る鉛直面の中にあり、anchor の向きから δ（tan δ = (1 − 2·yFraction)·tan(fov/2)）だけ下を向く。
        static func aimed(from position: SIMD3<Float>, at anchor: SIMD3<Float>, yFraction: Double, verticalFieldOfView fov: Float, mirrored: Bool = false) -> Camera {
            let v = anchor - position
            let ahead = simd_normalize(v)
            let right = simd_normalize(simd_cross(ahead, [0, 1, 0]))
            let up = simd_cross(right, ahead)
            let delta = atan((1 - 2 * Float(yFraction)) * tan(fov * .pi / 360))
            let forward = ahead * cos(delta) - up * sin(delta)
            return Camera(position: position, target: position + forward * simd_length(v), verticalFieldOfView: fov, mirrored: mirrored)
        }
    }

    /// 打席カメラ（#1506・会長決裁 2026-09-28: 前 / 後ろの 2 択・既定は前）。打席の「⋯」メニューで切り替え、選んだ方は次回も残る
    /// （`HomerunModel.atBatCamera`）。どちらもストライクゾーンの中心が画面の横の中央・高さ `zoneScreenFraction` に映る
    /// （2D のゾーン・的・カーソルの位置と片手操作を変えない）。切り替えるのは見た目だけで、判定・座標・解析は変えない。
    /// `rawValue` は保存に使うので変えない。
    enum CameraPreset: String, CaseIterable, Sendable {
        /// 前: 中継のセンターカメラ（本塁から 43m・高さ 6m・望遠 9.6°・ほぼ水平）。
        case front
        /// 後ろ: 本塁の 7.5m 後ろ・三塁側へ 0.5m（打者の側）・高さ 3m から、ストライクゾーンを 15.6° 見下ろす（画角 53°・光軸は 18.5° 下向き）。
        /// 審判・捕手の肩越しに打者・本塁・バッターボックスを手前に大きく、奥に投手・外野の柵を映す（左右反転で HUD の右 = 右翼に合わせる）。
        /// 検討時の案 B（14m 後ろ・一塁側 0.5m・高さ 7m・54°・23.5° 見下ろす）から寄せて打者の背丈を約 2.1 倍にした。
        /// 三塁側へずらすのは、真後ろだと手前の審判・捕手が本塁とゾーンの右下を塞ぐため（右端へ逃がす）。これ以上寄せる・下げると、
        /// 打者（本塁の 1m 左）が画面の左端へ、投手の頭が上端の HUD（球数・今回・直前の球）の裏へ寄る。
        case back

        /// 「⋯」メニューの文言。
        var title: String {
            switch self {
            case .front: "カメラ: 前"
            case .back: "カメラ: 後ろ"
            }
        }

        var camera: Camera {
            switch self {
            case .front:
                return Camera(position: [0, 6, 43], target: [0, 0.57, 0.3], verticalFieldOfView: 9.6)
            case .back:
                return .aimed(from: [-0.5, 3, -7.5], at: HomerunAtBatLayout.zoneWorldCenter,
                              yFraction: HomerunAtBatLayout.zoneScreenFraction, verticalFieldOfView: 53, mirrored: true)
            }
        }
    }

    /// 前のカメラ（`CameraPreset.front`）。センター側の遠くからの望遠（投手と打者の大きさの差を縮め、
    /// 投手は腰から上だけ映す = 中継のセンターカメラ）。注視点は、ストライクゾーンの中心（`zoneWorldCenter`）が画面の高さの
    /// `zoneScreenFraction` に映るように決めている（原本より少し下を向く = 打席の HUD の 2D のゾーン・的・カーソルをそこへ重ねる。
    /// 押せる帯の下 1/3 と重ねない）。
    static var cameraPosition: SIMD3<Float> { CameraPreset.front.camera.position }
    static var cameraTarget: SIMD3<Float> { CameraPreset.front.camera.target }
    static var verticalFieldOfView: Float { CameraPreset.front.camera.verticalFieldOfView }

    /// ストライクゾーンの中心（本塁の真上・胸の高さ）。
    static let zoneWorldCenter: SIMD3<Float> = [0, 0.9, 0]
    /// 2D のゾーンの中心を置く画面の高さの割合（上端 = 0）。
    static let zoneScreenFraction: Double = 0.45

    /// 世界の点が前のカメラで画面の高さのどこ（上端 = 0・下端 = 1）に映るか。
    static func screenFraction(of point: SIMD3<Float>) -> Double {
        CameraPreset.front.camera.screenFraction(of: point)
    }
}

extension HomerunAtBatLayout {
    /// いまの局面での打者のポーズ。投球中は構え、結果の間は打球の種別で決まる（空振り = うなだれ・柵越え = 喜び・それ以外 = 振り切り）。
    static func batterPose(phase: HomerunModel.Phase, lastKind: HomerunKind?) -> HomerunOjisanPose3 {
        guard phase == .ballResult, let kind = lastKind else { return .stance }
        switch kind {
        case .miss: return .whiff
        case .homer: return .cheer
        case .foul, .inPlay, .fenceHit: return .swing
        }
    }

    /// いまの局面での投手のポーズ。投手のモーション中（的が出る前・`elapsed` が負）は振りかぶり、
    /// 的が出た後（リリース）〜結果の間はリリースのまま止める。
    static func pitcherPose(phase: HomerunModel.Phase, elapsed: TimeInterval?) -> HomerunOjisanPose3 {
        guard phase == .pitching, let elapsed, elapsed < 0 else { return .pitch }
        return .windup
    }
}

/// 3D の打席シーン（球場 + 打者・投手・捕手・審判）を SwiftUI に置く。RealityKit の描画は iOS だけ（macOS の `swift test` では空色の背景だけ）。
///
/// **当たり判定を持たない**（`allowsHitTesting(false)`）。3D は UIKit の `ARView` なので、当たり判定を残すと
/// 手前に重ねた押せる帯（`HomerunAtBatView.touchPad`）へのドラッグを `ARView` が吸ってしまい、
/// カーソルが動かずスイングもできなくなる（会長 QA 2026-09-28。チャリンコ・ブロックの SpriteView と同じ扱い）。
struct HomerunAtBatScene3DView: View {
    var batterPose: HomerunOjisanPose3 = .stance
    var pitcherPose: HomerunOjisanPose3 = .pitch
    var cameraPreset: HomerunAtBatLayout.CameraPreset = .front
    /// 打者のスイング（試作）。nil なら構え、値が変わるたびにスイングを頭から 1 回再生する。
    var batterSwing: Int?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.64, blue: 0.90), Color(red: 0.60, green: 0.82, blue: 0.96), Color(red: 0.85, green: 0.93, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            #if os(iOS) && canImport(RealityKit)
            HomerunAtBatSceneView(batterPose: batterPose, pitcherPose: pitcherPose, camera: cameraPreset.camera,
                                  batterSwing: batterSwing)
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(iOS) && canImport(RealityKit)
import RealityKit

private struct HomerunAtBatSceneView: UIViewRepresentable {
    let batterPose: HomerunOjisanPose3
    let pitcherPose: HomerunOjisanPose3
    let camera: HomerunAtBatLayout.Camera
    let batterSwing: Int?

    /// 打者・投手の実体（ポーズが変わったら差し替える）とカメラ（案が変わったら向け直す）。打者は Meshy のモデルが読めればそれ
    /// （`batterRig`）を使い、読めなければ旧モデル（プリミティブで組んだおじさん）をポーズごとに差し替える。
    final class Coordinator {
        var batterRig: HomerunBatterRig?
        var batterSwing: Int?
        var batter: Entity?
        var batterPose: HomerunOjisanPose3?
        var pitcher: Entity?
        var pitcherPose: HomerunOjisanPose3?
        var cameraEntity: PerspectiveCamera?
        var camera: HomerunAtBatLayout.Camera?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private static func characterEntity(_ pose: HomerunOjisanPose3, outfit: HomerunOjisanOutfit, _ p: HomerunAtBatLayout.Placement) -> Entity {
        let e = HomerunToonScene.entity(for: .ojisan(pose, outfit: outfit), scale: HomerunAtBatLayout.characterScale)
        e.position = p.position
        e.orientation = simd_quatf(angle: p.yaw, axis: [0, 1, 0])
        return e
    }

    /// 旧モデルの打者（正面向きに作られているので、打席の向きではなく本塁側へ少し開いた向きで置く）。
    private static func legacyBatter(_ pose: HomerunOjisanPose3) -> Entity {
        var p = HomerunAtBatLayout.batter
        p.yaw = -0.35
        return characterEntity(pose, outfit: .batter, p)
    }

    func makeUIView(context: Context) -> HomerunMirrorableView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // 触りは SwiftUI の押せる帯で受ける（`allowsHitTesting(false)` と二重に止める）。
        view.isUserInteractionEnabled = false
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
        if let rig = HomerunBatterRig() {
            rig.entity.position = HomerunAtBatLayout.batter.position
            rig.entity.orientation = simd_quatf(angle: HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0])
            anchor.addChild(rig.entity)
            context.coordinator.batterRig = rig
            if batterSwing != nil { rig.playSwing() }
            context.coordinator.batterSwing = batterSwing
        } else {
            let batter = Self.legacyBatter(batterPose)
            anchor.addChild(batter)
            context.coordinator.batter = batter
            context.coordinator.batterPose = batterPose
        }
        let pitcher = Self.characterEntity(pitcherPose, outfit: .pitcher, HomerunAtBatLayout.pitcher)
        anchor.addChild(pitcher)
        context.coordinator.pitcher = pitcher
        context.coordinator.pitcherPose = pitcherPose
        place(.catcher(), HomerunAtBatLayout.catcher)
        place(.umpire(), HomerunAtBatLayout.umpire)
        let cam = PerspectiveCamera()
        anchor.addChild(cam)
        Self.aim(cam, camera)
        context.coordinator.cameraEntity = cam
        context.coordinator.camera = camera
        view.scene.addAnchor(anchor)
        return HomerunMirrorableView(content: view, mirrored: camera.mirrored)
    }

    private static func aim(_ cam: PerspectiveCamera, _ camera: HomerunAtBatLayout.Camera) {
        cam.camera.fieldOfViewInDegrees = camera.verticalFieldOfView
        cam.look(at: camera.target, from: camera.position, relativeTo: nil)
    }

    func updateUIView(_ uiView: HomerunMirrorableView, context: Context) {
        let c = context.coordinator
        uiView.mirrored = camera.mirrored
        if let rig = c.batterRig {
            if c.batterSwing != batterSwing {
                if batterSwing != nil { rig.playSwing() } else { rig.showStance() }
                c.batterSwing = batterSwing
            }
        } else if c.batterPose != batterPose, let old = c.batter, let parent = old.parent {
            let new = Self.legacyBatter(batterPose)
            parent.addChild(new)
            parent.removeChild(old)
            c.batter = new
            c.batterPose = batterPose
        }
        if c.pitcherPose != pitcherPose, let old = c.pitcher, let parent = old.parent {
            let new = Self.characterEntity(pitcherPose, outfit: .pitcher, HomerunAtBatLayout.pitcher)
            parent.addChild(new)
            parent.removeChild(old)
            c.pitcher = new
            c.pitcherPose = pitcherPose
        }
        if c.camera != camera, let cam = c.cameraEntity {
            Self.aim(cam, camera)
            c.camera = camera
        }
    }
}

/// 中身（ARView）を左右反転できる入れ物。SwiftUI が frame を決めるのはこの入れ物で、中身は bounds と center で置いて transform を掛ける。
final class HomerunMirrorableView: UIView {
    let content: UIView
    var mirrored: Bool {
        didSet { if mirrored != oldValue { setNeedsLayout() } }
    }

    init(content: UIView, mirrored: Bool) {
        self.content = content
        self.mirrored = mirrored
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.transform = .identity
        content.bounds = bounds
        content.center = CGPoint(x: bounds.midX, y: bounds.midY)
        content.transform = mirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }
}
#endif
