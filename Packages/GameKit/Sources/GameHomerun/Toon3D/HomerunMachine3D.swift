import Foundation
import simd

/// バッティングマシンの型（#1612・会長が決めるまでのモック）。
enum HomerunMachineKind: String, CaseIterable {
    /// A: 2 つの車輪で打ち出す型（アーム付きの台・横に並んだ 2 つの円盤の車輪・上の受け皿と 2 本のレールから球を込める）。
    case wheels
    /// B: 腕で投げる型（箱の側面に軸があり、腕がうしろから上を通って前へ振られ、先のカップから球を放る）。
    case arm
}

/// マシンの動きのコマ（「込める → 打ち出す」の案。数コマのポーズで見せる）。
enum HomerunMachinePose: String, CaseIterable {
    /// 待機: 次の球が受け皿・レールで待っている。
    case idle
    /// 込める: 球がレールを転がり落ちる（A）／腕がうしろへ倒れてカップに球が載る（B）。
    case load
    /// 打ち出す瞬間: 球が車輪の間から出る（A）／腕が前へ振り切られカップから球が離れる（B）。
    case launch
}

extension HomerunToonModel {
    /// マシンの色（球場・おじさんのパレットに合わせた紺・黄・灰）。
    enum MachineColor {
        static let body: UInt32 = 0x3E4E80, frame: UInt32 = 0x626270, rail: UInt32 = 0x9696A2
        static let tire: UInt32 = 0x2E2E38, hub: UInt32 = 0xF0C030, lever: UInt32 = 0xE0503C
        static let ball: UInt32 = 0xFAF6EC, arm: UInt32 = 0xF0C030, cup: UInt32 = 0x4A4A55
    }

    /// 球の半径（`HomerunSwingContact.ballRadius` と同じ 0.037m）。
    static let machineBallRadius: Float = 0.037

    /// マシン（メートル・原点は台の底の中心・**-z（本塁）へ打ち出す**。置くときは yaw 0 でよい）。
    static func machine(_ kind: HomerunMachineKind, pose: HomerunMachinePose) -> HomerunToonModel {
        switch kind {
        case .wheels: return wheelMachine(pose: pose)
        case .arm: return armMachine(pose: pose)
        }
    }

    /// A: 2 輪式。台（板 + 柱 + 斜めのアーム）の上に紺の本体、その前に横並びの 2 つの車輪（黒いタイヤ・黄のハブ）。
    /// 本体の上の受け皿から 2 本のレールで球が車輪の間へ転がり落ち、赤いレバーが押し込む。
    static func wheelMachine(pose: HomerunMachinePose) -> HomerunToonModel {
        typealias C = MachineColor
        var m = HomerunToonModel()
        // 台: 板・柱・柱から本体へ伸びる斜めのアーム
        m.box(0.8, 0.06, 0.8, C.frame, at: [0, 0.03, 0.05], radius: 0.02, outline: 0.02)
        m.cylinder(0.05, 0.6, C.frame, at: [0, 0.36, 0.2], outline: 0.015)
        m.limb([0, 0.62, 0.2], [0, 0.92, 0.08], r: 0.05, C.frame, outline: 0.015)
        // 本体（モーターの箱）と、その前の 2 つの車輪（軸は縦・球は車輪の間を -z へ抜ける）
        m.box(0.38, 0.3, 0.36, C.body, at: [0, 1.0, 0.12], radius: 0.05, outline: 0.02)
        for sx: Float in [-1, 1] {
            m.cylinder(0.24, 0.07, C.tire, at: [sx * 0.27, 1.0, -0.12], outline: 0.02)
            m.cylinder(0.1, 0.09, C.hub, at: [sx * 0.27, 1.0, -0.12], outline: 0.015)
        }
        // 受け皿（円錐台）と 2 本のレール（受け皿から車輪の間の真上へ）
        m.frustum(top: 0.16, bottom: 0.07, height: 0.12, C.rail, at: [0, 1.5, 0.42], outline: 0.015)
        for sx: Float in [-1, 1] {
            m.limb([sx * 0.05, 1.44, 0.42], [sx * 0.05, 1.1, -0.1], r: 0.015, C.rail, outline: 0.01)
        }
        // 押し込みのレバー（本体の横・赤い玉つき）
        let pivot = SIMD3<Float>(0.24, 1.12, 0.12)
        let tip: SIMD3<Float> = pose == .launch ? [0.24, 1.22, -0.18] : [0.24, 1.42, 0.2]
        m.limb(pivot, tip, r: 0.025, C.lever, outline: 0.012)
        m.ball(0.045, C.lever, at: tip)
        // 球: 待機は受け皿の中、込めるはレールの途中、打ち出す瞬間は車輪の間から出た所（受け皿には次の球）
        switch pose {
        case .idle:
            m.ball(machineBallRadius, C.ball, at: [0, 1.58, 0.42])
        case .load:
            m.ball(machineBallRadius, C.ball, at: [0, 1.31, 0.18])
            m.ball(machineBallRadius, C.ball, at: [0, 1.58, 0.42])
        case .launch:
            m.ball(machineBallRadius, C.ball, at: [0, 1.0, -0.32])
            m.ball(machineBallRadius, C.ball, at: [0, 1.58, 0.42])
        }
        return m
    }

