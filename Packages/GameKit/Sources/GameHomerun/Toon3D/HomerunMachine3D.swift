import Foundation
import simd

/// バッティングマシン（2 輪式・#1612 会長決裁 A: 投手のおじさんの代わりにマウンドへ常設）。
///
/// 動く部品（2 つの車輪・押し込みのレバー・込める球・受け皿の次の球）は別々の実体にして、1 コマごとに位置・向きだけを
/// 変える（メッシュを作り直さない）。動きは投球の時刻（`HomerunModel.pitchElapsed`）から決まる純粋な関数
/// `HomerunMachineMotion.state` で、**球が車輪の間から出る瞬間 = 的が出て輪が縮み始める時刻（elapsed 0）**。
/// そこから 3D の球（`HomerunBallFlight`）が打ち出し口（`HomerunMachineMotion.mouth`）から打点へ飛ぶ。
extension HomerunToonModel {
    /// マシンの色（球場・おじさんのパレットに合わせた紺・黄・灰）。
    enum MachineColor {
        static let body: UInt32 = 0x3E4E80, frame: UInt32 = 0x626270, rail: UInt32 = 0x9696A2
        static let tire: UInt32 = 0x2E2E38, hub: UInt32 = 0xF0C030, lever: UInt32 = 0xE0503C
        static let ball: UInt32 = 0xFAF6EC, mark: UInt32 = 0xF4F0E6
    }

    /// 動かない部分（メートル・原点は台の底の中心・**-z（本塁）へ打ち出す**）。台（板 + 柱 + 斜めのアーム）・紺の本体・
    /// 上の受け皿（円錐台）と、受け皿から車輪の間の上へ下る 2 本のレール。
    static func machineBody() -> HomerunToonModel {
        typealias C = MachineColor
        var m = HomerunToonModel()
        m.box(0.8, 0.06, 0.8, C.frame, at: [0, 0.03, 0.05], radius: 0.02, outline: 0.02)
        m.cylinder(0.05, 0.6, C.frame, at: [0, 0.36, 0.2], outline: 0.015)
        m.limb([0, 0.62, 0.2], [0, 0.92, 0.08], r: 0.05, C.frame, outline: 0.015)
        m.box(0.38, 0.3, 0.36, C.body, at: [0, 1.0, 0.12], radius: 0.05, outline: 0.02)
        m.frustum(top: 0.16, bottom: 0.07, height: 0.12, C.rail, at: [0, 1.5, 0.42], outline: 0.015)
        // レールの間隔（0.06m）は球の直径（0.074m）より狭く、球はレールに載って転がる。
        for sx: Float in [-1, 1] {
            m.limb([sx * 0.03, 1.44, 0.42], [sx * 0.03, 1.1, -0.1], r: 0.015, C.rail, outline: 0.01)
        }
        return m
    }

    /// 車輪 1 つ（原点は車輪の中心・軸は y）。黒いタイヤ・黄のハブと、回っているのが分かる白い印（縁の近く）。
    static func machineWheel() -> HomerunToonModel {
        typealias C = MachineColor
        var m = HomerunToonModel()
        m.cylinder(0.24, 0.07, C.tire, at: .zero, outline: 0.02)
        m.cylinder(0.1, 0.09, C.hub, at: .zero, outline: 0.015)
        m.box(0.09, 0.02, 0.05, C.mark, at: [0.17, 0.04, 0], outline: 0)
        return m
    }

    /// 押し込みのレバー（原点は支点・+y へ伸びる。x 軸まわりに回して使う）。先に赤い玉。
    static func machineLever() -> HomerunToonModel {
        var m = HomerunToonModel()
        m.limb(.zero, [0, HomerunMachineMotion.leverLength, 0], r: 0.025, MachineColor.lever, outline: 0.012)
        m.ball(0.045, MachineColor.lever, at: [0, HomerunMachineMotion.leverLength, 0])
        return m
    }

    /// マシンの球（原点は球の中心・`HomerunSwingContact.ballRadius` と同じ 0.037m）。
    static func machineBall() -> HomerunToonModel {
        var m = HomerunToonModel()
        m.ball(HomerunSwingContact.ballRadius, MachineColor.ball, at: .zero)
        return m
    }

    /// 円錐台（y 軸に沿う・受け皿）。
    fileprivate mutating func frustum(top: Float, bottom: Float, height h: Float, _ color: UInt32, at p: SIMD3<Float>, outline: Float) {
        let t = Self.translation(p)
        parts.append(HomerunToonPart(mesh: HomerunToonMesh.frustum(top: top, bottom: bottom, height: h).placed(t),
                                     outline: HomerunToonMesh.frustum(top: top + outline, bottom: bottom + outline, height: h + 2 * outline).placed(t).flipped(),
                                     color: color))
    }

