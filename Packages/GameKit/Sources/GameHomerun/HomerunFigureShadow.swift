import Foundation
import simd

/// 打者のおじさん・バッティングマシンの足元に落とす丸い影（#1653・球の影 #1648 と同じ見た目で統一）。
/// 球の影（`HomerunBallShadow`）と同じインク色の半透明の円板を、足元の地面（白線・土の上へ浮かせる高さも同じ）に置き、
/// 低いカメラでは視線の向きへ伸ばして画面で横 : 縦 = 2 : 1 の楕円に見せる（線につぶれない）。
///
/// 打者の影は打者の実体（構え・踏み込みで外へずらす `batterOffset` を含む）の原点から決まった所に置く。USDZ の振りは
/// 足を踏み替えない（踏み込み・振り抜きとも両足は地面に着いたまま）ので、腰の真下の決まった楕円で足元から外れない。
/// 毎コマ骨を読まない（重い処理を足さない）。見た目だけで、判定（`HomerunJudge`）は変えない。純粋な値なのでテストで固定する。
enum HomerunFigureShadow {
    /// 影 1 枚の置き方（**描画の世界座標**。人物・マシンは鏡映せずに置き、鏡映するカメラはカメラ側を鏡映する = `Camera.renderPose`
    /// ので、影も鏡映しない）。
    typealias Shape = HomerunBallShadow.Shape

    /// 打者の影の中心（打者の実体の局所座標・m）。構えで胸が +z・左肩（投手側）が +x の向きで、両足の間・腰の真下
    /// （本来の位置で世界の x ≈ 0.40・z ≈ −0.08 = 足 z −0.37〜+0.20 の真ん中）。
    static let batterCenterLocal: SIMD3<Float> = [0.02, 0, -0.10]
    /// 打者の影の半径（m）。両足の幅（約 0.57m）と体の厚みを覆う。
    static let batterRadius: Float = 0.36
    /// バッティングマシンの影の半径（m・台の板 0.8m 角より一回り大きく、縁から覗く）。中心は台の底の中心（マシンの原点）。
    static let machineRadius: Float = 0.55
    /// 濃さ（球が地面に着いたとき 0.55 より少し淡く。人物の下の大きな影が重く見えないように）。
    static let opacity: Float = 0.42

