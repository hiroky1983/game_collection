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
    /// 人物の置き方はすべて打席のカメラ（センターカメラ）用。左右反転するカメラ（`Camera.mirrored`）では `castMirrored` で
    /// x について鏡映して置いた扱いになる（いまの打席のカメラは反転しない）。
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
    /// 外れた所にいるように見えた。打席のカメラ（センターカメラ）ではヘルメットの上がゾーンの下の段の後ろに隠れる
    /// （実際の中継のセンターカメラと同じ並び）。審判は無し（会長決裁 2026-09-30）。
    static let catcher = Placement(position: [-0.15, 0, -0.95], yaw: 0)
    /// 捕手の大きさ（頭の半径 1 の単位 → m）。打者（`characterScale` の頃の 2 頭身のおじさん）に合わせた 0.354 では、しゃがんだ
    /// 背丈が 1.38m と Meshy の打者（身長 1.72m）の肩まであって大きすぎた（#1666・会長 QA 2026-10-01）。頭の大きさが打者のヘルメットと揃う 0.18（しゃがんだ背丈 0.70m）に縮める。
    static let catcherScale: Float = 0.18
    /// 人物（打者・捕手）を x について鏡映して置くか。左右反転するカメラ（本塁の後ろから外野を向くカメラ用の仕組み。
    /// いまの打席のカメラは反転しない）では人物も鏡映し、反転を打ち消す（そのままだと右打ちの Meshy の打者が左打ちに見える）。
    /// 判定・座標・HUD は鏡映しない。
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

    /// 打席のカメラ: 中継のセンターカメラ（本塁から 28m・高さ 4.5m・望遠 9.6°）。会長指示「おじさん遠すぎ」（2026-09-29）で
    /// 43m・6m から寄せ、打者の背丈を画面の高さの 23% → 36% にした。マウンドのバッティングマシン（17.6m・#1612）は
    /// カメラの 10.4m 前で画角の下に外れて映らない（会長決裁でそのまま）。ストライクゾーンの中心（`zoneWorldCenter`）が
    /// 画面の横の中央・高さ `zoneScreenFraction` に映るように注視点を決めている（打席の HUD の 2D のゾーン・的・カーソルを
    /// そこへ重ねる。押せる帯の下 1/3 と重ねない）。以前は後ろのカメラとの 2 択だったが、後ろからはおじさんの表情が
    /// 見えないので廃止した（#1770・会長決裁 2026-10-02）。
    static var camera: Camera {
        .aimed(from: [0, 4.5, 28], at: zoneWorldCenter, yFraction: zoneScreenFraction, verticalFieldOfView: 9.6)
    }

    static var cameraPosition: SIMD3<Float> { camera.position }
    static var cameraTarget: SIMD3<Float> { camera.target }
    static var verticalFieldOfView: Float { camera.verticalFieldOfView }

    /// ストライクゾーンの中心（本塁の真上・胸の高さ）。
    static let zoneWorldCenter: SIMD3<Float> = [0, 0.9, 0]
    /// 2D のゾーンの中心を置く画面の高さの割合（上端 = 0）。
    static let zoneScreenFraction: Double = 0.45

    /// 世界の点が前のカメラで画面の高さのどこ（上端 = 0・下端 = 1）に映るか。
    static func screenFraction(of point: SIMD3<Float>) -> Double {
        camera.screenFraction(of: point)
    }

    /// 投球が輪の重なる瞬間に着く点（世界座標・#1647）: 打点の奥行き（`HomerunSwingContact.approachTarget` の z）の面で、
    /// `camera` から見て 2D の的（`HomerunZoneGeometry.ballPoint`・判定のボールの位置）にちょうど重なって映る点。
    /// `screen` は 3D を描く全画面の大きさ（pt・安全域の外まで）。
    ///
    /// 以前は 3D の球が列（左右）でしか変わらない打点の上（`approachTarget`）に着き、行（上下）を無視していた。2D の的は 1 行
    /// 29.3pt ずつ上下するので、打席のカメラでは上の行で球が的の約 32pt 下・下の行で約 27pt 上に映っていた（iPhone 17 の画面で計算）。判定は 2D の的で測るので、球を見て照準を
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

    /// 構えの間だけ打者を本塁から離して置く幅（m・一塁側から見て外 = +x・#1667・会長 QA 2026-10-01）。本来の位置
    /// （`batter`・本塁から 0.30m。バットが外の列に届く所で決まっている・#1558）の構えは右足のつま先（靴の皮の頂点）が
    /// x 0.06 まで本塁側へ出て、バッターボックスの内側の線を越え本塁にかかっていた。構えでは 0.25m 外（0.55m）に立ち、
    /// 踏み込み（`HomerunBatterMotion.load`）の間に本来の位置へ寄る。振りは本来の位置でしか当たらない（当たり窓は
    /// 踏み込みを終えた後）ので、判定・打点・球の通り道は変えない。
    static let stanceSlide: Float = 0.25

    /// 構えの間だけ打者を捕手側へ下げる幅（m・-z・#1619）。本来の位置（z −0.10）の構えは足が z −0.37〜+0.20 で、
    /// バッターボックスの前の線からはみ出て見えた。構えでは 0.25m 下げて足を z −0.62〜−0.05（本塁の前縁より手前・ボックスの
    /// 後ろ半分）に置き、外への寄り（`stanceSlide`）と一緒に踏み込みの間に本来の位置へ戻す（踏み込みで投手側へ出る = 実際の
    /// 踏み込みと同じ向き）。当たり窓は踏み込みの後なので打点は変えない。
    static let stanceSetBack: Float = 0.25

    /// 外へのずれ `slide`（m・`batterSlideTarget`）のときに打者を本来の位置からずらす量（m）。外（+x）と捕手側（-z）へ
    /// 同じ割合で寄せる（構え = (`stanceSlide`, 0, −`stanceSetBack`)・本来の位置 = 0）。
    static func batterOffset(slide: Float) -> SIMD3<Float> {
        [slide, 0, -stanceSetBack * slide / stanceSlide]
    }

    /// 打者を本来の位置からどれだけ外へずらして見せるか（m）の目標。構え = `stanceSlide`、踏み込みの間に 0 へ
    /// （なめらかに）、振り（本番・素振り）の間は nil（いまのずれのまま振る = 振りの途中で滑らせない）。
    static func batterSlideTarget(_ motion: HomerunBatterMotion, now: Date) -> Float? {
        switch motion {
        case .stance:
            return stanceSlide
        case .load(let start):
            let k = Float(min(max(now.timeIntervalSince(start) / HomerunBatterMotion.loadDuration, 0), 1))
            return stanceSlide * (1 - k * k * (3 - 2 * k))
        case .swing, .whiffGag, .tankobu:
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
    /// 打球を追うカメラ（#1613・`HomerunBallChase`）。nil なら打席のカメラ（`HomerunAtBatLayout.camera`）。
    var cameraOverride: HomerunAtBatLayout.Camera? = nil
    /// Meshy の打者の動きの段階（試作）。変わるたびにその段階を流し直す（振り抜きは `start` からの経過ぶん進めた所から）。
    var batterMotion: HomerunBatterMotion = .stance
    /// 結果に応じて頭に重ねる記号（#1760）。
    var faceMark: HomerunFaceMark = .none
    /// 3D の球の位置（世界座標・打席のカメラの置き方・`HomerunSwingPlan.ballPosition`）。nil なら見せない。
    /// 左右反転するカメラ（`Camera.mirrored`）では人物と同じく x について鏡映して置く。
    var ballPosition: SIMD3<Float>? = nil
    /// 球の拡大率（打球を追う間は遠くでも見えるよう大きくする・#1613）。
    var ballScale: Float = 1
    /// 今の時刻（振り抜きの再生位置を合わせるのに使う）。
    var now: Date = Date()
    /// 打者の振りの再生位置を毎コマ `now` から決め直す（ジャストミートの演出・#1775で `now` を実時刻より遅らせている間）。
    var batterClockHeld = false
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
            HomerunAtBatSceneView(batterPose: batterPose, machine: machine, camera: cameraOverride ?? HomerunAtBatLayout.camera,
                                  batterMotion: batterMotion, faceMark: faceMark, ballPosition: ballPosition, ballScale: ballScale, now: now,
                                  batterClockHeld: batterClockHeld, moon: moon, onFirstFrame: onFirstFrame)
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
/// （控えたままだと、ほかのゲームへ移っても球場・打者の 3D 一式がメモリに残り続ける）。先読み（`HomerunAtBatScenePrewarm`）も止める。
/// 部品の原本（`HomerunAtBatAssets`）はプロセスの間持つ（メッシュだけ・入り直しで頂点を計算し直さない）。
@MainActor
enum HomerunAtBatSceneReuse {
    static func drop() {
        HomerunAtBatScenePrewarm.handOff()
        HomerunAtBatSceneView.reusable = nil
    }
}

/// 打席の 3D の先読み（#1695）。打席前の画面が出て落ち着いてから、打席の `ARView` を**見えない所で**作って一度描いておき、
/// 控え（`HomerunAtBatSceneView.reusable`）に置く。「打席に立つ」（広告を見てプレイ・#1694 も同じ）で打席に入ると、
/// 2 回目以降の打席と同じ使い回しの経路に乗り、球場・打者の組み立てと最初の描画の準備（シェーダ・メッシュの転送）を待たない
/// （タップから 1 球目の合図まで Release で約 0.7〜1.0 秒 → 約 0.1 秒）。
///
/// - 見えない所: 画面のウインドウの**いちばん奥**（アプリの画面の後ろ）に全画面の大きさで差し込み、数コマ描いたら外す。
///   手前のアプリの画面は不透明なので映らない。描画は `ARView` 自身のループで行われ、覆われていても止まらない。
/// - カクつき対策: 打席前の画面が出てから `delay` 待ってから始め（画面の切り替えのアニメーション・打席前のおじさんの 3D の
///   描き始めと重ねない）、頂点の計算はバックグラウンド、主スレッドの組み立ては部品ごとに 1 コマ空ける（`HomerunAtBatAssets.preload`）。
/// - 先読みの途中で打席に入ったら（`handOff`）、そこで止めて、できている控えがあればそれを使う（無ければ従来どおりその場で作る）。
/// - メモリ: 打席に入らなくても、打席前の画面にいる間は打席の 3D 一式（球場のメッシュ・打者・`ARView`）を 1 組持つ。
///   画面を離れると `HomerunAtBatSceneReuse.drop` で手放す（打席に入った後の控えと同じ扱い）。
@MainActor
enum HomerunAtBatScenePrewarm {
    /// 打席前の画面が出てから先読みを始めるまで（秒）。
    static let delay: TimeInterval = 0.8
    /// 見えない所で描くコマ数（描き始めのコマ落ちが収まるまで・`HomerunAtBatSceneView.steadyFrames` と同じ見方）と、待つ上限（秒）。
    static let framesToRender = 6
    static let renderTimeout: TimeInterval = 2

    private static var task: Task<Void, Never>?
    private static var host: ARView?

    /// 打席前の画面が出たときに呼ぶ。控えがすでにあれば（もう一回・結果から戻ったとき）何もしない。
    static func schedule() {
        guard task == nil, HomerunAtBatSceneView.reusable == nil else { return }
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await HomerunAtBatAssets.preload()
            guard !Task.isCancelled, HomerunAtBatSceneView.reusable == nil, let window = keyWindow else { return }
            // 打者（骨の動きの準備を含む）と `ARView` 一式は 1 コマ空けて別々に作る（続けて作ると打席前の画面が約 0.1 秒止まる）。
            let rig = HomerunBatterRig()
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled, HomerunAtBatSceneView.reusable == nil else { return }
            let prepared = HomerunAtBatSceneView.prepared(camera: HomerunAtBatLayout.camera, batterRig: rig)
            HomerunAtBatSceneView.reusable = prepared
            let view = prepared.view
            view.frame = window.bounds
            // 見えない所に差している間も VoiceOver に読ませない（打席では SwiftUI 側で隠している）。
            view.accessibilityElementsHidden = true
            window.insertSubview(view, at: 0)
            host = view
            await renderFrames(view)
            if host === view {
                view.removeFromSuperview()
                host = nil
            }
        }
    }

    /// 打席の 3D が画面に出る直前・画面を離れるときに呼ぶ。先読みを止め、見えない所に差していれば外す（控えは残す）。
    static func handOff() {
        task?.cancel()
        task = nil
        host?.removeFromSuperview()
        host = nil
    }

    private static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    /// `framesToRender` コマ描くまで（上限 `renderTimeout` 秒）待つ。
    private static func renderFrames(_ view: ARView) async {
        var frames = 0
        var subscription: (any Cancellable)?
        let deadline = Date().addingTimeInterval(renderTimeout)
        subscription = view.scene.subscribe(to: SceneEvents.Update.self) { _ in frames += 1 }
        while frames < framesToRender, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
        }
        subscription?.cancel()
    }
}

