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
    }

    /// 地面から円板を浮かせる高さ（m）。白線（上面 0.08m）・土（0.06m）より上に置いて、同じ面で描画がちらつかないようにする。
    /// 追う球は地面に着くと中心が見かけの半径（0.1m 以上・`HomerunBallChase.ballScale`）の高さに来るので、円板は球の中心より下。
    static let lift: Float = 0.1

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

    /// 球（中心 `ball`・見かけの半径 `ballRadius`）の影。
    static func shape(ball: SIMD3<Float>, ballRadius: Float) -> Shape {
        let ground = groundHeight(below: ball)
        let height = max(ball.y - ballRadius - ground, 0)
        let k = sqrt(min(height / fadeHeight, 1))
        return Shape(center: [ball.x, ground + lift, ball.z],
                     radius: ballRadius * (groundRadiusFactor + (highRadiusFactor - groundRadiusFactor) * k),
                     opacity: groundOpacity + (highOpacity - groundOpacity) * k)
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
        // 本塁からの方向（度・`HomerunBallChase.world` の逆: x = −s·sin θ・z = s·cos θ）と距離。
        let degrees = Double(atan2(-p.x, p.z)) * 180 / .pi
        let s = hypot(p.x, p.z)
        guard abs(degrees) >= 6 else { return 0 }
        let front = HomerunToonModel.standFront(degrees, depth: 0)
        let depth = Double(s - front)
        return Float(HomerunBallChase.standSurface(depth: depth))
    }
}
