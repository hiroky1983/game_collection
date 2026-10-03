import Foundation
import simd
import HomerunCore

/// 3D の球の足元に落とす丸い影（#1648・会長 QA 2026-10-01「ボールに影を付けてほしい」）。投球中（マシン → 本塁）も
/// 打球を追うカメラの間（`HomerunBallChase`）も、同じ 1 枚の円板を球の**真下**の地面（グラウンド・マウンド・スタンドの座面）
/// に置く。トゥーン調に合わせて単色（輪郭線のインク色）の円で、高いほど薄く・少し大きく、地面に着くと濃く小さく球と重なる。
/// 見た目だけで、判定（`HomerunJudge`）と打球の道（`HomerunBallChase.Track`）は変えない。純粋な値なのでテストで固定する。
enum HomerunBallShadow {
    /// 影 1 枚の置き方（世界座標・前のカメラの置き方。鏡映するカメラでは描画側が x を鏡映する）。
    struct Shape: Equatable {
        /// 円板の中心（地面の高さ + `lift`）。
        var center: SIMD3<Float>
        /// 円の半径（m）。
        var radius: Float
        /// 濃さ（0〜1・不透明度）。
        var opacity: Float
        /// 円板を視線の向き（カメラから影へ・水平）に伸ばす倍率（1 以上・`maxStretch` まで）。低いカメラから見た平らな円は
        /// 線のようにつぶれて消えるので、画面の上で横 : 縦 = `screenAspect` の楕円に見える長さまで奥行きを伸ばす。
        var stretch: Float
        /// 伸ばす向き（y 軸まわりの回転・ラジアン。円板の奥行き = 局所 +z を、カメラから影への水平の向きに合わせる）。
        var yaw: Float
    }

    /// 画面の上での影の縦 / 横の目標（楕円の高さ = 幅の半分）。
    static let screenAspect: Float = 0.5
    /// 視線の向きへ伸ばす倍率の上限（ほぼ水平に見る追うカメラでも、球の直径の 6 倍の奥行きまで）。
    static let maxStretch: Float = 6

    /// カメラから影を見下ろす角の正弦 `sinElevation`（0 = 真横・1 = 真上）で、円が画面で `screenAspect` の楕円に映る奥行きの倍率。
    static func stretch(sinElevation: Float) -> Float {
        min(max(screenAspect / max(sinElevation, 1e-3), 1), maxStretch)
    }

    /// 地面（`groundHeight`）から円板を浮かせる高さ（m）。その所に塗ってある物の上に置いて、同じ面で描画がちらつかないようにする。
    /// 浮かせすぎると、地面に着いた球（下端が地面・見かけの半径 0.1m 以上）の中心を円板が通って影が球に隠れるので、
    /// 塗り物の無い所（外野の芝・スタンドの座面）は球の下端のすぐ上に置く。
    /// 内野（マウンド中心の土の円・半径 29m）と ファウルゾーン（|方向| ≥ 45°・芝の板 0.04）: 土 0.06・白線 0.08 の上。
    static let infieldClearance: Float = 0.09
    /// ウォーニングトラック（柵の 7m 手前から・上面 0.03）の上。
    static let trackClearance: Float = 0.035
    /// マウンドの上（投手板 0.325 の上）。
    static let moundClearance: Float = 0.03
    /// 外野の芝（上面 0）・スタンドの座面。
    static let plainClearance: Float = 0.01
    static let infieldRadius: Float = 29
    static let trackWidth: Float = 7

    /// 地面に着いた球の影: 半径は球の見かけの半径の `groundRadiusFactor` 倍・濃さ `groundOpacity`。追うカメラはほぼ水平に見るので
    /// 円板はつぶれて映る。球より少し広くして、球の下に接地の影が覗くようにする。
    static let groundRadiusFactor: Float = 1.4
    static let groundOpacity: Float = 0.55
    /// `fadeHeight` m 以上の高さの影: 半径 `highRadiusFactor` 倍・濃さ `highOpacity`（ぼやけて広がった影を単色で真似る）。
    /// 間は高さの平方根でなめらかに（上がり始めで早く薄くなる）。濃さの下限は、色とりどりの座席の上でも読める 0.25。
    static let highRadiusFactor: Float = 2.6
    static let highOpacity: Float = 0.25
    static let fadeHeight: Float = 8

