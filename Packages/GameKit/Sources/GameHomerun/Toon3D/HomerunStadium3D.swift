import Foundation
import simd
import HomerunCore

extension HomerunToonModel {
    /// 球場の色（`mock3d.swift` の `P` のうち球場のもの）。
    enum StadiumColor {
        static let grass: UInt32 = 0x4FA653, grassDark: UInt32 = 0x3F8E45, dirt: UInt32 = 0xC28C58
        static let fence: UInt32 = 0x2F7A4F, track: UInt32 = 0xB8804C, backWall: UInt32 = 0x3C5A3A
        /// 客席の色（`crowd` を灰色 `0x8A8A96` に混ぜて控えめにしたもの）。
        static let crowd: [UInt32] = [0x8C7BE0, 0xFF8FB1, 0x22C3BE, 0xFFC24B, 0xFF6F61, 0xE9E1D6, 0x6C8BD8, 0x9AD0A0]
        static func mutedCrowd(_ i: Int, fraction: Float) -> UInt32 {
            let c = crowd[i % crowd.count], g: UInt32 = 0x8A8A96
            func mix(_ shift: UInt32) -> UInt32 {
                let a = Float((c >> shift) & 0xFF), b = Float((g >> shift) & 0xFF)
                return UInt32((a * (1 - fraction) + b * fraction).rounded())
            }
            return mix(16) << 16 | mix(8) << 8 | mix(0)
        }
    }

    /// 球場（メートル。本塁が原点・+z がセンター・+x が一塁側。`mock3d.swift` の `stadium(withOutfieldDetail: false)` の写し）。
    /// センターカメラの打席では外野の奥（照明塔・スコアボード）は見えないので省く。柵の距離は判定と同じ `HomerunJudge.fence`。
    /// 数千個の箱を色ごとのメッシュ 1 個にまとめてある（`merged()`）。
    static func stadium() -> HomerunToonModel {
        typealias C = HomerunToonPalette
        typealias S = StadiumColor
        var m = HomerunToonModel()
        let quarter = Float.pi / 4
        // 芝（刈り筋 = 原本の画像は 400m に 40 周期 = 淡・濃を 5m 幅で交互に。奥行き 400m）
        for k in 0..<80 {
            m.box(400, 0.02, 5, k % 2 == 0 ? S.grass : S.grassDark, at: [0, -0.01, Float(k) * 5 - 197.5], outline: 0)
        }
        // 本塁まわりの土・マウンド・走路・塁・ファウルライン
        m.cylinder(4.0, 0.02, S.dirt, at: [0, 0.01, 0], outline: 0)
        m.cylinder(2.75, 0.3, S.dirt, at: [0, 0.15, 18.44], outline: 0)
        m.box(0.61, 0.03, 0.15, C.white, at: [0, 0.31, 18.44], outline: 0)
        for s: Float in [-1, 1] {
            m.box(1.9, 0.02, 27.4, S.dirt, at: [s * 9.7, 0.012, 9.7], outline: 0, yaw: s * quarter)
            m.box(0.4, 0.1, 0.4, C.white, at: [s * 19.4, 0.05, 19.4], outline: 0)
            m.box(0.12, 0.02, 100, C.white, at: [s * 35.4, 0.013, 35.4], outline: 0, yaw: s * quarter)
        }
        m.box(0.4, 0.1, 0.4, C.white, at: [0, 0.05, 38.8], outline: 0)
        // 本塁（五角形 = 長方形 + 45° に回した正方形の和。頂点は原本と同じ (±0.216, 0)・(±0.216, -0.216)・(0, -0.432)）・バッターボックス
        m.box(0.432, 0.02, 0.216, C.white, at: [0, 0.03, -0.108], outline: 0)
        m.box(0.3055, 0.02, 0.3055, C.white, at: [0, 0.03, -0.216], outline: 0, yaw: quarter)
        for s: Float in [-1, 1] {
            let cx = s * 0.9
            m.box(1.22, 0.02, 0.06, C.white, at: [cx, 0.03, 0.9], outline: 0)
            m.box(1.22, 0.02, 0.06, C.white, at: [cx, 0.03, -0.93], outline: 0)
            m.box(0.06, 0.02, 1.83, C.white, at: [cx - s * 0.61, 0.03, 0], outline: 0)
            m.box(0.06, 0.02, 1.83, C.white, at: [cx + s * 0.61, 0.03, 0], outline: 0)
        }
        // フェンス（黄色の上線）・ウォーニングトラック・外野スタンド。柵の距離は方向で変わるので、隣の点を結ぶ弦の向きで板を回す。
        func point(_ deg: Double, _ dr: Double = 0) -> SIMD2<Float> {
            let r = HomerunJudge.fence(atDirection: deg) + dr
            return [Float(r * sin(deg * .pi / 180)), Float(r * cos(deg * .pi / 180))]
        }
        func chord(_ deg: Double, _ step: Double, _ dr: Double = 0) -> (center: SIMD2<Float>, length: Float, yaw: Float) {
            let a = point(deg, dr), b = point(deg + step, dr), d = b - a
            return ((a + b) / 2, simd_length(d), Float(atan2(Double(-d.y), Double(d.x))))
        }
        for deg in stride(from: -46.0, to: 46.0, by: 1.5) {
            let c = chord(deg, 1.5)
            m.box(c.length + 0.15, 3.2, 0.4, S.fence, at: [c.center.x, 1.6, c.center.y], outline: 0, yaw: c.yaw)
            m.box(c.length + 0.15, 0.18, 0.5, C.yellow, at: [c.center.x, 3.25, c.center.y], outline: 0, yaw: c.yaw)
            let t = chord(deg, 1.5, -3.35)
            m.box(t.length + 0.3, 0.02, 7.3, S.track, at: [t.center.x, 0.02, t.center.y], outline: 0, yaw: t.yaw)
        }
        for row in 0..<5 {
            for deg in stride(from: -50.0, to: 50.0, by: 0.8) {
                let c = chord(deg, 0.8, 2.0 + Double(row) * 1.6)
                let color = S.mutedCrowd(Int(abs(deg) * 13) + row * 5, fraction: 0.4)
                m.box(1.5, 0.9, 1.5, color, at: [c.center.x, 0.9 + Float(row) * 0.95, c.center.y], outline: 0, yaw: c.yaw)
            }
        }
        // 本塁の後ろのスタンド（センターカメラの背景）とバックネット裏の低い壁
        for row in 0..<14 {
            for deg in stride(from: 128.0, to: 232.0, by: 1.0) {
                let r = 16.0 + Double(row) * 1.5, a = Float(deg * .pi / 180)
                let color = S.mutedCrowd(Int(deg * 7) + row * 5, fraction: 0.35)
                m.box(1.2, 0.9, 1.4, color, at: [Float(r) * sin(a), 1.0 + Float(row) * 0.9, Float(r) * cos(a)], outline: 0, yaw: -a)
            }
        }
        for deg in stride(from: 126.0, to: 234.0, by: 3.0) {
            let a = Float(deg * .pi / 180)
            m.box(1.0, 1.1, 0.4, S.backWall, at: [14.5 * sin(a), 0.55, 14.5 * cos(a)], outline: 0, yaw: -a)
        }
        return m.merged()
    }
}