    /// B: アーム式。紺の箱の右側面（+x）に横向きの軸があり、黄色い腕がうしろ（+z）から上を通って前（-z）へ振られる。
    /// 腕の先のカップに、箱の上のレールに並んだ球が 1 個ずつ載る。反対側には錘の球。
    static func armMachine(pose: HomerunMachinePose) -> HomerunToonModel {
        typealias C = MachineColor
        var m = HomerunToonModel()
        m.box(0.8, 0.06, 0.9, C.frame, at: [0, 0.03, 0.05], radius: 0.02, outline: 0.02)
        m.box(0.7, 0.86, 0.8, C.body, at: [0, 0.49, 0.05], radius: 0.04, outline: 0.02)
        // 横向きの軸（x に沿う円柱 = y 軸の円柱を z まわりに 90° 回す）
        let axle = SIMD3<Float>(0, 0.95, -0.1)
        m.group(translation(axle) * rotation(angle: .pi / 2, axis: [0, 0, 1])) { a in
            a.cylinder(0.04, 0.96, C.frame, at: .zero, outline: 0.015)
        }
        // 腕: 軸の右端が支点。向きは y-z 面の中で、うしろ下（待機）→ うしろ水平（込める）→ 前上 60°（打ち出す瞬間）
        let pivot = SIMD3<Float>(0.46, axle.y, axle.z)
        let direction: SIMD3<Float> = switch pose {
        case .idle: simd_normalize([0, -0.35, 1])
        case .load: [0, 0, 1]
        case .launch: [0, sin(Float.pi / 3), -cos(Float.pi / 3)]
        }
        let hand = pivot + direction * 0.85
        m.limb(pivot, hand, r: 0.035, C.arm, outline: 0.015)
        m.ball(0.07, C.frame, at: pivot - direction * 0.2)   // 錘
        m.group(translation(hand) * alignY(to: direction)) { c in
            c.cylinder(0.065, 0.05, C.cup, at: .zero, outline: 0.012)
        }
        // レール（箱の上のうしろ・x に沿って腕の「込める」位置へ下る）と支柱、並んで待つ球
        for dz: Float in [-0.03, 0.03] {
            m.limb([-0.2, 1.1, 0.75 + dz], [0.36, 0.98, 0.75 + dz], r: 0.015, C.rail, outline: 0.01)
        }
        m.limb([0, 0.9, 0.45], [0, 1.05, 0.75], r: 0.03, C.frame, outline: 0.012)
        let queued: [Float] = pose == .idle ? [-0.12, 0.03, 0.18] : [-0.12, 0.03]
        for x in queued {
            m.ball(machineBallRadius, C.ball, at: [x, 1.1 - (x + 0.2) * 0.21 + 0.05, 0.75])
        }
        switch pose {
        case .idle: break
        case .load: m.ball(machineBallRadius, C.ball, at: hand + direction * 0.02 + [0, 0.06, 0])
        case .launch: m.ball(machineBallRadius, C.ball, at: hand + direction * 0.16 + [0, 0.04, -0.06])
        }
        return m
    }