    /// 濃さの刻み（マテリアルの差し替えはこの段が変わったときだけ・毎コマ作り直さない）。
    static let opacitySteps = 12

    /// 球（中心 `ball`・見かけの半径 `ballRadius`）を `camera`（位置・鏡映前の世界座標）から見たときの影。
    static func shape(ball: SIMD3<Float>, ballRadius: Float, camera: SIMD3<Float>) -> Shape {
        let ground = groundHeight(below: ball)
        let height = max(ball.y - ballRadius - ground, 0)
        let k = sqrt(min(height / fadeHeight, 1))
        let center: SIMD3<Float> = [ball.x, ground + clearance(below: ball), ball.z]
        let toShadow = center - camera
        let distance = simd_length(toShadow)
        let sinElevation = distance > 0 ? max(-toShadow.y, 0) / distance : 1
        return Shape(center: center,
                     radius: ballRadius * (groundRadiusFactor + (highRadiusFactor - groundRadiusFactor) * k),
                     opacity: groundOpacity + (highOpacity - groundOpacity) * k,
                     stretch: stretch(sinElevation: sinElevation),
                     yaw: hypot(toShadow.x, toShadow.z) > 1e-6 ? atan2(toShadow.x, toShadow.z) : 0)
    }

    /// 濃さを `opacitySteps` 段に丸めた段（0〜`opacitySteps`）。
    static func opacityStep(_ opacity: Float) -> Int {
        Int((min(max(opacity, 0), 1) * Float(opacitySteps)).rounded())
    }

    /// 段 `step` の濃さ。
    static func opacity(step: Int) -> Float { Float(step) / Float(opacitySteps) }

    // MARK: 地面

    /// マウンド（`HomerunToonModel.stadium`: 中心 (0, 18.44)・半径 2.75m・高さ 0.3m）。
    static let moundCenterZ: Float = 18.44
    static let moundRadius: Float = 2.75
    static let moundHeight: Float = 0.3

    /// 球の真下の地面の高さ（m）。グラウンドは 0、マウンドの上は 0.3、スタンドの中（前縁から最前列の座席より奥）は
    /// その所の座面の上面（`HomerunBallChase.standSurface`）。中堅のバックスクリーンの裏（|方向| < 6°）は座席が無いので 0
    /// （`HomerunBallChase.homer` と同じ扱い）。
    static func groundHeight(below p: SIMD3<Float>) -> Float {
        if hypot(p.x, p.z - moundCenterZ) <= moundRadius { return moundHeight }
        return standHeight(below: p)
    }

    /// 本塁からの方向（度・`HomerunBallChase.world` の逆: x = −s·sin θ・z = s·cos θ）と距離（m）。
    private static func polar(_ p: SIMD3<Float>) -> (degrees: Double, s: Float) {
        (Double(atan2(-p.x, p.z)) * 180 / .pi, hypot(p.x, p.z))
    }

    /// スタンドの座面の高さ（スタンドの外 = 前縁の手前・最後列の後端より先は 0）。
    private static func standHeight(below p: SIMD3<Float>) -> Float {
        let (degrees, s) = polar(p)
        guard abs(degrees) >= 6 else { return 0 }
        let front = HomerunToonModel.standFront(degrees, depth: 0)
        // 最後列の後端より先（場外の球が抜けていく所・#1654）はスタンドの外 = 地面。
        guard s - front <= HomerunBallChase.standBackEdgeDepth else { return 0 }
        return Float(HomerunBallChase.standSurface(depth: Double(s - front)))
    }

    /// 地面から円板を浮かせる高さ（その所に塗ってある物の上・`infieldClearance` ほか）。
    static func clearance(below p: SIMD3<Float>) -> Float {
        if hypot(p.x, p.z - moundCenterZ) <= moundRadius { return moundClearance }
        if standHeight(below: p) > 0 { return plainClearance }
        let (degrees, s) = polar(p)
        if hypot(p.x, p.z - moundCenterZ) <= infieldRadius || abs(degrees) >= 45 { return infieldClearance }
        if s >= Float(HomerunJudge.fence(atDirection: degrees)) - trackWidth { return trackClearance }
        return plainClearance
    }
}
