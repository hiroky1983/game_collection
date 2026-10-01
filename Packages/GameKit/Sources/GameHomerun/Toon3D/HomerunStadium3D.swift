import Foundation
import simd
import HomerunCore

extension HomerunToonModel {
    /// 球場の色（`mock3d.swift` の `P` のうち球場のもの + #1506 で足した部品の色 + #1651 で足した部品の色）。
    enum StadiumColor {
        static let grass: UInt32 = 0x4FA653, grassDark: UInt32 = 0x3F8E45, dirt: UInt32 = 0xC28C58
        static let fence: UInt32 = 0x2F7A4F, fenceSeam: UInt32 = 0x1F5A38, track: UInt32 = 0xB8804C
        /// ファウルゾーンの壁（内野〜外野ファウルの客席の手前に 1 周つながるラバー。外野の柵とほぼ同じ緑・別メッシュ）。
        static let foulPad: UInt32 = 0x2D744B
        /// スタンドの構造（段のコンクリート・通路・手すり・屋根・屋根の下の壁）と設備（照明塔・スコアボード・バックスクリーン）。
        static let tread: UInt32 = 0xA9A6B4, concourse: UInt32 = 0xB9B5C2, rail: UInt32 = 0x4E5468, wire: UInt32 = 0xD8DBE2
        static let roof: UInt32 = 0x565C74, roofWall: UInt32 = 0x7C8299, dugout: UInt32 = 0x3A3645
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
    ///
    /// #1651 で「色の帯の積み重ね」から「コンクリートの段（踏み面）の上に座席の列」に変えた。段は前の段の上面から自分の上面まで
    /// を 1 つの箱にして地面から隙間なく積み（`treadTop` / `treadBottom`）、座席はその上の後ろ寄りに置く。打球が落ちる面
    /// （`HomerunBallChase.standSurface` = `height + seatHeight / 2`）は段の上面で変えていない。
    enum Stand {
        static let lowerRows = 7, upperRows = 6
        static var rows: Int { lowerRows + upperRows }
        /// 座席 1 つの幅（周に沿う刻み）と、段 1 つの高さ（`height` は段の上面より `seatHeight / 2` 下 = 段の中心）。
        static let seatSize: Float = 1.5, seatHeight: Float = 0.9
        /// 下段は 1.6m 刻みで 0.95m ずつ上がり、上段は通路（3m）を挟んで 1.5m 刻みで 1.15m ずつ（下段より急）上がる。
        static func depth(row: Int) -> Float {
            row < lowerRows ? 2 + Float(row) * 1.6 : 2 + Float(lowerRows) * 1.6 + 3.0 + Float(row - lowerRows) * 1.5
        }
        static func height(row: Int) -> Float {
            row < lowerRows ? 0.9 + Float(row) * 0.95 : 0.9 + Float(lowerRows - 1) * 0.95 + 1.4 + Float(row - lowerRows) * 1.15
        }
        static func pitch(row: Int) -> Float { row < lowerRows ? 1.6 : 1.5 }
        /// 段（踏み面）の上面・下面の高さと、前縁からの手前・奥の奥行き。最前列は前縁（奥行き 0）から始めて壁の裏を埋める。
        static func treadTop(row: Int) -> Float { height(row: row) + seatHeight / 2 }
        static func treadBottom(row: Int) -> Float { row == 0 ? 0 : treadTop(row: row - 1) }
        static func treadFront(row: Int) -> Float { row == 0 ? 0 : depth(row: row) - pitch(row: row) / 2 }
        static func treadBack(row: Int) -> Float { depth(row: row) + pitch(row: row) / 2 }
        /// 下段と上段の間の通路（床は下段の最後列の上面と同じ高さ・奥は上段の最前列の段の立ち上がり）。
        static var walkwayFront: Float { treadBack(row: lowerRows - 1) }
        static var walkwayBack: Float { treadFront(row: lowerRows) }
        static var walkwayFloor: Float { treadTop(row: lowerRows - 1) }
        /// 座席（背もたれの箱）: 幅は刻みから `seatGap` 引き、段の奥寄りに置く。
        static let seatBackHeight: Float = 0.5, seatDepth: Float = 0.55, seatGap: Float = 0.25
        /// 階段通路の間隔（下段の中ほどの周に沿って約 12m・本塁から放射状）と、通路の脇の手すりの高さ。
        static let aisleSpacing: Float = 12, railHeight: Float = 0.9
        /// 中堅はバックスクリーン（|deg| < 6）なので座席を置かない。
        static let battersEyeGap = 6.0
        /// 両翼の柵の端（46°）から続くファウルゾーンの壁は、スタンドの前縁が弧から直線に変わる 54° まで柵と同じ高さ、その先は低い。
        static let tallPadEnd = 54.0, padHeight: Float = 1.4, tallPadHeight: Float = 3.2
        /// 上段の後ろの壁と屋根（内野側だけ。外野はスコアボードと照明塔）。
        static var backDepth: Float { depth(row: rows - 1) + 1.6 }
        static var roofHeight: Float { height(row: rows - 1) + 4.2 }
        /// バックネット裏の放送席（上段の後ろ 2 列・本塁の真後ろ ±10.5°）。
        static let pressBoxHalfAngle = 10.5, pressBoxWidth: Float = 14
    }

