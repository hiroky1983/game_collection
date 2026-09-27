import Foundation
import simd
import HomerunCore

extension HomerunToonModel {
    /// 球場の色（`mock3d.swift` の `P` のうち球場のもの + #1506 で足した部品の色）。
    enum StadiumColor {
        static let grass: UInt32 = 0x4FA653, grassDark: UInt32 = 0x3F8E45, dirt: UInt32 = 0xC28C58
        static let fence: UInt32 = 0x2F7A4F, fenceSeam: UInt32 = 0x1F5A38, track: UInt32 = 0xB8804C, backWall: UInt32 = 0x3C5A3A
        /// スタンドの構造（通路の壁・屋根・屋根の下の壁）と設備（照明塔・スコアボード・バックスクリーン）。
        static let concourse: UInt32 = 0xB9B5C2, roof: UInt32 = 0x565C74, roofWall: UInt32 = 0x7C8299
        static let tower: UInt32 = 0x9AA0AE, lamp: UInt32 = 0xFFF2C2, board: UInt32 = 0x2B2634, screen: UInt32 = 0x1A2A3C
        static let battersEye: UInt32 = 0x28553A
        /// 遠景（街並み 2 段・雲）。陰影を付けず（`shade` = 1）平らに塗る。
        static let skylineNear: UInt32 = 0x9FB2CC, skylineFar: UInt32 = 0xBFCCDF, cloud: UInt32 = 0xFFFFFF
        /// 客席の色（`crowd` を灰色 `0x8A8A96` に混ぜて控えめにしたもの）。
        static let crowd: [UInt32] = [0x8C7BE0, 0xFF8FB1, 0x22C3BE, 0xFFC24B, 0xFF6F61, 0xE9E1D6, 0x6C8BD8, 0x9AD0A0]
        /// 下段・上段の混ぜる割合（上段は遠いぶん薄く）。
        static let lowerTierMute: Float = 0.4, upperTierMute: Float = 0.55
        static func mutedCrowd(_ i: Int, fraction: Float) -> UInt32 {
            let c = crowd[i % crowd.count], g: UInt32 = 0x8A8A96
            func mix(_ shift: UInt32) -> UInt32 {
                let a = Float((c >> shift) & 0xFF), b = Float((g >> shift) & 0xFF)
                return UInt32((a * (1 - fraction) + b * fraction).rounded())
            }
            return mix(16) << 16 | mix(8) << 8 | mix(0)
        }
    }

    /// スタンドの段（下段 7 列 + 通路 + 上段 6 列。#1506「段のあるスタンド」）。前縁からの奥行き（m）と座面の高さ（m）。
    enum Stand {
        static let lowerRows = 7, upperRows = 6
        static var rows: Int { lowerRows + upperRows }
        static let seatSize: Float = 1.5, seatHeight: Float = 0.9
        /// 下段は 1.6m 刻みで 0.95m ずつ上がり、上段は通路（3m）を挟んで 1.5m 刻みで 1.15m ずつ（下段より急）上がる。
        static func depth(row: Int) -> Float {
            row < lowerRows ? 2 + Float(row) * 1.6 : 2 + Float(lowerRows) * 1.6 + 3.0 + Float(row - lowerRows) * 1.5
        }
        static func height(row: Int) -> Float {
            row < lowerRows ? 0.9 + Float(row) * 0.95 : 0.9 + Float(lowerRows - 1) * 0.95 + 1.4 + Float(row - lowerRows) * 1.15
        }
        /// 通路の壁（下段の最後列のすぐ後ろ）。
        static var concourseDepth: Float { 2 + Float(lowerRows) * 1.6 + 0.4 }
        static var concourseWallBottom: Float { height(row: lowerRows - 1) }
        static var concourseWallTop: Float { height(row: lowerRows) - 0.1 }
        /// 上段の後ろの壁と屋根（内野側だけ。外野はスコアボードと照明塔）。
        static var backDepth: Float { depth(row: rows - 1) + 1.6 }
        static var roofHeight: Float { height(row: rows - 1) + 4.2 }
    }

