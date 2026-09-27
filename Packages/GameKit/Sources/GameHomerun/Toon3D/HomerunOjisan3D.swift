import Foundation
import simd

/// 3D モデルのパレット（`mock3d.swift` の `P`。Core の `OjisanPixel` と同じ色）。
enum HomerunToonPalette {
    static let ink: UInt32 = 0x2B2634, skin: UInt32 = 0xF2C8A0, skinDark: UInt32 = 0xD69E76, white: UInt32 = 0xFAF6EC
    static let yellow: UInt32 = 0xF0C030, navy: UInt32 = 0x3E4E80, navyDark: UInt32 = 0x28345C, gray: UInt32 = 0x9696A2, grayDark: UInt32 = 0x626270
    static let eye: UInt32 = 0x221E28, cheek: UInt32 = 0xF0A088, wood: UInt32 = 0xAA763E, woodDark: UInt32 = 0x7A5228
    static let uniform: UInt32 = 0xF4F2F6, mouth: UInt32 = 0x5E1418, sweat: UInt32 = 0x6CB8E8, glove: UInt32 = 0x8A5A32
}

enum HomerunOjisanEyes { case open, closed }
enum HomerunOjisanMouth { case smile, open, line }
enum HomerunOjisanOutfit { case batter, pitcher }

/// おじさんのポーズ。肘・手・バット先端の座標だけで決まる（2D の走者と同じ「座標 2 点でポーズ」の発想）。
struct HomerunOjisanPose3: Equatable {
    var elbowR: SIMD3<Float>, handR: SIMD3<Float>, elbowL: SIMD3<Float>, handL: SIMD3<Float>
    var batTip: SIMD3<Float>?
    var batOnGround = false
    var helmetOn = true, capInAir = false, sweat = false
    var eyes = HomerunOjisanEyes.open, mouth = HomerunOjisanMouth.smile
    var headTilt: Float = 0, bodyYaw: Float = 0
    /// 右手だけでバットを持つ（空振りのうなだれ）。
    var batOneHand = false
    /// 負で見上げる。
    var headPitch: Float = 0

    static let stance = HomerunOjisanPose3(
        elbowR: [1.45, 1.85, 0.4], handR: [0.95, 2.5, 0.85], elbowL: [-0.85, 1.55, 0.7], handL: [0.6, 2.35, 0.95],
        batTip: [1.75, 4.9, -0.35])
    static let swing = HomerunOjisanPose3(
        elbowR: [0.55, 1.95, 1.15], handR: [-0.75, 1.95, 1.35], elbowL: [-1.05, 2.0, 0.65], handL: [-1.0, 1.9, 1.25],
        batTip: [-3.6, 1.75, 1.75], headTilt: -0.15, bodyYaw: -0.35)
    static let cheer = HomerunOjisanPose3(
        elbowR: [1.55, 3.05, 0.3], handR: [1.5, 4.35, 0.35], elbowL: [-1.55, 3.05, 0.3], handL: [-1.5, 4.35, 0.35],
        batOnGround: true, helmetOn: false, capInAir: true, mouth: .open)
    static let whiff = HomerunOjisanPose3(
        elbowR: [1.25, 1.55, 0.2], handR: [1.2, 1.0, 0.45], elbowL: [-1.25, 1.55, 0.2], handL: [-1.15, 1.0, 0.45],
        batTip: [1.6, 0.1, 1.3], sweat: true, eyes: .closed, mouth: .line, headTilt: 0.18, batOneHand: true)
    /// 投手（背中をカメラへ向ける・投球の瞬間＝リリース）。`mock3d.swift` の「投球」ポーズの写し。
    static let pitch = HomerunOjisanPose3(
        elbowR: [1.55, 3.3, -0.45], handR: [1.35, 4.35, -0.75], elbowL: [-1.35, 2.25, 0.5], handL: [-1.0, 2.65, 1.15],
        headTilt: 0.05)
    /// 投手の振りかぶり（セットポジション。両手を胸の前で合わせる）。`mock3d.swift` に定義が無いため、
    /// リリース（`.pitch`）から逆算した当番側の追加ポーズ（README 未記載）。
    static let windup = HomerunOjisanPose3(
        elbowR: [0.5, 2.9, 0.3], handR: [0.15, 3.55, 0.55], elbowL: [-0.5, 2.9, 0.3], handL: [-0.15, 3.55, 0.55])
    /// 外野手（見上げる。グラブの左手を上げて追う。`mock3d.swift` の `outfieldShot()` の写し）。
    static let outfielder = HomerunOjisanPose3(
        elbowR: [1.3, 1.6, 0.2], handR: [1.1, 1.0, 0.4], elbowL: [-1.4, 3.0, 0.2], handL: [-1.2, 4.2, 0.5],
        headPitch: -0.55)
}