private struct HomerunAtBatSceneView: UIViewRepresentable {
    let batterPose: HomerunOjisanPose3
    let machine: HomerunMachineMotion.State
    let camera: HomerunAtBatLayout.Camera
    let batterMotion: HomerunBatterMotion
    /// 結果に応じて頭に重ねる記号（#1760）。
    var faceMark: HomerunFaceMark = .none
    let ballPosition: SIMD3<Float>?
    let ballScale: Float
    let now: Date
    var batterClockHeld = false
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
        /// 実時刻より表示の時刻がどれだけ遅れているか（秒・ジャストミートの演出・#1775）。描画の更新で記号などを置くとき、
        /// `Date()` から引いて SwiftUI 側の更新と同じ時刻に揃える。
        var clockLag: TimeInterval = 0
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
        /// 空振りの演出（#1681）の回転・目・星・影を毎コマ置き直す購読（SwiftUI の更新が止まった後も動かす）。
        var whiffGagUpdates: (any Cancellable)?
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
        let ball = ModelEntity(mesh: HomerunAtBatAssets.ball(), materials: [material])
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
        let shadow = ModelEntity(mesh: HomerunAtBatAssets.disc(),
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
        ModelEntity(mesh: HomerunAtBatAssets.disc(),
                    materials: [shadowMaterial(step: HomerunBallShadow.opacityStep(HomerunFigureShadow.opacity))])
    }

