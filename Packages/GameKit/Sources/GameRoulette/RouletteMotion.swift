import SwiftUI

/// ルーレットの演出の長さと形（#1318）。**状態を持たない定数と純関数だけ**を置き、View から切り出す。
///
/// ブラックジャック（`BlackjackMotion`）・ポーカー（`PokerMotion`）と同じ方針で、長さは秒の定数として
/// 持ち `Animation` はそこから組む。Reduce Motion への追従は `withGameAnimation(_:_:)` 側が持ち、
/// ON のときはホイールが止まった位置へ即座に飛ぶだけで、出目そのものは従来どおり反映される。
enum RouletteMotion {

    // MARK: - スピン（山場）

    /// ホイールが回り始めてから止まるまでの長さ（秒）。Model の待ち時間と同じ値にする
    /// （回転が止まる前に結果が出ると、止まった位置と出目が食い違って見える）。
    static let spinDuration: TimeInterval = 2.6

    /// 止まるまでに回る周回数。少なすぎると「回った」感じがせず、多すぎると目が回る。
    static let spinTurns: Double = 4

    /// スピン。減速して止まるので `easeOut`。
    static let spin: Animation = .easeOut(duration: spinDuration)

    /// `spinDuration` を Model に渡す形。Model は秒ではなく `Duration` で受ける。
    static var spinInterval: Duration {
        .milliseconds(Int((spinDuration * 1000).rounded()))
    }

    /// ポケット 1 つぶんの角度（度）。
    static let pocketStep: Double = 360 / Double(RouletteWheel.pocketCount)

    /// 回転 0 のとき、`index` 番目のポケットの中心が 12 時から時計回りに何度の位置にあるか。
    static func pocketAngle(index: Int) -> Double {
        Double(index) * pocketStep
    }

    /// `index` 番目のポケットを 12 時の玉の真下へ持ってくる回転角（度）。
    ///
    /// いまの回転角 `current` から**必ず時計回りに `spinTurns` 周以上**回って止まる値を返す
    /// （前回より小さい値を返すと逆回転になる）。`.rotationEffect` は角度を数値として補間するので、
    /// 何周ぶんでも 1 つの値で表せる。
    static func targetRotation(from current: Double, toPocket index: Int) -> Double {
        // ポケットが 12 時から `a` 度の位置にあるとき、ホイールを `-a`（= 360 - a）回すと 12 時に来る。
        let desired = (360 - pocketAngle(index: index)).truncatingRemainder(dividingBy: 360)
        let base = current + spinTurns * 360
        // `base` から先で、360 で割った余りが `desired` になる最初の値まで進める。
        let remainder = ((desired - base).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return base + remainder
    }

    /// 回っている途中で「結果まで進める」を押したとき、ホイールを止まる位置へ即座に飛ばすための値。
    ///
    /// `wheelRotation` の**状態**は回し始めた時点で既に止まる角度になっていて、動いているのは
    /// 表示だけ。同じ値を書き直しても変化にならず、走っているアニメーションは止まらない。
    /// 1 周ぶん引いた値は見た目が同じで値だけが変わるので、アニメーション無しで書けば
    /// その場で止まる。次のスピンは `targetRotation` が 360 で割った余りだけを見るので影響しない。
    static func snapped(_ rotation: Double) -> Double {
        rotation - 360
    }

    // MARK: - 結果

    /// 出目のバッジが現れるまでの長さ（秒）。日常の表示なので山場より短く取る。
    static let resultBadgeDuration: TimeInterval = 0.2

    /// 出目のバッジの出現。ホイールが止まる前に答えを見せない。
    static let resultBadge: Animation = .easeIn(duration: resultBadgeDuration)
}
