import Testing
import Foundation
import simd
import HomerunCore
#if canImport(RealityKit)
import RealityKit
#endif
@testable import GameHomerun

@Suite("柵越えおじさんの 3D 球場と打席シーンの置き方")
struct HomerunStadium3DTests {
    private let stadium = HomerunToonModel.stadium()

    private var allPositions: [SIMD3<Float>] { stadium.parts.flatMap { $0.mesh.positions } }

    @Test("球場は輪郭線の無い色ごとのメッシュにまとまり、実体の数は色数と同じ")
    func stadiumIsMergedByColor() {
        let colors = stadium.parts.map(\.color)
        #expect(Set(colors).count == colors.count, "同じ色の部品が分かれている")
        #expect(stadium.parts.allSatisfy { $0.outline == nil && !$0.striped })
        #expect(stadium.parts.count < 48, "実体が \(stadium.parts.count) 個ある（客席が色ごとにまとまっていない）")
        for part in stadium.parts {
            let m = part.mesh
            #expect(m.indices.count % 3 == 0 && m.indices.allSatisfy { Int($0) < m.positions.count })
            #expect(m.positions.count == m.normals.count && m.positions.count == m.shade.count && m.positions.count == m.stripe.count)
        }
    }

    @Test("フェンスの板は判定の柵の距離（両翼 100m・中堅 122m）の上に立っている")
    func fenceFollowsJudgeDistance() {
        let fence = stadium.parts.first { $0.color == HomerunToonModel.StadiumColor.fence }!.mesh
        for (degrees, expected) in [(0.0, 122.0), (45.0, 100.0), (-45.0, 100.0)] {
            let radians = degrees * .pi / 180
            let near = fence.positions.filter { abs(Double($0.x) - expected * sin(radians)) < 2 && abs(Double($0.z) - expected * cos(radians)) < 2 }
            #expect(!near.isEmpty, "方向 \(degrees)° の柵 \(expected)m の位置に板が無い")
            // 同じ方向で柵より 5m 手前・奥には板が無い（板が柵の距離から外れていない）。
            let off = fence.positions.filter { abs(Double($0.x) - (expected - 5) * sin(radians)) < 1 && abs(Double($0.z) - (expected - 5) * cos(radians)) < 1 }
            #expect(off.isEmpty, "方向 \(degrees)° の柵の 5m 手前に板がある")
        }
        #expect(HomerunJudge.fence(atDirection: 0) == 122 && abs(HomerunJudge.fence(atDirection: 45) - 100) < 1e-9)
    }

    @Test("球場は地面（y ≒ 0）から雲までで、本塁の後ろにも客席がある")
    func stadiumExtent() {
        let ys = allPositions.map(\.y)
        #expect(ys.min()! >= -0.03)
        #expect(ys.max()! < 100)
        #expect(allPositions.contains { $0.z < -20 && $0.y > 5 }, "本塁の後ろのスタンドが無い")
        #expect(allPositions.contains { $0.z > 110 }, "外野スタンドが無い")
    }

    private func positions(of color: UInt32) -> [SIMD3<Float>] {
        stadium.parts.first { $0.color == color }?.mesh.positions ?? []
    }

