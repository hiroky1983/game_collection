#if canImport(RealityKit)
import Foundation
import RealityKit

/// 打席の 3D の部品（球場・捕手・マシンの部品・影と球のメッシュ）の原本（#1695）。プロセスの間だけ持ち、打席を作るたびに
/// 複製（`clone(recursive:)`・メッシュとマテリアルは原本と共有）を渡す。
///
/// 以前は打席の `ARView` を作るたびに、数千個の箱を並べる球場の頂点計算から主スレッドでやり直していた（タップから描き始めまで
/// 約 0.2 秒）。頂点の計算（RealityKit に依らない `HomerunToonModel`）は `preload()` でバックグラウンドで先に済ませ、
/// 主スレッドでは RealityKit の実体にするだけにする。`preload()` を通らずに要ったとき（先読みより先に打席に入ったとき）は、
/// その場で主スレッドで作って原本にする（結果は同じ）。
@MainActor
enum HomerunAtBatAssets {
    /// 頂点データ（バックグラウンドで作る）。
    struct Models: Sendable {
        var stadium: HomerunToonModel
        var catcher: HomerunToonModel
        var machineBody: HomerunToonModel
        var machineWheel: HomerunToonModel
        var machineLever: HomerunToonModel
        var machineBall: HomerunToonModel

        nonisolated static func make() -> Models {
            Models(stadium: .stadium(), catcher: .catcher(), machineBody: .machineBody(), machineWheel: .machineWheel(),
                   machineLever: .machineLever(), machineBall: .machineBall())
        }
    }

    private static var models: Models?
    private static var stadiumTemplate: Entity?
    private static var catcherTemplate: Entity?
    private static var machineBodyTemplate: Entity?
    private static var machineWheelTemplate: Entity?
    private static var machineLeverTemplate: Entity?
    private static var machineBallTemplate: Entity?
    private static var discMesh: MeshResource?
    private static var ballMesh: MeshResource?

    /// 原本がすべてそろっているか。
    static var isLoaded: Bool { stadiumTemplate != nil && catcherTemplate != nil && machineBallTemplate != nil }

    /// 頂点の計算をバックグラウンドで済ませ、主スレッドでは部品ごとに 1 コマ空けながら実体の原本を作る
    /// （一度に作ると打席前の画面が 0.3 秒ほど止まる）。何度呼んでもよい（そろっていれば何もしない）。
    static func preload() async {
        if models == nil, !isLoaded {
            let made = await Task.detached(priority: .userInitiated) { Models.make() }.value
            if models == nil { models = made }
        }
        let steps: [@MainActor () -> Void] = [
            { _ = template(\.stadium, &stadiumTemplate) },
            { _ = template(\.catcher, &catcherTemplate) },
            { _ = template(\.machineBody, &machineBodyTemplate); _ = template(\.machineWheel, &machineWheelTemplate) },
            { _ = template(\.machineLever, &machineLeverTemplate); _ = template(\.machineBall, &machineBallTemplate) },
            { _ = disc(); _ = ball() },
        ]
        for step in steps {
            if Task.isCancelled { return }
            step()
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private static func template(_ key: KeyPath<Models, HomerunToonModel>, _ slot: inout Entity?) -> Entity {
        if let slot { return slot }
        let model = models?[keyPath: key] ?? fresh(key)
        let e = HomerunToonScene.entity(for: model)
        slot = e
        return e
    }

    /// 先読みの前に要ったとき、その部品の頂点だけを主スレッドで作る。
    private static func fresh(_ key: KeyPath<Models, HomerunToonModel>) -> HomerunToonModel {
        switch key {
        case \Models.stadium: .stadium()
        case \Models.catcher: .catcher()
        case \Models.machineBody: .machineBody()
        case \Models.machineWheel: .machineWheel()
        case \Models.machineLever: .machineLever()
        default: .machineBall()
        }
    }

    static func stadium() -> Entity { template(\.stadium, &stadiumTemplate).clone(recursive: true) }
    static func catcher() -> Entity { template(\.catcher, &catcherTemplate).clone(recursive: true) }
    static func machineBody() -> Entity { template(\.machineBody, &machineBodyTemplate).clone(recursive: true) }
    static func machineWheel() -> Entity { template(\.machineWheel, &machineWheelTemplate).clone(recursive: true) }
    static func machineLever() -> Entity { template(\.machineLever, &machineLeverTemplate).clone(recursive: true) }
    static func machineBall() -> Entity { template(\.machineBall, &machineBallTemplate).clone(recursive: true) }

    /// 影の円板（半径 0.5・xz 面）のメッシュ。球・打者・マシン・バットの影で共有する。
    static func disc() -> MeshResource {
        if let discMesh { return discMesh }
        let m = MeshResource.generatePlane(width: 1, depth: 1, cornerRadius: 0.5)
        discMesh = m
        return m
    }

    /// 3D の球のメッシュ。
    static func ball() -> MeshResource {
        if let ballMesh { return ballMesh }
        let m = MeshResource.generateSphere(radius: HomerunSwingContact.ballRadius)
        ballMesh = m
        return m
    }
}
#endif