    /// 打者・マシンの影をいまの打者の位置・カメラに合わせる（数個の値の計算だけ・毎コマ呼んでよい）。
    @MainActor private static func placeFigureShadows(_ c: Coordinator, batterOrigin: SIMD3<Float>, camera: HomerunAtBatLayout.Camera) {
        let eye = camera.renderPose.position
        // 空振りの演出（#1681）の間は、体全体の回転・傾きと倒れていく体・バットに影を合わせる。
        // たんこぶの演出（#1793）は体を回さず、座る位置の補正（`shift`・打者の局所）だけ掛ける。
        let gag: (clip: TimeInterval, turn: simd_quatf, shift: SIMD3<Float>)? = c.batterRig.flatMap { rig in
            if rig.isWhiffGag, let clip = rig.whiffGagClipTime { return (clip, HomerunWhiffGag.turn(atClipTime: clip), .zero) }
            if rig.isTankobu, let pose = rig.tankobuPose { return (pose.clip, simd_quatf(angle: 0, axis: [0, 1, 0]), pose.correction) }
            return nil
        }
        let facing = simd_quatf(angle: HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0])
        if let s = c.batterShadow {
            placeFigureShadow(s, gag.map {
                HomerunFigureShadow.whiffGagBatter(origin: batterOrigin + facing.act($0.shift), clipTime: $0.clip, turn: $0.turn, camera: eye)
            } ?? HomerunFigureShadow.batter(origin: batterOrigin, camera: eye))
        }
        if let s = c.machineShadow { placeFigureShadow(s, HomerunFigureShadow.machine(camera: eye)) }
        if let s = c.batShadow {
            // バットの両端は打者の局所座標の表（`HomerunBatPath`）から、いま流しているクリップの位置で引く（骨は読まない）。
            if let rig = c.batterRig {
                let clip: TimeInterval = switch c.batterMotion {
                case .stance: 0
                case .load: rig.playbackTime ?? 0
                case .swing, .whiffGag, .tankobu: rig.swingClipTime ?? HomerunBatterMotion.loadDuration
                }
                let shift = gag?.shift ?? .zero
                var bat = gag.map { HomerunFigureShadow.whiffGagBat(clipTime: $0.clip, turn: $0.turn) } ?? HomerunBatPath.segment(atClipTime: clip)
                bat = (bat.grip + shift, bat.tip + shift)
                let strip = HomerunFigureShadow.bat(grip: batterOrigin + facing.act(bat.grip), tip: batterOrigin + facing.act(bat.tip), camera: eye)
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

    func makeCoordinator() -> Coordinator {
        // 先読み（`HomerunAtBatScenePrewarm`）の途中なら止め、見えない所から外す（できていれば控えとして使う）。
        HomerunAtBatScenePrewarm.handOff()
        return Self.idleReusable?.coordinator ?? Coordinator()
    }

    /// 打席前の画面で先読みする打席の 3D（構え・球なし・マシンは止まった状態）。
    static func prepared(camera: HomerunAtBatLayout.Camera, batterRig: HomerunBatterRig?) -> (view: ARView, coordinator: Coordinator) {
        let scene = HomerunAtBatSceneView(batterPose: .stance, machine: HomerunMachineMotion.state(elapsed: nil, now: .distantPast),
                                          camera: camera, batterMotion: .stance, ballPosition: nil, ballScale: 1, now: Date(),
                                          moon: nil, onFirstFrame: nil)
        let coordinator = Coordinator()
        return (scene.build(coordinator, batterRig: batterRig), coordinator)
    }

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
            apply(reused.coordinator)
            subscribeFirstFrame(reused.view, reused.coordinator)
            Self.subscribeWhiffGag(reused.view, reused.coordinator)
            return reused.view
        }
        let view = build(context.coordinator)
        subscribeFirstFrame(view, context.coordinator)
        Self.subscribeWhiffGag(view, context.coordinator)
        Self.reusable = (view, context.coordinator)
        return view
    }