    /// 円錐台（y 軸に沿う・受け皿）。
    fileprivate mutating func frustum(top: Float, bottom: Float, height h: Float, _ color: UInt32, at p: SIMD3<Float>, outline: Float) {
        let t = Self.translation(p)
        parts.append(HomerunToonPart(mesh: HomerunToonMesh.frustum(top: top, bottom: bottom, height: h).placed(t),
                                     outline: HomerunToonMesh.frustum(top: top + outline, bottom: bottom + outline, height: h + 2 * outline).placed(t).flipped(),
                                     color: color))
    }

    /// 小さな球（ボール・玉・錘）。`sphere` の 32 分割（1,088 三角形）は小さな球には過剰なので 16 分割（288 三角形）にする。
    fileprivate mutating func ball(_ r: Float, _ color: UInt32, at p: SIMD3<Float>, outline: Float = 0.012) {
        let t = Self.translation(p)
        parts.append(HomerunToonPart(mesh: HomerunToonMesh.sphere(radius: r, segments: 16).placed(t),
                                     outline: HomerunToonMesh.sphere(radius: r + outline, segments: 16).placed(t).flipped(),
                                     color: color))
    }

    /// 三角形の数（本体 + 輪郭線）。モックの報告と予算の確認用。
    var triangleCount: Int {
        parts.reduce(0) { $0 + $1.mesh.indices.count / 3 + ($1.outline?.indices.count ?? 0) / 3 }
    }
}

extension HomerunAtBatLayout {
    /// マシンの置き場所の候補（会長が決める）。
    enum MachinePlace: String, CaseIterable {
        /// マウンドの上（投手の位置）。前のカメラでは画角の下に外れ、後ろのカメラでだけ見える。
        case mound
        /// 本塁寄り（本塁から 9m）。前のカメラでも押せる帯の高さに入り、打ち出した球が画面の中で出てくる。
        case near

        var placement: Placement {
            switch self {
            case .mound: Placement(position: [0, 0.3, 17.6], yaw: 0)
            case .near: Placement(position: [0, 0, 9.0], yaw: 0)
            }
        }
    }

    /// いまの局面でのマシンのコマ。的が出る `windup`（0.8 秒）前から込め始め、的が出る 0.25 秒前から打ち出しの構え、
    /// 打ち出して 0.3 秒たったら待機に戻る（次の球の分が受け皿に載る）。
    static func machinePose(phase: HomerunModel.Phase, elapsed: TimeInterval?) -> HomerunMachinePose {
        guard phase == .pitching, let elapsed else { return .idle }
        if elapsed < -0.25 { return .load }
        return elapsed < 0.3 ? .launch : .idle
    }
}

/// モックの撮影用の起動引数（#1612。型が決まったら本実装に置き換えて外す）。
/// `-homerunMachine wheels|arm`（投手の代わりにマシンを置く）・`-homerunMachinePlace mound|near`・
/// `-homerunMachinePose idle|load|launch`（時刻に関係なくそのコマで止める）。
enum HomerunMachineMock {
    static func value(after key: String, in arguments: [String]) -> String? {
        guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static func kind(arguments: [String] = ProcessInfo.processInfo.arguments) -> HomerunMachineKind? {
        value(after: "-homerunMachine", in: arguments).flatMap(HomerunMachineKind.init(rawValue:))
    }

    static func place(arguments: [String] = ProcessInfo.processInfo.arguments) -> HomerunAtBatLayout.MachinePlace {
        value(after: "-homerunMachinePlace", in: arguments).flatMap(HomerunAtBatLayout.MachinePlace.init(rawValue:)) ?? .mound
    }

    static func forcedPose(arguments: [String] = ProcessInfo.processInfo.arguments) -> HomerunMachinePose? {
        value(after: "-homerunMachinePose", in: arguments).flatMap(HomerunMachinePose.init(rawValue:))
    }

    /// `-homerunMachineCloseup`: 型の形を見せるため、置いたマシンを本塁側の斜め前 3m から見るカメラ（撮影用）。
    static func closeupCamera(arguments: [String] = ProcessInfo.processInfo.arguments) -> HomerunAtBatLayout.Camera? {
        guard arguments.contains("-homerunMachineCloseup") else { return nil }
        let p = place(arguments: arguments).placement.position
        return .aimed(from: p + [2.0, 1.5, -2.4], at: p + [0, 0.85, 0], yFraction: 0.5, verticalFieldOfView: 40)
    }
}
