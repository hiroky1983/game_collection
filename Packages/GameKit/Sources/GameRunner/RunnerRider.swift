import Foundation

/// 走者ノードのローカル座標の点（原点 = 接地点）。
struct RunnerPoint: Equatable, Sendable {
    var x: Double
    var y: Double
}

/// 自転車に乗ったおじさんの体の寸法と、漕ぐ脚の形（#569 決裁A「絵の底上げ」）。
///
/// **SpriteKit に依存しない純粋な幾何**にしてある。脚は腰・膝・ペダルの2リンクで組むので、
/// 位相によっては「膝が伸びきる」「関節が裏返る」といった破綻が起きうるが、その検証を
/// シミュレータ抜きで回せる（地形・当たり判定を値型に寄せてあるのと同じ分け方）。
/// `RunnerScene` はここで出た座標をノードへ写すだけで、寸法を自前で持たない。
enum RunnerRider {
    // MARK: - 寸法

    /// 腰（脚の付け根）。サドルの少し上・前。
    static let hip = RunnerPoint(x: -1.2, y: 6.4)
    /// 肩（腕の付け根）。
    static let shoulder = RunnerPoint(x: 0.55, y: 8.5)
    /// ハンドルの握り（腕の先）。
    static let grip = RunnerPoint(x: 2.95, y: 6.7)
    /// クランクの軸（ペダルの回転中心）。車体の下端。
    ///
    /// **腰との高低差が脚の見え方を決める**。腰に近づけると腿が水平に張り出して
    /// 「脚を前へ突き出して座っている」形になり、漕いでいるように見えない
    /// （最初の実機確認で判明）。走者の寸法は変えられないので、軸を下げて差を稼ぐ。
    static let crank = RunnerPoint(x: 0.2, y: 3.6)
    /// 後輪・前輪の軸。
    static let rearHub = RunnerPoint(x: -2.6, y: 2.6)
    static let frontHub = RunnerPoint(x: 2.6, y: 2.6)
    /// ハンドルの付け根（フォークの上端）。
    static let headTop = RunnerPoint(x: 2.5, y: 6.3)
    /// サドルの付け根（シートチューブの上端）。
    static let seatBase = RunnerPoint(x: -2.0, y: 6.1)
    /// クランクの腕の長さ。
    static let crankRadius: Double = 1.1
    /// 腿の長さ。
    static let thigh: Double = 2.2
    /// すねの長さ。
    static let shin: Double = 2.3
    /// クランク 1 回転で進む距離（ワールド単位）。
    ///
    /// 実車のギア比の代わりに、ケイデンスがそれらしく見える値を置く。小さくすると脚が
    /// 高速で回りすぎ、大きくすると走っているのに漕いでいないように見える。
    static let crankTravel: Double = 13

    // MARK: - 脚

    /// 片脚の形。
    struct Leg: Equatable, Sendable {
        var hip: RunnerPoint
        var knee: RunnerPoint
        var pedal: RunnerPoint
    }

    /// クランクの位相（ラジアン）を、接地して進んだ距離から進める。
    ///
    /// **接地しているあいだだけ進める**。空中ではペダルを漕げない（`RunnerField.currentSpeed` が
    /// 乗りを無視するのと同じ扱い）ので、脚も止まって見えるのが正しい。
    /// 距離が戻る場合（ステージのやり直し・チェックポイント再開）は進めない。
    static func advance(phase: Double, by distanceDelta: Double, isPedaling: Bool) -> Double {
        guard isPedaling, distanceDelta > 0 else { return phase }
        return phase + distanceDelta / crankTravel * 2 * .pi
    }

    /// ペダルの位置。`isFar` の脚は半回転ずらす（左右の脚は常に反対側を踏む）。
    static func pedal(phase: Double, isFar: Bool) -> RunnerPoint {
        let angle = phase + (isFar ? .pi : 0)
        return RunnerPoint(
            x: crank.x + crankRadius * cos(angle),
            y: crank.y + crankRadius * sin(angle)
        )
    }

    /// 腰とペダルから膝を求める（2リンクの逆運動学）。
    ///
    /// 解は2つあるが、**膝が前（+x）へ出るほう**を採る。もう一方は膝が後ろへ折れた
    /// 自転車の乗り方にならない姿勢になる。
    static func knee(hip: RunnerPoint, pedal: RunnerPoint) -> RunnerPoint {
        let dx = pedal.x - hip.x
        let dy = pedal.y - hip.y
        let reach = (dx * dx + dy * dy).squareRoot()
        // 伸びきり・折り畳みでは余弦定理の値が定義域を外れる。届く範囲へ丸めてから解く。
        let distance = min(thigh + shin, max(abs(thigh - shin) + 0.001, reach))
        let cosine = (distance * distance + thigh * thigh - shin * shin) / (2 * distance * thigh)
        let angle = atan2(dy, dx) + acos(min(1, max(-1, cosine)))
        return RunnerPoint(x: hip.x + thigh * cos(angle), y: hip.y + thigh * sin(angle))
    }

    /// 片脚の形をまとめて求める。
    static func leg(phase: Double, isFar: Bool) -> Leg {
        let pedal = pedal(phase: phase, isFar: isFar)
        return Leg(hip: hip, knee: knee(hip: hip, pedal: pedal), pedal: pedal)
    }
}
