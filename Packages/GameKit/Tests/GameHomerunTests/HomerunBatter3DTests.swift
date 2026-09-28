import Testing
import Foundation
import GameKitTestSupport
@testable import GameHomerun
#if canImport(RealityKit)
import RealityKit
#endif

/// 3D（RealityKit の `ARView`）の当たり判定と、Meshy の打者おじさん（試作）の素材。
@Suite("柵越えおじさんの 3D の当たり判定と打者の素材")
struct HomerunBatter3DTests {
    /// `Sources/GameHomerun/Toon3D/` の Swift ソース一式（行コメントを落とす）。
    private func toon3DSources() throws -> String {
        let dir = SourceScan.packageRoot.appendingPathComponent("Sources/GameHomerun/Toon3D")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty)
        return SourceScan.strippingComments(try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n"))
    }

    // 打席の押せる帯（下 1/3）は 3D の背景の手前に重ねた透明の層。3D は UIKit の `ARView` なので、当たり判定を
    // 残すとドラッグを `ARView` が吸い、カーソルが動かずスイングもできなくなった（会長 QA 2026-09-28）。
    @Test("ARView はすべて触りを受けない（isUserInteractionEnabled = false）")
    func arViewsIgnoreTouches() throws {
        let source = try toon3DSources()
        let made = SourceScan.matchCount(of: #"ARView\(frame:"#, in: source)
        let disabled = SourceScan.matchCount(of: #"isUserInteractionEnabled = false"#, in: source)
        #expect(made >= 3, "ARView の生成が見つからない（\(made) 件）")
        #expect(disabled == made, "ARView \(made) 個のうち触りを止めているのは \(disabled) 個")
    }

    @Test("3D を置く SwiftUI の View は当たり判定を持たない（allowsHitTesting(false)）")
    func sceneViewsDoNotHitTest() throws {
        let source = try toon3DSources()
        for header in ["struct HomerunAtBatScene3DView", "struct HomerunOutfieldScene3DView", "struct HomerunOjisan3DView"] {
            let body = try #require(SourceScan.declaration(of: header, in: source), "\(header) が無い")
            #expect(body.contains(".allowsHitTesting(false)"), "\(header) に当たり判定が残っている")
        }
    }

    @Test("打者の USDZ はパッケージの素材に入っている")
    func assetIsBundled() throws {
        let url = try #require(HomerunBatterAsset.url)
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(size > 1_000_000 && size < 6_000_000, "USDZ の大きさが想定外（\(size) バイト）")
    }

    #if canImport(RealityKit)
    @Test("打者を読むと 44 コマ（30fps で約 1.43 秒）のスイングが 1 本あり、バットは右手の骨の子")
    @MainActor
    func rigLoads() throws {
        let rig = try #require(HomerunBatterRig(), "USDZ が読めない")
        #expect(abs(rig.swingDuration - 43.0 / 30) < 0.02, "スイングの長さ \(rig.swingDuration) 秒")
        let joints = allJointNames(rig.entity)
        #expect(joints.contains { $0.hasSuffix("RightHand/Bat") }, "バットの骨が右手の子になっていない")
        let bounds = rig.entity.visualBounds(relativeTo: nil)
        #expect(abs(bounds.min.y) < 0.05 && abs(bounds.max.y - 1.72) < 0.1, "足元が y = 0・身長 1.72m になっていない（\(bounds.min.y)〜\(bounds.max.y)）")
    }

    @MainActor
    private func allJointNames(_ e: Entity) -> [String] {
        let own = e.components[ModelComponent.self] != nil ? ((e as? ModelEntity)?.jointNames ?? []) : []
        return own + e.children.flatMap { allJointNames($0) }
    }
    #endif
}