    /// バッターボックスの白線（m・本塁が原点・左右に 1 つずつ）。線の中心の位置で、線の幅は `line`。
    /// 打者の足がこの中に収まることをテストで固定する（#1619）。
    enum BatterBox {
        /// 箱の中心の |x|・横幅（内側の線 = centerX − width/2 = 0.29・外側の線 = 1.51）。
        static let centerX: Float = 0.9, width: Float = 1.22
        /// 前（投手側）・後ろ（捕手側）の線の z と、横の線の長さ。
        static let frontZ: Float = 0.9, backZ: Float = -0.93, sideLength: Float = 1.83
        static let line: Float = 0.06
        static var innerX: Float { centerX - width / 2 }
        static var outerX: Float { centerX + width / 2 }
    }

    /// 外野の柵（ラバー 3.2m + 黄色の線 + その上の金網）。柵の距離は判定と同じ `HomerunJudge.fence`。
    /// 金網の上端は柵越えの球が通る高さ（`HomerunBallChase.fenceClearance` 4.6m・球の半径 0.1m）より下。
    enum Fence {
        static let rubberHeight: Float = 3.2, lineY: Float = 3.25, lineHeight: Float = 0.18
        static let netWireYs: [Float] = [3.62, 3.88, 4.12], netTopY: Float = 4.36
        /// 柵の面に貼る距離表示（中堅 122・左右中間 111・両翼 100）。角度と文字。
        static let distanceMarks: [(deg: Double, text: String)] = [(0, "122"), (30, "111"), (-30, "111"), (43, "100"), (-43, "100")]
    }

    /// 球場（メートル。本塁が原点・+z がセンター・左右対称。RealityKit は右手系なので描画の上では +x が三塁側（打球の置き方は `HomerunAtBatLayout.pullSideX`・`HomerunBallChase.world`）。`mock3d.swift` の `stadium()` を出発点に #1506 で作り込んだもの）。
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
        typealias B = BatterBox
        for s: Float in [-1, 1] {
            let cx = s * B.centerX
            m.box(B.width, 0.02, B.line, C.white, at: [cx, 0.07, B.frontZ], outline: 0)
            m.box(B.width, 0.02, B.line, C.white, at: [cx, 0.07, B.backZ], outline: 0)
            m.box(B.line, 0.02, B.sideLength, C.white, at: [cx - s * B.width / 2, 0.07, 0], outline: 0)
            m.box(B.line, 0.02, B.sideLength, C.white, at: [cx + s * B.width / 2, 0.07, 0], outline: 0)
        }
        fence(into: &m)
        stands(into: &m)
        battersEye(into: &m)
        // 照明塔（外野 2 基・内野 2 基。灯体はホームを向く）
        for (deg, dr, height) in [(-36.0, 30.0, Float(42)), (36.0, 30.0, 42), (-104.0, 0.0, 38), (104.0, 0.0, 38)] {
            let r = dr > 0 ? HomerunJudge.fence(atDirection: deg) + dr : Double(standFront(deg, depth: Stand.backDepth + 4))
            let x = Float(r * sin(deg * .pi / 180)), z = Float(r * cos(deg * .pi / 180))
            m.cylinder(1.0, height, S.tower, at: [x, height / 2, z], outline: 0)
            // 幅の向きを円の接線（yaw = +角）にして灯体の面をホームへ向ける（`box` の yaw は正で x 軸を -z 側へ回す）。
            m.box(10, 6, 1.5, S.lamp, at: [x, height + 2.5, z], outline: 0, yaw: Float(deg * .pi / 180))
        }
        skyline(into: &m)
        return m.merged()
    }