    /// 打者の影。`batterOrigin` は打者の実体の位置（`HomerunAtBatLayout.batter.position` + ずらし）、`camera` は描画のカメラの位置
    /// （`Camera.renderPose.position`）。
    static func batter(origin batterOrigin: SIMD3<Float>, camera: SIMD3<Float>) -> Shape {
        let foot = batterOrigin + simd_quatf(angle: HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0]).act(batterCenterLocal)
        return shape(foot: foot, radius: batterRadius, camera: camera)
    }

    /// 空振りの演出（#1681・`HomerunWhiffGag`）の間の打者の影。体の中心のずれ（回って倒れて座る）と体全体の回転・傾き `turn` を掛けた
    /// 所に置く（クリップ時刻 `clipTime` の 20 コマ目では `batter` と同じ所）。
    static func whiffGagBatter(origin batterOrigin: SIMD3<Float>, clipTime: TimeInterval, turn: simd_quatf, camera: SIMD3<Float>) -> Shape {
        let local = HomerunWhiffGag.place(batterCenterLocal + HomerunWhiffGag.bodyShift(atClipTime: clipTime), turn: turn)
        let foot = batterOrigin + simd_quatf(angle: HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0]).act(local)
        return shape(foot: foot, radius: batterRadius, camera: camera)
    }

    /// 空振りの演出の間のバットの両端（打者の局所・回転・傾きを掛けた）。振り終わり（44 コマ）までは振りの表（`HomerunBatPath`）、
    /// その後は演出の表から引く。
    static func whiffGagBat(clipTime: TimeInterval, turn: simd_quatf) -> (grip: SIMD3<Float>, tip: SIMD3<Float>) {
        let bat = clipTime <= HomerunBatPath.duration ? HomerunBatPath.segment(atClipTime: clipTime) : HomerunWhiffGag.bat(atClipTime: clipTime)
        return (HomerunWhiffGag.place(bat.grip, turn: turn), HomerunWhiffGag.place(bat.tip, turn: turn))
    }

    /// バッティングマシンの影（マシンは動かないので置き場所は `HomerunAtBatLayout.machine` で決まる）。
    static func machine(camera: SIMD3<Float>) -> Shape {
        shape(foot: HomerunAtBatLayout.machine.position, radius: machineRadius, camera: camera)
    }

    /// バットの影（#1668）: 細長い楕円（横 `size.x`・縦 `size.y` の円板を縦がバットの向きに沿うよう `yaw` 回す）。描画の世界座標。
    struct Strip: Equatable {
        var center: SIMD3<Float>
        var size: SIMD2<Float>
        var yaw: Float
    }

    /// バットの影の太さ（m・バットの太さ 7cm より少しぼかして太め）。
    static let batWidth: Float = 0.09

    /// バットの影（#1668・会長 QA 2026-10-01「バットの影が無い」）。グリップ端 `grip`・先端 `tip`（描画の世界座標）を真下の地面へ
    /// 落とした線分を覆う細長い楕円。真上から照らす体の影と同じ向きの光で、構えのように立てたバットは手元の短い影になる。
    /// 低いカメラでは体の影と同じ `HomerunBallShadow.stretch` の分だけ、視線の向きに沿う成分を伸ばす（線につぶれない）。
    /// 骨は読まず、打者の局所座標のバットの表（`HomerunBatPath`）から両端を引くだけ（毎コマ数個の値の計算）。
    static func bat(grip: SIMD3<Float>, tip: SIMD3<Float>, camera: SIMD3<Float>) -> Strip {
        let mid = (grip + tip) / 2
        let center: SIMD3<Float> = [mid.x, HomerunBallShadow.groundHeight(below: mid) + HomerunBallShadow.clearance(below: mid), mid.z]
        let along = SIMD2<Float>(tip.x - grip.x, tip.z - grip.z)
        let length = simd_length(along)
        let dir = length > 1e-5 ? along / length : SIMD2<Float>(0, 1)
        let toShadow = center - camera
        let distance = simd_length(toShadow)
        let sinElevation = distance > 0 ? max(-toShadow.y, 0) / distance : 1
        let stretch = HomerunBallShadow.stretch(sinElevation: sinElevation)
        let flat = SIMD2<Float>(toShadow.x, toShadow.z)
        let view = simd_length(flat) > 1e-6 ? simd_normalize(flat) : SIMD2<Float>(0, 1)
        // 視線に沿う成分ほど伸ばす（沿う向き = 1 で stretch 倍・直交 = 1 倍）。
        func grow(_ d: SIMD2<Float>) -> Float { 1 + (stretch - 1) * abs(simd_dot(d, view)) }
        let side = SIMD2<Float>(-dir.y, dir.x)
        return Strip(center: center,
                     size: [batWidth * grow(side), (length + batWidth) * grow(dir)],
                     yaw: atan2(dir.x, dir.y))
    }

    /// 足元 `foot`（x・z を使う）の地面に、半径 `radius` の円板を置く。浮かせる高さは球の影と同じ（`HomerunBallShadow.clearance`）。
    static func shape(foot: SIMD3<Float>, radius: Float, camera: SIMD3<Float>) -> Shape {
        let center: SIMD3<Float> = [foot.x, HomerunBallShadow.groundHeight(below: foot) + HomerunBallShadow.clearance(below: foot), foot.z]
        let toShadow = center - camera
        let distance = simd_length(toShadow)
        let sinElevation = distance > 0 ? max(-toShadow.y, 0) / distance : 1
        return Shape(center: center, radius: radius, opacity: opacity,
                     stretch: HomerunBallShadow.stretch(sinElevation: sinElevation),
                     yaw: hypot(toShadow.x, toShadow.z) > 1e-6 ? atan2(toShadow.x, toShadow.z) : 0)
    }
}
