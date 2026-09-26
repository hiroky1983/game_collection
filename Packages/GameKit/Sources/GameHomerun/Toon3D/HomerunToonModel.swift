import Foundation
import simd

/// 色 1 色ぶんの部品（RealityKit に依存しない値）。`mesh` はモデルの座標系に置いた本体、`outline` は輪郭線用の反転ハル。
struct HomerunToonPart: Equatable {
    var mesh: HomerunToonMesh
    var outline: HomerunToonMesh?
    var color: UInt32
    /// 胴のピンストライプ（白地に紺の縦線）を引くか。
    var striped = false
}

/// 図形合成のモデル（`docs/design/homerun/mock3d.swift` の `sphere` / `box` / `limb` / `bat` を写したもの）。
/// 座標は頭の半径 = 1 の単位。組み立てた後に `scale` を掛けて置く。
struct HomerunToonModel: Equatable {
    static let ink: UInt32 = 0x2B2634

    var parts: [HomerunToonPart] = []

    /// 球（`scale` でつぶすと楕円体）。`outline` は縁取りの厚み（モデルの単位・0 で無し）。
    mutating func sphere(_ r: Float, _ color: UInt32, at p: SIMD3<Float>, scale: SIMD3<Float> = SIMD3(1, 1, 1), outline: Float = 0.05) {
        let t = Self.translation(p) * Self.scaling(scale)
        add(HomerunToonMesh.sphere(radius: r).placed(t), outline == 0 ? nil : HomerunToonMesh.sphere(radius: r + outline).placed(t).flipped(), color)
    }

    /// 角丸の箱。`turn` は z 軸まわりの傾き（ラジアン）。
    mutating func box(_ w: Float, _ h: Float, _ d: Float, _ color: UInt32, at p: SIMD3<Float>, radius: Float = 0, outline: Float = 0.05, turnZ: Float = 0) {
        let t = Self.translation(p) * Self.rotation(angle: turnZ, axis: SIMD3(0, 0, 1))
        let o = outline
        add(HomerunToonMesh.box(width: w, height: h, depth: d, radius: radius).placed(t),
            o == 0 ? nil : HomerunToonMesh.box(width: w + 2 * o, height: h + 2 * o, depth: d + 2 * o, radius: radius + o).placed(t).flipped(), color)
    }

    /// 円柱（ツバなど・y 軸に沿う）。`tiltX` は x 軸まわりの傾き。
    mutating func cylinder(_ r: Float, _ h: Float, _ color: UInt32, at p: SIMD3<Float>, tiltX: Float = 0, outline: Float = 0.03) {
        let t = Self.translation(p) * Self.rotation(angle: tiltX, axis: SIMD3(1, 0, 0))
        add(HomerunToonMesh.frustum(top: r, bottom: r, height: h).placed(t),
            outline == 0 ? nil : HomerunToonMesh.frustum(top: r + outline, bottom: r + outline, height: h + 2 * outline).placed(t).flipped(), color)
    }

    /// 2 点を結ぶカプセル（腕・脚・襟）。ポーズ替えは座標 2 点で済む。
    mutating func limb(_ a: SIMD3<Float>, _ b: SIMD3<Float>, r: Float, _ color: UInt32, outline: Float = 0.05, striped: Bool = false) {
        let d = b - a
        let len = simd_length(d)
        let t = Self.translation((a + b) / 2) * Self.alignY(to: d)
        add(HomerunToonMesh.capsule(radius: r, length: len).placed(t),
            outline == 0 ? nil : HomerunToonMesh.capsule(radius: r + outline, length: len).placed(t).flipped(), color, striped: striped)
    }

    /// バット（円錐台 + 先端と握りの球）。`a` が握り、`b` が先端。
    mutating func bat(_ a: SIMD3<Float>, _ b: SIMD3<Float>, wood: UInt32, woodDark: UInt32) {
        let d = b - a
        let len = simd_length(d)
        let t = Self.translation((a + b) / 2) * Self.alignY(to: d)
        let o: Float = 0.05
        add(HomerunToonMesh.frustum(top: 0.17, bottom: 0.09, height: len).placed(t),
            HomerunToonMesh.frustum(top: 0.17 + o, bottom: 0.09 + o, height: len + 2 * o).placed(t).flipped(), wood)
        sphere(0.17, wood, at: b)
        sphere(0.12, woodDark, at: a)
    }

    private mutating func add(_ mesh: HomerunToonMesh, _ outline: HomerunToonMesh?, _ color: UInt32, striped: Bool = false) {
        parts.append(HomerunToonPart(mesh: mesh, outline: outline, color: color, striped: striped))
    }

    // MARK: 行列

    static func translation(_ p: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(p, 1)
        return m
    }

    static func scaling(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s, 1))
    }

    static func rotation(angle: Float, axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: axis))
    }

    /// y 軸を `direction` へ向ける回転（真逆でも壊れないよう x にごく小さな量を足す。mock3d と同じ）。
    static func alignY(to direction: SIMD3<Float>) -> simd_float4x4 {
        let d = simd_length(direction) == 0 ? SIMD3<Float>(0, 1, 0) : direction
        return simd_float4x4(simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(d + SIMD3(1e-4, 0, 0))))
    }
}
