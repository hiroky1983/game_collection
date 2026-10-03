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
        ("五角形の柱", .prism(HomerunToonModel.HomePlate.polygon, height: 0.02)),
        ("縁を落とした五角形の柱", .prism(HomerunToonModel.HomePlate.polygon, height: 0.016, bevel: 0.012)),
        ("楕円の柱", .prism(HomerunToonMesh.ellipse(center: [1, -2], rx: 0.5, rz: 0.3), height: 0.006)),
        ("閉じた帯", .ribbon([[0, 0], [1, 0], [1, 2], [0, 2]], width: 0.05, height: 0.01, closed: true)),
        ("開いた帯", .ribbon([[-0.5, 0], [-0.5, -2], [0.5, -2], [0.5, 0]], width: 0.05, height: 0.01, closed: false)),
    ]

    // #1677: 本塁・白線は平らな図形（柱・帯）で作る。
    @Test("多角形の柱: 上面は多角形そのまま（縁を落とすと内へ寄る）・底の外周は元の頂点で、高さは ±h/2")
    func prismShape() {
        let square: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
        let plain = HomerunToonMesh.prism(square, height: 0.2)
        #expect(plain.positions.allSatisfy { abs(abs($0.y) - 0.1) < 1e-6 })
        #expect(plain.positions.filter { $0.y > 0 }.allSatisfy { abs(abs($0.x) - 1) < 1e-6 && abs(abs($0.z) - 1) < 1e-6 })
        // 上面は 4 頂点 + 側面 4 × 4 = 20 頂点・三角形は 2 + 8。底は張らない。
        #expect(plain.positions.count == 20 && plain.indices.count == 30)
        let beveled = HomerunToonMesh.prism(square, height: 0.2, bevel: 0.25)
        let top = beveled.positions.filter { $0.y > 0 }
        #expect(top.allSatisfy { abs(abs($0.x) - 0.75) < 1e-5 && abs(abs($0.z) - 0.75) < 1e-5 }, "上面が 0.25 内へ寄っていない")
        #expect(beveled.positions.filter { $0.y < 0 }.allSatisfy { abs(abs($0.x) - 1) < 1e-6 }, "底の外周は元のまま")
        // 斜めの側面の法線は外と上を向く。
        let side = zip(beveled.positions, beveled.normals).filter { abs($0.0.x - 0.75) < 1e-5 && $0.0.y > 0 && abs($0.1.x) > 0.1 }
        #expect(!side.isEmpty && side.allSatisfy { $0.1.x > 0.5 && $0.1.y > 0.3 })
        // 頂点の並びがどちら回りでも同じ形。
        let reversed = HomerunToonMesh.prism(square.reversed(), height: 0.2)
        #expect(Set(reversed.positions.map { "\($0)" }) == Set(plain.positions.map { "\($0)" }))
    }

    @Test("帯: 幅の半分だけ両側へ広がり、角は留め継ぎで閉じる（閉じた帯の外の角は (±(1 + w/2)) に 1 点ずつ）・開いた帯は両端にふた")
    func ribbonShape() {
        let w: Float = 0.1
        let ring = HomerunToonMesh.ribbon([[-1, -1], [1, -1], [1, 1], [-1, 1]], width: w, height: 0.01, closed: true)
        let xs = ring.positions.map(\.x), zs = ring.positions.map(\.z)
        #expect(abs(xs.max()! - (1 + w / 2)) < 1e-5 && abs(xs.min()! + (1 + w / 2)) < 1e-5)
        #expect(abs(zs.max()! - (1 + w / 2)) < 1e-5 && abs(zs.min()! + (1 + w / 2)) < 1e-5)
        // 上面の頂点は外の角（1.05）か内の角（0.95）だけ = 継ぎ目に飛び出しも欠けもない。
        for p in ring.positions where p.y > 0 {
            #expect((abs(abs(p.x) - 1.05) < 1e-5 || abs(abs(p.x) - 0.95) < 1e-5) && (abs(abs(p.z) - 1.05) < 1e-5 || abs(abs(p.z) - 0.95) < 1e-5), "\(p)")
        }
        let open = HomerunToonMesh.ribbon([[0, 0], [0, -2], [1, -2], [1, 0]], width: w, height: 0.01, closed: false)
        // 端（z = 0）はまっすぐ切れ、角（z = -2）は留め継ぎ。両端のふた（法線 ±z）がある。
        #expect(abs(open.positions.map(\.z).max()!) < 1e-5 && abs(open.positions.map(\.z).min()! + 2 + w / 2) < 1e-5)
        // 端（z = 0）の頂点の法線は上・横（±x）・ふた（+z = U の字の開いた側）だけで、内向き（−z）のふたは無い。
        let ends = zip(open.positions, open.normals).filter { $0.0.z > -1e-5 }.map(\.1)
        #expect(ends.contains { $0.z > 0.99 } && !ends.contains { $0.z < -0.99 }, "ふたは両端とも +z 向き（U の字の開いた側）")
        let axisAligned = open.normals.filter { abs($0.y) < 1e-5 }
        #expect(axisAligned.allSatisfy { abs(abs($0.x) - 1) < 1e-5 || abs(abs($0.z) - 1) < 1e-5 })
    }

    @Test("多角形の寄せ（offset）: 正で外・負で内へ、辺に垂直な距離が等しい。向きはどちら回りでも同じ")
    func polygonOffset() {
        let square: [SIMD2<Float>] = [[-1, -1], [1, -1], [1, 1], [-1, 1]]
        for polygon in [square, square.reversed()] {
            let out = HomerunToonMesh.offset(HomerunToonMesh.clockwise(polygon), by: 0.5, closed: true)
            #expect(out.allSatisfy { abs(abs($0.x) - 1.5) < 1e-5 && abs(abs($0.y) - 1.5) < 1e-5 }, "\(out)")
            let inner = HomerunToonMesh.offset(HomerunToonMesh.clockwise(polygon), by: -0.5, closed: true)
            #expect(inner.allSatisfy { abs(abs($0.x) - 0.5) < 1e-5 && abs(abs($0.y) - 0.5) < 1e-5 }, "\(inner)")
        }
        // 五角形の本塁を 0.05 外へ: 先端は 45° の 2 辺の交点なので 0.05 / sin45° = 0.0707 下へ。
        let plate = HomerunToonMesh.offset(HomerunToonMesh.clockwise(HomerunToonModel.HomePlate.polygon), by: 0.05, closed: true)
        let apex = plate.min { $0.y < $1.y }!
        #expect(abs(apex.x) < 1e-5 && abs(apex.y - (-0.432 - 0.05 * Float(2).squareRoot())) < 1e-4, "\(apex)")
        #expect(plate.contains { abs($0.x - 0.266) < 1e-4 && abs($0.y - 0.05) < 1e-4 }, "前の角 \(plate)")
    }

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
