import Testing
import Foundation
import simd
import HomerunCore
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
        let seam = lower.filter { abs($0.x) < 3 && $0.z < -17 && $0.z > -19 && abs($0.y - 0.45) < 0.01 }.map(\.x).sorted()
        #expect(seam.count >= 8, "継ぎ目の座席が見つからない")
        // 隣り合う箱の縁（頂点が 0.1m 未満に固まる）を数え、縁と縁の間隔は座席の幅 1.5m を超えない。
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
        #expect(positions(of: S.screen).contains { abs(abs($0.x) - 12) < 0.01 && $0.z > 145 && $0.y > 16 }, "スコアボードが無い")
        // 灯体（幅 10m の箱）は幅の向きが円の接線 = 面がホームを向く: 外野右の塔（36°）の角は接線 (cos36°, -sin36°) 方向に ±5m。
        let lamp36 = lamps.filter { $0.x > 20 && $0.z > 5 && $0.y > 40 }
        let r36 = HomerunJudge.fence(atDirection: 36) + 30, a36 = 36.0 * .pi / 180
        let center36 = SIMD2(Float(r36 * sin(a36)), Float(r36 * cos(a36)))
        let tangent = SIMD2(Float(cos(a36)), Float(-sin(a36)))
        #expect(lamp36.contains { simd_length(SIMD2($0.x, $0.z) - (center36 + tangent * 5)) < 1.0 }, "灯体の面がホームを向いていない（yaw の符号）")
        // バックネット裏の壁も接線向き（180° の板の幅は x 方向）。
        let wall = positions(of: HomerunToonModel.StadiumColor.backWall)
        #expect(wall.contains { abs($0.x - 0.5) < 0.01 && abs($0.z + 14.5) < 0.25 }, "バックネット裏の壁が接線を向いていない")
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

    @Test("打席シーンの置き方: 打者は本塁の一塁側・捕手と審判は本塁の後ろ・投手はマウンドでカメラに背を向け、カメラは打者を正面から見る")
    func atBatLayout() {
        typealias L = HomerunAtBatLayout
        #expect(L.batter.position.z == 0.15 && L.batter.position.x < 0)
        #expect(L.catcher.position.z < 0 && L.umpire.position.z < L.catcher.position.z, "審判は捕手のさらに後ろ")
        #expect(abs(L.pitcher.position.z - 17.4) < 1e-4 && abs(L.pitcher.position.y - 0.3) < 1e-4, "マウンドの上（高さ 0.3m）")
        #expect(abs(L.pitcher.yaw - .pi) < 1e-6)
        #expect(L.cameraPosition.z > 30 && L.cameraTarget.z < 1, "センターの遠くから本塁を見る")
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

    @Test("カメラ（前・後ろ）はどちらもストライクゾーンの中心を画面の横の中央・高さ 45% に映し、打者の頭と足元が画面に収まる",
          arguments: HomerunAtBatLayout.CameraPreset.allCases)
    func presetsKeepZoneWhereTheHUDIs(preset: HomerunAtBatLayout.CameraPreset) {
        typealias L = HomerunAtBatLayout
        let cam = preset.camera
        for aspect in [9.0 / 19.5, 9.0 / 16.0] {
            let zone = cam.screenPoint(of: L.zoneWorldCenter, aspect: aspect)
            #expect(abs(zone.x - 0.5) < 0.005 && abs(zone.y - L.zoneScreenFraction) < 0.005, "\(preset): ゾーンが (\(zone.x), \(zone.y))")
            let head = cam.screenPoint(of: [L.batter.position.x, 1.75, L.batter.position.z], aspect: aspect)
            let feet = cam.screenPoint(of: [L.batter.position.x, 0, L.batter.position.z], aspect: aspect)
            #expect(head.y > 0.05 && feet.y < 0.95 && head.x > 0.05 && head.x < 0.95, "\(preset): 打者が画面の外（頭 \(head)・足元 \(feet)）")
            // 投手（マウンドの上・頭）も画面の中。
            let pitcher = cam.screenPoint(of: [L.pitcher.position.x, 2.1, L.pitcher.position.z], aspect: aspect)
            #expect(pitcher.x > 0 && pitcher.x < 1 && pitcher.y > 0 && pitcher.y < 1, "\(preset): 投手が画面の外 \(pitcher)")
        }
        #expect(simd_length(cam.target - cam.position) > 5)
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
                cam.screenPoint(of: [L.batter.position.x, 0, L.batter.position.z], aspect: aspect).y
                    - cam.screenPoint(of: [L.batter.position.x, 1.75, L.batter.position.z], aspect: aspect).y
            }
            #expect(height(back) > 2 * height(caseB), "打者の背丈 \(height(back)) / 案 B \(height(caseB))")
            #expect(back.screenPoint(of: [0, 0, 0], aspect: aspect).y > caseB.screenPoint(of: [0, 0, 0], aspect: aspect).y + 0.05)
            // 手前の審判・捕手の頭はゾーン（2D・SE の幅 375pt で測る）の右の外に逃がし、ゾーンと本塁を塞がない。
            let zoneRight = 0.5 + Double(HomerunZoneGeometry.zoneSize) / 2 / 375
            for head: SIMD3<Float> in [[L.umpire.position.x, 1.77, L.umpire.position.z + 0.2], [L.catcher.position.x, 1.53, L.catcher.position.z]] {
                #expect(back.screenPoint(of: head, aspect: aspect).x > zoneRight, "審判・捕手の頭がゾーンに重なる \(back.screenPoint(of: head, aspect: aspect))")
            }
        }
    }

    @Test("後ろのカメラだけ左右反転し、反転しても打者（x < 0）は画面の左半分に映る（HUD の右 = 一塁側に合う）")
    func rearPresetsAreMirrored() {
        typealias L = HomerunAtBatLayout
        #expect(!L.CameraPreset.front.camera.mirrored && L.CameraPreset.back.camera.mirrored)
        for preset in L.CameraPreset.allCases {
            let cam = preset.camera
            let batter = cam.screenPoint(of: [L.batter.position.x, 1, L.batter.position.z], aspect: 0.5)
            let firstBase = cam.screenPoint(of: [19.4, 0, 19.4], aspect: 0.5)
            #expect(batter.x < 0.5, "\(preset): 打者が画面の右半分に映る")
            #expect(firstBase.x > 0.5, "\(preset): 一塁側（+x）が画面の左に映り、方向メーターの右と食い違う")
        }
        // 反転は x だけ（y はそのまま）。
        var cam = L.CameraPreset.front.camera
        let before = cam.screenPoint(of: [3, 1, 0], aspect: 0.5)
        cam.mirrored = true
        let after = cam.screenPoint(of: [3, 1, 0], aspect: 0.5)
        #expect(abs(before.x + after.x - 1) < 1e-9 && before.y == after.y)
    }

    @Test("前のカメラは以前のセンターカメラと同じ位置・注視点・画角のまま（既定の見た目を変えない）")
    func centerPresetUnchanged() {
        #expect(HomerunAtBatLayout.CameraPreset.allCases == [.front, .back], "選べるのは前・後ろの 2 つだけ")
        let cam = HomerunAtBatLayout.CameraPreset.front.camera
        #expect(cam.position == [0, 6, 43] && cam.target == [0, 0.57, 0.3] && cam.verticalFieldOfView == 9.6)
        #expect(HomerunAtBatLayout.cameraPosition == cam.position && HomerunAtBatLayout.verticalFieldOfView == 9.6)
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

@Suite("柵越えおじさんの投手のポーズ")
struct HomerunPitcherPoseTests {
    @Test("投手のモーション中（的が出る前・elapsed が負）は振りかぶり")
    func windupBeforeBallAppears() {
        #expect(HomerunAtBatLayout.pitcherPose(phase: .pitching, elapsed: -0.8) == .windup)
        #expect(HomerunAtBatLayout.pitcherPose(phase: .pitching, elapsed: -0.001) == .windup)
    }

    @Test("的が出た後（elapsed が 0 以上）・投球中でない・elapsed が無いときはリリースのまま")
    func pitchOtherwise() {
        #expect(HomerunAtBatLayout.pitcherPose(phase: .pitching, elapsed: 0) == .pitch)
        #expect(HomerunAtBatLayout.pitcherPose(phase: .pitching, elapsed: 0.5) == .pitch)
        #expect(HomerunAtBatLayout.pitcherPose(phase: .pitching, elapsed: nil) == .pitch)
        for phase in [HomerunModel.Phase.idle, .ballResult, .finished] {
            #expect(HomerunAtBatLayout.pitcherPose(phase: phase, elapsed: -0.5) == .pitch)
        }
    }
}
