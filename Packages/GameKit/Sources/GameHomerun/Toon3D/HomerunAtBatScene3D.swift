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
    /// 外の列（-0.12m）にも先端が届く 0.30m に寄せる（腰は 0.40m・バッターボックスの内側の線 0.25m の内）。z は本塁の前縁より
    /// 少し捕手側（-0.10m）にして、ジャストの打点が本塁の前縁の 0.3m 前に来るようにする。
    static let batter = Placement(position: [0.30, 0, -0.10], yaw: -.pi / 2)

    /// 打者の局所座標の点を打席の世界座標（前のカメラの置き方・鏡映なし）へ置く。
    static func batterWorld(_ local: SIMD3<Float>) -> SIMD3<Float> {
        batter.position + simd_quatf(angle: batter.yaw, axis: [0, 1, 0]).act(local)
    }
    /// 捕手は本塁の真後ろ（五角形の先端 z −0.43 の 0.5m 後ろ）でしゃがみ、ミット（左手・+x）を本塁の中央に構える（会長 QA 2026-10-01・#1673）。
    /// 以前（#1617）は大きかった捕手をゾーンと打者から逃がすため本塁の左奥（-0.6, -2.2）に置いていて、縮めた後は本塁から
    /// 外れた所にいるように見えた。後ろのカメラではゾーンの下（本塁の手前）に映り、前のカメラではヘルメットの上がゾーンの下の
    /// 段の後ろに隠れる（実際の中継のセンターカメラと同じ並び）。審判は無し（会長決裁 2026-09-30）。
    static let catcher = Placement(position: [-0.15, 0, -0.95], yaw: 0)
    /// 捕手の大きさ（頭の半径 1 の単位 → m）。打者（`characterScale` の頃の 2 頭身のおじさん）に合わせた 0.354 では、しゃがんだ
    /// 背丈が 1.38m と Meshy の打者（身長 1.72m）の肩まであって大きすぎた（#1666・会長 QA 2026-10-01）。頭の大きさが打者のヘルメットと揃う 0.18（しゃがんだ背丈 0.70m）に縮める。
    static let catcherScale: Float = 0.18
    /// 人物（打者・捕手）を x について鏡映して置くか。左右反転するカメラ（後ろ）では人物も鏡映し、
    /// 反転を打ち消す（そのままだと右打ちの Meshy の打者が画面の右に立つ左打ちに見える）。これで後ろから見て右打者が
    /// 画面の左に右打ちで立ち、捕手は画面の右へ逃げる。判定・座標・HUD は鏡映しない。
    /// 描画では人物を鏡映せず、カメラ側を鏡映して同じ画を作る（`Camera.renderPose`）。
    static func castMirrored(for camera: Camera) -> Bool { camera.mirrored }

    /// 3D の球の座標（`HomerunSwingPlan.ballPosition`）で、右打者の引っ張り（判定の負 = レフト = 三塁側）が飛ぶ x の向き（+1 / -1）。
    /// 描画では打者は鏡映せずに +x に立ち（RealityKit は右手系なので、本塁からセンターを向いて左手の +x が三塁側 = 右打者の立つ側）、
    /// 球だけを左右反転するカメラで x について鏡映して置く（`placeBall`）。どちらのカメラでも描画の上で打者の側（+x）へ
    /// 引っ張るように、反転するカメラでは鏡映の前の向きを逆にする（#1594 会長 QA 2026-09-30）。
    static func pullSideX(for camera: Camera) -> Float {
        (batter.position.x > 0 ? 1 : -1) * (castMirrored(for: camera) ? -1 : 1)
    }

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

        /// `screenPoint` の逆: 画面の点（左上 = (0, 0)・右下 = (1, 1)）に映る、奥行きの面 `z = planeZ` 上の世界の点。
        func worldPoint(screenX: Double, screenY: Double, aspect: Double, onPlaneZ planeZ: Float) -> SIMD3<Float> {
            let forward = simd_normalize(target - position)
            let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
            let up = simd_cross(right, forward)
            let halfTan = tan(Double(verticalFieldOfView) * .pi / 360)
            let sx = mirrored ? 1 - screenX : screenX
            let ray = forward + right * Float((sx - 0.5) * 2 * halfTan * aspect) + up * Float((0.5 - screenY) * 2 * halfTan)
            guard abs(ray.z) > 1e-6 else { return position }
            return position + ray * ((planeZ - position.z) / ray.z)
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
        /// 打者の背丈を画面の高さの 23% → 36% にした。マウンドのバッティングマシン（17.6m・#1612）は
        /// カメラの 10.4m 前で画角の下に外れて映らない（会長決裁でそのまま）。
        case front
        /// 後ろ: 本塁の 5.5m 後ろ・三塁側へ 0.5m（打者の側）・高さ 2.6m から、ストライクゾーンを見下ろす（画角 50°）。
        /// 打者の背丈は画面の高さの 31%（7.5m・3m・53° のときの 22% から寄せた・会長指示 2026-09-29）。
        /// 捕手の肩越しに打者・本塁・バッターボックスを手前に大きく、奥にマウンドのマシン・外野の柵を映す（左右反転で HUD の右 = 右翼に合わせる）。
        /// 三塁側へずらすのは、真後ろだと手前の捕手が本塁とゾーンの右下を塞ぐため（右端へ逃がす）。
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

    /// 投球が輪の重なる瞬間に着く点（世界座標・#1647）: 打点の奥行き（`HomerunSwingContact.approachTarget` の z）の面で、
    /// `camera` から見て 2D の的（`HomerunZoneGeometry.ballPoint`・判定のボールの位置）にちょうど重なって映る点。
    /// `screen` は 3D を描く全画面の大きさ（pt・安全域の外まで）。
    ///
    /// 以前は 3D の球が列（左右）でしか変わらない打点の上（`approachTarget`）に着き、行（上下）を無視していた。2D の的は 1 行
    /// 29.3pt ずつ上下するので、前のカメラでは上の行で球が的の約 32pt 下・下の行で約 27pt 上、後ろのカメラでは真ん中の行でも
    /// 約 24pt 上（下の行で約 54pt 上）に映っていた（iPhone 17 の画面で計算）。判定は 2D の的で測るので、球を見て照準を
    /// 合わせると判定上は大きく上を叩いたことになり、的の下を大きく外すと判定上は芯に近かった（会長 QA「下に大きく外しても
    /// 柵越え」「かなり下を狙わないと柵越えが出ない」）。判定を動かさず、3D の球の通り道を的に合わせる。
    static func pitchTarget(zone: Int, camera: Camera, screen: CGSize) -> SIMD3<Float> {
        let approach = HomerunSwingContact.approachTarget(column: HomerunSwingContact.column(zone: zone))
        guard screen.width > 0, screen.height > 0 else { return approach }
        let offset = HomerunZoneGeometry.ballPoint(zone: zone)
        return camera.worldPoint(screenX: 0.5 + Double(offset.x) / Double(screen.width),
                                 screenY: zoneScreenFraction + Double(offset.y) / Double(screen.height),
                                 aspect: Double(screen.width / screen.height), onPlaneZ: approach.z)
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

    /// 後ろのカメラで、構えの間だけ打者を本塁から離して置く幅（m・一塁側から見て外 = +x）。会長 QA 2026-09-30「後ろのとき
    /// おじさんがベースに近すぎる」。打者の置き場所（`batter`・本塁から 0.30m）はバットが外の列に届く所で決まっていて
    /// （#1558）、後ろから見ると体がゾーンの内側の列に重なる。構えでは 0.25m 外（0.55m・体がゾーンの外に出る）に立ち、
    /// 踏み込み（`HomerunBatterMotion.load`）の間に本来の位置へ寄る。振りは本来の位置でしか当たらない（当たり窓は
    /// 踏み込みを終えた後）ので、判定・打点・球の通り道は変えない。
    /// 前のカメラも同じだけずらす（#1667・会長 QA 2026-10-01）: 本来の位置の構えは右足のつま先（靴の皮の頂点）が x 0.06 まで
    /// 本塁側へ出て、バッターボックスの内側の線を越え本塁にかかっていた。
    static let backStanceSlide: Float = 0.25

    /// 後ろのカメラで、構えの間だけ打者を捕手側へ下げる幅（m・-z）。会長 QA 2026-09-30（#1619）「後ろのとき、おじさんが
    /// 前（投手側）に出すぎてバッターボックスからはみ出る」。本来の位置（z −0.10）の構えは足が z −0.37〜+0.20 で、
    /// 後ろ・上から見下ろすと体（ひざ〜頭）がボックスの前の線より奥に重なって前寄りに見える。構えでは 0.25m 下げて足を
    /// z −0.62〜−0.05（本塁の前縁より手前・ボックスの後ろ半分）に置き、外への寄り（`backStanceSlide`）と一緒に踏み込みの間に
    /// 本来の位置へ戻す（踏み込みで投手側へ出る = 実際の踏み込みと同じ向き）。当たり窓は踏み込みの後なので打点は変えない。
    static let backStanceSetBack: Float = 0.25

    /// 外へのずれ `slide`（m・`batterSlideTarget`）のときに打者を本来の位置からずらす量（m）。外（+x）と捕手側（-z）へ
    /// 同じ割合で寄せる（構え = (`backStanceSlide`, 0, −`backStanceSetBack`)・本来の位置 = 0）。
    static func batterOffset(slide: Float) -> SIMD3<Float> {
        [slide, 0, -backStanceSetBack * slide / backStanceSlide]
    }

    /// 打者を本来の位置からどれだけ外へずらして見せるか（m）の目標。構え = `backStanceSlide`、踏み込みの間に 0 へ
    /// （なめらかに）、振り（本番・素振り）の間は nil（いまのずれのまま振る = 振りの途中で滑らせない）。前・後ろのカメラで同じ（#1667）。
    static func batterSlideTarget(_ motion: HomerunBatterMotion, camera: Camera, now: Date) -> Float? {
        switch motion {
        case .stance:
            return backStanceSlide
        case .load(let start):
            let k = Float(min(max(now.timeIntervalSince(start) / HomerunBatterMotion.loadDuration, 0), 1))
            return backStanceSlide * (1 - k * k * (3 - 2 * k))
        case .swing:
            return nil
        }
    }

    /// 目標へ寄せる速さ（m/秒）。踏み込みの寄り（0.25m / 0.63 秒 ≒ 0.4m/秒）には遅れず、構えへ戻るときは瞬間移動に見えない速さ。
    static let batterSlideSpeed: Float = 0.8
}

/// 3D の打席シーン（球場 + 打者・捕手・マウンドのバッティングマシン）を SwiftUI に置く。RealityKit の描画は iOS だけ（macOS の `swift test` では空色の背景だけ）。
///
/// **当たり判定を持たない**（`allowsHitTesting(false)`）。3D は UIKit の `ARView` なので、当たり判定を残すと
/// 手前に重ねた押せる帯（`HomerunAtBatView.touchPad`）へのドラッグを `ARView` が吸ってしまい、
/// カーソルが動かずスイングもできなくなる（会長 QA 2026-09-28。チャリンコ・ブロックの SpriteView と同じ扱い）。
struct HomerunAtBatScene3DView: View {
    var batterPose: HomerunOjisanPose3 = .stance
    /// バッティングマシンの動き（`HomerunMachineMotion.state`・#1612）。
    var machine = HomerunMachineMotion.state(elapsed: nil, now: .distantPast)
    var cameraPreset: HomerunAtBatLayout.CameraPreset = .front
    /// 打球を追うカメラ（#1613・`HomerunBallChase`）。nil なら `cameraPreset` のカメラ。
    var cameraOverride: HomerunAtBatLayout.Camera? = nil
    /// Meshy の打者の動きの段階（試作）。変わるたびにその段階を流し直す（振り抜きは `start` からの経過ぶん進めた所から）。
    var batterMotion: HomerunBatterMotion = .stance
    /// 3D の球の位置（世界座標・前のカメラの置き方・`HomerunSwingPlan.ballPosition`）。nil なら見せない。
    /// 左右反転する後ろのカメラでは人物と同じく x について鏡映して置く。
    var ballPosition: SIMD3<Float>? = nil
    /// 球の拡大率（打球を追う間は遠くでも見えるよう大きくする・#1613）。
    var ballScale: Float = 1
    /// 今の時刻（振り抜きの再生位置を合わせるのに使う）。
    var now: Date = Date()
    /// 月まで飛んだ打球（#1680）の月・夜空。nil なら出さない。
    var moon: HomerunMoonShot.Look? = nil
    /// 3D の描画が落ち着いたとき（作った直後のコマ落ちが収まったとき）に 1 回だけ呼ぶ（iOS だけ）。
    var onFirstFrame: (@MainActor () -> Void)? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.31, green: 0.64, blue: 0.90), Color(red: 0.60, green: 0.82, blue: 0.96), Color(red: 0.85, green: 0.93, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            if let moon, moon.night > 0 { HomerunNightSky(amount: moon.night) }
            #if os(iOS) && canImport(RealityKit)
            HomerunAtBatSceneView(batterPose: batterPose, machine: machine, camera: cameraOverride ?? cameraPreset.camera,
                                  batterMotion: batterMotion, ballPosition: ballPosition, ballScale: ballScale, now: now,
                                  moon: moon, onFirstFrame: onFirstFrame)
            #endif
            if let moon, moon.flash > 0 { Color.white.opacity(moon.flash * 0.85) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#if os(iOS) && canImport(RealityKit)
import Combine
import RealityKit

/// 打席の 3D の控え（`HomerunAtBatSceneView.reusable`）を手放す。柵越えおじさんの画面を離れたら呼ぶ
/// （控えたままだと、ほかのゲームへ移っても球場・打者の 3D 一式がメモリに残り続ける）。
@MainActor
enum HomerunAtBatSceneReuse {
    static func drop() { HomerunAtBatSceneView.reusable = nil }
}

private struct HomerunAtBatSceneView: UIViewRepresentable {
    let batterPose: HomerunOjisanPose3
    let machine: HomerunMachineMotion.State
    let camera: HomerunAtBatLayout.Camera
    let batterMotion: HomerunBatterMotion
    let ballPosition: SIMD3<Float>?
    let ballScale: Float
    let now: Date
    let moon: HomerunMoonShot.Look?
    let onFirstFrame: (@MainActor () -> Void)?
    /// 描き始めの合図は、更新の刻みがこのコマ数続けて `steadyFrameInterval` 以内になったとき（作った直後の約 0.3〜0.5 秒は
    /// 刻みが 0.1〜0.8 秒に跳ねてコマ落ちする・シミュレータで実測。落ち着いた後の刻みは端末の負荷で 1/60〜1/20 秒）。
    static let steadyFrames = 3
    static let steadyFrameInterval: TimeInterval = 0.07
    /// 落ち着かない端末でもこのコマ数で合図を出す。
    static let maxFramesBeforeReady = 60

    /// 打者の実体（ポーズが変わったら差し替える）・マシン（動く部品の位置・向きを毎コマ変える）とカメラ（案が変わったら向け直す）。打者は Meshy のモデルが読めればそれ
    /// （`batterRig`）を使い、読めなければ旧モデル（プリミティブで組んだおじさん）をポーズごとに差し替える。
    final class Coordinator {
        var batterRig: HomerunBatterRig?
        var batterMotion: HomerunBatterMotion = .stance
        var batter: Entity?
        var batterPose: HomerunOjisanPose3?
        var machine: HomerunMachineRig?
        var cameraEntity: PerspectiveCamera?
        var camera: HomerunAtBatLayout.Camera?
        var ball: ModelEntity?
        /// 前のコマの球の位置（動いている間だけ縫い目を回す・#1656）。
        var ballPosition: SIMD3<Float>?
        /// 球の足元の影（#1648・`HomerunBallShadow`）と、いま張ってある濃さの段（変わったときだけマテリアルを差し替える）。
        var shadow: ModelEntity?
        var shadowStep: Int?
        /// 打者・マシンの足元の影（#1653・`HomerunFigureShadow`）。
        var batterShadow: ModelEntity?
        /// バットの影（#1668・`HomerunFigureShadow.bat`）。
        var batShadow: ModelEntity?
        var machineShadow: ModelEntity?
        var updates: (any Cancellable)?
        var frames = 0
        var steadyFrames = 0
        /// 打者を本来の位置から外へずらして見せている幅（m・`batterSlideTarget`）と、最後に寄せた時刻。
        var batterSlide: Float?
        var slideTick: Date?
        /// 月（#1680）。月まで飛んだ打球で初めて要るときに作って足す（ふだんは作らない）。
        var moon: HomerunMoonRig?
        /// 燃えている球（#1680）。月と同じく要るときに作る。
        var fire: HomerunFireballRig?
    }

    /// 縫い目の画像（#1656・`HomerunBallSeam`）。1 回だけ作る。作れない環境では nil で、白い球のまま。
    @MainActor private static var seamTexture: TextureResource?

    /// 3D の球（白地に赤い縫い目・陰影なし）。
    @MainActor private static func makeBall() -> ModelEntity {
        var material = UnlitMaterial()
        if seamTexture == nil, let image = HomerunBallSeam.image() {
            seamTexture = try? TextureResource.generate(from: image, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        }
        if let seamTexture {
            material.color = .init(tint: .white, texture: .init(seamTexture))
        } else {
            material.color = .init(tint: HomerunPlatformColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1))
        }
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

    /// 球の足元の影（#1648）: 半径 0.5 の円板（xz 面・角の丸め = 半分の幅で円になる）。大きさは `scale` で、濃さはマテリアルで変える。
    @MainActor private static func makeShadow() -> ModelEntity {
        let shadow = ModelEntity(mesh: .generatePlane(width: 1, depth: 1, cornerRadius: 0.5),
                                 materials: [shadowMaterial(step: HomerunBallShadow.opacityStep(HomerunBallShadow.groundOpacity))])
        shadow.isEnabled = false
        return shadow
    }

    /// 濃さの段ごとの影のマテリアル（インク色・半透明）。段の数ぶんだけ作って使い回す。
    @MainActor private static var shadowMaterials: [Int: UnlitMaterial] = [:]
    @MainActor private static func shadowMaterial(step: Int) -> UnlitMaterial {
        if let m = shadowMaterials[step] { return m }
        let ink = HomerunToonModel.ink
        var m = UnlitMaterial(color: HomerunPlatformColor(red: CGFloat((ink >> 16) & 0xFF) / 255, green: CGFloat((ink >> 8) & 0xFF) / 255,
                                                          blue: CGFloat(ink & 0xFF) / 255, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: HomerunBallShadow.opacity(step: step)))
        shadowMaterials[step] = m
        return m
    }

    /// 影を球の真下の地面に置く（球と同じく鏡映するカメラでは x を鏡映）。球が無ければ隠す。
    @MainActor private static func placeShadow(_ shadow: ModelEntity, coordinator: Coordinator, ball position: SIMD3<Float>?, ballScale: Float,
                                    camera: HomerunAtBatLayout.Camera) {
        guard let position else {
            shadow.isEnabled = false
            return
        }
        let shape = HomerunBallShadow.shape(ball: position, ballRadius: ballScale * HomerunSwingContact.ballRadius, camera: camera.position)
        let mirrored = HomerunAtBatLayout.castMirrored(for: camera)
        shadow.position = mirrored ? [-shape.center.x, shape.center.y, shape.center.z] : shape.center
        shadow.scale = [shape.radius * 2, 1, shape.radius * 2 * shape.stretch]
        // 鏡映するカメラでは向きも x について鏡映（y 軸まわりの角の符号が反転する）。
        shadow.orientation = simd_quatf(angle: mirrored ? -shape.yaw : shape.yaw, axis: [0, 1, 0])
        let step = HomerunBallShadow.opacityStep(shape.opacity)
        if coordinator.shadowStep != step {
            shadow.model?.materials = [shadowMaterial(step: step)]
            coordinator.shadowStep = step
        }
        shadow.isEnabled = true
    }

    /// 打者・マシンの足元の影（#1653）を置く。球の影と同じ円板・同じマテリアルで、人物と同じく鏡映しない（描画の世界座標）。
    @MainActor private static func placeFigureShadow(_ shadow: ModelEntity, _ shape: HomerunFigureShadow.Shape) {
        shadow.position = shape.center
        shadow.scale = [shape.radius * 2, 1, shape.radius * 2 * shape.stretch]
        shadow.orientation = simd_quatf(angle: shape.yaw, axis: [0, 1, 0])
    }

    @MainActor private static func makeFigureShadow() -> ModelEntity {
        ModelEntity(mesh: .generatePlane(width: 1, depth: 1, cornerRadius: 0.5),
                    materials: [shadowMaterial(step: HomerunBallShadow.opacityStep(HomerunFigureShadow.opacity))])
    }

    /// 打者・マシンの影をいまの打者の位置・カメラに合わせる（数個の値の計算だけ・毎コマ呼んでよい）。
    @MainActor private static func placeFigureShadows(_ c: Coordinator, batterOrigin: SIMD3<Float>, camera: HomerunAtBatLayout.Camera) {
        let eye = camera.renderPose.position
        if let s = c.batterShadow { placeFigureShadow(s, HomerunFigureShadow.batter(origin: batterOrigin, camera: eye)) }
        if let s = c.machineShadow { placeFigureShadow(s, HomerunFigureShadow.machine(camera: eye)) }
        if let s = c.batShadow {
            // バットの両端は打者の局所座標の表（`HomerunBatPath`）から、いま流しているクリップの位置で引く（骨は読まない）。
            if let rig = c.batterRig {
                let clip: TimeInterval = switch c.batterMotion {
                case .stance: 0
                case .load: rig.playbackTime ?? 0
                case .swing: rig.swingClipTime ?? HomerunBatterMotion.loadDuration
                }
                let bat = HomerunBatPath.segment(atClipTime: clip)
                let turn = simd_quatf(angle: HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0])
                let strip = HomerunFigureShadow.bat(grip: batterOrigin + turn.act(bat.grip), tip: batterOrigin + turn.act(bat.tip), camera: eye)
                s.position = strip.center
                s.scale = [strip.size.x, 1, strip.size.y]
                s.orientation = simd_quatf(angle: strip.yaw, axis: [0, 1, 0])
                s.isEnabled = true
            } else {
                s.isEnabled = false
            }
        }
    }

    /// 打席の 3D（`ARView`）を画面をまたいで使い回すための控え（#1594・会長 QA 2026-09-30）。
    ///
    /// 10 球の結果から「もう一回」で打席を作り直すと、新しい `ARView` は描き始めるまで前の `ARView` の最後のコマ
    /// （振り終わりの打者・ミット直前の球）を映したまま約 2 秒止まり、その間に 1 球目が進んで見送りで終わっていた
    /// （画面の E2E の録画で確認）。作るのは最初の 1 回だけにして、2 回目からは同じ `ARView` を今の局面に合わせ直して使う。
    @MainActor fileprivate static var reusable: (view: ARView, coordinator: Coordinator)?

    /// 控えの `ARView` がいま画面に出ていなければ、その控えの状態を使う。
    @MainActor private static var idleReusable: (view: ARView, coordinator: Coordinator)? {
        guard let reusable, reusable.view.superview == nil else { return nil }
        return reusable
    }

    func makeCoordinator() -> Coordinator { Self.idleReusable?.coordinator ?? Coordinator() }

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
        if let reused = Self.idleReusable, reused.coordinator === context.coordinator {
            // 前の打席の段階（振り終わりなど）を捨て、今の局面から流し直す。
            if let rig = reused.coordinator.batterRig {
                rig.show(batterMotion, now: now)
                reused.coordinator.batterMotion = batterMotion
            }
            reused.coordinator.batterSlide = nil
            updateUIView(reused.view, context: context)
            subscribeFirstFrame(reused.view, reused.coordinator)
            return reused.view
        }
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
        func place(_ model: HomerunToonModel, _ p: HomerunAtBatLayout.Placement, scale: Float = HomerunAtBatLayout.characterScale) {
            let e = HomerunToonScene.entity(for: model, scale: scale)
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
        let machine = HomerunMachineRig()
        machine.apply(self.machine)
        anchor.addChild(machine.entity)
        context.coordinator.machine = machine
        place(.catcher(), HomerunAtBatLayout.catcher, scale: HomerunAtBatLayout.catcherScale)
        let batterShadow = Self.makeFigureShadow(), machineShadow = Self.makeFigureShadow()
        anchor.addChild(batterShadow)
        anchor.addChild(machineShadow)
        context.coordinator.batterShadow = batterShadow
        context.coordinator.machineShadow = machineShadow
        let batShadow = Self.makeFigureShadow()
        anchor.addChild(batShadow)
        context.coordinator.batShadow = batShadow
        Self.placeFigureShadows(context.coordinator, batterOrigin: HomerunAtBatLayout.batter.position, camera: camera)
        let ball = Self.makeBall()
        anchor.addChild(ball)
        Self.placeBall(ball, at: ballPosition, camera: camera)
        context.coordinator.ball = ball
        let shadow = Self.makeShadow()
        anchor.addChild(shadow)
        context.coordinator.shadow = shadow
        Self.placeShadow(shadow, coordinator: context.coordinator, ball: ballPosition, ballScale: ballScale, camera: camera)
        let cam = PerspectiveCamera()
        anchor.addChild(cam)
        Self.aim(cam, camera)
        context.coordinator.cameraEntity = cam
        context.coordinator.camera = camera
        view.scene.addAnchor(anchor)
        subscribeFirstFrame(view, context.coordinator)
        Self.reusable = (view, context.coordinator)
        return view
    }

    /// 描き始めの合図（`onFirstFrame`）を待つ。使い回しのときも、画面に戻って描き直しが落ち着いてから知らせる。
    private func subscribeFirstFrame(_ view: ARView, _ coordinator: Coordinator) {
        coordinator.updates?.cancel()
        coordinator.updates = nil
        coordinator.frames = 0
        coordinator.steadyFrames = 0
        guard let onFirstFrame else { return }
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

    /// 画面から外れたら合図の待ちを止める（`ARView` と打者などの実体は控えに残す）。
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel()
        coordinator.updates = nil
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
            let target = HomerunAtBatLayout.batterSlideTarget(batterMotion, camera: camera, now: now)
            let current = c.batterSlide ?? target ?? 0
            var next = current
            if let target {
                let dt = Float(min(max(now.timeIntervalSince(c.slideTick ?? now), 0), 0.1))
                let step = HomerunAtBatLayout.batterSlideSpeed * dt
                // 見た目の切り替え（カメラを前 ⇄ 後ろ）ではすぐ合わせる。
                next = c.camera != camera ? target : current + min(max(target - current, -step), step)
            }
            c.batterSlide = next
            c.slideTick = now
            rig.entity.position = HomerunAtBatLayout.batter.position + HomerunAtBatLayout.batterOffset(slide: next)
        } else if c.batterPose != batterPose, let old = c.batter, let parent = old.parent {
            let new = Self.legacyBatter(batterPose)
            parent.addChild(new)
            parent.removeChild(old)
            c.batter = new
            c.batterPose = batterPose
        }
        c.machine?.apply(machine)
        Self.placeFigureShadows(c, batterOrigin: c.batterRig?.entity.position ?? HomerunAtBatLayout.batter.position, camera: camera)
        if c.camera != camera, let cam = c.cameraEntity {
            Self.aim(cam, camera)
            c.camera = camera
        }
        if let ball = c.ball {
            Self.placeBall(ball, at: ballPosition, camera: camera)
            ball.scale = SIMD3(repeating: ballScale)
            // 飛んでいる間は回して見せ、ミット・地面で止まった球は回さない。
            if let ballPosition, ballPosition != c.ballPosition { ball.orientation = HomerunBallSeam.spin(at: now) }
            c.ballPosition = ballPosition
        }
        if let shadow = c.shadow {
            Self.placeShadow(shadow, coordinator: c, ball: ballPosition, ballScale: ballScale, camera: camera)
        }
        if c.moon == nil, moon?.moonVisible == true, let anchor = c.cameraEntity?.parent {
            let rig = HomerunMoonRig()
            anchor.addChild(rig.entity)
            c.moon = rig
        }
        c.moon?.apply(moon)
        if c.fire == nil, moon?.fire != nil, let anchor = c.cameraEntity?.parent {
            let rig = HomerunFireballRig()
            anchor.addChild(rig.entity)
            c.fire = rig
        }
        c.fire?.apply(moon?.fire, camera: camera.renderPose.position)
    }
}

#endif