    /// 柵の上の点（本塁からの方向 `deg`・柵から `dr` m 外）。
    static func fencePoint(_ deg: Double, _ dr: Double = 0) -> SIMD2<Float> {
        let r = HomerunJudge.fence(atDirection: deg) + dr
        return [Float(r * sin(deg * .pi / 180)), Float(r * cos(deg * .pi / 180))]
    }

    /// 2 点を結ぶ板の置き方（中心・長さ・y 軸まわりの向き）。板の局所の +x は a → b の向き（`box` の yaw は正で x 軸を -z 側へ回す）。
    private static func chord(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> (center: SIMD2<Float>, length: Float, yaw: Float) {
        let d = b - a
        return ((a + b) / 2, simd_length(d), Float(atan2(Double(-d.y), Double(d.x))))
    }

    /// 外野の柵（-46°〜46°）: ラバー（継ぎ目 = 横 2 本・縦は 3° ごと・足元の暗い帯）・黄色の上線・その上の金網（支柱 + 横線 3 本 + 上の桟）・
    /// 距離表示・ウォーニングトラック・ファウルポール。柵の距離は方向で変わるので、隣の点を結ぶ弦の向きで板を回す。
    /// 柵の端（±46°）はスタンドの前縁（2m 外）まで同じ高さの壁でつなぎ、そこからファウルゾーンの壁（`stands`）が 1 周続く。
    private static func fence(into m: inout HomerunToonModel) {
        typealias C = HomerunToonPalette
        typealias S = StadiumColor
        typealias F = Fence
        for deg in stride(from: -46.0, to: 46.0, by: 1.5) {
            let c = chord(fencePoint(deg), fencePoint(deg + 1.5))
            let (x, z) = (c.center.x, c.center.y)
            m.box(c.length + 0.15, F.rubberHeight, 0.4, S.fence, at: [x, F.rubberHeight / 2, z], outline: 0, yaw: c.yaw)
            m.box(c.length + 0.15, F.lineHeight, 0.5, C.yellow, at: [x, F.lineY, z], outline: 0, yaw: c.yaw)
            m.box(c.length + 0.15, 0.35, 0.46, S.fenceSeam, at: [x, 0.18, z], outline: 0, yaw: c.yaw)
            for y: Float in [1.15, 2.2] {
                m.box(c.length + 0.15, 0.07, 0.46, S.fenceSeam, at: [x, y, z], outline: 0, yaw: c.yaw)
            }
            // 金網: 横線は細く（0.03m）、上の桟は少し太く。追うカメラの柵越しの視線（柵の上端 + 0.5m）はこの線の間を通る。
            for y in F.netWireYs {
                m.box(c.length + 0.1, 0.03, 0.03, S.wire, at: [x, y, z], outline: 0, yaw: c.yaw)
            }
            m.box(c.length + 0.1, 0.08, 0.08, S.rail, at: [x, F.netTopY, z], outline: 0, yaw: c.yaw)
            if Int((deg + 46) / 1.5) % 2 == 0 {
                let p = fencePoint(deg)
                m.box(0.07, F.rubberHeight, 0.46, S.fenceSeam, at: [p.x, F.rubberHeight / 2, p.y], outline: 0, yaw: c.yaw)
                let postBottom = F.lineY + F.lineHeight / 2, postTop = F.netTopY + 0.04
                m.box(0.1, postTop - postBottom, 0.1, S.rail, at: [p.x, (postTop + postBottom) / 2, p.y], outline: 0, yaw: c.yaw)
            }
            let t = chord(fencePoint(deg, -3.35), fencePoint(deg + 1.5, -3.35))
            m.box(t.length + 0.3, 0.02, 7.3, S.track, at: [t.center.x, 0.02, t.center.y], outline: 0, yaw: t.yaw)
        }
        // 柵の端とスタンドの前縁をつなぐ壁（柵と同じ高さ・黄色の線は無し）
        for s in [-1.0, 1.0] {
            let c = chord(fencePoint(s * 46), standPoint(s * 46, depth: 0))
            m.box(c.length + 0.4, F.rubberHeight, 0.4, S.fence, at: [c.center.x, F.rubberHeight / 2, c.center.y], outline: 0, yaw: c.yaw)
        }
        for mark in F.distanceMarks { fenceNumber(mark.text, atDirection: mark.deg, into: &m) }
        // ファウルポール（両翼の柵の上・黄色）
        for s: Float in [-1, 1] {
            let p = fencePoint(Double(s) * 45)
            m.cylinder(0.3, 20, C.yellow, at: [p.x, 10, p.y], outline: 0)
            m.sphere(0.5, C.yellow, at: [p.x, 20.2, p.y], outline: 0)
        }
    }

    /// 7 セグメントの数字（高さ 0.8m・白）を、方向 `deg` の柵のラバーの面（本塁側）に貼る。本塁から見て左から右へ読める向き
    /// （板の局所 +x は角度が増す向き = 本塁から見て左なので、文字は局所 -x へ進める）。
    private static func fenceNumber(_ text: String, atDirection deg: Double, into m: inout HomerunToonModel) {
        let (height, width, stroke, pitch, baseY, thick): (Float, Float, Float, Float, Float, Float) = (0.8, 0.5, 0.09, 0.72, 1.3, 0.06)
        // 柵の板は弦の向きに回してあり、柵の距離は方向で変わる（弦は半径方向に直交しない）ので、面からの浮かせ方も弦の法線で測る。
        let c = chord(fencePoint(deg - 0.75), fencePoint(deg + 0.75))
        let tangent = SIMD2<Float>(cos(c.yaw), -sin(c.yaw))
        let toHome = SIMD2<Float>(-sin(c.yaw), -cos(c.yaw))
        let origin = c.center + toHome * (0.2 + thick / 2)
        // 見る人の右 = 局所 -x。(u, v) は数字の中心からの横・下端からの高さ、(w, h) は箱の大きさ。
        let segments: [Character: [(u: Float, v: Float, w: Float, h: Float)]] = [
            "0": [(0, height, width, stroke), (0, 0, width, stroke),
                  (width / 2, height * 0.75, stroke, height / 2), (-width / 2, height * 0.75, stroke, height / 2),
                  (width / 2, height * 0.25, stroke, height / 2), (-width / 2, height * 0.25, stroke, height / 2)],
            "1": [(-width / 2, height * 0.75, stroke, height / 2), (-width / 2, height * 0.25, stroke, height / 2)],
            "2": [(0, height, width, stroke), (-width / 2, height * 0.75, stroke, height / 2), (0, height / 2, width, stroke),
                  (width / 2, height * 0.25, stroke, height / 2), (0, 0, width, stroke)],
        ]
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            guard let segs = segments[ch] else { continue }
            let u0 = (Float(chars.count - 1) / 2 - Float(i)) * pitch
            for s in segs {
                let p = origin + tangent * (u0 + s.u)
                m.box(s.w, s.h, thick, HomerunToonPalette.white, at: [p.x, baseY + s.v, p.y], outline: 0, yaw: c.yaw)
            }
        }
    }

