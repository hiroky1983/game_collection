#if canImport(RealityKit)
import Testing
import RealityKit
@testable import GameHomerun

/// 打席の 3D の部品の原本（#1695・`HomerunAtBatAssets`）。複製が作り直したものと同じ形で、メッシュを作り直さず共有すること。
@Suite("柵越えおじさんの打席の部品の原本（#1695）")
@MainActor
struct HomerunAtBatAssetsTests {
    /// 実体の木の、メッシュを持つ実体の数と頂点の数。
    private func shape(_ e: Entity) -> (models: Int, vertices: Int) {
        var models = 0, vertices = 0
        func walk(_ e: Entity) {
            if let m = e.components[ModelComponent.self] {
                models += 1
                vertices += m.mesh.contents.models.reduce(0) { $0 + $1.parts.reduce(0) { $0 + $1.positions.count } }
            }
            e.children.forEach(walk)
        }
        walk(e)
        return (models, vertices)
    }

    private func meshes(_ e: Entity) -> [MeshResource] {
        var out: [MeshResource] = []
        func walk(_ e: Entity) {
            if let m = e.components[ModelComponent.self] { out.append(m.mesh) }
            e.children.forEach(walk)
        }
        walk(e)
        return out
    }

    @Test("先読みした球場・捕手・マシンの複製は、その場で組み立てたものと同じ形")
    func clonesMatchFreshBuild() async {
        await HomerunAtBatAssets.preload()
        #expect(HomerunAtBatAssets.isLoaded)
        let pairs: [(Entity, HomerunToonModel)] = [
            (HomerunAtBatAssets.stadium(), .stadium()), (HomerunAtBatAssets.catcher(), .catcher()),
            (HomerunAtBatAssets.machineBody(), .machineBody()), (HomerunAtBatAssets.machineWheel(), .machineWheel()),
            (HomerunAtBatAssets.machineLever(), .machineLever()), (HomerunAtBatAssets.machineBall(), .machineBall()),
        ]
        for (cached, model) in pairs {
            let fresh = shape(HomerunToonScene.entity(for: model))
            let got = shape(cached)
            #expect(got.models == fresh.models && got.vertices == fresh.vertices && got.models > 0)
        }
    }

    @Test("複製は別の実体で、メッシュは原本と共有する（打席を作るたびに頂点を作り直さない）")
    func clonesShareMeshes() {
        let a = HomerunAtBatAssets.stadium(), b = HomerunAtBatAssets.stadium()
        #expect(a !== b)
        let ma = meshes(a), mb = meshes(b)
        #expect(ma.count == mb.count && !ma.isEmpty)
        #expect(zip(ma, mb).allSatisfy { $0 === $1 })
        #expect(HomerunAtBatAssets.disc() === HomerunAtBatAssets.disc())
        #expect(HomerunAtBatAssets.ball() === HomerunAtBatAssets.ball())
    }
}
#endif