    @Test("スタンドは 1 周つながる: 両翼（60°〜120°）と外野・バックネット裏のどこにも下段・上段の座席がある")
    func standsWrapAround() {
        typealias S = HomerunToonModel.StadiumColor
        let lower = (0..<S.crowd.count).flatMap { positions(of: S.mutedCrowd($0, fraction: S.lowerTierMute)) }
        let upper = (0..<S.crowd.count).flatMap { positions(of: S.mutedCrowd($0, fraction: S.upperTierMute)) }
        #expect(!lower.isEmpty && !upper.isEmpty)
        func direction(_ p: SIMD3<Float>) -> Double { atan2(Double(p.x), Double(p.z)) * 180 / .pi }
        for deg in stride(from: -170.0, through: 170.0, by: 20) where abs(deg) >= 8 {
            #expect(lower.contains { abs(direction($0) - deg) < 5 }, "\(deg)° に下段の座席が無い")
            #expect(upper.contains { abs(direction($0) - deg) < 5 }, "\(deg)° に上段の座席が無い")
        }
        // 上段は下段より高く・奥にある（段差）。
        let topOfLower = lower.map(\.y).max()!, bottomOfUpper = upper.map(\.y).min()!
        #expect(bottomOfUpper > topOfLower - 0.5, "上段（\(bottomOfUpper)）が下段の最上列（\(topOfLower)）より低い")
        #expect(HomerunToonModel.Stand.depth(row: HomerunToonModel.Stand.lowerRows) - HomerunToonModel.Stand.depth(row: HomerunToonModel.Stand.lowerRows - 1) > 3,
                "上段の前に通路が無い")
        // 中堅（|θ| < 6°）はバックスクリーンで、座席は置かない。
        #expect(!lower.contains { abs(direction($0)) < 3 && $0.z > 100 }, "バックスクリーンの位置に座席がある")
        // 箱の頂点は角だけなので、幅 26m の板の角（x = ±13）で見る。
        #expect(positions(of: S.battersEye).contains { abs(abs($0.x) - 13) < 0.01 && $0.z > 120 && $0.y > 14 }, "バックスクリーンが無い")
    }

    @Test("スタンドの周回: 区間は -180° から 180° をちょうど埋め、各区間はその位置の座席 1 つ分以下（最後は切り詰め）で、箱の幅も区間に合わせる")
    func standSweepCoversTheLoopOnce() {
        typealias M = HomerunToonModel
        for depth: Float in [2, 13.6, 25.3] {
            let segments = M.standSweep(depth: depth, size: 1.5)
            #expect(segments.first?.deg == -180)
            let sum = segments.reduce(0.0) { $0 + $1.step }
            #expect(abs(sum - 360) < 1e-9, "区間の合計が \(sum)°")
            #expect(abs((segments.last!.deg + segments.last!.step) - 180) < 1e-9)
            for seg in segments {
                let nominal = Double(1.5 / M.standFront(seg.deg, depth: depth)) * 180 / .pi
                #expect(seg.step <= nominal + 1e-9 && seg.step > 0)
            }
            // 区間は重ならず隙間もない（次の始点 = 前の始点 + 幅）。
            for (a, b) in zip(segments, segments.dropFirst()) {
                #expect(abs(a.deg + a.step - b.deg) < 1e-9)
            }
        }
        // 最後の区間の箱は区間の長さに切り詰める（1 周の継ぎ目で -180° の最初の座席と重ねない）。座席の箱の x 幅は 1.5m 以下。
        typealias S = M.StadiumColor
        let lower = (0..<S.crowd.count).flatMap { color -> [SIMD3<Float>] in
            stadium.parts.first { $0.color == S.mutedCrowd(color, fraction: S.lowerTierMute) }?.mesh.positions ?? []
        }
        // 最前列の座席は段の上面（1.35m）の上に置く（#1651）。箱の底の頂点で見る。
        let seatBottom = M.Stand.treadTop(row: 0) + 0.01
        let seam = lower.filter { abs($0.x) < 3 && $0.z < -17 && $0.z > -19.5 && abs($0.y - seatBottom) < 0.01 }.map(\.x).sorted()
        #expect(seam.count >= 8, "継ぎ目の座席が見つからない")
        // 隣り合う箱の縁（頂点が 0.1m 未満に固まる）を数え、縁と縁の間隔は座席の幅 1.5m を超えない（座席の間の隙間 0.25m を含めて）。
        var edges: [Float] = []
        for x in seam where edges.last.map({ x - $0 > 0.1 }) ?? true { edges.append(x) }
        for (a, b) in zip(edges, edges.dropFirst()) { #expect(b - a <= 1.5 + 0.01, "縁の間隔 \(b - a)") }
    }

    @Test("スタンドの前縁: 外野は柵の 2m 外・バックネット裏は 16m・両翼はファウルラインの 16m 外側の直線で、弧と直線がつながる")
    func standFront() {
        typealias M = HomerunToonModel
        #expect(abs(Double(M.standFront(0, depth: 0)) - 124) < 1e-3)
        #expect(abs(Double(M.standFront(180, depth: 0)) - 16) < 1e-3 && abs(Double(M.standFront(-150, depth: 5)) - 21) < 1e-3)
        // 90°（一塁線の真横）: ファウルラインからの垂直距離 16m → 本塁から 16/sin45° = 22.6m。
        #expect(abs(Double(M.standFront(90, depth: 0)) - 16 / sin(Double.pi / 4)) < 1e-3)
        // 135° で直線と本塁の弧が一致し、46° 付近で直線は柵の弧に切り替わる（弧より外へは出ない）。
        #expect(abs(M.standFront(135, depth: 3) - M.standFront(136, depth: 3)) < 0.05)
        #expect(M.standFront(50, depth: 0) <= Float(HomerunJudge.fence(atDirection: 46)) + 2 + 1e-3)
        // 奥の列ほど外へ（両翼は垂直距離が増えるので本塁からの距離はより速く増える）。
        #expect(M.standFront(100, depth: 10) > M.standFront(100, depth: 0) + 10)
    }

    @Test("設備: 照明塔 4 基（灯体は 30m より上）・スコアボード（中堅の奥・16m より上）・ファウルポール（両翼 100m の柵の上・20m）")
    func facilities() {
        typealias S = HomerunToonModel.StadiumColor
        let lamps = positions(of: S.lamp).filter { $0.y > 30 }
        #expect(!lamps.isEmpty)
        for (x, z) in [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)] {
            #expect(lamps.contains { Double($0.x) * x > 20 && Double($0.z) * z > 5 }, "(\(x), \(z)) の象限に照明塔が無い")
        }
        // スコアボードはバックスクリーンの裏の建屋の上（z 137・17m より上。壁を越えた球の道に掛からない・#1651）。
        #expect(positions(of: S.screen).contains { abs(abs($0.x) - 13) < 0.01 && $0.z > 130 && $0.y > 16 }, "スコアボードが無い")
        let board = positions(of: S.board).filter { $0.z > 130 }
        #expect(!board.isEmpty && board.allSatisfy { $0.y >= 17 - 0.01 }, "スコアボードが壁を越えた球の道（17m 未満）に掛かる")
        // 灯体（幅 10m の箱）は幅の向きが円の接線 = 面がホームを向く: 外野右の塔（36°）の角は接線 (cos36°, -sin36°) 方向に ±5m。
        let lamp36 = lamps.filter { $0.x > 20 && $0.z > 5 && $0.y > 40 }
        let r36 = HomerunJudge.fence(atDirection: 36) + 30, a36 = 36.0 * .pi / 180
        let center36 = SIMD2(Float(r36 * sin(a36)), Float(r36 * cos(a36)))
        let tangent = SIMD2(Float(cos(a36)), Float(-sin(a36)))
        #expect(lamp36.contains { simd_length(SIMD2($0.x, $0.z) - (center36 + tangent * 5)) < 1.0 }, "灯体の面がホームを向いていない（yaw の符号）")
        // バックネット裏の壁はスタンドの前縁（半径 16m）の上で接線向き（180° の板の幅は x 方向・#1652 で 1 周の壁に統合）。
        let wall = positions(of: HomerunToonModel.StadiumColor.foulPad)
        #expect(wall.contains { abs($0.x) < 2 && abs($0.z + 16) < 0.3 && $0.y > 1.3 }, "バックネット裏の壁が無い・接線を向いていない")
        let yellow = positions(of: HomerunToonPalette.yellow)
        let r = 100 * sin(Double.pi / 4)
        for s in [-1.0, 1.0] {
            #expect(yellow.contains { abs(Double($0.x) - s * r) < 1 && abs(Double($0.z) - r) < 1 && $0.y > 19 }, "\(s > 0 ? "右" : "左")翼のファウルポールが無い")
        }
    }

    @Test("内野: 土の弧の上にダイヤモンドの内側とファウルラインの外側の芝が戻り、走路は 4 辺ある")
    func infieldDirtAndGrass() {
        typealias S = HomerunToonModel.StadiumColor
        let grass = positions(of: S.grass), dirt = positions(of: S.dirt)
        // 土の弧（マウンド中心・半径 29m）の頂点。
        #expect(dirt.contains { abs(Double($0.z) - (18.44 + 29)) < 0.5 && abs($0.x) < 0.5 })
        // 箱の頂点は角だけ。ダイヤモンドの内側の芝（走路の内側に 25.5m 角）は二塁側の角 (0, 19.4 + 25.5/√2) が土より上（y ≥ 0.02）。
        let diamondTip = 19.4 + 25.5 / Float(2).squareRoot()
        #expect(grass.contains { abs($0.x) < 0.01 && abs($0.z - diamondTip) < 0.01 && $0.y >= 0.02 }, "ダイヤモンドの内側の芝が無い・土より下にある")
        // ファウルラインの外側の芝は本塁の後ろ（z < -20）まで届き、縞（y ≤ 0）より上にある。
        #expect(grass.contains { $0.z < -20 && $0.y >= 0.02 }, "ファウル側の芝が無い")
        // 一塁→二塁・三塁→二塁の走路: 一塁側の端の内側の角 (±18.72, 18.74)（本塁→一塁の走路の角 (±20.06, 18.72) とは別）。
        for s: Float in [-1, 1] {
            #expect(dirt.contains { abs($0.x - s * 18.72) < 0.05 && abs($0.z - 18.74) < 0.05 && $0.y >= 0.04 }, "塁間の走路が無い")
        }
    }

    @Test("遠景（街並み・雲）は陰影なし（shade = 1）で、スタンドの外（220m 以遠）にある")
    func skylineIsFlatAndFar() {
        typealias S = HomerunToonModel.StadiumColor
        for color in [S.skylineNear, S.skylineFar, S.cloud] {
            let part = stadium.parts.first { $0.color == color }
            #expect(part != nil, "\(String(color, radix: 16)) が無い")
            guard let part else { continue }
            #expect(part.mesh.shade.allSatisfy { $0 == 1 })
            #expect(part.mesh.positions.allSatisfy { simd_length(SIMD2($0.x, $0.z)) > 200 })
        }
        // 球場の本体（座席）は陰影が付く。
        let seat = stadium.parts.first { $0.color == S.mutedCrowd(0, fraction: S.lowerTierMute) }!
        #expect(seat.mesh.shade.contains { $0 < 0.5 })
    }

    @Test("三角形の数は 20 万未満（古い端末で 60fps を保つ予算）")
    func triangleBudget() {
        let triangles = stadium.parts.reduce(0) { $0 + $1.mesh.indices.count / 3 }
        #expect(triangles < 200_000, "三角形が \(triangles) 個")
        #expect(triangles > 40_000, "球場が薄すぎる（\(triangles) 個）")
    }

    @Test("merged は輪郭線つきの部品を分けたまま残し、頂点数の合計を変えない")
    func mergedKeepsGeometry() {
        var m = HomerunToonModel()
        m.box(1, 1, 1, 0xFF0000, at: [0, 0, 0], outline: 0)
        m.box(1, 1, 1, 0xFF0000, at: [3, 0, 0], outline: 0)
        m.box(1, 1, 1, 0x00FF00, at: [6, 0, 0], outline: 0)
        m.box(1, 1, 1, 0xFF0000, at: [9, 0, 0])
        let merged = m.merged()
        // 赤（まとめた 1）+ 緑 + 輪郭線つきの赤（分けたまま。本体 1 と輪郭は 1 部品）
        #expect(merged.parts.count == 3)
        let before: Int = m.parts.reduce(0) { $0 + $1.mesh.positions.count }
        let after: Int = merged.parts.reduce(0) { $0 + $1.mesh.positions.count }
        #expect(after == before)
        #expect(merged.parts.filter { $0.outline != nil }.count == 1)
    }

    @Test("box の yaw は板を y 軸まわりに回す（x 方向に長い板が yaw 90° で z 方向に長くなる）")
    func boxYaw() {
        var m = HomerunToonModel()
        m.box(4, 1, 0.2, 0xFFFFFF, at: [0, 0, 0], outline: 0, yaw: .pi / 2)
        let p = m.parts[0].mesh.positions
        let zSpan = p.map(\.z).max()! - p.map(\.z).min()!, xSpan = p.map(\.x).max()! - p.map(\.x).min()!
        #expect(abs(zSpan - 4) < 1e-4 && abs(xSpan - 0.2) < 1e-4)
    }

    @Test("box の yaw は正の角で x 軸を -z 側へ回す（45° で板の角が (1.485, -1.343) に来る）")
    func boxYawSign() {
        var m = HomerunToonModel()
        m.box(4, 1, 0.2, 0xFFFFFF, at: [0, 0, 0], outline: 0, yaw: .pi / 4)
        let p = m.parts[0].mesh.positions
        // 局所の角 (2, 0.1) は x' = 2cos45° + 0.1sin45° = 1.485・z' = -2sin45° + 0.1cos45° = -1.343 へ動く。
        #expect(p.contains { abs($0.x - 1.485) < 0.01 && abs($0.z + 1.343) < 0.01 })
        #expect(!p.contains { $0.x > 1 && $0.z > 1 })
    }

    @Test("芝は 5m 幅の縞、本塁は五角形の先端（0, -0.432）まで届く")
    func groundDetails() {
        let grass = stadium.parts.first { $0.color == HomerunToonModel.StadiumColor.grass }!.mesh
        let zs = Set(grass.positions.map { ($0.z * 2).rounded() / 2 })
        #expect(zs.contains(-200) && zs.contains(-195) && zs.contains(-190), "縞の境目が 5m 刻みになっていない")
        let plate = stadium.parts.first { $0.color == HomerunToonPalette.white }!.mesh
        #expect(plate.positions.contains { abs($0.x) < 0.01 && abs($0.z + 0.432) < 0.01 }, "本塁の先端が無い")
    }

    // #1652 会長 QA「ファウルポールより外側のフェンスが無く客席が剥き出し」: 原因は形状（柵の板が ±46° で終わっていた）。
    @Test("ファウルゾーンの壁は柵の端から本塁の後ろまで前縁の上で 1 周つながり、柵の端は壁の高さのままスタンドの前縁までつなぐ")
    func foulWallWrapsAround() {
        typealias M = HomerunToonModel
        typealias S = M.StadiumColor
        let pad = positions(of: S.foulPad)
        func direction(_ p: SIMD3<Float>) -> Double { atan2(Double(p.x), Double(p.z)) * 180 / .pi }
        for deg in stride(from: 50.0, through: 180.0, by: 10) {
            for s in (deg == 180 ? [1.0] : [-1.0, 1.0]) {
                // 両翼の前縁は 1° で数 m 変わる直線なので、頂点ごとにその方向の前縁と比べる。
                let near = pad.filter { abs(direction($0) - s * deg) < 6 && abs(simd_length(SIMD2($0.x, $0.z)) - M.standFront(direction($0), depth: 0)) < 1.2 }
                #expect(near.contains { $0.y > 1.3 }, "\(s * deg)° の壁が無い")
                #expect(near.allSatisfy { $0.y >= -0.01 }, "\(s * deg)° の壁が地面に埋まる")
            }
        }
        // 柵の端（46°）から 54° までは柵と同じ高さ（3.2m）、その先の両翼は 2.2m、バックネット裏は 1.4m（会長 QA 2026-10-01）。
        #expect(pad.contains { abs(direction($0) - 50) < 4 && $0.y > 3.1 }, "柵の端に続く壁が低い")
        #expect(pad.contains { abs(direction($0)) > 60 && abs(direction($0)) < 130 && $0.y > 2.1 }, "両翼の壁が低い（フェンスに見えない）")
        #expect(!pad.contains { abs(direction($0)) > 60 && $0.y > 2.3 }, "両翼の壁が高すぎる")
        #expect(!pad.contains { abs(direction($0)) > 140 && $0.y > 1.5 }, "バックネット裏の壁が高すぎる")
        // 両翼の壁の上にも黄色の線（柵と同じ見た目）。バックネット裏には無い。
        let yellow = positions(of: HomerunToonPalette.yellow)
        #expect(yellow.contains { abs(direction($0) - 90) < 3 && $0.y > 2.1 && $0.y < 2.5 }, "両翼の壁に黄色の線が無い")
        #expect(!yellow.contains { abs(direction($0)) > 140 && $0.y < 5 }, "バックネット裏に黄色の線がある")
        // 柵の端（46°・柵の距離）とスタンドの前縁（2m 外）をつなぐ壁は柵の色。
        let fence = positions(of: S.fence)
        for s in [-1.0, 1.0] {
            #expect(fence.contains { abs(direction($0) - s * 46) < 0.5 && simd_length(SIMD2($0.x, $0.z)) > Float(HomerunJudge.fence(atDirection: 46)) + 1.5 && $0.y > 3 },
                    "\(s * 46)° の柵の端とスタンドをつなぐ壁が無い")
        }
    }

    @Test("柵の上の金網は柵越えの球が柵の上で通る高さ（4.6m − 球の半径）より下で、距離表示（122・111・100）は柵の面にある")
    func fenceNetAndDistanceMarks() {
        typealias M = HomerunToonModel
        typealias S = M.StadiumColor
        func onFence(_ p: SIMD3<Float>) -> Bool {
            let deg = atan2(Double(p.x), Double(p.z)) * 180 / .pi
            return abs(deg) <= 46.5 && abs(Double(simd_length(SIMD2(p.x, p.z))) - HomerunJudge.fence(atDirection: deg)) < 0.6
        }
        let net = (positions(of: S.wire) + positions(of: S.rail)).filter(onFence)
        #expect(net.contains { $0.y > 4.0 }, "金網が無い")
        #expect(net.allSatisfy { Double($0.y) <= HomerunBallChase.fenceClearance - HomerunBallChase.ballRadius - 0.05 }, "金網が柵越えの球に掛かる")
        #expect(M.Fence.netTopY < Float(HomerunBallChase.fenceClearance - HomerunBallChase.ballRadius))
        // 黄色の線はラバーの上端のまま（追うカメラが柵越しに見る `fenceTop` 3.45 より下）。
        #expect(Double(M.Fence.lineY + M.Fence.lineHeight / 2) <= HomerunBallChase.fenceTop + 0.01)
        let white = positions(of: HomerunToonPalette.white).filter(onFence)
        for (deg, _) in M.Fence.distanceMarks {
            let r = HomerunJudge.fence(atDirection: deg), a = deg * .pi / 180
            let digits = white.filter { abs(Double($0.x) - r * sin(a)) < 1.5 && abs(Double($0.z) - r * cos(a)) < 1.5 }
            #expect(digits.contains { $0.y > 1.9 } && digits.contains { $0.y < 1.4 }, "\(deg)° の距離表示が無い")
            // 本塁側の面（柵の中心より 0.2m 手前）の上に浮かせ、面から離れすぎない（頂点ごとにその方向の柵の距離で見る）。
            for p in digits {
                let own = HomerunJudge.fence(atDirection: atan2(Double(p.x), Double(p.z)) * 180 / .pi)
                let radius = Double(simd_length(SIMD2(p.x, p.z)))
                #expect(radius < own - 0.12 && radius > own - 0.45, "\(deg)° の距離表示が柵に埋まる・浮く（\(radius) / \(own)）")
            }
        }
    }

    @Test("スタンドの段は地面から隙間なく積み（前の段の上面 = 次の段の下面）、打球が落ちる面（HomerunBallChase.standSurface）は段の上面のまま")
    func treadsAreSolidAndMatchTheLandingSurface() {
        typealias Stand = HomerunToonModel.Stand
        #expect(Stand.treadBottom(row: 0) == 0 && Stand.treadFront(row: 0) == 0)
        for row in 1..<Stand.rows {
            #expect(Stand.treadBottom(row: row) == Stand.treadTop(row: row - 1))
            #expect(Stand.treadFront(row: row) >= Stand.treadBack(row: row - 1) - 1e-4, "\(row) 列目の段が前の段と重なる")
        }
        for row in 0..<Stand.rows {
            #expect(abs(HomerunBallChase.standSurface(depth: Double(Stand.depth(row: row))) - Double(Stand.treadTop(row: row))) < 1e-5, "\(row) 列目")
        }
        // 段の箱は 1 周にあり、最前列は地面（y = 0）から立ち上がる。
        let tread = positions(of: HomerunToonModel.StadiumColor.tread)
        func direction(_ p: SIMD3<Float>) -> Double { atan2(Double(p.x), Double(p.z)) * 180 / .pi }
        for deg in stride(from: -170.0, through: 170.0, by: 20) {
            #expect(tread.contains { abs(direction($0) - deg) < 5 && $0.y < 0.01 }, "\(deg)° の最前列の段が地面から始まらない")
        }
    }

    @Test("階段通路は本塁から放射状で約 12m おき・真後ろ（180°）には置かず、通路の脇に手すりがある")
    func aislesAndRails() {
        typealias M = HomerunToonModel
        let aisles = M.aisleAngles
        #expect(aisles.count > 20 && !aisles.contains { abs($0) > 170 })
        for (a, b) in zip(aisles, aisles.dropFirst()) {
            let r = M.standFront((a + b) / 2, depth: M.Stand.depth(row: M.Stand.lowerRows / 2))
            let gap = Double(r) * (b - a) * .pi / 180
            #expect(gap > 6 && gap < 18, "通路の間隔 \(gap)m")
        }
        let rail = positions(of: M.StadiumColor.rail)
        #expect(rail.contains { $0.y > 10 && $0.z < -20 }, "上段の通路に手すりが無い")
    }

    // 会長指示 2026-10-01: 後ろ（バックネット・ネット裏の客席・内野スタンドの後方）にカメラを向けても破綻しない。
    @Test("バックネット裏: 壁の上に網（支柱 + 横線・本塁の真後ろには支柱を置かない）、上段の後ろに放送席、両翼にダッグアウト")
    func backstopAndDugouts() {
        typealias M = HomerunToonModel
        typealias S = M.StadiumColor
        let posts = positions(of: S.rail).filter { $0.z < -14 && $0.y > 8 }
        #expect(posts.contains { $0.x > 10 } && posts.contains { $0.x < -10 }, "バックネットの支柱が無い")
        #expect(!posts.contains { abs($0.x) < 1.5 && abs($0.z + 16) < 1 && $0.y > 5 && $0.y < 8.8 }, "本塁の真後ろに支柱がある（前のカメラで打者の後ろに柱が立つ）")
        let wires = positions(of: S.wire).filter { $0.z < -14 }
        #expect(wires.contains { abs($0.x) < 3 && $0.y > 4 && $0.y < 7 }, "網の横線が無い")
        // 放送席は上段の後ろ 2 列の上（本塁の後ろ 38m 前後・13〜17m）で屋根より低い。
        let press = positions(of: S.concourse).filter { abs($0.x) <= M.Stand.pressBoxWidth / 2 + 0.01 && $0.z < -35 && $0.z > -42 && $0.y > 12 }
        #expect(!press.isEmpty, "放送席が無い")
        #expect(press.allSatisfy { $0.y < M.Stand.roofHeight - 0.5 })
        let window = positions(of: S.screen).filter { $0.z < -30 }
        #expect(window.contains { $0.y > 14 && $0.y < 17 }, "放送席の窓が無い")
        // ダッグアウト（ファウルラインに沿って 20〜32m・線の 16m 外）: 開口は壁より手前（グラウンド側）にある。
        let dugout = positions(of: S.dugout)
        let root2 = Float(2).squareRoot()
        for s: Float in [-1, 1] {
            let center = SIMD2<Float>(s * (26 + 16) / root2, (26 - 16) / root2)
            let near = dugout.filter { simd_length(SIMD2($0.x, $0.z) - center) < 7 }
            #expect(near.count >= 8, "\(s > 0 ? "三塁" : "一塁")側のダッグアウトが無い")
            #expect(near.allSatisfy { $0.y >= 0.05 && $0.y <= 1.75 })
        }
    }

    @Test("打席シーンの置き方: 右打者は前のカメラの画面の右（+x）で左肩を投手へ・捕手は本塁の後ろの打者と反対側・投手はマウンドでカメラに背を向ける")
    func atBatLayout() {
        typealias L = HomerunAtBatLayout
        // バットが本塁の上の球の通り道に届く距離（`HomerunSwingContact`）。バッターボックスの内側の線（0.246m）より外に腰（原点 + 0.1m）がある。
        #expect(L.batter.position.x > 0.15 && L.batter.position.x + 0.1 >= 0.29, "右打者は前のカメラの画面の右（+x）のバッターボックスに立つ")
        // Meshy の打者は構えで左肩が +x。y 軸まわりに yaw 回すと +x は (cos, 0, -sin) へ向く → 投手（+z）を向くこと。
        let leftShoulder = SIMD3<Float>(cos(L.batter.yaw), 0, -sin(L.batter.yaw))
        #expect(simd_dot(leftShoulder, [0, 0, 1]) > 0.99, "左肩が投手を向いていない")
        let chest = SIMD3<Float>(sin(L.batter.yaw), 0, cos(L.batter.yaw))
        #expect(simd_dot(chest, [-1, 0, 0]) > 0.99, "胸が本塁（-x）を向いていない")
        #expect(L.catcher.position.z < 0, "捕手は本塁の奥")
        #expect(L.catcher.position.x < 0, "捕手は打者と反対側へ寄せる")
        // 本塁の真後ろ（五角形の先端 z −0.432 より奥・本塁の幅 ±0.216 の中）で、ミットは本塁の中央の後ろ。
        #expect(L.catcher.position.z < -0.432 && L.catcher.position.z > -1.3 && abs(L.catcher.position.x) < 0.216)
        #expect(abs(HomerunBallFlight.mittPoint().x) < 0.15, "ミット \(HomerunBallFlight.mittPoint())")
        #expect(abs(L.machine.position.z - 17.6) < 1e-4 && abs(L.machine.position.y - 0.3) < 1e-4, "マシンはマウンドの上（高さ 0.3m）")
        #expect(abs(L.machine.yaw) < 1e-6, "マシンは -z（本塁）へ打ち出す向きのまま置く")
        #expect(L.cameraPosition.z > 20 && L.cameraTarget.z < 1, "センター側から本塁を見る")
        let toBatter = simd_normalize(SIMD3<Float>(L.batter.position.x, 1.7, L.batter.position.z) - L.cameraPosition)
        let axis = simd_normalize(L.cameraTarget - L.cameraPosition)
        let angle = acos(simd_dot(toBatter, axis)) * 180 / .pi
        #expect(angle < L.verticalFieldOfView / 2, "打者の頭が画角の外（\(angle)°）")
    }

    @Test("ストライクゾーンの中心は画面の高さの 45% に映り（2D のゾーンを重ねる位置）、打者の頭・足元も画面に収まる")
    func zoneProjectsWhereTheHUDPutsIt() {
        typealias L = HomerunAtBatLayout
        let zone = L.screenFraction(of: L.zoneWorldCenter)
        #expect(abs(zone - L.zoneScreenFraction) < 0.005, "ゾーンの中心が \(zone)")
        let head = L.screenFraction(of: [L.batter.position.x, 1.75, L.batter.position.z])
        let feet = L.screenFraction(of: [L.batter.position.x, 0, L.batter.position.z])
        #expect(head > 0.05 && feet < 0.95, "打者が画面の外（頭 \(head)・足元 \(feet)）")
        #expect(L.zoneScreenFraction + 0.2 < 2.0 / 3, "ゾーンの下端が押せる帯（下 1/3）に食い込む")
    }

    @Test("カメラ（前・後ろ）はどちらもストライクゾーンの中心を画面の横の中央・高さ 45% に映し、打者の頭と足元・振り抜いたバットが画面に収まる",
          arguments: HomerunAtBatLayout.CameraPreset.allCases)
    func presetsKeepZoneWhereTheHUDIs(preset: HomerunAtBatLayout.CameraPreset) {
        typealias L = HomerunAtBatLayout
        let cam = preset.camera
        for aspect in [9.0 / 19.5, 9.0 / 16.0] {
            let zone = cam.screenPoint(of: L.zoneWorldCenter, aspect: aspect)
            #expect(abs(zone.x - 0.5) < 0.005 && abs(zone.y - L.zoneScreenFraction) < 0.005, "\(preset): ゾーンが (\(zone.x), \(zone.y))")
            let head = cam.screenPoint(of: L.worldPoint([0, 1.75, 0], of: L.batter, for: cam), aspect: aspect)
            let feet = cam.screenPoint(of: L.worldPoint([0, 0, 0], of: L.batter, for: cam), aspect: aspect)
            #expect(head.y > 0.05 && feet.y < 0.95 && head.x > 0.05 && head.x < 0.95, "\(preset): 打者が画面の外（頭 \(head)・足元 \(feet)）")
            // 振り抜いたバット（USDZ から測った軌跡の全コマ）も SE（9:16）・Pro Max（9:19.5）の画面の中。
            for t in stride(from: 0.0, through: HomerunBatPath.duration, by: 1.0 / 30) {
                let s = HomerunBatPath.segment(atClipTime: t)
                for local in [s.grip, s.tip] {
                    let p = cam.screenPoint(of: L.worldPoint(local, of: L.batter, for: cam), aspect: aspect)
                    #expect(p.x > 0.02 && p.x < 0.98 && p.y > 0.05 && p.y < 0.95, "\(preset): \(HomerunBatPath.frame(atClipTime: t)) コマ目のバットが画面の外 \(p)")
                }
            }
            // 投手（マウンドの上）が画面に入る制約は外した: 投手は廃止してバッティングマシンに置き換える予定（会長決裁 2026-09-29）。
            // 前のカメラは 28m まで寄せたので投手は画角の下に外れる。
        }
        #expect(simd_length(cam.target - cam.position) > 5)
    }

    // 会長指示「おじさん遠すぎ」（2026-09-29）: 前・後ろとも打者の背丈が画面の高さの 30% 以上。
    @Test("カメラ（前・後ろ）は打者の背丈（足元〜頭 1.72m）を画面の高さの 30% 以上に映す", arguments: HomerunAtBatLayout.CameraPreset.allCases)
    func presetsShowTheBatterLarge(preset: HomerunAtBatLayout.CameraPreset) {
        typealias L = HomerunAtBatLayout
        let cam = preset.camera
        for aspect in [9.0 / 19.5, 9.0 / 16.0] {
            let height = cam.screenPoint(of: L.worldPoint([0, 0, 0], of: L.batter, for: cam), aspect: aspect).y
                - cam.screenPoint(of: L.worldPoint([0, 1.72, 0], of: L.batter, for: cam), aspect: aspect).y
            #expect(height >= 0.30, "\(preset): 打者の背丈が画面の \(height)")
        }
    }

    @Test("aimed は指定の点を画面の (0.5, yFraction) に置き、位置と画角は変えない")
    func aimedCamera() {
        let anchor: SIMD3<Float> = [1, 0.9, 0]
        for (position, fov, y) in [(SIMD3<Float>(8, 10, 40), Float(14), 0.45), ([-3, 6, -12], 45, 0.3), ([0, 2, 20], 30, 0.6)] {
            let cam = HomerunAtBatLayout.Camera.aimed(from: position, at: anchor, yFraction: y, verticalFieldOfView: fov)
            let p = cam.screenPoint(of: anchor, aspect: 0.5)
            #expect(abs(p.x - 0.5) < 1e-4 && abs(p.y - y) < 1e-4, "\(p)")
            #expect(cam.position == position && cam.verticalFieldOfView == fov)
        }
    }

    @Test("後ろのカメラは打者を検討時の案 B（14m 後ろ・高さ 7m・54°）より 2 倍以上大きく、本塁を画面のより下（手前）に映す")
    func backCameraBringsTheBoxCloser() {
        typealias L = HomerunAtBatLayout
        let caseB = L.Camera.aimed(from: [0.5, 7, -14], at: L.zoneWorldCenter, yFraction: L.zoneScreenFraction,
                                   verticalFieldOfView: 54, mirrored: true)
        let back = L.CameraPreset.back.camera
        for aspect in [9.0 / 19.5, 9.0 / 16.0] {
            func height(_ cam: L.Camera) -> Double {
                cam.screenPoint(of: L.worldPoint([0, 0, 0], of: L.batter, for: cam), aspect: aspect).y
                    - cam.screenPoint(of: L.worldPoint([0, 1.75, 0], of: L.batter, for: cam), aspect: aspect).y
            }
            #expect(height(back) > 2 * height(caseB), "打者の背丈 \(height(back)) / 案 B \(height(caseB))")
            #expect(back.screenPoint(of: [0, 0, 0], aspect: aspect).y > caseB.screenPoint(of: [0, 0, 0], aspect: aspect).y + 0.05)
            // 本塁の真後ろの捕手の頭（ヘルメットの上）は、ゾーン（2D・SE の高さ 667pt で測る）の下の外に映り、ゾーンを塞がない。
            let zoneBottom = L.zoneScreenFraction + Double(HomerunZoneGeometry.zoneSize) / 2 / 667
            let head = L.worldPoint([0, 4.3 * L.catcherScale, 0], of: L.catcher, for: back)
            #expect(back.screenPoint(of: head, aspect: aspect).y > zoneBottom, "捕手の頭がゾーンに重なる \(back.screenPoint(of: head, aspect: aspect))")
        }
    }

    @Test("後ろのカメラだけ左右反転し（HUD の右 = 一塁側に合う）、右打者は前では画面の右・後ろでは画面の左に映る")
    func rearPresetsAreMirrored() {
        typealias L = HomerunAtBatLayout
        #expect(!L.CameraPreset.front.camera.mirrored && L.CameraPreset.back.camera.mirrored)
        for preset in L.CameraPreset.allCases {
            let cam = preset.camera
            let batter = cam.screenPoint(of: L.worldPoint([0, 1, 0], of: L.batter, for: cam), aspect: 0.5)
            let firstBase = cam.screenPoint(of: [19.4, 0, 19.4], aspect: 0.5)
            // 右打者は前（センター側から見る）では画面の右、後ろ（本塁の後ろから見る）では画面の左に立つのが本来の見え方。
            #expect(preset == .front ? batter.x > 0.5 : batter.x < 0.5, "\(preset): 打者が \(batter.x)")
            #expect(firstBase.x > 0.5, "\(preset): 一塁側（+x）が画面の左に映り、方向メーターの右と食い違う")
        }
        // 反転は x だけ（y はそのまま）。
        var cam = L.CameraPreset.front.camera
        let before = cam.screenPoint(of: [3, 1, 0], aspect: 0.5)
        cam.mirrored = true
        let after = cam.screenPoint(of: [3, 1, 0], aspect: 0.5)
        #expect(abs(before.x + after.x - 1) < 1e-9 && before.y == after.y)
    }

    // 後ろのカメラは描画を左右反転するので、人物を鏡映しないと右打ちの Meshy の打者が左打ちに見える。
    // 画面に映った打者の「胸・上・左肩」の 3 本の向きの掌性（行列式の符号）が前と後ろで同じ = 同じ右打ちに見えること。
    @Test("後ろのカメラでも打者は前と同じ右打ちに見える（左右反転の描画を人物の鏡映で打ち消す）")
    func batterKeepsHandednessOnScreen() {
        typealias L = HomerunAtBatLayout
        func handedness(_ cam: L.Camera) -> Float {
            let forward = simd_normalize(cam.target - cam.position)
            let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
            let up = simd_cross(right, forward)
            func onScreen(_ local: SIMD3<Float>) -> SIMD3<Float> {
                let v = L.worldPoint(local, of: L.batter, for: cam) - L.worldPoint([0, 1, 0], of: L.batter, for: cam)
                return [simd_dot(v, right) * (cam.mirrored ? -1 : 1), simd_dot(v, up), simd_dot(v, forward)]
            }
            // Meshy の打者の局所座標: 胸 = +z・左肩 = +x・上 = +y。
            let chest = onScreen([0, 1, 1]), leftShoulder = onScreen([1, 1, 0]), head = onScreen([0, 2, 0])
            return simd_dot(chest, simd_cross(head, leftShoulder))
        }
        let front = handedness(L.CameraPreset.front.camera), back = handedness(L.CameraPreset.back.camera)
        #expect(abs(front) > 0.5 && front * back > 0, "前 \(front)・後ろ \(back) で掌性が逆（後ろで左打ちに見える）")
        #expect(!L.castMirrored(for: L.CameraPreset.front.camera) && L.castMirrored(for: L.CameraPreset.back.camera))
    }

    // 描画は反転（UIView の scaleX -1）と人物の鏡映の代わりに、カメラを x について鏡映して反転なしで描く
    // （人物を鏡映すると三角形の表裏が逆になり、iOS 17 では輪郭線が体を覆って真っ黒になった）。同じ画になること。
    @Test("後ろのカメラの描画（鏡映したカメラ・反転なし）は、人物を鏡映して反転した投影（screenPoint）と同じ画になる",
          arguments: HomerunAtBatLayout.CameraPreset.allCases)
    func renderPoseMatchesMirroredProjection(preset: HomerunAtBatLayout.CameraPreset) {
        typealias L = HomerunAtBatLayout
        let cam = preset.camera
        let pose = cam.renderPose
        let rendered = L.Camera(position: pose.position, target: pose.target, verticalFieldOfView: cam.verticalFieldOfView)
        for p in [L.batter, L.catcher, L.machine] {
            for local: SIMD3<Float> in [[0, 0, 0], [0.3, 1.2, 0.2], [-0.2, 1.7, -0.1]] {
                // 描画される世界の点（人物は鏡映しない）。
                let drawn = p.position + simd_quatf(angle: p.yaw, axis: [0, 1, 0]).act(local)
                let a = rendered.screenPoint(of: drawn, aspect: 0.5)
                let b = cam.screenPoint(of: L.worldPoint(local, of: p, for: cam), aspect: 0.5)
                #expect(abs(a.x - b.x) < 1e-5 && abs(a.y - b.y) < 1e-5, "\(preset): \(a) と \(b)")
            }
        }
        // 球場（左右対称）の点は鏡映した点どうしが対応する（ゾーンの中心は同じ所に映る）。
        let zone = rendered.screenPoint(of: L.zoneWorldCenter, aspect: 0.5)
        #expect(abs(zone.x - 0.5) < 0.005 && abs(zone.y - L.zoneScreenFraction) < 0.005)
    }

    @Test("前のカメラはセンター側 28m・高さ 4.5m・望遠 9.6°（43m・6m から寄せた・会長指示 2026-09-29）。後ろは 5.5m 後ろ・高さ 2.6m・50°")
    func presetNumbers() {
        #expect(HomerunAtBatLayout.CameraPreset.allCases == [.front, .back], "選べるのは前・後ろの 2 つだけ")
        let front = HomerunAtBatLayout.CameraPreset.front.camera
        #expect(front.position == [0, 4.5, 28] && front.verticalFieldOfView == 9.6 && !front.mirrored)
        #expect(HomerunAtBatLayout.cameraPosition == front.position && HomerunAtBatLayout.verticalFieldOfView == 9.6)
        let back = HomerunAtBatLayout.CameraPreset.back.camera
        #expect(back.position == [-0.5, 2.6, -5.5] && back.verticalFieldOfView == 50 && back.mirrored)
    }
}