    /// 小さな球（マシンの球・レバーの玉）。`sphere` の 32 分割（1,088 三角形）は小さな球には過剰なので 16 分割（288 三角形）にする。
    fileprivate mutating func ball(_ r: Float, _ color: UInt32, at p: SIMD3<Float>, outline: Float = 0.012) {
        let t = Self.translation(p)
        parts.append(HomerunToonPart(mesh: HomerunToonMesh.sphere(radius: r, segments: 16).placed(t),
                                     outline: HomerunToonMesh.sphere(radius: r + outline, segments: 16).placed(t).flipped(),
                                     color: color))
    }

    /// 三角形の数（本体 + 輪郭線）。軽さの確認用。
    var triangleCount: Int {
        parts.reduce(0) { $0 + $1.mesh.indices.count / 3 + ($1.outline?.indices.count ?? 0) / 3 }
    }
}

extension HomerunAtBatLayout {
    /// バッティングマシンはマウンドの上（投手板の 0.84m 本塁側・高さ 0.3m）に本塁を向けて置く（#1612 会長決裁: 置き場所 1）。
    /// 前のカメラ（28m）では画角の下に外れて映らない（投手のときと同じ）。後ろのカメラでは画面の上の方に小さく映る。
    static let machine = Placement(position: [0, 0.3, 17.6], yaw: 0)

    /// マシンの局所座標の点を打席の世界座標（前のカメラの置き方・鏡映なし）へ置く。
    static func machineWorld(_ local: SIMD3<Float>) -> SIMD3<Float> {
        machine.position + simd_quatf(angle: machine.yaw, axis: [0, 1, 0]).act(local)
    }
}

/// マシンの「込める → 打ち出す」の動き（マシンの局所座標・メートル）。時刻から決まる純粋な関数なのでテストで固定する。
///
/// 1 球の流れ（elapsed は的が出る時刻からの秒・込める間は負）:
/// - 込める（`-loadDuration` 〜 `-pushDuration`）: 受け皿の球がレールを転がり落ちる（だんだん速く）。
/// - 押し込む（`-pushDuration` 〜 0）: レバーが前へ倒れ、球が車輪の間を抜けて打ち出し口へ。**0 で打ち出し口に着く**。
/// - 打ち出した後: マシンの球は消え（3D の球に引き継ぐ）、レバーが戻り、受け皿に次の球が落ちてくる。
/// 車輪は時刻に比例して回り続ける（左右で逆向き）。
enum HomerunMachineMotion {
    /// 込める動きの長さ = 的が出るまでの時間（`HomerunModel.windup`）。
    static var loadDuration: TimeInterval { HomerunModel.windup }
    /// そのうち、レバーが押し込み球が車輪の間を抜ける長さ。
    static let pushDuration: TimeInterval = 0.25
    /// 打ち出した後にレバーが戻り切るまで。
    static let leverReturnDuration: TimeInterval = 0.35
    /// 打ち出した後、受け皿に次の球が出始める時刻と、出切るまでの長さ。
    static let refillDelay: TimeInterval = 0.35
    static let refillDuration: TimeInterval = 0.15
    /// 車輪の回る速さ（ラジアン/秒・約 2 回転/秒）。
    static let wheelSpeed: Double = 12.5

    /// 受け皿の球・レールの終わり（車輪の手前）・車輪の間・打ち出し口。
    static let hopper: SIMD3<Float> = [0, 1.58, 0.42]
    static let railEnd: SIMD3<Float> = [0, 1.14, -0.08]
    static let wheelGap: SIMD3<Float> = [0, 1.0, -0.12]
    static let mouth: SIMD3<Float> = [0, 1.0, -0.32]
    /// 込める間に球が通る道（受け皿 → レールに落ちる → レールの終わり）と、押し込む間の道（→ 車輪の間 → 打ち出し口）。
    static let rollPath: [SIMD3<Float>] = [hopper, [0, 1.48, 0.40], railEnd]
    static let pushPath: [SIMD3<Float>] = [railEnd, wheelGap, mouth]

    /// 2 つの車輪の中心（軸は y）。
    static let wheelCenters: [SIMD3<Float>] = [[-0.27, 1.0, -0.12], [0.27, 1.0, -0.12]]
    /// レバーの支点（本体の横）と長さ・角度（x 軸まわり・0 で真上。正でうしろ = +z へ倒れる）。
    static let leverPivot: SIMD3<Float> = [0.24, 1.12, 0.12]
    static let leverLength: Float = 0.31
    static let leverRestAngle: Float = 0.26
    static let leverPushedAngle: Float = -1.25

    struct State: Equatable {
        /// 込めている球の位置（無ければ nil = 受け皿の次の球だけ）。
        var loadedBall: SIMD3<Float>?
        /// 受け皿の次の球の大きさ（0 で無し・1 で出切った）。
        var hopperBall: Float
        /// レバーの角度（`leverRestAngle` 〜 `leverPushedAngle`）。
        var leverAngle: Float
        /// 左の車輪の回転角（ラジアン・y 軸まわり。右の車輪は逆向き）。
        var wheelAngle: Float
    }

