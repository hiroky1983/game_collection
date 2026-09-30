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

    /// 打者（右打者を中継のセンターカメラのように**前のカメラの画面の右**に立たせる = +x）。Meshy の 3D モデル（`HomerunBatterAsset`）は構えで
    /// 胸が +z・左肩が +x を向いているので、y 軸で -90° 回して左肩を投手（+z）へ、胸を本塁（-x）へ向ける（試作）。
    /// 人物の置き方はすべて前のカメラ用。左右反転する後ろのカメラでは `castMirrored` で x について鏡映して置いた扱いになる。
    ///
    /// 本塁からの距離は**バットが球の通り道に届く所**（`HomerunSwingContact`）。USDZ のスイングは腕を伸ばさず、バットの先端は
    /// 打者の原点から本塁側へ 0.48m しか出ない（実寸で測った値）。0.95m に置くと先端が本塁の 0.5m 手前で止まるので、
    /// 外の列（-0.12m）にも先端が届く 0.30m に寄せる（腰は 0.40m・バッターボックスの内側の線 0.29m の内）。z は本塁の前縁より
    /// 少し捕手側（-0.10m）にして、ジャストの打点が本塁の前縁の 0.3m 前に来るようにする。
    static let batter = Placement(position: [0.30, 0, -0.10], yaw: -.pi / 2)

    /// 打者の局所座標の点を打席の世界座標（前のカメラの置き方・鏡映なし）へ置く。
    static func batterWorld(_ local: SIMD3<Float>) -> SIMD3<Float> {
        batter.position + simd_quatf(angle: batter.yaw, axis: [0, 1, 0]).act(local)
    }
    /// 審判は捕手の後ろ（ほとんど隠れる）。捕手は本塁の少し打者と反対側（-x）・奥で、リングとストライクゾーンと打者の周りを空ける。
    static let umpire = Placement(position: [-0.75, 0, -3.2], yaw: 0)
    static let catcher = Placement(position: [-0.6, 0, -2.2], yaw: 0)
    /// 投手はマウンドの上・本塁に向く（カメラに背中）。
    static let pitcher = Placement(position: [0, 0.3, 17.4], yaw: .pi)

    /// 人物（打者・投手・捕手・審判）を x について鏡映して置くか。左右反転するカメラ（後ろ）では人物も鏡映し、
    /// 反転を打ち消す（そのままだと右打ちの Meshy の打者が画面の右に立つ左打ちに見える）。これで後ろから見て右打者が
    /// 画面の左に右打ちで立ち、捕手・審判は画面の右へ逃げる。判定・座標・HUD は鏡映しない。
    /// 描画では人物を鏡映せず、カメラ側を鏡映して同じ画を作る（`Camera.renderPose`）。
    static func castMirrored(for camera: Camera) -> Bool { camera.mirrored }

    /// 人物の置き方 `p` の中の点（人物の局所座標・`characterScale` 済みのメートル）が、`camera` の投影（`screenPoint`）で
    /// 世界のどこにある扱いになるか。テストはこれで画面の位置を測る（描画が同じ画になることは `renderPose` のテストで固定）。
    static func worldPoint(_ local: SIMD3<Float>, of p: Placement, for camera: Camera) -> SIMD3<Float> {
        let point = p.position + simd_quatf(angle: p.yaw, axis: [0, 1, 0]).act(local)
        return castMirrored(for: camera) ? [-point.x, point.y, point.z] : point
    }

    /// カメラ（位置・注視点・垂直画角）。純粋な値なので、どの点が画面のどこに映るかをテストで固定できる。
    struct Camera: Equatable {
        var position: SIMD3<Float>
        var target: SIMD3<Float>
        var verticalFieldOfView: Float
        /// 描画を左右反転する。世界座標は +x が一塁側で、センターカメラ（本塁を向く）では +x が画面の右 = HUD の方向メーター・
        /// スプレーチャートの「右」と一致する。本塁の後ろから外野を向くカメラでは +x が画面の左に来て HUD と食い違うので反転して合わせる
        /// （人物は `castMirrored` で鏡映した扱い。描画は反転の代わりにカメラを鏡映する = `renderPose`）。
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

        /// RealityKit のカメラを置く位置・注視点。左右反転するカメラは、描画を反転して人物を鏡映する（`castMirrored`）代わりに、
        /// カメラの位置・注視点を x について鏡映して反転なしで描く。人物を鏡映すると三角形の表裏が入れ替わり、iOS 17 では
        /// `UnlitMaterial` のカリングを変えられず反転ハルの輪郭線が体を覆って真っ黒になるため。球場は左右対称なので、
        /// 画は「球場も人物も鏡映して描画を反転する」のと同じになる（`screenPoint` と一致することをテストで固定）。
        var renderPose: (position: SIMD3<Float>, target: SIMD3<Float>) {
            guard mirrored else { return (position, target) }
            return ([-position.x, position.y, position.z], [-target.x, target.y, target.z])
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
        /// 前: 中継のセンターカメラ（本塁から 28m・高さ 4.5m・望遠 9.6°）。会長指示「おじさん遠すぎ」（2026-09-29）で 43m・6m から寄せ、
        /// 打者の背丈を画面の高さの 23% → 36% にした。投手（マウンド 17.4m）はカメラの 10.6m 前で画角の下に外れる
        /// （投手はバッティングマシンに置き換える予定なので画面内の制約を外した）。
        case front
        /// 後ろ: 本塁の 5.5m 後ろ・三塁側へ 0.5m（打者の側）・高さ 2.6m から、ストライクゾーンを見下ろす（画角 50°）。
        /// 打者の背丈は画面の高さの 31%（7.5m・3m・53° のときの 22% から寄せた・会長指示 2026-09-29）。
        /// 審判・捕手の肩越しに打者・本塁・バッターボックスを手前に大きく、奥に投手・外野の柵を映す（左右反転で HUD の右 = 右翼に合わせる）。
        /// 三塁側へずらすのは、真後ろだと手前の審判・捕手が本塁とゾーンの右下を塞ぐため（右端へ逃がす。審判・捕手は廃止予定）。
        case back

        /// 一時停止の画面のカメラの 2 択の文言。
        var title: String {
            switch self {
            case .front: "カメラ: 前"
            case .back: "カメラ: 後ろ"
            }
        }

        var camera: Camera {
            switch self {
            case .front:
                return .aimed(from: [0, 4.5, 28], at: HomerunAtBatLayout.zoneWorldCenter,
                              yFraction: HomerunAtBatLayout.zoneScreenFraction, verticalFieldOfView: 9.6)
            case .back:
                return .aimed(from: [-0.5, 2.6, -5.5], at: HomerunAtBatLayout.zoneWorldCenter,
                              yFraction: HomerunAtBatLayout.zoneScreenFraction, verticalFieldOfView: 50, mirrored: true)
            }
        }
    }

    /// 前のカメラ（`CameraPreset.front`）。センター側からの望遠（中継のセンターカメラ）。注視点は、ストライクゾーンの中心
    /// （`zoneWorldCenter`）が画面の高さの `zoneScreenFraction` に映るように決めている（打席の HUD の 2D のゾーン・的・カーソルを
    /// そこへ重ねる。押せる帯の下 1/3 と重ねない）。
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
    /// Meshy の打者の動きの段階（試作）。変わるたびにその段階を流し直す（振り抜きは `start` からの経過ぶん進めた所から）。
    var batterMotion: HomerunBatterMotion = .stance
    /// 3D の球の位置（世界座標・前のカメラの置き方・`HomerunSwingPlan.ballPosition`）。nil なら見せない。
    /// 左右反転する後ろのカメラでは人物と同じく x について鏡映して置く。
    var ballPosition: SIMD3<Float>? = nil
    /// 今の時刻（振り抜きの再生位置を合わせるのに使う）。
    var now: Date = Date()
    /// 3D の描画が落ち着いたとき（作った直後のコマ落ちが収まったとき）に 1 回だけ呼ぶ（iOS だけ）。
    var onFirstFrame: (@MainActor () -> Void)? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.64, blue: 0.90), Color(red: 0.60, green: 0.82, blue: 0.96), Color(red: 0.85, green: 0.93, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            #if os(iOS) && canImport(RealityKit)
            HomerunAtBatSceneView(batterPose: batterPose, pitcherPose: pitcherPose, camera: cameraPreset.camera,
                                  batterMotion: batterMotion, ballPosition: ballPosition, now: now, onFirstFrame: onFirstFrame)
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(iOS) && canImport(RealityKit)
import Combine
import RealityKit

private struct HomerunAtBatSceneView: UIViewRepresentable {
    let batterPose: HomerunOjisanPose3
    let pitcherPose: HomerunOjisanPose3
    let camera: HomerunAtBatLayout.Camera
    let batterMotion: HomerunBatterMotion
    let ballPosition: SIMD3<Float>?
    let now: Date
    let onFirstFrame: (@MainActor () -> Void)?
    /// 描き始めの合図は、更新の刻みがこのコマ数続けて `steadyFrameInterval` 以内になったとき（作った直後の約 0.3〜0.5 秒は
    /// 刻みが 0.1〜0.8 秒に跳ねてコマ落ちする・シミュレータで実測。落ち着いた後の刻みは端末の負荷で 1/60〜1/20 秒）。
    static let steadyFrames = 3
    static let steadyFrameInterval: TimeInterval = 0.07
    /// 落ち着かない端末でもこのコマ数で合図を出す。
    static let maxFramesBeforeReady = 60

    /// 打者・投手の実体（ポーズが変わったら差し替える）とカメラ（案が変わったら向け直す）。打者は Meshy のモデルが読めればそれ
    /// （`batterRig`）を使い、読めなければ旧モデル（プリミティブで組んだおじさん）をポーズごとに差し替える。
    final class Coordinator {
        var batterRig: HomerunBatterRig?
        var batterMotion: HomerunBatterMotion = .stance
        var batter: Entity?
        var batterPose: HomerunOjisanPose3?
        var pitcher: Entity?
        var pitcherPose: HomerunOjisanPose3?
        var cameraEntity: PerspectiveCamera?
        var camera: HomerunAtBatLayout.Camera?
        var ball: ModelEntity?
        var updates: (any Cancellable)?
        var frames = 0
        var steadyFrames = 0
    }

    /// 3D の球（白い球・陰影なし）。
    private static func makeBall() -> ModelEntity {
        var material = UnlitMaterial()
        material.color = .init(tint: HomerunPlatformColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1))
        let ball = ModelEntity(mesh: .generateSphere(radius: HomerunSwingContact.ballRadius), materials: [material])
        ball.isEnabled = false
        return ball
    }

    /// 球を置く（鏡映するカメラでは人物と同じく x を鏡映）。nil なら隠す。
    private static func placeBall(_ ball: ModelEntity, at position: SIMD3<Float>?, camera: HomerunAtBatLayout.Camera) {
        guard let position else {
            ball.isEnabled = false
            return
        }
        ball.position = HomerunAtBatLayout.castMirrored(for: camera) ? [-position.x, position.y, position.z] : position
        ball.isEnabled = true
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
            if batterMotion != .stance { rig.show(batterMotion, now: now) }
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
        let ball = Self.makeBall()
        anchor.addChild(ball)
        Self.placeBall(ball, at: ballPosition, camera: camera)
        context.coordinator.ball = ball
        let cam = PerspectiveCamera()
        anchor.addChild(cam)
        Self.aim(cam, camera)
        context.coordinator.cameraEntity = cam
        context.coordinator.camera = camera
        view.scene.addAnchor(anchor)
        if let onFirstFrame {
            let coordinator = context.coordinator
            coordinator.updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator] event in
                guard let coordinator else { return }
                coordinator.frames += 1
                coordinator.steadyFrames = event.deltaTime <= Self.steadyFrameInterval ? coordinator.steadyFrames + 1 : 0
                guard coordinator.steadyFrames >= Self.steadyFrames || coordinator.frames >= Self.maxFramesBeforeReady else { return }
                coordinator.updates?.cancel()
                coordinator.updates = nil
                MainActor.assumeIsolated { onFirstFrame() }
            }
        }
        return view
    }

    private static func aim(_ cam: PerspectiveCamera, _ camera: HomerunAtBatLayout.Camera) {
        cam.camera.fieldOfViewInDegrees = camera.verticalFieldOfView
        let pose = camera.renderPose
        cam.look(at: pose.target, from: pose.position, relativeTo: nil)
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        let c = context.coordinator
        if let rig = c.batterRig {
            if c.batterMotion != batterMotion {
                rig.show(batterMotion, now: now)
                c.batterMotion = batterMotion
            }
            rig.tick(now: now)
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
        if let ball = c.ball { Self.placeBall(ball, at: ballPosition, camera: camera) }
    }
}

#endif
