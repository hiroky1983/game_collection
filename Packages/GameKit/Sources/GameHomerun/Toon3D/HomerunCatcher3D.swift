import Foundation
import simd

extension HomerunToonModel {
    /// 捕手（`mock3d.swift` の `catcherNode()` の写し・頭の半径 = 1 の単位）。白い太ももを開いたしゃがみ・グレーのレガース・
    /// 紺の胸当て・スカルキャップ + ケージ付きマスク（顔がケージ越しに見える）・左手（+x）に大きな茶のミット。+z（投手）を向く。
    static func catcher() -> HomerunToonModel {
        typealias C = HomerunToonPalette
        let pad: UInt32 = 0x9A9AA6, band: UInt32 = 0x7A8CC4, cage: UInt32 = 0xB4B4C0
        var m = HomerunToonModel()
        // 脚: 太ももを外へ開き、すね（レガース）は垂直。靴は黒
        for sx: Float in [-1, 1] {
            let hip = SIMD3<Float>(sx * 0.45, 1.05, 0.1), knee = SIMD3<Float>(sx * 1.35, 0.95, 0.95), ankle = SIMD3<Float>(sx * 1.35, 0.25, 1.0)
            m.limb(hip, knee, r: 0.36, C.uniform)
            m.limb(knee, ankle, r: 0.3, C.uniform)
            m.box(0.72, 0.95, 0.5, pad, at: [sx * 1.35, 0.6, 1.15], radius: 0.2)
            m.sphere(0.34, pad, at: knee, scale: [1, 0.9, 0.9])
            m.box(0.66, 0.3, 0.9, C.eye, at: [sx * 1.35, 0.15, 1.05], radius: 0.1)
        }
        // 胴: 胸当て（紺の角丸の箱）と肩の帯。後ろに白の胴
        m.limb([0, 1.0, -0.1], [0, 1.9, -0.1], r: 0.8, C.uniform)
        m.box(2.2, 1.7, 0.85, C.navy, at: [0, 1.4, 0.25], radius: 0.36)
        m.box(1.9, 0.42, 0.9, band, at: [0, 2.05, 0.25], radius: 0.18)
        // 腕: 左手（+x）は前へ出してミット、右手（-x）は膝に置く
        m.limb([1.05, 1.95, 0.15], [1.6, 1.55, 0.75], r: 0.27, C.uniform)
        m.limb([1.6, 1.55, 0.75], [1.55, 1.65, 1.35], r: 0.21, C.skin)
        m.sphere(0.62, C.glove, at: [1.55, 1.7, 1.55], scale: [1, 1.05, 0.55])
        m.sphere(0.4, 0xD9A070, at: [1.5, 1.72, 1.86], scale: [0.8, 0.9, 0.12], outline: 0.02)   // ミットのポケット
        m.limb([-1.05, 1.95, 0.15], [-1.5, 1.35, 0.55], r: 0.27, C.uniform)
        m.limb([-1.5, 1.35, 0.55], [-1.35, 1.05, 1.0], r: 0.21, C.skin)
        m.sphere(0.27, C.skin, at: [-1.35, 1.05, 1.0])
        // 頭: 肌の球 + 紺のスカルキャップ（中心を上へ = 顔が開く）+ ケージ付きマスク
        m.group(translation([0, 2.85, 0])) { h in
            h.sphere(1.0, C.skin, at: [0, 0, 0])
            h.sphere(1.06, C.navy, at: [0, 0.42, -0.1])
            for sx: Float in [-1, 1] {
                h.sphere(0.2, C.white, at: [sx * 0.36, 0.02, 0.86], outline: 0.03)
                h.sphere(0.11, C.eye, at: [sx * 0.33, 0.0, 1.02], outline: 0)
                h.box(0.36, 0.11, 0.1, C.grayDark, at: [sx * 0.37, 0.33, 0.9], radius: 0.03, outline: 0.025)
            }
            h.sphere(0.12, C.skinDark, at: [0, -0.16, 1.0], outline: 0.03)
            h.limb([-0.15, -0.5, 0.92], [0.15, -0.5, 0.92], r: 0.035, C.mouth, outline: 0)
            h.cage(color: cage, r: 0.035, outline: 0.015, front: 1.22, halfWidth: 0.78, top: 0.62, bottom: -0.78,
                   rows: [0.25, -0.15, -0.5], columns: [-0.28, 0.28])
            // 枠から頭へ戻る側面のバー（マスクが顔に付いて見えるように）
            for sx: Float in [-1, 1] {
                h.limb([sx * 0.78, 0.62, 1.22], [sx * 0.95, 0.35, 0.35], r: 0.035, cage, outline: 0.015)
                h.limb([sx * 0.78, -0.78, 1.22], [sx * 0.9, -0.55, 0.4], r: 0.035, cage, outline: 0.015)
            }
        }
        return m
    }

    /// ケージ付きマスクの枠（角丸の四角 + 横棒 + 縦棒）。棒は細く（打席ではストライクゾーンの 9 分割と重なって見えないよう、格子に見せない太さにする）。
    fileprivate mutating func cage(color: UInt32, r: Float, outline: Float, front z: Float, halfWidth w: Float, top: Float, bottom: Float,
                                   rows: [Float], columns: [Float]) {
        func bar(_ a: SIMD3<Float>, _ b: SIMD3<Float>) { limb(a, b, r: r, color, outline: outline) }
        bar([-w, top, z], [w, top, z]); bar([-w, bottom, z], [w, bottom, z])
        bar([-w, top, z], [-w, bottom, z]); bar([w, top, z], [w, bottom, z])
        for y in rows { bar([-w, y, z + 0.02], [w, y, z + 0.02]) }
        for x in columns { bar([x, top, z + 0.02], [x, bottom, z + 0.02]) }
    }
}