extension HomerunToonModel {
    /// 部品の集まりを `transform` で置き直して取り込む（`SceneKit` のノードの親子の代わり）。
    mutating func group(_ transform: simd_float4x4, _ build: (inout HomerunToonModel) -> Void) {
        var sub = HomerunToonModel()
        build(&sub)
        parts += sub.parts.map { part in
            var p = part
            p.mesh = part.mesh.placed(transform)
            p.outline = part.outline?.placed(transform)
            return p
        }
    }

    /// `mock3d.swift` の `ojisan()` の写し（頭の半径 = 1 の単位・+z が正面）。
    static func ojisan(_ p: HomerunOjisanPose3, outfit: HomerunOjisanOutfit = .batter) -> HomerunToonModel {
        typealias C = HomerunToonPalette
        var m = HomerunToonModel()
        // 脚・靴・ストッキング
        for sx: Float in [-0.42, 0.42] {
            m.limb([sx, 0.35, 0], [sx, 1.25, 0], r: 0.34, C.uniform)
            m.limb([sx, 0.3, 0], [sx, 0.62, 0], r: 0.35, C.navy)
            m.box(0.62, 0.3, 0.9, C.eye, at: [sx, 0.15, 0.12], radius: 0.1)
        }
        // 胴・ベルト・襟・ボタン（胴だけ bodyYaw で回る）
        m.group(rotation(angle: p.bodyYaw, axis: [0, 1, 0])) { t in
            t.limb([0, 1.35, 0], [0, 2.05, 0], r: 0.88, C.uniform, striped: outfit == .batter)
            t.limb([0, 1.18, 0], [0, 1.19, 0], r: 0.9, C.navy)
            t.box(0.28, 0.22, 0.12, C.yellow, at: [0, 1.18, 0.86])
            if outfit == .batter {
                t.limb([-0.5, 2.55, 0.62], [0, 2.1, 0.86], r: 0.075, C.yellow, outline: 0.03)
                t.limb([0.5, 2.55, 0.62], [0, 2.1, 0.86], r: 0.075, C.yellow, outline: 0.03)
                for y: Float in [1.5, 1.8] { t.sphere(0.075, C.navy, at: [0, y, 0.87], outline: 0.02) }
            } else {
                t.limb([-0.5, 2.55, 0.62], [0, 2.15, 0.86], r: 0.06, C.navy, outline: 0.02)
                t.limb([0.5, 2.55, 0.62], [0, 2.15, 0.86], r: 0.06, C.navy, outline: 0.02)
            }
        }
        // 腕（袖は白・前腕は肌・手は黄のグローブ。投手は左手に茶のグラブ）
        func arm(_ s: SIMD3<Float>, _ e: SIMD3<Float>, _ h: SIMD3<Float>, left: Bool) {
            m.limb(s, e, r: 0.27, C.uniform)
            m.limb(e, h, r: 0.21, C.skin)
            if outfit == .pitcher && left { m.sphere(0.36, C.glove, at: h, scale: [1, 1.1, 0.6]) }
            else if outfit == .pitcher { m.sphere(0.26, C.skin, at: h) }
            else { m.sphere(0.28, C.yellow, at: h) }
        }
        arm([0.95, 2.15, 0], p.elbowR, p.handR, left: false)
        arm([-0.95, 2.15, 0], p.elbowL, p.handL, left: true)
        // バット
        if let tip = p.batTip {
            let grip = p.batOneHand ? p.handR : (p.handR + p.handL) / 2
            let d = simd_normalize(tip - grip)
            m.bat(grip - d * 0.5, tip, wood: C.wood, woodDark: C.woodDark)
        } else if p.batOnGround {
            m.bat([-1.3, 0.14, 1.3], [1.4, 0.14, 1.7], wood: C.wood, woodDark: C.woodDark)
        }
        // 頭
        let headTurn = rotation(angle: p.headPitch, axis: [1, 0, 0]) * rotation(angle: p.bodyYaw * 0.4, axis: [0, 1, 0])
            * rotation(angle: p.headTilt, axis: [0, 0, 1])
        m.group(translation([0, 3.3, 0]) * headTurn) { $0.head(p, outfit: outfit) }
        return m
    }

