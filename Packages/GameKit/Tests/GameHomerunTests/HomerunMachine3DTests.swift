import Testing
import Foundation
import simd
@testable import GameHomerun

@Suite("柵越えおじさんのバッティングマシン（#1612 モック）")
struct HomerunMachine3DTests {
    @Test("どの型・どのコマも部品が整っていて、三角形は輪郭線込みで 2 万枚以下（投手のおじさんより軽い）", arguments: HomerunMachineKind.allCases)
    func machineIsLight(kind: HomerunMachineKind) {
        for pose in HomerunMachinePose.allCases {
            let m = HomerunToonModel.machine(kind, pose: pose)
            for part in m.parts {
                for mesh in [part.mesh, part.outline].compactMap({ $0 }) {
                    #expect(mesh.positions.count == mesh.normals.count && mesh.positions.count == mesh.shade.count)
                    #expect(mesh.indices.count % 3 == 0 && mesh.indices.allSatisfy { Int($0) < mesh.positions.count })
                }
            }
            print("machine \(kind) \(pose): parts \(m.parts.count) triangles \(m.triangleCount)")
            #expect(m.triangleCount <= 20_000, "\(kind) \(pose) が \(m.triangleCount) 枚")
        }
        let pitcher = HomerunToonModel.ojisan(.pitch, outfit: .pitcher)
        print("pitcher ojisan: parts \(pitcher.parts.count) triangles \(pitcher.triangleCount)")
    }

    @Test("マシンは地面（y ≒ 0）に立ち、球は -z（本塁）側へ出る。打ち出す瞬間の球は待機の球より本塁側にある")
    func machineFacesHome() {
        for kind in HomerunMachineKind.allCases {
            let idle = HomerunToonModel.machine(kind, pose: .idle)
            let ys = idle.parts.flatMap { $0.mesh.positions.map(\.y) }
            #expect(ys.min()! >= -0.03 && ys.max()! < 2.0)
            func ballZ(_ pose: HomerunMachinePose) -> Float {
                HomerunToonModel.machine(kind, pose: pose).parts
                    .filter { $0.color == HomerunToonModel.MachineColor.ball }
                    .map { $0.mesh.positions.map(\.z).reduce(0, +) / Float($0.mesh.positions.count) }.min()!
            }
            #expect(ballZ(.launch) < ballZ(.idle), "\(kind): 打ち出す球が本塁側に出ていない")
        }
    }

    @Test("コマは投球の時刻から決まる: 的が出る前は込める、出た直後は打ち出す、その後は待機")
    func poseFollowsPitchClock() {
        #expect(HomerunAtBatLayout.machinePose(phase: .pitching, elapsed: -0.8) == .load)
        #expect(HomerunAtBatLayout.machinePose(phase: .pitching, elapsed: -0.1) == .launch)
        #expect(HomerunAtBatLayout.machinePose(phase: .pitching, elapsed: 0.2) == .launch)
        #expect(HomerunAtBatLayout.machinePose(phase: .pitching, elapsed: 0.5) == .idle)
        #expect(HomerunAtBatLayout.machinePose(phase: .ballResult, elapsed: nil) == .idle)
    }

    @Test("起動引数で型・置き場所・コマを選べる（無ければマシン無し・マウンド・時刻どおり）")
    func launchArguments() {
        #expect(HomerunMachineMock.kind(arguments: ["-homerunMachine", "arm"]) == .arm)
        #expect(HomerunMachineMock.kind(arguments: ["-homerunMachine"]) == nil)
        #expect(HomerunMachineMock.kind(arguments: []) == nil)
        #expect(HomerunMachineMock.place(arguments: ["-homerunMachinePlace", "near"]) == .near)
        #expect(HomerunMachineMock.place(arguments: []) == .mound)
        #expect(HomerunMachineMock.forcedPose(arguments: ["-homerunMachinePose", "launch"]) == .launch)
        #expect(HomerunMachineMock.forcedPose(arguments: []) == nil)
        #expect(HomerunAtBatLayout.MachinePlace.near.placement.position.z < HomerunAtBatLayout.MachinePlace.mound.placement.position.z)
    }
}