    /// `elapsed`: 的が出てからの秒（投球中でなければ nil = 待機: 受け皿に球・レバーは戻った位置）。
    static func state(elapsed: TimeInterval?, now: Date) -> State {
        let wheel = Float((now.timeIntervalSinceReferenceDate * wheelSpeed).truncatingRemainder(dividingBy: 2 * .pi))
        guard let elapsed else {
            return State(loadedBall: nil, hopperBall: 1, leverAngle: leverRestAngle, wheelAngle: wheel)
        }
        let e = max(elapsed, -loadDuration)
        if e < -pushDuration {
            // 転がり落ちる: 等加速（重力で転がる）ように道のりを 2 乗で進める。
            let k = (e + loadDuration) / (loadDuration - pushDuration)
            return State(loadedBall: point(on: rollPath, at: Float(k * k)), hopperBall: 0, leverAngle: leverRestAngle, wheelAngle: wheel)
        }
        if e < 0 {
            // 押し込む: レバーは前半で倒れ切り、球は車輪につかまって速くなる（2 乗）。
            let k = (e + pushDuration) / pushDuration
            let lever = smooth(min(k / 0.6, 1))
            return State(loadedBall: point(on: pushPath, at: Float(k * k)), hopperBall: 0,
                         leverAngle: leverRestAngle + (leverPushedAngle - leverRestAngle) * lever, wheelAngle: wheel)
        }
        // 打ち出した後: レバーが戻り、次の球が受け皿に出る。
        let back = smooth(min(e / leverReturnDuration, 1))
        let refill = Float(min(max((e - refillDelay) / refillDuration, 0), 1))
        return State(loadedBall: nil, hopperBall: refill,
                     leverAngle: leverPushedAngle + (leverRestAngle - leverPushedAngle) * back, wheelAngle: wheel)
    }

    /// 折れ線 `path` の上で、全長に対する割合 `s`（0〜1）の点。
    static func point(on path: [SIMD3<Float>], at s: Float) -> SIMD3<Float> {
        let lengths = zip(path, path.dropFirst()).map { simd_distance($0, $1) }
        var rest = min(max(s, 0), 1) * lengths.reduce(0, +)
        for (i, l) in lengths.enumerated() {
            if rest <= l || i == lengths.count - 1 {
                return path[i] + (path[i + 1] - path[i]) * (l > 0 ? min(rest / l, 1) : 1)
            }
            rest -= l
        }
        return path[path.count - 1]
    }

    private static func smooth(_ k: Double) -> Float {
        Float(k * k * (3 - 2 * k))
    }
}

#if canImport(RealityKit)
import RealityKit

/// マシンの実体一式（台と本体・2 つの車輪・レバー・込める球・受け皿の次の球）。`apply` で動く部品の位置・向きだけを変える。
@MainActor
final class HomerunMachineRig {
    let entity = Entity()
    private let wheels: [Entity]
    private let lever: Entity
    private let loadedBall: Entity
    private let hopperBall: Entity

    init() {
        typealias M = HomerunMachineMotion
        var wheels: [Entity] = []
        for c in M.wheelCenters {
            let w = HomerunAtBatAssets.machineWheel()
            w.position = c
            wheels.append(w)
        }
        self.wheels = wheels
        lever = HomerunAtBatAssets.machineLever()
        lever.position = M.leverPivot
        loadedBall = HomerunAtBatAssets.machineBall()
        hopperBall = HomerunAtBatAssets.machineBall()
        hopperBall.position = M.hopper
        entity.addChild(HomerunAtBatAssets.machineBody())
        for e in wheels + [lever, loadedBall, hopperBall] { entity.addChild(e) }
        let p = HomerunAtBatLayout.machine
        entity.position = p.position
        entity.orientation = simd_quatf(angle: p.yaw, axis: [0, 1, 0])
        apply(M.state(elapsed: nil, now: Date()))
    }

    func apply(_ s: HomerunMachineMotion.State) {
        for (i, w) in wheels.enumerated() {
            w.orientation = simd_quatf(angle: i == 0 ? s.wheelAngle : -s.wheelAngle, axis: [0, 1, 0])
        }
        lever.orientation = simd_quatf(angle: s.leverAngle, axis: [1, 0, 0])
        if let p = s.loadedBall {
            loadedBall.position = p
            loadedBall.isEnabled = true
        } else {
            loadedBall.isEnabled = false
        }
        hopperBall.isEnabled = s.hopperBall > 0
        hopperBall.scale = SIMD3(repeating: max(s.hopperBall, 0.01))
    }
}
#endif
