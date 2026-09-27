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

    /// 打者（右打席・胸を少し一塁側に開く）。
    static let batter = Placement(position: [-1.0, 0, 0.15], yaw: 0.35)
    /// 審判は捕手の後ろ（ほとんど隠れる）。捕手は本塁の少し一塁側・奥で、リングとストライクゾーンの周りを空ける。
    static let umpire = Placement(position: [0.75, 0, -3.2], yaw: 0)
    static let catcher = Placement(position: [0.6, 0, -2.2], yaw: 0)
    /// 投手はマウンドの上・本塁に向く（カメラに背中）。
    static let pitcher = Placement(position: [0, 0.3, 17.4], yaw: .pi)

    /// カメラ（位置・注視点・垂直画角）。純粋な値なので、どの点が画面のどこに映るかをテストで固定できる。
    struct Camera: Equatable {
        var position: SIMD3<Float>
        var target: SIMD3<Float>
        var verticalFieldOfView: Float

        /// 世界の点が画面のどこ（左上 = (0, 0)・右下 = (1, 1)）に映るか。`aspect` は画面の幅 / 高さ。透視投影・ロール無し。
        func screenPoint(of point: SIMD3<Float>, aspect: Double) -> (x: Double, y: Double) {
            let forward = simd_normalize(target - position)
            let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
            let up = simd_cross(right, forward)
            let v = point - position
            let depth = Double(simd_dot(v, forward))
            let halfTan = tan(Double(verticalFieldOfView) * .pi / 360)
            return (0.5 + 0.5 * Double(simd_dot(v, right)) / depth / (halfTan * aspect),
                    0.5 - 0.5 * Double(simd_dot(v, up)) / depth / halfTan)
        }

        /// 世界の点が画面の高さのどこ（上端 = 0・下端 = 1）に映るか。
        func screenFraction(of point: SIMD3<Float>) -> Double { screenPoint(of: point, aspect: 1).y }

        /// `anchor` が画面の横の中央・高さ `yFraction` に映るように注視点を決めたカメラ。
        /// 注視点は anchor を通る鉛直面の中にあり、anchor の向きから δ（tan δ = (1 − 2·yFraction)·tan(fov/2)）だけ下を向く。
        static func aimed(from position: SIMD3<Float>, at anchor: SIMD3<Float>, yFraction: Double, verticalFieldOfView fov: Float) -> Camera {
            let v = anchor - position
            let ahead = simd_normalize(v)
            let right = simd_normalize(simd_cross(ahead, [0, 1, 0]))
            let up = simd_cross(right, ahead)
            let delta = atan((1 - 2 * Float(yFraction)) * tan(fov * .pi / 360))
            let forward = ahead * cos(delta) - up * sin(delta)
            return Camera(position: position, target: position + forward * simd_length(v), verticalFieldOfView: fov)
        }
    }

    /// 打席カメラの案（#1506 のモック。会長が選ぶまで既定は `.center`）。どの案もストライクゾーンの中心が
    /// 画面の横の中央・高さ `zoneScreenFraction` に映る（2D のゾーン・的・カーソルの位置と片手操作を変えないため）。
    enum CameraPreset: String, CaseIterable, Sendable {
        /// 現行: 中継のセンターカメラ（本塁から 43m・高さ 6m・望遠 9.6°・ほぼ水平）。
        case center
        /// 案 A「中継・センター高め」: センター（やや一塁側 x 1m）・高さ 9.5m から 12° 見下ろす望遠。打者は正面のまま内野の土・走路・打席が
        /// 奥行きをもって見え、投手は帽子だけが下端に残る（横へ寄せる・近づけるほど投手が画面の下に落ちるので、寄せは 1m に留めた）。
        case broadcastHigh
        /// 案 B「バックネット裏の高め」: 本塁の 14m 後ろ・高さ 8m から 27° 見下ろす。打者は背中・捕手越しに投手と外野の柵・スタンドまで映る。
        case highHome
        /// 案 C「打者の斜め後ろ上方」: 三塁側やや後ろ（x −2.5m・z −13m）・高さ 5m から 17° 見下ろす。打者の背中越しに投手が右上に映る。
        case overShoulder

        var title: String {
            switch self {
            case .center: "現行（センターカメラ・水平）"
            case .broadcastHigh: "案 A 中継・センター高め（やや一塁側）"
            case .highHome: "案 B バックネット裏の高め"
            case .overShoulder: "案 C 打者の斜め後ろ上方"
            }
        }

        var camera: Camera {
            let zone = HomerunAtBatLayout.zoneWorldCenter, y = HomerunAtBatLayout.zoneScreenFraction
            switch self {
            case .center:
                return Camera(position: [0, 6, 43], target: [0, 0.57, 0.3], verticalFieldOfView: 9.6)
            case .broadcastHigh:
                return .aimed(from: [1, 9.5, 40], at: zone, yFraction: y, verticalFieldOfView: 11.5)
            case .highHome:
                return .aimed(from: [0.5, 8, -14], at: zone, yFraction: y, verticalFieldOfView: 50)
            case .overShoulder:
                return .aimed(from: [-2.5, 5, -13], at: zone, yFraction: y, verticalFieldOfView: 42)
            }
        }
    }

    /// 現行のセンターカメラ（`CameraPreset.center`）。センター側の遠くからの望遠（投手と打者の大きさの差を縮め、
    /// 投手は腰から上だけ映す = 中継のセンターカメラ）。注視点は、ストライクゾーンの中心（`zoneWorldCenter`）が画面の高さの
    /// `zoneScreenFraction` に映るように決めている（原本より少し下を向く = 打席の HUD の 2D のゾーン・的・カーソルをそこへ重ねる。
    /// 押せる帯の下 1/3 と重ねない）。
    static var cameraPosition: SIMD3<Float> { CameraPreset.center.camera.position }
    static var cameraTarget: SIMD3<Float> { CameraPreset.center.camera.target }
    static var verticalFieldOfView: Float { CameraPreset.center.camera.verticalFieldOfView }

    /// ストライクゾーンの中心（本塁の真上・胸の高さ）。
    static let zoneWorldCenter: SIMD3<Float> = [0, 0.9, 0]
    /// 2D のゾーンの中心を置く画面の高さの割合（上端 = 0）。
    static let zoneScreenFraction: Double = 0.45

    /// 世界の点が現行のセンターカメラで画面の高さのどこ（上端 = 0・下端 = 1）に映るか。
    static func screenFraction(of point: SIMD3<Float>) -> Double {
        CameraPreset.center.camera.screenFraction(of: point)
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
struct HomerunAtBatScene3DView: View {
    var batterPose: HomerunOjisanPose3 = .stance
    var pitcherPose: HomerunOjisanPose3 = .pitch
    var cameraPreset: HomerunAtBatLayout.CameraPreset = .center

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.64, blue: 0.90), Color(red: 0.60, green: 0.82, blue: 0.96), Color(red: 0.85, green: 0.93, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            #if os(iOS) && canImport(RealityKit)
            HomerunAtBatSceneView(batterPose: batterPose, pitcherPose: pitcherPose, camera: cameraPreset.camera)
            #endif
        }
        .accessibilityHidden(true)
    }
}

#if os(iOS) && canImport(RealityKit)
import RealityKit

private struct HomerunAtBatSceneView: UIViewRepresentable {
    let batterPose: HomerunOjisanPose3
    let pitcherPose: HomerunOjisanPose3
    let camera: HomerunAtBatLayout.Camera

    /// 打者・投手の実体（ポーズが変わったら差し替える）とカメラ（案が変わったら向け直す）。
    final class Coordinator {
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
        let batter = Self.characterEntity(batterPose, outfit: .batter, HomerunAtBatLayout.batter)
        anchor.addChild(batter)
        context.coordinator.batter = batter
        context.coordinator.batterPose = batterPose
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
        return view
    }

    private static func aim(_ cam: PerspectiveCamera, _ camera: HomerunAtBatLayout.Camera) {
        cam.camera.fieldOfViewInDegrees = camera.verticalFieldOfView
        cam.look(at: camera.target, from: camera.position, relativeTo: nil)
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let c = context.coordinator
        if c.batterPose != batterPose, let old = c.batter, let parent = old.parent {
            let new = Self.characterEntity(batterPose, outfit: .batter, HomerunAtBatLayout.batter)
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
#endif
