import Testing
import Foundation
import simd
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
        #expect(abs(rig.fullDuration - 43.0 / 30) < 0.02, "スイングの長さ \(rig.fullDuration) 秒")
        let joints = allJointNames(rig.entity)
        #expect(joints.contains { $0.hasSuffix("RightHand/Bat") }, "バットの骨が右手の子になっていない")
        let bounds = rig.entity.visualBounds(relativeTo: nil)
        #expect(abs(bounds.min.y) < 0.05 && abs(bounds.max.y - 1.72) < 0.1, "足元が y = 0・身長 1.72m になっていない（\(bounds.min.y)〜\(bounds.max.y)）")
    }

    @Test("踏み込みの長さは 19/30 秒（20 コマ目まで）。投球中の段階の切り替えは HomerunSwingPlan が逆算した振り始めから決める")
    func loadDuration() {
        #expect(abs(HomerunBatterMotion.loadDuration - 19.0 / 30) < 1e-9)
        #expect(HomerunSwingContact.swingClipStart == HomerunBatterMotion.loadDuration)
    }

    // 離した瞬間に頭から流すと最初の 0.63 秒は踏み込みでバットがほぼ動かず、先に外野カメラへ切り替わって
    // 「振らない」ように見えた（会長 QA 2026-09-28）。振り抜きの段は流し始めてすぐバットが大きく動くこと。
    @Test("振り抜きの段は流し始めて 0.2 秒でバットの骨が大きく回る（踏み込みの段はほとんど回らない）")
    @MainActor
    func swingSegmentMovesTheBatImmediately() async throws {
        guard #available(macOS 15.0, iOS 18.0, *) else { return }
        let rig = try #require(HomerunBatterRig())
        let renderer = try RealityRenderer()
        renderer.entities.append(rig.entity)
        let now = Date()
        func batAngle(after motion: HomerunBatterMotion, seconds: Double) throws -> Float {
            rig.show(.stance, now: now)
            try renderer.update(0.05)
            let start = try batRotation(rig)
            rig.show(motion, now: now)
            for _ in 0..<Int(seconds / 0.05) { try renderer.update(0.05) }
            let end = try batRotation(rig)
            return 2 * acos(min(1, abs(simd_dot(start.vector, end.vector))))
        }
        let swing = try batAngle(after: .swing(start: now), seconds: 0.2)
        let load = try batAngle(after: .load, seconds: 0.2)
        #expect(swing > 0.5, "振り抜きの 0.2 秒でバットが \(swing) rad しか回らない")
        #expect(load < swing / 2, "踏み込み \(load) rad・振り抜き \(swing) rad")
    }

    @Test("振り抜きは start が過去ならその分だけ進めた所から流す（離した瞬間に打点のコマへ合わせ直す）")
    @MainActor
    func swingSeeksWhenStartIsInThePast() throws {
        let rig = try #require(HomerunBatterRig())
        let now = Date()
        rig.show(.swing(start: now), now: now)
        #expect(abs((rig.swingClipTime ?? -1) - HomerunBatterMotion.loadDuration) < 0.01)
        rig.show(.swing(start: now.addingTimeInterval(-0.2)), now: now)
        #expect(abs((rig.swingClipTime ?? -1) - (HomerunBatterMotion.loadDuration + 0.2)) < 0.01)
        rig.show(.swing(start: now.addingTimeInterval(0.5)), now: now)
        #expect(abs((rig.swingClipTime ?? -1) - HomerunBatterMotion.loadDuration) < 0.01, "未来の start は頭から")
    }

    @MainActor
    private func batRotation(_ rig: HomerunBatterRig) throws -> simd_quatf {
        let model = try #require(findSkinned(rig.entity))
        let index = try #require(model.jointNames.firstIndex { $0.hasSuffix("RightHand/Bat") })
        // 親（右手）ごと回るので、根からの向きを合成して比べる。
        var q = simd_quatf(angle: 0, axis: [0, 1, 0])
        let names = model.jointNames
        var path = names[index]
        while true {
            if let i = names.firstIndex(of: path) { q = model.jointTransforms[i].rotation * q }
            guard let slash = path.lastIndex(of: "/") else { break }
            path = String(path[..<slash])
        }
        return q
    }

    @MainActor
    private func findSkinned(_ e: Entity) -> ModelEntity? {
        if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
        for c in e.children { if let m = findSkinned(c) { return m } }
        return nil
    }

    @MainActor
    private func allJointNames(_ e: Entity) -> [String] {
        let own = e.components[ModelComponent.self] != nil ? ((e as? ModelEntity)?.jointNames ?? []) : []
        return own + e.children.flatMap { allJointNames($0) }
    }
    #endif
}