    /// 球場（メートル。本塁が原点・+z がセンター・+x が一塁側。`mock3d.swift` の `stadium()` を出発点に #1506 で作り込んだもの）。
    /// 柵の距離は判定と同じ `HomerunJudge.fence`。数千個の箱を色ごとのメッシュ 1 個にまとめてある（`merged()`）。
    ///
    /// スタンドは本塁を中心とする 1 周の極座標（`standFront`）で組む: 外野は柵に沿う弧、両翼はファウルラインに平行な直線、
    /// バックネット裏は半径 16m の弧。同じ関数で列ごとに奥へ・上へ積むので、段差（下段・通路・上段・屋根）が 1 周つながる。
    static func stadium() -> HomerunToonModel {
        typealias C = HomerunToonPalette
        typealias S = StadiumColor
        var m = HomerunToonModel()
        let quarter = Float.pi / 4
        // 芝（刈り筋 = 淡・濃を 5m 幅で交互に。遠景の足元まで届くよう 600m 四方）
        for k in 0..<120 {
            m.box(600, 0.02, 5, k % 2 == 0 ? S.grass : S.grassDark, at: [0, -0.01, Float(k) * 5 - 297.5], outline: 0)
        }
        // 内野の土（マウンドを中心に半径 29m の弧）と、その上に戻す芝: ファウルラインの外側（2 枚の大きな板）とダイヤモンドの内側
        m.cylinder(29, 0.02, S.dirt, at: [0, 0.01, 18.44], outline: 0)
        for s: Float in [-1, 1] {
            // ファウルラインに平行な板（線から外側へ 80m・線に沿って -40m〜160m）。本塁の後ろは両方の板が重なる（同色）。
            m.box(80, 0.02, 200, S.grass, at: [s * 70.7, 0.03, 14.1], outline: 0, yaw: s * quarter)
        }
        m.box(25.5, 0.02, 25.5, S.grass, at: [0, 0.03, 19.4], outline: 0, yaw: quarter)
        // 本塁まわりの土・マウンド・塁の土・走路（4 辺）・ネクストバッターズサークル・ファウルライン
        m.cylinder(4.0, 0.02, S.dirt, at: [0, 0.05, 0], outline: 0)
        m.cylinder(5.5, 0.02, S.dirt, at: [0, 0.05, 18.44], outline: 0)
        m.cylinder(2.75, 0.3, S.dirt, at: [0, 0.15, 18.44], outline: 0)
        m.box(0.61, 0.03, 0.15, C.white, at: [0, 0.31, 18.44], outline: 0)
        m.cylinder(4.0, 0.02, S.dirt, at: [0, 0.05, 38.8], outline: 0)
        for s: Float in [-1, 1] {
            m.cylinder(4.0, 0.02, S.dirt, at: [s * 19.4, 0.05, 19.4], outline: 0)
            m.box(1.9, 0.02, 27.4, S.dirt, at: [s * 9.7, 0.05, 9.7], outline: 0, yaw: s * quarter)
            m.box(1.9, 0.02, 27.4, S.dirt, at: [s * 9.7, 0.05, 29.1], outline: 0, yaw: -s * quarter)
            m.box(0.4, 0.1, 0.4, C.white, at: [s * 19.4, 0.05, 19.4], outline: 0)
            m.box(0.12, 0.02, 100, C.white, at: [s * 35.4, 0.07, 35.4], outline: 0, yaw: s * quarter)
            m.cylinder(1.3, 0.02, S.dirt, at: [s * 9, 0.05, -5], outline: 0)
        }
        m.box(0.4, 0.1, 0.4, C.white, at: [0, 0.05, 38.8], outline: 0)
        // 本塁（五角形 = 長方形 + 45° に回した正方形の和。頂点は原本と同じ (±0.216, 0)・(±0.216, -0.216)・(0, -0.432)）・バッターボックス
        m.box(0.432, 0.02, 0.216, C.white, at: [0, 0.07, -0.108], outline: 0)
        m.box(0.3055, 0.02, 0.3055, C.white, at: [0, 0.07, -0.216], outline: 0, yaw: quarter)
        for s: Float in [-1, 1] {
            let cx = s * 0.9
            m.box(1.22, 0.02, 0.06, C.white, at: [cx, 0.07, 0.9], outline: 0)
            m.box(1.22, 0.02, 0.06, C.white, at: [cx, 0.07, -0.93], outline: 0)
            m.box(0.06, 0.02, 1.83, C.white, at: [cx - s * 0.61, 0.07, 0], outline: 0)
            m.box(0.06, 0.02, 1.83, C.white, at: [cx + s * 0.61, 0.07, 0], outline: 0)
        }
        // フェンス（ラバーの継ぎ目 = 横 2 本・縦は 3° ごと・足元の暗い帯）・黄色の上線・ウォーニングトラック。
        // 柵の距離は方向で変わるので、隣の点を結ぶ弦の向きで板を回す。
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
            m.box(c.length + 0.15, 0.35, 0.46, S.fenceSeam, at: [c.center.x, 0.18, c.center.y], outline: 0, yaw: c.yaw)
            for y: Float in [1.15, 2.2] {
                m.box(c.length + 0.15, 0.07, 0.46, S.fenceSeam, at: [c.center.x, y, c.center.y], outline: 0, yaw: c.yaw)
            }
            if Int((deg + 46) / 1.5) % 2 == 0 {
                let p = point(deg)
                m.box(0.07, 3.2, 0.46, S.fenceSeam, at: [p.x, 1.6, p.y], outline: 0, yaw: c.yaw)
            }
            let t = chord(deg, 1.5, -3.35)
            m.box(t.length + 0.3, 0.02, 7.3, S.track, at: [t.center.x, 0.02, t.center.y], outline: 0, yaw: t.yaw)
        }
        // ファウルポール（両翼の柵の上・黄色）
        for s: Float in [-1, 1] {
            let p = point(Double(s) * 45)
            m.cylinder(0.3, 20, C.yellow, at: [p.x, 10, p.y], outline: 0)
            m.sphere(0.5, C.yellow, at: [p.x, 20.2, p.y], outline: 0)
        }
        stands(into: &m)
        // バックスクリーン（中堅の客席を塞ぐ濃い緑の板）とスコアボード（その上・脚 2 本）
        m.box(26, 15, 1.0, S.battersEye, at: [0, 7.5, 125.5], outline: 0)
        m.box(26, 10, 1.5, S.board, at: [0, 21, 151], outline: 0)
        m.box(24, 8, 0.3, S.screen, at: [0, 21, 150.2], outline: 0)
        for s: Float in [-1, 1] {
            m.cylinder(0.6, 16, S.tower, at: [s * 9, 8, 152], outline: 0)
        }
        // 照明塔（外野 2 基・内野 2 基。灯体はホームを向く）
        for (deg, dr, height) in [(-36.0, 30.0, Float(42)), (36.0, 30.0, 42), (-104.0, 0.0, 38), (104.0, 0.0, 38)] {
            let r = dr > 0 ? HomerunJudge.fence(atDirection: deg) + dr : Double(standFront(deg, depth: Stand.backDepth + 4))
            let x = Float(r * sin(deg * .pi / 180)), z = Float(r * cos(deg * .pi / 180))
            m.cylinder(1.0, height, S.tower, at: [x, height / 2, z], outline: 0)
            m.box(10, 6, 1.5, S.lamp, at: [x, height + 2.5, z], outline: 0, yaw: Float(-deg * .pi / 180))
        }
        // バックネット裏の低い壁
        for deg in stride(from: 132.0, to: 228.0, by: 3.0) {
            let a = Float(deg * .pi / 180)
            m.box(1.0, 1.1, 0.4, S.backWall, at: [14.5 * sin(a), 0.55, 14.5 * cos(a)], outline: 0, yaw: -a)
        }
        skyline(into: &m)
        return m.merged()
    }

    /// スタンドの前縁（本塁からの距離・m）。`deg` は本塁からの方向（0 = センター・正が一塁側）、`depth` は前縁からの奥行き。
    /// 外野（|deg| ≤ 46）は柵の 2m 外、バックネット裏（|deg| ≥ 135）は半径 16m、両翼はファウルラインの 16m 外側に平行な直線
    /// （直線が柵の弧より外に出る方向では弧を取る = 外野の弧が両翼へ回り込む）。
    static func standFront(_ deg: Double, depth: Float) -> Float {
        let a = abs(deg)
        let arc = Float(HomerunJudge.fence(atDirection: min(a, 46))) + 2 + depth
        if a <= 46 { return arc }
        if a >= 135 { return 16 + depth }
        let line = (16 + depth) / Float(sin((a - 45) * .pi / 180))
        return min(line, arc)
    }

    private static func standPoint(_ deg: Double, depth: Float) -> SIMD2<Float> {
        let r = standFront(deg, depth: depth), a = deg * .pi / 180
        return [r * Float(sin(a)), r * Float(cos(a))]
    }

    /// 1 周のスタンド: 段の座席・通路の壁・（内野側だけ）上段の後ろの壁と屋根。中堅（|deg| < 6）はバックスクリーンなので座席を置かない。
    private static func stands(into m: inout HomerunToonModel) {
        typealias S = StadiumColor
        /// `deg` を、奥行き `depth` の周で `size` m 刻みになるよう回す。
        func sweep(depth: Float, size: Float, _ body: (Double, Double) -> Void) {
            var deg = -180.0
            while deg < 180 {
                let step = Double(size / standFront(deg, depth: depth)) * 180 / .pi
                body(deg, min(step, 180 - deg))
                deg += step
            }
        }
        func segment(_ deg: Double, _ step: Double, depth: Float) -> (center: SIMD2<Float>, length: Float, yaw: Float) {
            let a = standPoint(deg, depth: depth), b = standPoint(deg + step, depth: depth), d = b - a
            return ((a + b) / 2, simd_length(d), Float(atan2(Double(-d.y), Double(d.x))))
        }
        for row in 0..<Stand.rows {
            let depth = Stand.depth(row: row), y = Stand.height(row: row)
            let upper = row >= Stand.lowerRows
            sweep(depth: depth, size: Stand.seatSize) { deg, step in
                guard abs(deg + step / 2) >= 6 else { return }
                let s = segment(deg, step, depth: depth)
                let color = S.mutedCrowd(Int((deg + 180) * 13) + row * 5, fraction: upper ? S.upperTierMute : S.lowerTierMute)
                m.box(Stand.seatSize, Stand.seatHeight, Stand.seatSize, color, at: [s.center.x, y, s.center.y], outline: 0, yaw: s.yaw)
            }
        }
        // 通路の壁（1 周）
        let wallHeight = Stand.concourseWallTop - Stand.concourseWallBottom
        sweep(depth: Stand.concourseDepth, size: 3) { deg, step in
            let s = segment(deg, step, depth: Stand.concourseDepth)
            m.box(s.length + 0.2, wallHeight, 0.5, S.concourse, at: [s.center.x, Stand.concourseWallBottom + wallHeight / 2, s.center.y], outline: 0, yaw: s.yaw)
        }
        // 上段の後ろの壁と屋根（内野側 |deg| ≥ 60 だけ）
        let topRow = Stand.height(row: Stand.rows - 1)
        sweep(depth: Stand.backDepth, size: 4) { deg, step in
            guard abs(deg + step / 2) >= 60 else { return }
            let s = segment(deg, step, depth: Stand.backDepth)
            let wallTop = Stand.roofHeight - 0.25
            m.box(s.length + 0.3, wallTop - topRow + 1.5, 1.0, S.roofWall, at: [s.center.x, (wallTop + topRow - 1.5) / 2, s.center.y], outline: 0, yaw: s.yaw)
            let roofDepth = Stand.backDepth - Stand.depth(row: Stand.lowerRows) + 2
            let r = segment(deg, step, depth: Stand.backDepth - roofDepth / 2 + 0.5)
            m.box(r.length + 0.6, 0.5, roofDepth, S.roof, at: [r.center.x, Stand.roofHeight, r.center.y], outline: 0, yaw: r.yaw)
        }
    }

    /// 遠景: スタンドの外の街並み（2 段・陰影なし）と雲。乱数なし（高さ・間隔は角度の式で決める）。
    private static func skyline(into m: inout HomerunToonModel) {
        typealias S = StadiumColor
        let start = m.parts.count
        for (radius, color, base) in [(Float(290), S.skylineFar, Float(22)), (Float(250), S.skylineNear, Float(10))] {
            var deg = 0.0
            while deg < 360 {
                let a = deg * .pi / 180
                let wave = Float(sin(deg * 0.37) * 0.5 + sin(deg * 1.13 + 1) * 0.3 + sin(deg * 2.7) * 0.2)
                let height = base + 14 + wave * 12
                let width = Float(9 + (Int(deg) % 3) * 4)
                m.box(width, height, width, color, at: [radius * Float(sin(a)), height / 2, radius * Float(cos(a))], outline: 0, yaw: Float(-a))
                deg += Double(width + 5) / Double(radius) * 180 / .pi
            }
        }
        for (deg, height, size) in [(-38.0, Float(62), Float(9)), (-12.0, 70, 12), (14.0, 58, 8), (36.0, 66, 11), (160.0, 60, 10), (200.0, 68, 12)] {
            let a = deg * .pi / 180, r: Float = 230
            let c = SIMD3<Float>(r * Float(sin(a)), height, r * Float(cos(a)))
            for (dx, dy, rr) in [(Float(0), Float(0), Float(1)), (-1.1, -0.2, 0.75), (1.0, -0.15, 0.8), (0.3, 0.4, 0.7)] {
                let side = SIMD3<Float>(Float(cos(a)), 0, -Float(sin(a)))
                m.sphere(rr * size, S.cloud, at: c + side * (dx * size) + [0, dy * size, 0], scale: [1, 0.7, 1], outline: 0)
            }
        }
        for i in start..<m.parts.count {
            m.parts[i].mesh.shade = Array(repeating: 1, count: m.parts[i].mesh.shade.count)
        }
    }
}