    /// 頭（首・頭・耳・白髪・顔・ヘルメット/帽子）。原点が頭の中心。
    private mutating func head(_ p: HomerunOjisanPose3, outfit: HomerunOjisanOutfit) {
        typealias C = HomerunToonPalette
        sphere(1.0, C.skin, at: [0, 0, 0])
        limb([0, -1.1, 0], [0, -0.7, 0], r: 0.32, C.skin)
        for sx: Float in [-1, 1] {
            sphere(0.2, C.skin, at: [sx * 0.98, -0.1, 0.05], scale: [0.6, 1, 1])
            // 側頭の白髪: ヘルメットの縁の下に出る房
            sphere(0.3, C.gray, at: [sx * 0.9, -0.04, -0.22], scale: [0.4, 0.5, 0.95], outline: 0.035)
        }
        sphere(0.3, C.gray, at: [0, -0.02, -0.88], scale: [1.6, 0.5, 0.45], outline: 0.035)   // 後頭部の白髪
        for sx: Float in [-1, 1] {
            if p.eyes == .open {
                sphere(0.23, C.white, at: [sx * 0.38, 0.06, 0.85], outline: 0.035)
                sphere(0.13, C.eye, at: [sx * 0.35, 0.04, 1.03], outline: 0)
                sphere(0.045, C.white, at: [sx * 0.3, 0.1, 1.13], outline: 0)
            } else {
                // ＞＜ 目（2 本の短い線をハの字に）
                limb([sx * 0.2, 0.2, 0.95], [sx * 0.48, 0.08, 0.9], r: 0.035, C.eye, outline: 0)
                limb([sx * 0.2, -0.05, 0.95], [sx * 0.48, 0.08, 0.9], r: 0.035, C.eye, outline: 0)
            }
            box(0.42, 0.13, 0.12, C.grayDark, at: [sx * 0.4, 0.4, 0.9], radius: 0.03, outline: 0.03, turnZ: sx * 0.12)
            sphere(0.2, C.cheek, at: [sx * 0.66, -0.2, 0.72], scale: [1, 0.8, 0.5], outline: 0)
            sphere(0.18, C.gray, at: [sx * 0.23, -0.32, 0.9], scale: [1.4, 0.55, 0.7], outline: 0.035)   // ヒゲ
        }
        sphere(0.13, C.skinDark, at: [0, -0.12, 1.0], outline: 0.03)
        switch p.mouth {
        case .smile: limb([-0.18, -0.52, 0.92], [0.18, -0.52, 0.92], r: 0.04, C.mouth, outline: 0)
        case .line: limb([-0.14, -0.5, 0.94], [0.14, -0.5, 0.94], r: 0.035, C.mouth, outline: 0)
        case .open: sphere(0.2, C.mouth, at: [0, -0.5, 0.88], scale: [1, 1.1, 0.5], outline: 0.03)
        }
        // ヘルメットの球は中心を少し後ろへずらす: 頭の球との交線が前で高く・横と後ろで低くなり、
        // 顔が開いて耳まで覆う形が図形 1 個で出る。
        let helmetC = SIMD3<Float>(0, 0.35, -0.22)
        func headwear(into t: inout HomerunToonModel, cap: Bool) {
            t.sphere(cap ? 1.05 : 1.08, C.navy, at: helmetC)
            if !cap {
                // 黄の中央ライン: 前（ツバの上）から頭頂を越えて後方 48° までの弧だけ。
                for deg in stride(from: -48.0 as Float, through: 118.0, by: 3.5) {
                    let a = deg * .pi / 180
                    t.sphere(0.075, C.yellow, at: [0, helmetC.y + 1.09 * cos(a), helmetC.z + 1.09 * sin(a)], outline: 0.025)
                }
                t.box(0.3, 0.55, 0.5, C.navy, at: [-1.0, -0.15, 0.1], radius: 0.12)   // 左耳（投手側）の耳当て
            }
            // ツバ: 短く厚く、ヘルメットの前の縁から生える角度に。
            t.cylinder(cap ? 0.75 : 0.66, 0.13, C.navyDark, at: [0, 0.66, cap ? 0.66 : 0.6], tiltX: 0.28)
        }
        if p.helmetOn {
            headwear(into: &self, cap: outfit == .pitcher)
        } else if p.capInAir {
            group(Self.translation([1.9, 2.1, -0.2]) * Self.rotation(angle: 0.9, axis: [0, 0, 1]) * Self.rotation(angle: 0.3, axis: [1, 0, 0])) {
                headwear(into: &$0, cap: false)
            }
        }
        if p.sweat { sphere(0.13, C.sweat, at: [1.25, 0.55, 0.55], scale: [1, 1.4, 1], outline: 0.03) }
    }

}