    /// 打席の 3D 一式を組み立てる。球場・捕手・マシンの部品は原本（`HomerunAtBatAssets`）の複製。
    /// `batterRig` は先に作っておいた打者（無ければここで作る）。
    private func build(_ coordinator: Coordinator, batterRig: HomerunBatterRig? = nil) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        // 触りは SwiftUI の押せる帯で受ける（`allowsHitTesting(false)` と二重に止める）。
        view.isUserInteractionEnabled = false
        view.environment.background = .color(.clear)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableHDR, .disableGroundingShadows,
                                      .disableCameraGrain, .disableAREnvironmentLighting])
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(HomerunAtBatAssets.stadium())
        if let rig = batterRig ?? HomerunBatterRig() {
            rig.entity.position = HomerunAtBatLayout.batter.position
            rig.entity.orientation = simd_quatf(angle: HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0])
            anchor.addChild(rig.entity)
            coordinator.batterRig = rig
            if batterMotion != .stance { rig.show(batterMotion, now: now) }
            coordinator.batterMotion = batterMotion
        } else {
            let batter = Self.legacyBatter(batterPose)
            anchor.addChild(batter)
            coordinator.batter = batter
            coordinator.batterPose = batterPose
        }
        let machine = HomerunMachineRig()
        machine.apply(self.machine)
        anchor.addChild(machine.entity)
        coordinator.machine = machine
        let catcher = HomerunAtBatAssets.catcher()
        catcher.scale = SIMD3(repeating: HomerunAtBatLayout.catcherScale)
        catcher.position = HomerunAtBatLayout.catcher.position
        catcher.orientation = simd_quatf(angle: HomerunAtBatLayout.catcher.yaw, axis: [0, 1, 0])
        anchor.addChild(catcher)
        let batterShadow = Self.makeFigureShadow(), machineShadow = Self.makeFigureShadow()
        anchor.addChild(batterShadow)
        anchor.addChild(machineShadow)
        coordinator.batterShadow = batterShadow
        coordinator.machineShadow = machineShadow
        let batShadow = Self.makeFigureShadow()
        anchor.addChild(batShadow)
        coordinator.batShadow = batShadow
        Self.placeFigureShadows(coordinator, batterOrigin: HomerunAtBatLayout.batter.position, camera: camera)
        let ball = Self.makeBall()
        anchor.addChild(ball)
        Self.placeBall(ball, at: ballPosition, camera: camera)
        coordinator.ball = ball
        let shadow = Self.makeShadow()
        anchor.addChild(shadow)
        coordinator.shadow = shadow
        Self.placeShadow(shadow, coordinator: coordinator, ball: ballPosition, ballScale: ballScale, camera: camera)
        let cam = PerspectiveCamera()
        anchor.addChild(cam)
        Self.aim(cam, camera)
        coordinator.cameraEntity = cam
        coordinator.camera = camera
        view.scene.addAnchor(anchor)
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

    /// 空振りの演出（#1681）の間、毎コマ（描画の更新ごと）に体全体の回転・傾き、ぐるぐる目・星、影を置き直す。結果のカードが
    /// 出た後は SwiftUI の `TimelineView` が止まり `updateUIView` が呼ばれないので、描画の更新で動かす。演出でなければ何もしない。
    private static func subscribeWhiffGag(_ view: ARView, _ coordinator: Coordinator) {
        coordinator.whiffGagUpdates?.cancel()
        coordinator.whiffGagUpdates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator] _ in
            MainActor.assumeIsolated {
                guard let coordinator, let rig = coordinator.batterRig, rig.isWhiffGag || rig.isTankobu || rig.showsFaceMark,
                      let camera = coordinator.camera else { return }
                let now = Date().addingTimeInterval(-coordinator.clockLag)
                rig.tick(now: now, clockHeld: coordinator.clockLag > 0)
                if rig.isWhiffGag {
                    rig.applyWhiffGag(now: now, camera: camera.renderPose.position)
                } else if rig.isTankobu {
                    rig.applyTankobu(now: now, camera: camera.renderPose.position)
                } else {
                    rig.applyFaceMark(now: now, camera: camera.renderPose.position)
                }
                placeFigureShadows(coordinator, batterOrigin: rig.entity.position, camera: camera)
            }
        }
    }

    /// 画面から外れたら合図の待ちを止める（`ARView` と打者などの実体は控えに残す）。
    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel()
        coordinator.updates = nil
        // 空振りの演出の購読も止める（使い回すときは `makeUIView` で張り直す）。
        coordinator.whiffGagUpdates?.cancel()
        coordinator.whiffGagUpdates = nil
    }

    private static func aim(_ cam: PerspectiveCamera, _ camera: HomerunAtBatLayout.Camera) {
        cam.camera.fieldOfViewInDegrees = camera.verticalFieldOfView
        let pose = camera.renderPose
        cam.look(at: pose.target, from: pose.position, relativeTo: nil)
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        apply(context.coordinator)
    }

    /// 今の局面（打者の動き・マシン・カメラ・球・月）に合わせ直す。
    private func apply(_ c: Coordinator) {
        if let rig = c.batterRig {
            if c.batterMotion != batterMotion {
                rig.show(batterMotion, now: now)
                c.batterMotion = batterMotion
            }
            rig.faceMark = faceMark
            c.clockLag = batterClockHeld ? max(Date().timeIntervalSince(now), 0) : 0
            rig.tick(now: now, clockHeld: batterClockHeld)
            if rig.showsFaceMark {
                rig.applyFaceMark(now: now, camera: camera.renderPose.position)
            }
            let target = HomerunAtBatLayout.batterSlideTarget(batterMotion, now: now)
            let current = c.batterSlide ?? target ?? 0
            var next = current
            if let target {
                let dt = Float(min(max(now.timeIntervalSince(c.slideTick ?? now), 0), 0.1))
                let step = HomerunAtBatLayout.batterSlideSpeed * dt
                // カメラが変わった（打球を追うカメラから打席のカメラへ戻った等）ときはすぐ合わせる。
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
