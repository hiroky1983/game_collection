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

    /// センター側の遠くからの望遠（投手と打者の大きさの差を縮め、投手は腰から上だけ映す = 中継のセンターカメラ）。
    static let cameraPosition: SIMD3<Float> = [0, 6, 43]
    /// 注視点は、ストライクゾーンの中心（`zoneWorldCenter`）が画面の高さの `zoneScreenFraction` に映るように決めている
    /// （原本より少し下を向く = 打席の HUD の 2D のゾーン・的・カーソルをそこへ重ねる。押せる帯の下 1/3 と重ねない）。
    static let cameraTarget: SIMD3<Float> = [0, 0.57, 0.3]
    static let verticalFieldOfView: Float = 9.6

    /// ストライクゾーンの中心（本塁の真上・胸の高さ）。
    static let zoneWorldCenter: SIMD3<Float> = [0, 0.9, 0]
    /// 2D のゾーンの中心を置く画面の高さの割合（上端 = 0）。
    static let zoneScreenFraction: Double = 0.45

    /// 世界の点が画面の高さのどこ（上端 = 0・下端 = 1）に映るか。カメラは左右に振らない（真正面）前提の透視投影。
    static func screenFraction(of point: SIMD3<Float>) -> Double {
        let forward = simd_normalize(cameraTarget - cameraPosition)
        let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
        let up = simd_cross(right, forward)
        let v = point - cameraPosition
        let depth = Double(simd_dot(v, forward))
        let height = Double(simd_dot(v, up))
        let halfTan = tan(Double(verticalFieldOfView) * .pi / 360)
        return 0.5 - 0.5 * height / depth / halfTan
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
    /// Meshy の打者の動きの段階（試作）。変わるたびにその段階を頭から流す。
    var batterMotion: HomerunBatterMotion = .stance

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.64, blue: 0.90), Color(red: 0.60, green: 0.82, blue: 0.96), Color(red: 0.85, green: 0.93, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            #if os(iOS) && canImport(RealityKit)
            HomerunAtBatSceneView(batterPose: batterPose, pitcherPose: pitcherPose, batterMotion: batterMotion)
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
    let batterMotion: HomerunBatterMotion

    /// 打者・投手の実体（ポーズが変わったら差し替える）。打者は Meshy のモデルが読めればそれ（`batterRig`）を使い、
    /// 読めなければ旧モデル（プリミティブで組んだおじさん）をポーズごとに差し替える。
    final class Coordinator {
        var batterRig: HomerunBatterRig?
        var batterMotion: HomerunBatterMotion = .stance
        var batter: Entity?
        var batterPose: HomerunOjisanPose3?
        var pitcher: Entity?
        var pitcherPose: HomerunOjisanPose3?
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

    func makeUIView(context: Context) -> ARView {
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
            if batterMotion != .stance { rig.show(batterMotion) }
            context.coordinator.batterMotion = batterMotion
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
        cam.camera.fieldOfViewInDegrees = HomerunAtBatLayout.verticalFieldOfView
        anchor.addChild(cam)
        cam.look(at: HomerunAtBatLayout.cameraTarget, from: HomerunAtBatLayout.cameraPosition, relativeTo: nil)
        view.scene.addAnchor(anchor)
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let c = context.coordinator
        if let rig = c.batterRig {
            if c.batterMotion != batterMotion {
                rig.show(batterMotion)
                c.batterMotion = batterMotion
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
    }
}
#endif
