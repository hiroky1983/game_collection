import Testing
import Foundation
import simd
@testable import GameHomerun

@Suite("柵越えおじさんのバッティングマシン（2 輪式・#1612）")
@MainActor
struct HomerunMachine3DTests {
    typealias M = HomerunMachineMotion
    static let now = Date(timeIntervalSinceReferenceDate: 1_000)

    /// 動かない部分 + 車輪 2 つ + レバー + 球 2 つ。
    static var parts: [HomerunToonModel] {
        [.machineBody(), .machineWheel(), .machineWheel(), .machineLever(), .machineBall(), .machineBall()]
    }

    @Test("部品が整っていて、三角形は輪郭線込みで 2 万枚以下（投手のおじさんより軽い）")
    func machineIsLight() {
        for m in Self.parts {
            for part in m.parts {
                for mesh in [part.mesh, part.outline].compactMap({ $0 }) {
                    #expect(mesh.positions.count == mesh.normals.count && mesh.positions.count == mesh.shade.count)
                    #expect(mesh.indices.count % 3 == 0 && mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
                }
            }
        }
        let total = Self.parts.reduce(0) { $0 + $1.triangleCount }
        let pitcher = HomerunToonModel.ojisan(.pitch, outfit: .pitcher).triangleCount
        print("machine triangles \(total) (parts \(Self.parts.reduce(0) { $0 + $1.parts.count })) / pitcher ojisan \(pitcher)")
        #expect(total <= 20_000, "\(total) 枚")
        #expect(total * 4 < pitcher, "投手のおじさん（\(pitcher) 枚）の 1/4 未満")
    }

    @Test("マシンは地面（y ≒ 0）に立ち、打ち出し口は車輪の間より本塁（-z）側")
    func machineFacesHome() {
        let ys = HomerunToonModel.machineBody().parts.flatMap { $0.mesh.positions.map(\.y) }
        #expect(ys.min()! >= -0.03 && ys.max()! < 2.0)
        #expect(M.mouth.z < M.wheelGap.z && M.wheelGap.z <= M.railEnd.z && M.railEnd.z < M.hopper.z)
        // 2 つの車輪の隙間は球の直径より狭い（車輪が球をはさんで打ち出す）。
        let gap = M.wheelCenters[1].x - M.wheelCenters[0].x - 2 * 0.24
        #expect(gap > 0 && gap < 2 * HomerunSwingContact.ballRadius)
    }

    @Test("打ち出す瞬間 = 的が出て輪が縮み始める時刻（elapsed 0）: 込めた球が打ち出し口に着き、そこから 3D の球が引き継ぐ")
    func launchMatchesRingStart() throws {
        // 込めた球は 0 の直前に打ち出し口へ着き、0 以降はマシンからは消える。
        let before = try #require(M.state(elapsed: -1e-6, now: Self.now).loadedBall)
        #expect(simd_distance(before, M.mouth) < 1e-3)
        #expect(M.state(elapsed: 0, now: Self.now).loadedBall == nil)
        // 3D の球は的が出る瞬間に、打ち出し口（世界座標）から出る。
        let t0 = Self.now
        let arrival = t0.addingTimeInterval(HomerunModel.travel)
        let launched = try #require(HomerunBallFlight.pitchPosition(at: t0, pitchStart: t0, arrival: arrival, column: 1))
        #expect(simd_distance(launched, HomerunAtBatLayout.machineWorld(M.mouth)) < 1e-4)
        #expect(HomerunBallFlight.pitchPosition(at: t0.addingTimeInterval(-0.01), pitchStart: t0, arrival: arrival, column: 1) == nil,
                "的が出る前は 3D の球は無い（マシンの中の球だけ）")
        // 輪が重なる時刻（判定の 0）に打点へ着くのは従来どおり（#1608）。
        let atArrival = try #require(HomerunBallFlight.pitchPosition(at: arrival, pitchStart: t0, arrival: arrival, column: 1))
        #expect(simd_distance(atArrival, HomerunSwingContact.approachTarget(column: 1)) < 1e-4)
    }

    @Test("込める間: 受け皿から転がり始め、だんだん本塁側・下へ進み、押し込みでレバーが前へ倒れる")
    func loadingMovesForward() throws {
        let start = try #require(M.state(elapsed: -M.loadDuration, now: Self.now).loadedBall)
        #expect(simd_distance(start, M.hopper) < 1e-4, "込め始めは受け皿の球の位置から（入れ替わりが見えない）")
        var last = start
        for e in stride(from: -M.loadDuration + 0.05, to: 0, by: 0.05) {
            let p = try #require(M.state(elapsed: e, now: Self.now).loadedBall)
            #expect(p.z <= last.z + 1e-5 && p.y <= last.y + 1e-5, "elapsed \(e) で戻った")
            last = p
        }
        #expect(M.state(elapsed: -M.pushDuration - 0.01, now: Self.now).leverAngle == M.leverRestAngle)
        #expect(abs(M.state(elapsed: -0.01, now: Self.now).leverAngle - M.leverPushedAngle) < 1e-4)
        #expect(M.state(elapsed: -0.5, now: Self.now).hopperBall == 0, "込めている間の受け皿は空")
    }

    @Test("打ち出した後: レバーが戻り、受け皿に次の球が出る。投球中でなければ待機（受け皿に球・レバーは戻った位置）")
    func afterLaunchAndIdle() {
        let after = M.state(elapsed: 1.0, now: Self.now)
        #expect(after.loadedBall == nil && after.hopperBall == 1 && abs(after.leverAngle - M.leverRestAngle) < 1e-5)
        #expect(M.state(elapsed: 0.1, now: Self.now).hopperBall == 0)
        let idle = M.state(elapsed: nil, now: Self.now)
        #expect(idle.loadedBall == nil && idle.hopperBall == 1 && idle.leverAngle == M.leverRestAngle)
    }

    @Test("車輪は時刻に比例して回り続ける")
    func wheelsSpin() {
        let a = M.state(elapsed: nil, now: Self.now).wheelAngle
        let b = M.state(elapsed: nil, now: Self.now.addingTimeInterval(0.1)).wheelAngle
        #expect(abs(b - a - Float(M.wheelSpeed * 0.1)) < 1e-3)
    }

    @Test("込める時間は的が出るまでの時間と同じ（投手の 0.8 秒から 1.2 秒へ延ばした・#1612）")
    func tempo() {
        #expect(M.loadDuration == HomerunModel.windup)
        #expect(HomerunModel.windup == 1.2)
    }
}
