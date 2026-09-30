import Testing
import Foundation
import simd
@testable import GameHomerun

@Suite("柵越えおじさんの 3D 部品（メッシュ・陰影・モデル）")
struct HomerunToonMeshTests {
    private let shapes: [(String, HomerunToonMesh)] = [
        ("球", .sphere(radius: 1)),
        ("カプセル", .capsule(radius: 0.5, length: 2)),
        ("箱", .box(width: 1, height: 2, depth: 3)),
        ("角丸の箱", .box(width: 1, height: 2, depth: 3, radius: 0.3)),
        ("円柱", .frustum(top: 1, bottom: 1, height: 2)),
        ("円錐台", .frustum(top: 0.17, bottom: 0.09, height: 3)),
    ]

    /// 三角形の表（反時計回り）が法線と同じ側を向く = 外向き。縮退した三角形（極の点）は面積 0 なので数えない。
    private func facesOutward(_ m: HomerunToonMesh) -> (outward: Int, inward: Int) {
        var outward = 0, inward = 0
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let a = Int(m.indices[t]), b = Int(m.indices[t + 1]), c = Int(m.indices[t + 2])
            let face = simd_cross(m.positions[b] - m.positions[a], m.positions[c] - m.positions[a])
            guard simd_length(face) > 1e-6 else { continue }
            let n = m.normals[a] + m.normals[b] + m.normals[c]
            if simd_dot(face, n) > 0 { outward += 1 } else { inward += 1 }
        }
        return (outward, inward)
    }

    @Test("どの図形も三角形の表が外を向き、法線は単位長で、配列の長さが揃っている")
    func shapesAreWellFormed() {
        for (name, m) in shapes {
            #expect(m.positions.count == m.normals.count, "\(name): 頂点と法線の数")
            #expect(m.positions.count == m.stripe.count, "\(name): 頂点と縞の数")
            #expect(m.indices.count % 3 == 0 && m.indices.allSatisfy { Int($0) < m.positions.count }, "\(name): 添字")
            #expect(m.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-4 }, "\(name): 法線が単位長")
            let f = facesOutward(m)
            #expect(f.outward > 0 && f.inward == 0, "\(name): 内向きの三角形が \(f.inward) 枚ある")
        }
    }

    @Test("反転ハル（輪郭線）は三角形の表が元の外向きの法線と逆（内）を向き、法線も反転している")
    func flippedHullFacesInward() {
        for (name, m) in shapes {
            let hull = m.flipped()
            // 法線は反転済みなので、元の法線（= 外向き）に直して面の向きを見る。
            var restored = hull
            restored.normals = hull.normals.map { -$0 }
            let f = facesOutward(restored)
            #expect(f.inward > 0 && f.outward == 0, "\(name): 反転後に外向きが \(f.outward) 枚残っている")
            #expect(hull.normals == m.normals.map { -$0 }, "\(name): 法線の反転")
            #expect(hull.indices.count == m.indices.count && hull.positions == m.positions, "\(name): 頂点は変えない")
        }
    }

    @Test("陰影の u は 0 以上 1 以下で、光の当たる側ほど大きい")
    func shadeFollowsLight() {
        let m = HomerunToonMesh.sphere(radius: 1).placed(matrix_identity_float4x4)
        #expect(m.shade.allSatisfy { (0...1).contains($0) })
        let lit = zip(m.normals, m.shade).max { $0.1 < $1.1 }!
        let dark = zip(m.normals, m.shade).min { $0.1 < $1.1 }!
        #expect(simd_dot(lit.0, HomerunToonMesh.lightDirection) > 0.99)
        #expect(dark.1 == 0)
        // 3 段の明るさが実際に引ける（明・中・暗のすべてが球に現れる）。
        #expect(Set(m.shade.map(HomerunToonMesh.brightness(forShade:))) == Set(HomerunToonMesh.bandBrightness))
    }

    @Test("つぶした球でも法線は逆転置行列で変換され、向きが崩れない")
    func nonUniformScaleKeepsNormalsOutward() {
        let squashed = HomerunToonMesh.sphere(radius: 1).placed(HomerunToonModel.scaling([1, 0.2, 1]))
        #expect(squashed.normals.allSatisfy { abs(simd_length($0) - 1) < 1e-4 })
        let f = facesOutward(squashed)
        #expect(f.inward == 0)
        // 上端の法線はほぼ真上のまま（つぶしても横へ倒れない）。
        let top = zip(squashed.positions, squashed.normals).max { $0.0.y < $1.0.y }!
        #expect(top.1.y > 0.99)
    }

    @Test("ランプ画像の段は境目 0.18・0.5 で 0.6 / 0.78 / 1.0")
    func bandBrightnessMatchesMock() {
        #expect(HomerunToonMesh.brightness(forShade: 0) == 0.6)
        #expect(HomerunToonMesh.brightness(forShade: 0.18) == 0.6)
        #expect(HomerunToonMesh.brightness(forShade: 0.19) == 0.78)
        #expect(HomerunToonMesh.brightness(forShade: 0.5) == 0.78)
        #expect(HomerunToonMesh.brightness(forShade: 0.51) == 1.0)
        #expect(HomerunToonMesh.brightness(forShade: 1) == 1.0)
    }

    @Test("おじさんは 4 ポーズとも部品ができ、輪郭線つきの部品が大半で、同じ入力は同じ結果")
    func ojisanPosesBuild() {
        let poses: [HomerunOjisanPose3] = [.stance, .swing, .cheer, .whiff]
        for pose in poses {
            let m = HomerunToonModel.ojisan(pose)
            #expect(m.parts.count > 60, "頭の半径 1 の単位で約 60 個以上の部品（README §4.4）")
            #expect(m.parts.filter { $0.outline != nil }.count > m.parts.count / 2)
            #expect(m == HomerunToonModel.ojisan(pose), "乱数なし")
            #expect(m.parts.contains { $0.striped }, "打者の胴にはピンストライプ")
        }
        #expect(!HomerunToonModel.ojisan(.pitch, outfit: .pitcher).parts.contains { $0.striped })
        // ポーズが違えば形が違う（バットの位置）。
        #expect(HomerunToonModel.ojisan(.stance) != HomerunToonModel.ojisan(.swing))
        // 空振り以外は目が開き、空振りは「＞＜」の線なので部品の数が違う。
        #expect(HomerunToonModel.ojisan(.stance).parts.count != HomerunToonModel.ojisan(.whiff).parts.count)
    }

    @Test("モデルの座標は人の背丈（頭の半径 1 で約 5）に収まる")
    func ojisanFitsInFigureBox() {
        let m = HomerunToonModel.ojisan(.stance)
        let ys = m.parts.flatMap { $0.mesh.positions.map(\.y) }
        #expect(ys.min()! > -0.1 && ys.max()! < 6)
        #expect(m.parts.allSatisfy { $0.mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite } })
    }

    @Test("捕手は +z（投手）向きで、しゃがみの背丈に収まり、茶のミットがある")
    func catcherBuild() {
        let catcher = HomerunToonModel.catcher()
        let pos = catcher.parts.flatMap { $0.mesh.positions }
        #expect(pos.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        #expect(pos.map(\.y).min()! > -0.1 && pos.map(\.y).max()! < 5.5, "しゃがみは立ちより低い")
        #expect(catcher.parts.count > 15 && catcher.parts.filter { $0.outline != nil }.count > catcher.parts.count / 2)
        #expect(catcher.parts.allSatisfy { !$0.striped }, "ピンストライプは打者だけ")
        #expect(catcher.parts.contains { $0.color == HomerunToonPalette.glove }, "ミットは茶")
        let front = catcher.parts.flatMap { $0.mesh.positions }.map(\.z).max()!
        #expect(front > 1.8 && front < 2.6, "ミットとケージは投手側（+z）に出る")
        #expect(catcher == HomerunToonModel.catcher(), "乱数なし")
    }

    #if canImport(RealityKit)
    @Test("階段状ランプ画像: ふつうは 1 行・縞つきは 9 本ぶんの高さ")
    func rampImages() {
        let plain = HomerunToonRamp.image(stripes: 0)
        #expect(plain?.width == HomerunToonRamp.width && plain?.height == 1)
        let striped = HomerunToonRamp.image(stripes: HomerunToonRamp.jerseyStripes)
        #expect(striped?.width == HomerunToonRamp.width && striped?.height == HomerunToonRamp.jerseyStripes * 32)
    }
    #endif
}