@Suite("柵越えおじさんの打者のポーズ")
struct HomerunBatterPoseTests {
    @Test("投球中・打席前・終了後は構え")
    func stanceOutsideResult() {
        for phase in [HomerunModel.Phase.idle, .pitching, .finished] {
            #expect(HomerunAtBatLayout.batterPose(phase: phase, lastKind: .homer) == .stance)
        }
        #expect(HomerunAtBatLayout.batterPose(phase: .ballResult, lastKind: nil) == .stance)
    }

    @Test("結果の間は打球の種別でポーズが決まる")
    func poseByKind() {
        let expected: [HomerunKind: HomerunOjisanPose3] = [
            .miss: .whiff, .homer: .cheer, .foul: .swing, .inPlay: .swing, .fenceHit: .swing,
        ]
        #expect(expected.count == HomerunKind.allCases.count)
        for (kind, pose) in expected {
            #expect(HomerunAtBatLayout.batterPose(phase: .ballResult, lastKind: kind) == pose)
        }
    }
}

// 会長 QA 2026-09-30「後ろのカメラのとき、おじさんがベースに近すぎる」。構えの間だけ外へ離して見せ、踏み込みで本来の位置へ寄る。
@Suite("柵越えおじさんの後ろのカメラの打者の立ち位置")
struct HomerunBackStanceSlideTests {
    typealias L = HomerunAtBatLayout
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test("前のカメラも後ろと同じだけずらす（構えのつま先がボックスの線を越えないように・#1667）")
    func frontSlidesLikeBack() {
        let front = L.CameraPreset.front.camera, back = L.CameraPreset.back.camera
        for motion in [HomerunBatterMotion.stance, .load(start: t0), .swing(start: t0)] {
            #expect(L.batterSlideTarget(motion, camera: front, now: t0.addingTimeInterval(0.3))
                    == L.batterSlideTarget(motion, camera: back, now: t0.addingTimeInterval(0.3)))
        }
    }

    @Test("後ろのカメラは構えで外へ 0.25m、踏み込みの間に 0 へ寄り、振りの間はずれを変えない")
    func backSlidesDuringLoad() {
        let back = L.CameraPreset.back.camera
        #expect(L.batterSlideTarget(.stance, camera: back, now: t0) == L.backStanceSlide)
        #expect(L.batterSlideTarget(.load(start: t0), camera: back, now: t0) == L.backStanceSlide)
        let half = L.batterSlideTarget(.load(start: t0), camera: back, now: t0.addingTimeInterval(HomerunBatterMotion.loadDuration / 2))
        #expect(abs((half ?? -1) - L.backStanceSlide / 2) < 1e-4)
        #expect(L.batterSlideTarget(.load(start: t0), camera: back, now: t0.addingTimeInterval(HomerunBatterMotion.loadDuration)) == 0)
        #expect(L.batterSlideTarget(.swing(start: t0), camera: back, now: t0) == nil)
    }

    @Test("構えで外へ離すと、後ろから見て体の本塁側の縁がゾーンから遠ざかる（本来の位置ではゾーンに重なる）")
    func stanceClearsTheZone() {
        let back = L.CameraPreset.back.camera
        let aspect = 9.0 / 19.5
        // ゾーン（幅 0.36m）の打者側の縁。後ろのカメラでは人物は鏡映して置く扱い（`worldPoint`）なので、打者は -x・縁も -x 側。
        let zoneEdge = back.screenPoint(of: [-0.18, 0.9, 0], aspect: aspect).x
        // 打者の体の本塁側の縁（胸の前 0.2m・肩の高さ）。
        func edge(slide: Float) -> Double {
            var p = L.batter
            p.position.x += slide
            return back.screenPoint(of: L.worldPoint([0, 1.3, 0.2], of: p, for: back), aspect: aspect).x
        }
        #expect(edge(slide: 0) > zoneEdge, "本来の位置では体がゾーンに重なる（前提）: \(edge(slide: 0)) / \(zoneEdge)")
        #expect(edge(slide: L.backStanceSlide) < zoneEdge, "外へ離すと体がゾーンの外に出る: \(edge(slide: L.backStanceSlide)) / \(zoneEdge)")
    }

    @Test("当たり窓の始まり（輪が重なる 110ms 前）には踏み込みが終わって本来の位置にいる = 打点・判定は変わらない")
    func contactHappensAtTheRealPlacement() {
        let travel = TimeInterval(HomerunPitch.travelMilliseconds) / 1000
        let clock = HomerunModel.BallClock(pitchStart: t0, zone: 4, pressedAt: nil, releasedAt: nil, timingOffset: nil)
        let plan = HomerunSwingPlan(phase: .pitching, clock: clock, lastBall: nil)
        let windowStart = t0.addingTimeInterval(travel - HomerunTiming.hitWindow / 1000)
        let motion = plan.batterMotion(at: windowStart)
        #expect((L.batterSlideTarget(motion, camera: L.CameraPreset.back.camera, now: windowStart) ?? 1) < 1e-4)
    }

    @Test("後ろのカメラの構えは外へ 0.25m・捕手側へ 0.25m ずらし、ずれ 0（踏み込みの後）では本来の位置（#1619）")
    func stanceOffsetMovesOutAndBack() {
        #expect(L.batterOffset(slide: L.backStanceSlide) == [L.backStanceSlide, 0, -L.backStanceSetBack])
        #expect(L.batterOffset(slide: 0) == [0, 0, 0])
        let half = L.batterOffset(slide: L.backStanceSlide / 2)
        #expect(abs(half.x - L.backStanceSlide / 2) < 1e-6 && abs(half.z + L.backStanceSetBack / 2) < 1e-6, "外と捕手側へ同じ割合で寄る")
    }

    #if canImport(RealityKit)
    /// USDZ の構え（1 コマ目）の両足の骨（Foot・ToeBase）の打者の局所座標。
    @MainActor
    private func stanceFeet() throws -> [SIMD3<Float>] { try feet(.stance, now: Date()) }

    /// 段階 `motion` を時刻 `now` に見せたときの両足の骨の打者の局所座標。
    @MainActor
    private func feet(_ motion: HomerunBatterMotion, now: Date) throws -> [SIMD3<Float>] {
        let rig = try #require(HomerunBatterRig())
        if #available(macOS 15.0, iOS 18.0, *) {
            let renderer = try RealityRenderer()
            renderer.entities.append(rig.entity)
            rig.show(motion, now: now)
            try renderer.update(0.001)
        }
        func find(_ e: Entity) -> ModelEntity? {
            if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
            for c in e.children { if let m = find(c) { return m } }
            return nil
        }
        let model = try #require(find(rig.entity))
        let names = model.jointNames
        let feet = names.indices.filter { i in
            let leaf = names[i].split(separator: "/").last.map(String.init) ?? ""
            return leaf.hasSuffix("Foot") || leaf.hasSuffix("ToeBase")
        }
        #expect(feet.count == 4, "両足の Foot・ToeBase: \(feet.map { names[$0] })")
        return feet.map { index in
            var m = matrix_identity_float4x4
            var path = names[index]
            while true {
                if let i = names.firstIndex(of: path) { m = model.jointTransforms[i].matrix * m }
                guard let slash = path.lastIndex(of: "/") else { break }
                path = String(path[..<slash])
            }
            let p = m * SIMD4<Float>(0, 0, 0, 1)
            return [p.x, p.y, p.z]
        }
    }

    @Test("後ろのカメラの構えでは、両足がバッターボックスの線の内側にあり、本塁の前縁より捕手側にある（#1619）")
    @MainActor
    func backStanceFeetAreInsideTheBox() throws {
        typealias B = HomerunToonModel.BatterBox
        let offset = L.batterOffset(slide: try #require(L.batterSlideTarget(.stance, camera: L.CameraPreset.back.camera, now: t0)))
        for local in try stanceFeet() {
            let w = L.batterWorld(local) + offset
            #expect(w.x > B.innerX + B.line / 2 && w.x < B.outerX - B.line / 2, "足が横の線をはみ出す: x \(w.x)")
            #expect(w.z > B.backZ + B.line / 2 && w.z < B.frontZ - B.line / 2, "足が前後の線をはみ出す: z \(w.z)")
            #expect(w.z < 0, "足が本塁の前縁（z 0）より投手側に出る: z \(w.z)")
        }
    }

    // #1667 会長 QA（2026-10-01）: 骨（Foot・ToeBase）は線の内側でも、靴の皮は本塁側へ 0.1m ほど先に出ていて、
    // 構え・振りの間につま先が内側の線を越えていた。骨ではなく皮の頂点（スキニングを手で計算）で測る。
    @Test("構え（前・後ろのカメラのずらし込み）では、両足の靴の皮がバッターボックスの線の内側に収まる（#1667）")
    @MainActor
    func stanceShoesAreInsideTheBox() throws {
        typealias B = HomerunToonModel.BatterBox
        let now = Date()
        let shoes = try skinnedFootVertices(.stance, now: now)
        #expect(shoes.count > 500, "足元の頂点が \(shoes.count) 個しか取れない")
        for preset in L.CameraPreset.allCases {
            let offset = L.batterOffset(slide: try #require(L.batterSlideTarget(.stance, camera: preset.camera, now: now)))
            let w = shoes.map { L.batterWorld($0) + offset }
            let minX = w.map(\.x).min()!, maxX = w.map(\.x).max()!, minZ = w.map(\.z).min()!, maxZ = w.map(\.z).max()!
            #expect(minX > B.innerX + B.line / 2 && maxX < B.outerX - B.line / 2, "\(preset): 横の線をはみ出す x \(minX)〜\(maxX)")
            #expect(minZ > B.backZ + B.line / 2 && maxZ < B.frontZ - B.line / 2, "\(preset): 前後の線をはみ出す z \(minZ)〜\(maxZ)")
        }
    }

    // 振りは本来の位置でしか打点が合わない（バットの先端が外の列に 7cm しか余らない・`HomerunSwingContactTests`）ので打者は
    // 動かせない。内側の線を本塁の縁まで寄せ、つま先が本塁の縁を越えるのは振り抜きの一瞬（最大 6cm）に抑える。
    @Test("踏み込み〜振り終わり: つま先は内側の線の本塁側の縁（= 本塁の縁）を 7cm より先へ越えず、前後の線の内側にある（#1667）")
    @MainActor
    func swingShoesStayNearTheBox() throws {
        typealias B = HomerunToonModel.BatterBox
        #expect(abs((B.innerX - B.line / 2) - 0.216) < 0.001, "内側の線の本塁側の縁は本塁の縁")
        let now = Date()
        let back = L.CameraPreset.back.camera
        var motions: [HomerunBatterMotion] = (0...19).map { .load(start: now.addingTimeInterval(-Double($0) / 30)) }
        motions += (0...24).map { .swing(start: now.addingTimeInterval(-Double($0) / 30)) }
        for motion in motions {
            let offset = L.batterOffset(slide: L.batterSlideTarget(motion, camera: back, now: now) ?? 0)
            let w = try skinnedFootVertices(motion, now: now).map { L.batterWorld($0) + offset }
            let minX = w.map(\.x).min()!, minZ = w.map(\.z).min()!, maxZ = w.map(\.z).max()!
            #expect(minX > B.innerX - B.line / 2 - 0.07, "\(motion): つま先 x \(minX)")
            #expect(minZ > B.backZ + B.line / 2 && maxZ < B.frontZ - B.line / 2, "\(motion): 前後の線をはみ出す z \(minZ)〜\(maxZ)")
        }
    }

    /// 段階 `motion` を時刻 `now` に見せたときの、足元（高さ 0.15m 未満）の皮の頂点（打者の局所座標・スキニングを手で計算）。
    @MainActor
    private func skinnedFootVertices(_ motion: HomerunBatterMotion, now: Date) throws -> [SIMD3<Float>] {
        let rig = try #require(HomerunBatterRig())
        if #available(macOS 15.0, iOS 18.0, *) {
            let renderer = try RealityRenderer()
            renderer.entities.append(rig.entity)
            rig.show(motion, now: now)
            try renderer.update(0.001)
        }
        func models(_ e: Entity) -> [ModelEntity] {
            var r: [ModelEntity] = []
            if let m = e as? ModelEntity, !m.jointNames.isEmpty { r.append(m) }
            for c in e.children { r += models(c) }
            return r
        }
        var out: [SIMD3<Float>] = []
        for model in models(rig.entity) {
            let names = model.jointNames
            // 骨の打者の局所座標の行列（親をたどって掛ける）。
            let world: [String: simd_float4x4] = Dictionary(uniqueKeysWithValues: names.indices.map { index in
                var m = matrix_identity_float4x4
                var path = names[index]
                while true {
                    if let i = names.firstIndex(of: path) { m = model.jointTransforms[i].matrix * m }
                    guard let slash = path.lastIndex(of: "/") else { break }
                    path = String(path[..<slash])
                }
                return (names[index], m)
            })
            let entityToRig = model.transformMatrix(relativeTo: rig.entity)
            guard #available(macOS 15.0, iOS 18.0, *), let contents = model.model?.mesh.contents else { continue }
            for instance in contents.instances {
                guard let meshModel = contents.models[instance.model] else { continue }
                for part in meshModel.parts {
                    guard let skelID = part.skeletonID, let skeleton = contents.skeletons[skelID],
                          let influences = part.jointInfluences else { continue }
                    let infl = influences.influences.elements
                    let positions = part.positions.elements
                    let per = infl.count / max(positions.count, 1)
                    let jointMatrices: [simd_float4x4] = skeleton.joints.map { joint in
                        let leaf = joint.name.split(separator: "/").last.map(String.init) ?? joint.name
                        let m: simd_float4x4 = world[joint.name] ?? world.first { $0.key.split(separator: "/").last.map(String.init) == leaf }?.value ?? matrix_identity_float4x4
                        return m * joint.inverseBindPoseMatrix
                    }
                    for (vi, p) in positions.enumerated() {
                        let v = instance.transform * SIMD4<Float>(p.x, p.y, p.z, 1)
                        var acc = SIMD4<Float>(0, 0, 0, 0)
                        for k in 0..<per {
                            let inf = infl[vi * per + k]
                            if inf.weight > 0 { acc += inf.weight * (jointMatrices[inf.jointIndex] * v) }
                        }
                        let r: SIMD4<Float> = entityToRig * acc
                        if r.y < 0.15 { out.append(SIMD3<Float>(r.x, r.y, r.z)) }
                    }
                }
            }
        }
        return out
    }

    @Test("前のカメラの構えでは、両足がバッターボックスの前後の線の内側にある（本来の位置のまま・#1619）")
    @MainActor
    func frontStanceFeetAreInsideTheBoxLengthwise() throws {
        typealias B = HomerunToonModel.BatterBox
        #expect(L.batterSlideTarget(.stance, camera: L.CameraPreset.front.camera, now: t0) == L.backStanceSlide, "前のカメラも構えはずらす（#1667）")
        for local in try stanceFeet() {
            let w = L.batterWorld(local)
            #expect(w.z > B.backZ + B.line / 2 && w.z < B.frontZ - B.line / 2, "足が前後の線をはみ出す: z \(w.z)")
        }
    }
    #endif
}
