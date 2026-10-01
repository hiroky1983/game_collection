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

    // MARK: 地面に敷く平らな図形（#1677 本塁・バッターボックス・ファウルライン）

    /// 凸多角形の柱（上面は y = +h/2・底は -h/2。`polygon` は (x, z) の頂点で、向きはどちら回りでもよい）。
    /// `bevel` > 0 なら上面の多角形を `bevel` だけ内へ寄せ、側面を底の外周から上面の内周へ斜めに張る（薄いゴム板の縁）。
    /// 底は見えないので張らない。面ごとに頂点を持ち、面の法線で陰影が付く。
    static func prism(_ polygon: [SIMD2<Float>], height h: Float, bevel: Float = 0) -> HomerunToonMesh {
        let outer = clockwise(polygon)
        let top = bevel > 0 ? offset(outer, by: -bevel, closed: true) : outer
        var m = HomerunToonMesh()
        m.addFan(top.map { SIMD3($0.x, h / 2, $0.y) }, normal: SIMD3(0, 1, 0))
        for i in outer.indices {
            let j = (i + 1) % outer.count
            let (a, b) = (outer[i], outer[j])
            let n = outwardNormal(a, b)
            m.addQuad(SIMD3(a.x, -h / 2, a.y), SIMD3(b.x, -h / 2, b.y), SIMD3(top[j].x, h / 2, top[j].y), SIMD3(top[i].x, h / 2, top[i].y),
                      outward: SIMD3(n.x, 0.5, n.y))
        }
        return m
    }

    /// 折れ線に沿う幅 `width`・厚み `height` の帯（白線）。角は留め継ぎ（左右の縁を交点でつなぐ）で、`closed` なら最後の点から最初へ戻って輪にする。
    /// 上面と外側・内側の側面（開いた帯は両端のふたも）を張り、底は張らない。原点中心ではなく、`points` の座標にそのまま置く（y = ±height/2）。
    static func ribbon(_ points: [SIMD2<Float>], width w: Float, height h: Float, closed: Bool) -> HomerunToonMesh {
        precondition(points.count >= 2)
        let path = closed ? clockwise(points) : points
        let left = offset(path, by: w / 2, closed: closed), right = offset(path, by: -w / 2, closed: closed)
        var m = HomerunToonMesh()
        let n = path.count
        let segments = closed ? n : n - 1
        for i in 0..<segments {
            let j = (i + 1) % n
            // 上面（左右の縁の間）・左右の側面（上から底へ）。側面の向きは左右の縁の外向き。
            m.addQuad(SIMD3(left[i].x, h / 2, left[i].y), SIMD3(left[j].x, h / 2, left[j].y),
                      SIMD3(right[j].x, h / 2, right[j].y), SIMD3(right[i].x, h / 2, right[i].y), outward: SIMD3(0, 1, 0))
            let d = path[j] - path[i]
            let leftNormal = SIMD2<Float>(-d.y, d.x)
            m.addQuad(SIMD3(left[i].x, h / 2, left[i].y), SIMD3(left[j].x, h / 2, left[j].y),
                      SIMD3(left[j].x, -h / 2, left[j].y), SIMD3(left[i].x, -h / 2, left[i].y), outward: SIMD3(leftNormal.x, 0, leftNormal.y))
            m.addQuad(SIMD3(right[i].x, h / 2, right[i].y), SIMD3(right[j].x, h / 2, right[j].y),
                      SIMD3(right[j].x, -h / 2, right[j].y), SIMD3(right[i].x, -h / 2, right[i].y), outward: SIMD3(-leftNormal.x, 0, -leftNormal.y))
        }
        if !closed {
            for (i, sign) in [(0, Float(-1)), (n - 1, 1)] {
                let d = path[min(i + 1, n - 1)] - path[max(i - 1, 0)]
                m.addQuad(SIMD3(left[i].x, h / 2, left[i].y), SIMD3(right[i].x, h / 2, right[i].y),
                          SIMD3(right[i].x, -h / 2, right[i].y), SIMD3(left[i].x, -h / 2, left[i].y), outward: SIMD3(d.x, 0, d.y) * sign)
            }
        }
        return m
    }

    /// 中心 `center`・半径 (rx, rz) の楕円の頂点（`segments` 角形）。
    static func ellipse(center: SIMD2<Float>, rx: Float, rz: Float, segments: Int = 20) -> [SIMD2<Float>] {
        (0..<segments).map { i in
            let a = Float(i) / Float(segments) * 2 * .pi
            return center + SIMD2(rx * cos(a), rz * sin(a))
        }
    }

    /// (x, z) の多角形を、上（+y）から見て表になる向き（x–z の符号付き面積が負）に揃える。
    static func clockwise(_ polygon: [SIMD2<Float>]) -> [SIMD2<Float>] {
        var area: Float = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            area += a.x * b.y - b.x * a.y
        }
        return area > 0 ? polygon.reversed() : polygon
    }

    /// `clockwise` に揃えた多角形の辺 a → b の外向きの単位法線（左手側）。
    static func outwardNormal(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float> {
        let d = b - a
        return simd_normalize(SIMD2(-d.y, d.x))
    }

    /// 折れ線の各点を、進む向きの左手側へ `distance` だけずらした点（角は留め継ぎ = 隣り合う辺の平行線の交点）。
    /// `clockwise` に揃えた閉じた多角形では左手側が外なので、正で外へ・負で内へ寄る。
    static func offset(_ points: [SIMD2<Float>], by distance: Float, closed: Bool) -> [SIMD2<Float>] {
        let n = points.count
        func normal(_ i: Int, _ j: Int) -> SIMD2<Float> { outwardNormal(points[i], points[j]) }
        return points.indices.map { i in
            let hasPrev = closed || i > 0, hasNext = closed || i < n - 1
            let prev = hasPrev ? normal((i + n - 1) % n, i) : normal(i, i + 1)
            let next = hasNext ? normal(i, (i + 1) % n) : normal(i - 1, i)
            let sum = prev + next
            guard simd_length(sum) > 1e-5 else { return points[i] + prev * distance }
            let miter = simd_normalize(sum)
            return points[i] + miter * (distance / max(simd_dot(miter, prev), 0.2))
        }
    }

    /// 凸多角形の面（扇形に三角形を張る）。`normal` の側が表になるよう巻きを揃える。
    private mutating func addFan(_ points: [SIMD3<Float>], normal: SIMD3<Float>) {
        guard points.count >= 3 else { return }
        let start = UInt32(positions.count)
        let flip = simd_dot(simd_cross(points[1] - points[0], points[2] - points[0]), normal) < 0
        for p in points { positions.append(p); normals.append(simd_normalize(normal)); stripe.append(0.5) }
        for k in 1..<UInt32(points.count - 1) {
            indices += flip ? [start, start + k + 1, start + k] : [start, start + k, start + k + 1]
        }
    }

    /// 四角形の面（a → b → c → d の順の 4 点）。法線は面の幾何から求め、`outward` と同じ側を向くように巻きと法線を揃える。
    private mutating func addQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, outward: SIMD3<Float>) {
        var n = simd_cross(b - a, c - a)
        if simd_length(n) < 1e-9 { n = simd_cross(c - a, d - a) }
        guard simd_length(n) > 1e-9 else { return }
        n = simd_normalize(n)
        let flip = simd_dot(n, outward) < 0
        if flip { n = -n }
        let start = UInt32(positions.count)
        for p in [a, b, c, d] { positions.append(p); normals.append(n); stripe.append(0.5) }
        indices += flip ? [start, start + 2, start + 1, start, start + 3, start + 2] : [start, start + 1, start + 2, start, start + 2, start + 3]
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