    /// スタンドの前縁（本塁からの距離・m）。`deg` は本塁からの方向（0 = センター。左右対称なので符号の向きは問わない）、`depth` は前縁からの奥行き。
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

    /// 奥行き `depth` の周を `size` m 刻みで -180° から 180° まで回した区間（始点の角度・幅）。最後の区間は 180° で切り詰める。
    static func standSweep(depth: Float, size: Float) -> [(deg: Double, step: Double)] {
        var segments: [(deg: Double, step: Double)] = []
        var deg = -180.0
        while deg < 180 {
            let step = Double(size / standFront(deg, depth: depth)) * 180 / .pi
            segments.append((deg, min(step, 180 - deg)))
            deg += step
        }
        return segments
    }

    static func standPoint(_ deg: Double, depth: Float) -> SIMD2<Float> {
        let r = standFront(deg, depth: depth), a = deg * .pi / 180
        return [r * Float(sin(a)), r * Float(cos(a))]
    }

    /// 階段通路の角度（本塁から放射状。下段の中ほどの周に沿って `aisleSpacing` おき）。-180° 始まりの区間の中点にして、
    /// 本塁の真後ろ（|deg| > 170 = 前のカメラで打者の後ろに映る範囲）には置かない。
    static var aisleAngles: [Double] {
        standSweep(depth: Stand.depth(row: Stand.lowerRows / 2), size: Stand.aisleSpacing).map { $0.deg + $0.step / 2 }.filter { abs($0) <= 170 }
    }

