import Foundation
import simd

/// 3D の部品 1 個ぶんの頂点データ（RealityKit に依存しない純粋な値。テストできるようにここで作る）。
///
/// 3 段階のトゥーン陰影は Metal シェーダを使わず（段 0: SwiftPM の `.metal` は Metal Toolchain が無い環境で
/// `swift test` ごと落ちる）、**頂点の `u` に「法線・光の向きの内積」を焼き、明・中・暗の 3 段の階段状ランプ画像を引く**形で出す。
/// 部品はモデルの座標系に変換したうえで法線を求めるので、光源はモデルに対して固定。
struct HomerunToonMesh: Equatable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    /// 陰影の段を引くための u（0…1）。法線・光の向きの内積を 0 以上に切ったもの。
    var shade: [Float] = []
    /// 縞模様などを引く v（0…1）。ふつうのランプ画像では読まれない（縞のあるジャージの胴だけが使う）。
    var stripe: [Float] = []
    var indices: [UInt32] = []

    /// 光源の向き（モデルから光源へ）。カメラ（+z）の左上手前から当てる。
    static let lightDirection = simd_normalize(SIMD3<Float>(-0.45, 0.7, 0.55))

    /// 階段状ランプ画像の段の境目（u）と明るさ。`mock3d.swift` の `toonModifier`（0.5・0.18 で 1.0 / 0.78 / 0.6）と同じ。
    static let bandEdges: [Float] = [0.18, 0.5]
    static let bandBrightness: [Float] = [0.6, 0.78, 1.0]

    static func brightness(forShade u: Float) -> Float {
        u > bandEdges[1] ? bandBrightness[2] : (u > bandEdges[0] ? bandBrightness[1] : bandBrightness[0])
    }

    /// 輪郭線用（反転ハル）: 三角形の巻き順を逆にする。既定の背面カリングで、大きくした殻の**内側の面だけ**が見えて縁取りになる。
    func flipped() -> HomerunToonMesh {
        var m = self
        m.indices = stride(from: 0, to: indices.count, by: 3).flatMap { [indices[$0], indices[$0 + 2], indices[$0 + 1]] }
        m.normals = normals.map { -$0 }
        return m
    }

    /// `transform` でモデルの座標系へ写し、陰影の u を求める（法線は逆転置行列で変換するので、つぶした球でも向きが崩れない）。
    func placed(_ transform: simd_float4x4) -> HomerunToonMesh {
        let linear = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
        let normalMatrix = linear.inverse.transpose
        var m = self
        m.positions = positions.map { p in
            let q = transform * SIMD4(p, 1)
            return SIMD3(q.x, q.y, q.z)
        }
        m.normals = normals.map { simd_normalize(normalMatrix * $0) }
        m.shade = m.normals.map { max(simd_dot($0, Self.lightDirection), 0) }
        return m
    }

    mutating func append(_ other: HomerunToonMesh) {
        let base = UInt32(positions.count)
        positions += other.positions
        normals += other.normals
        shade += other.shade
        stripe += other.stripe
        indices += other.indices.map { $0 + base }
    }

    // MARK: 図形

    /// 球（半径 r・原点中心）。
    static func sphere(radius r: Float, segments: Int = 32) -> HomerunToonMesh {
        capsule(radius: r, length: 0, segments: segments)
    }

    /// カプセル（y 軸に沿う・`length` は両端の球の中心間の距離）。長さ 0 なら球。
    static func capsule(radius r: Float, length: Float, segments: Int = 32) -> HomerunToonMesh {
        let rings = max(segments / 2, 4)
        let hemi = rings / 2
        var m = HomerunToonMesh()
        // 行: 上半球（北極 → 赤道）、下半球（赤道 → 南極）。赤道は上下で 2 行になり、その間が円筒。
        var rows: [(theta: Float, dy: Float)] = []
        for k in 0...hemi { rows.append((Float(k) / Float(hemi) * .pi / 2, length / 2)) }
        for k in 0...hemi { rows.append((.pi / 2 + Float(k) / Float(hemi) * .pi / 2, -length / 2)) }
        for row in rows {
            for j in 0...segments {
                let phi = Float(j) / Float(segments) * 2 * .pi
                let n = SIMD3(sin(row.theta) * cos(phi), cos(row.theta), sin(row.theta) * sin(phi))
                m.positions.append(SIMD3(n.x * r, n.y * r + row.dy, n.z * r))
                m.normals.append(n)
                m.stripe.append(phi / (2 * .pi))
            }
        }
        m.appendGridIndices(rows: rows.count, columns: segments + 1)
        return m
    }

    /// 角丸の箱（w・h・d・角の丸め `radius`・原点中心）。丸めは「内側の箱 + 半径 r の球」の和で、0 なら普通の箱。
    static func box(width w: Float, height h: Float, depth d: Float, radius: Float = 0) -> HomerunToonMesh {
        let r = min(radius, w / 2, h / 2, d / 2)
        let half = SIMD3(w, h, d) / 2
        let inner = half - SIMD3(repeating: r)
        let grid = r > 0 ? 6 : 1
        var m = HomerunToonMesh()
        // 6 面（法線の向き・面内の 2 軸）。面ごとに頂点を持ち、丸め 0 でも面ごとの法線になる。
        let faces: [(n: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            (SIMD3(1, 0, 0), SIMD3(0, 0, -1), SIMD3(0, 1, 0)), (SIMD3(-1, 0, 0), SIMD3(0, 0, 1), SIMD3(0, 1, 0)),
            (SIMD3(0, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, -1)), (SIMD3(0, -1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 1)),
            (SIMD3(0, 0, 1), SIMD3(1, 0, 0), SIMD3(0, 1, 0)), (SIMD3(0, 0, -1), SIMD3(-1, 0, 0), SIMD3(0, 1, 0)),
        ]
        for f in faces {
            let start = m.positions.count
            for iu in 0...grid {
                for iv in 0...grid {
                    let a = Float(iu) / Float(grid) * 2 - 1, b = Float(iv) / Float(grid) * 2 - 1
                    let p = (f.n + f.u * a + f.v * b) * half
                    if r > 0 {
                        let clamped = simd_clamp(p, -inner, inner)
                        let n = simd_normalize(p - clamped)
                        m.positions.append(clamped + n * r)
                        m.normals.append(n)
                    } else {
                        m.positions.append(p)
                        m.normals.append(f.n)
                    }
                    m.stripe.append(0.5)
                }
            }
            // 面の表側が f.n を向くよう、u × v が n と同じ向きの並びで三角形を張る。
            let flip = simd_dot(simd_cross(f.u, f.v), f.n) < 0
            for iu in 0..<grid {
                for iv in 0..<grid {
                    let a = UInt32(start + iu * (grid + 1) + iv), b = a + 1
                    let c = a + UInt32(grid + 1), e = c + 1
                    m.indices += flip ? [a, b, c, b, e, c] : [a, c, b, b, c, e]
                }
            }
        }
        return m
    }

    /// 円錐台（y 軸に沿う・高さ `height`・上の半径 `top`・下の半径 `bottom`）と両端のふた。円柱は top == bottom。
    static func frustum(top: Float, bottom: Float, height h: Float, segments: Int = 32) -> HomerunToonMesh {
        var m = HomerunToonMesh()
        // 側面: 法線は半径の傾き分だけ上（下が太いなら上向き）へ傾く。
        let slope = (bottom - top) / h
        for (y, r) in [(h / 2, top), (-h / 2, bottom)] {
            for j in 0...segments {
                let phi = Float(j) / Float(segments) * 2 * .pi
                m.positions.append(SIMD3(r * cos(phi), y, r * sin(phi)))
                m.normals.append(simd_normalize(SIMD3(cos(phi), slope, sin(phi))))
                m.stripe.append(0.5)
            }
        }
        m.appendGridIndices(rows: 2, columns: segments + 1)
        for (y, r, up) in [(h / 2, top, Float(1)), (-h / 2, bottom, Float(-1))] where r > 0 {
            let center = UInt32(m.positions.count)
            m.positions.append(SIMD3(0, y, 0)); m.normals.append(SIMD3(0, up, 0)); m.stripe.append(0.5)
            let ring = UInt32(m.positions.count)
            for j in 0...segments {
                let phi = Float(j) / Float(segments) * 2 * .pi
                m.positions.append(SIMD3(r * cos(phi), y, r * sin(phi))); m.normals.append(SIMD3(0, up, 0)); m.stripe.append(0.5)
            }
            for j in 0..<UInt32(segments) {
                m.indices += up > 0 ? [center, ring + j + 1, ring + j] : [center, ring + j, ring + j + 1]
            }
        }
        return m
    }

    /// `rows` 行 × `columns` 列の格子の頂点（行が北から南・列が phi 方向）に、外向き（表が外）の三角形を張る。
    private mutating func appendGridIndices(rows: Int, columns: Int) {
        for i in 0..<(rows - 1) {
            for j in 0..<(columns - 1) {
                let a = UInt32(i * columns + j), b = a + 1
                let c = a + UInt32(columns), e = c + 1
                indices += [a, b, c, b, e, c]
            }
        }
    }
}
