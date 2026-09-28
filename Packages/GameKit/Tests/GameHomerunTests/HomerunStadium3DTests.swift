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
        #expect(stadium.parts.count < 40, "実体が \(stadium.parts.count) 個ある（客席が色ごとにまとまっていない）")
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

    @Test("球場は地面（y ≒ 0）から客席の最上段までで、本塁の後ろにも客席がある")
    func stadiumExtent() {
        let ys = allPositions.map(\.y)
        #expect(ys.min()! >= -0.03)
        #expect(ys.max()! < 20)
        #expect(allPositions.contains { $0.z < -20 && $0.y > 5 }, "本塁の後ろのスタンドが無い")
        #expect(allPositions.contains { $0.z > 110 }, "外野スタンドが無い")
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

    @Test("打席シーンの置き方: 右打者は三塁側（センターカメラから見て右）で左肩を投手へ・捕手と審判は本塁の後ろの一塁側・投手はマウンドでカメラに背を向ける")
    func atBatLayout() {
        typealias L = HomerunAtBatLayout
        #expect(L.batter.position.x > 0.5, "右打者は三塁側（+x）の打席に立つ")
        // Meshy の打者は構えで左肩が +x。y 軸まわりに yaw 回すと +x は (cos, 0, -sin) へ向く → 投手（+z）を向くこと。
        let leftShoulder = SIMD3<Float>(cos(L.batter.yaw), 0, -sin(L.batter.yaw))
        #expect(simd_dot(leftShoulder, [0, 0, 1]) > 0.99, "左肩が投手を向いていない")
        let chest = SIMD3<Float>(sin(L.batter.yaw), 0, cos(L.batter.yaw))
        #expect(simd_dot(chest, [-1, 0, 0]) > 0.99, "胸が本塁（-x）を向いていない")
        #expect(L.catcher.position.z < 0 && L.umpire.position.z < L.catcher.position.z, "審判は捕手のさらに後ろ")
        #expect(L.catcher.position.x < 0 && L.umpire.position.x < 0, "捕手・審判は打者と反対の一塁側へ寄せる")
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