    /// 1 周のスタンド: コンクリートの段（地面から隙間なく積む）・その上の座席の列・階段通路と手すり・下段と上段の間の通路・
    /// 最前列と通路の手前の手すり・（内野側だけ）上段の後ろの壁と屋根・ファウルゾーンの壁（1 周の前縁）・バックネット（支柱 + 横線）・
    /// 放送席・ダッグアウト。中堅（|deg| < 6）はバックスクリーンなので座席を置かない。
    private static func stands(into m: inout HomerunToonModel) {
        typealias S = StadiumColor
        func sweep(depth: Float, size: Float, _ body: (Double, Double) -> Void) {
            for seg in standSweep(depth: depth, size: size) { body(seg.deg, seg.step) }
        }
        func segment(_ deg: Double, _ step: Double, depth: Float) -> (center: SIMD2<Float>, length: Float, yaw: Float) {
            chord(standPoint(deg, depth: depth), standPoint(deg + step, depth: depth))
        }
        let aisles = aisleAngles
        func isAisle(_ deg: Double, _ step: Double) -> Bool { aisles.contains { $0 >= deg && $0 < deg + step } }
        func inPressBox(row: Int, _ mid: Double) -> Bool { row >= Stand.rows - 2 && abs(mid) >= 180 - Stand.pressBoxHalfAngle }
        // 段（踏み面）: 前の段の上面から自分の上面まで。3m 刻みの板で 1 周。
        for row in 0..<Stand.rows {
            let top = Stand.treadTop(row: row), bottom = Stand.treadBottom(row: row)
            let front = Stand.treadFront(row: row), back = Stand.treadBack(row: row)
            sweep(depth: (front + back) / 2, size: 3) { deg, step in
                let s = segment(deg, step, depth: (front + back) / 2)
                m.box(s.length + 0.1, top - bottom, back - front, S.tread, at: [s.center.x, (top + bottom) / 2, s.center.y], outline: 0, yaw: s.yaw)
            }
        }
        // 通路の床（下段の最後列の上面と同じ高さ・上段の最前列の段の立ち上がりまで）
        let walkwayDepth = (Stand.walkwayFront + Stand.walkwayBack) / 2
        let walkwayBottom = Stand.treadTop(row: Stand.lowerRows - 2)
        sweep(depth: walkwayDepth, size: 3) { deg, step in
            let s = segment(deg, step, depth: walkwayDepth)
            m.box(s.length + 0.1, Stand.walkwayFloor - walkwayBottom, Stand.walkwayBack - Stand.walkwayFront, S.concourse,
                  at: [s.center.x, (Stand.walkwayFloor + walkwayBottom) / 2, s.center.y], outline: 0, yaw: s.yaw)
        }
        // 座席の列（段の奥寄り・背もたれの箱）。階段通路の所は座席を置かず、脇に手すりの薄い板を立てる。
        for row in 0..<Stand.rows {
            let treadTop = Stand.treadTop(row: row)
            let depth = Stand.treadBack(row: row) - Stand.seatDepth / 2 - 0.1
            let upper = row >= Stand.lowerRows
            sweep(depth: depth, size: Stand.seatSize) { deg, step in
                let mid = deg + step / 2
                guard abs(mid) >= Stand.battersEyeGap, !inPressBox(row: row, mid) else { return }
                let s = segment(deg, step, depth: depth)
                if isAisle(deg, step) {
                    let treadDepth = Stand.treadBack(row: row) - Stand.treadFront(row: row)
                    let railCenter = standPoint(mid, depth: (Stand.treadFront(row: row) + Stand.treadBack(row: row)) / 2)
                    m.box(0.06, Stand.railHeight, treadDepth, S.rail, at: [railCenter.x, treadTop + Stand.railHeight / 2, railCenter.y], outline: 0, yaw: s.yaw)
                    return
                }
                let color = S.mutedCrowd(Int((deg + 180) * 13) + row * 5, fraction: upper ? S.upperTierMute : S.lowerTierMute)
                // 最後の区間（180° で切り詰めた分）は箱も短くし、-180° の最初の座席と重ねない。
                let width = max(min(Stand.seatSize, s.length) - Stand.seatGap, 0.3)
                m.box(width, Stand.seatBackHeight, Stand.seatDepth, color, at: [s.center.x, treadTop + Stand.seatBackHeight / 2 + 0.01, s.center.y], outline: 0, yaw: s.yaw)
            }
        }
        // 手すり（最前列の前・通路の手前）: 上の桟 + 3m ごとの支柱。バックネット裏（|deg| ≥ 135）は網の支柱があるので最前列には置かない。
        for (depth, bottom, frontOnly) in [(Float(0.3), Stand.treadTop(row: 0), true), (Stand.walkwayFront + 0.15, Stand.walkwayFloor, false)] {
            sweep(depth: depth, size: 3) { deg, step in
                let mid = deg + step / 2
                guard abs(mid) >= Stand.battersEyeGap, !(frontOnly && abs(mid) >= 135) else { return }
                let s = segment(deg, step, depth: depth)
                m.box(s.length + 0.1, 0.08, 0.08, S.rail, at: [s.center.x, bottom + 0.95, s.center.y], outline: 0, yaw: s.yaw)
                let p = standPoint(deg, depth: depth)
                m.box(0.08, 0.95, 0.08, S.rail, at: [p.x, bottom + 0.475, p.y], outline: 0, yaw: s.yaw)
            }
        }
        // ファウルゾーンの壁（|deg| ≥ 46・前縁の上）: 柵の端から 54° までは柵と同じ高さ、その先とバックネット裏は低いラバー。足元に暗い帯。
        sweep(depth: 0, size: 3) { deg, step in
            let mid = abs(deg + step / 2)
            guard mid >= 46 else { return }
            let s = segment(deg, step, depth: 0)
            let h = mid <= Stand.tallPadEnd ? Stand.tallPadHeight : Stand.padHeight
            m.box(s.length + 0.1, h, 0.4, S.foulPad, at: [s.center.x, h / 2, s.center.y], outline: 0, yaw: s.yaw)
            m.box(s.length + 0.1, 0.3, 0.46, S.fenceSeam, at: [s.center.x, 0.15, s.center.y], outline: 0, yaw: s.yaw)
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
        backstop(into: &m)
        dugouts(into: &m)
    }

    /// バックネット裏: 網（壁の上の支柱 10 本 + 横線 3 本 + 上の桟。本塁の真後ろ 180° には支柱を置かず、前のカメラで打者の後ろに
    /// 柱が立たないようにする）と、上段の後ろの放送席（暗い窓の帯）。
    private static func backstop(into m: inout HomerunToonModel) {
        typealias S = StadiumColor
        let (postTop, wireYs): (Float, [Float]) = (9.0, [3.2, 5.0, 6.8])
        let posts = stride(from: 135.0, through: 225.0, by: 9.0).filter { abs($0 - 180) > 1 }
        for deg in posts {
            let p = standPoint(deg, depth: 0)
            m.cylinder(0.12, postTop, S.rail, at: [p.x, postTop / 2, p.y], outline: 0)
        }
        for (a, b) in zip(posts, posts.dropFirst()) {
            let c = chord(standPoint(a, depth: 0), standPoint(b, depth: 0))
            for y in wireYs {
                m.box(c.length, 0.04, 0.04, S.wire, at: [c.center.x, y, c.center.y], outline: 0, yaw: c.yaw)
            }
            m.box(c.length + 0.1, 0.12, 0.12, S.rail, at: [c.center.x, postTop, c.center.y], outline: 0, yaw: c.yaw)
        }
        // 放送席（上段の後ろ 2 列の上・屋根の下）
        let rows = Stand.rows
        let front = Stand.treadFront(row: rows - 2), back = Stand.treadBack(row: rows - 1)
        let bottom = Stand.treadTop(row: rows - 2), top = Stand.roofHeight - 1.0
        let c = standPoint(180, depth: (front + back) / 2)
        m.box(Stand.pressBoxWidth, top - bottom, back - front, S.concourse, at: [c.x, (top + bottom) / 2, c.y], outline: 0)
        let window = standPoint(180, depth: front - 0.05)
        m.box(Stand.pressBoxWidth - 1, 1.3, 0.1, S.screen, at: [window.x, Stand.treadTop(row: rows - 1) + 1.1, window.y], outline: 0)
    }

    /// ダッグアウト（両翼の壁の下・ファウルラインに沿って本塁から 20〜32m）: 暗い開口 + コンクリートの屋根の板。
    private static func dugouts(into m: inout HomerunToonModel) {
        typealias S = StadiumColor
        let root2 = Float(2).squareRoot()
        for s: Float in [-1, 1] {
            // ファウルラインに沿った距離 L の壁の点 = ((L + 16) / √2, (L − 16) / √2)（一塁側）。長さの向きは線に平行。
            let l: Float = 26
            let center = SIMD2<Float>(s * (l + 16) / root2, (l - 16) / root2)
            let yaw = -s * Float.pi / 4
            let inward = SIMD2<Float>(-s / root2, 1 / root2)   // 壁からグラウンドへ（線に垂直）
            let opening = center + inward * 0.25
            m.box(12, 1.2, 0.3, S.dugout, at: [opening.x, 0.7, opening.y], outline: 0, yaw: yaw)
            let roof = center + inward * 0.6
            m.box(13, 0.25, 1.6, S.tread, at: [roof.x, Stand.padHeight + 0.125, roof.y], outline: 0, yaw: yaw)
        }
    }

    /// バックスクリーン（中堅の客席を塞ぐ濃い緑の大壁 26m × 15m・手前の面は z = 125 = `HomerunBallChase.battersEyeZ`）と、
    /// その裏の建屋・上のスコアボード（脚 2 本・暗い画面・上の縁）。壁の面には上の縁の帯と横の継ぎ目。
    /// 壁を越えた球の道（z 125 で 15m 超・149m までに地面）に掛からないよう、建屋は 8m 以下、スコアボードは z 137 で 17m より上。
    private static func battersEye(into m: inout HomerunToonModel) {
        typealias S = StadiumColor
        m.box(26, 15, 1.0, S.battersEye, at: [0, 7.5, 125.5], outline: 0)
        m.box(26.4, 0.5, 1.2, S.tower, at: [0, 14.75, 125.5], outline: 0)
        for y: Float in [5, 10] {
            m.box(25.6, 0.08, 0.06, S.fenceSeam, at: [0, y, 124.98], outline: 0)
        }
        m.box(26, 8, 8, S.roofWall, at: [0, 4, 131], outline: 0)
        for s: Float in [-1, 1] {
            m.cylinder(0.7, 9.5, S.tower, at: [s * 10, 12.5, 137], outline: 0)
        }
        m.box(28, 9, 1.5, S.board, at: [0, 21.5, 137], outline: 0)
        m.box(26, 7, 0.3, S.screen, at: [0, 21.5, 136.2], outline: 0)
        m.box(29, 0.5, 2.0, S.tower, at: [0, 26.25, 137], outline: 0)
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
