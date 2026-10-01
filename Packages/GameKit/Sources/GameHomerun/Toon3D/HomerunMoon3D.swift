#if canImport(RealityKit)
import Foundation
import RealityKit
import simd

/// 月の 3D（#1680）。クレーターの模様の球（ヒビ無し・ヒビ入りの 2 枚の模様を差し替え）と、割れた半球 2 つ。どちらもインクの
/// 輪郭線（反転ハル）付きのトゥーン調。打席の 3D（`HomerunAtBatScene3DView`）が月まで飛んだ打球のときだけ作って足す。
@MainActor
final class HomerunMoonRig {
    let entity = Entity()
    private let whole = Entity()
    private let wholeBody: ModelEntity
    private let halves: [Entity]
    private let plain: UnlitMaterial
    private let cracked: UnlitMaterial
    private var showsCrack = false

    init() {
        let plain = Self.surfaceMaterial(cracked: false), cracked = Self.surfaceMaterial(cracked: true)
        self.plain = plain
        self.cracked = cracked
        let root = entity
        let r = HomerunMoonShot.moonRadius
        let ink = UnlitMaterial(color: HomerunPlatformColor(red: 0x2B / 255, green: 0x26 / 255, blue: 0x34 / 255, alpha: 1))
        let sphere = HomerunMoonMesh.shell(radius: r)
        wholeBody = ModelEntity(mesh: Self.resource(sphere) ?? .generateSphere(radius: r), materials: [plain])
        whole.addChild(wholeBody)
        if let outline = Self.resource(sphere.outline(scale: 1.035)) {
            whole.addChild(ModelEntity(mesh: outline, materials: [ink]))
        }
        entity.addChild(whole)
        // 半球: x ≥ 0（右）と x ≤ 0（左）。模様はヒビ入り（割れるのはヒビの後）。断面は岩の色。
        let core = UnlitMaterial(color: HomerunPlatformColor(red: CGFloat((HomerunMoonArt.core >> 16) & 0xFF) / 255,
                                                             green: CGFloat((HomerunMoonArt.core >> 8) & 0xFF) / 255,
                                                             blue: CGFloat(HomerunMoonArt.core & 0xFF) / 255, alpha: 1))
        halves = [(Float(-0.5), false), (Float(0.5), true)].map { start, capFacesPositiveX in
            let half = Entity()
            let shell = HomerunMoonMesh.shell(radius: r, fromLon: start * .pi, toLon: (start + 1) * .pi, segments: 24)
            if let m = Self.resource(shell) { half.addChild(ModelEntity(mesh: m, materials: [cracked])) }
            if let m = Self.resource(shell.outline(scale: 1.035)) { half.addChild(ModelEntity(mesh: m, materials: [ink])) }
            if let m = Self.resource(HomerunMoonMesh.cap(radius: r, facingPositiveX: capFacesPositiveX)) {
                half.addChild(ModelEntity(mesh: m, materials: [core]))
            }
            half.isEnabled = false
            root.addChild(half)
            return half
        }
        entity.position = HomerunMoonShot.moonCenter
        entity.orientation = HomerunMoonShot.moonOrientation
        entity.isEnabled = false
    }

    /// 1 コマぶんの見え方を当てる。nil なら隠す（ふだんの打球・投球中）。
    func apply(_ look: HomerunMoonShot.Look?) {
        guard let look, look.moonVisible else {
            entity.isEnabled = false
            return
        }
        entity.isEnabled = true
        entity.position = look.moonCenter + look.shake
        if look.cracked != showsCrack {
            wholeBody.model?.materials = [look.cracked ? cracked : plain]
            showsCrack = look.cracked
        }
        let split = Float(look.split)
        whole.isEnabled = split <= 0
        let r = HomerunMoonShot.moonRadius
        for (i, half) in halves.enumerated() {
            half.isEnabled = split > 0
            let side: Float = i == 0 ? 1 : -1
            // 左右（局所の x）へ離れながら少し下へ落ち、外側へ傾く。
            half.position = [side * r * 0.9 * split, -r * 0.35 * split * split, 0]
            half.orientation = simd_quatf(angle: -side * 0.45 * split, axis: [0, 0, 1])
        }
    }

    private static func resource(_ mesh: HomerunMoonMesh) -> MeshResource? {
        var d = MeshDescriptor(name: "moon")
        d.positions = MeshBuffer(mesh.positions)
        d.normals = MeshBuffer(mesh.normals)
        d.textureCoordinates = MeshBuffer(mesh.uvs)
        d.primitives = .triangles(mesh.indices)
        return try? MeshResource.generate(from: [d])
    }

    private static func surfaceMaterial(cracked: Bool) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let image = HomerunMoonArt.image(cracked: cracked),
           let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) {
            m.color = .init(tint: .white, texture: .init(texture))
        } else {
            m.color = .init(tint: HomerunPlatformColor(red: 0.96, green: 0.91, blue: 0.68, alpha: 1))
        }
        return m
    }
}
#endif

#if canImport(RealityKit)
/// 燃えている球（#1680・会長 QA）: 赤橙の炎の玉（インクの輪郭線付き）・手前の黄色い芯・後ろへ細くなる火の尾の玉。
/// 板ポリ・パーティクルは使わず、陰影なしの球を `HomerunMoonShot.trailCount + 2` 個並べるだけ（毎コマは位置と大きさを変えるだけ）。
@MainActor
final class HomerunFireballRig {
    let entity = Entity()
    private let flame: ModelEntity
    private let outline: ModelEntity
    private let core: ModelEntity
    private let trail: [ModelEntity]

    init() {
        func color(_ v: UInt32) -> UnlitMaterial {
            UnlitMaterial(color: HomerunPlatformColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                                                      blue: CGFloat(v & 0xFF) / 255, alpha: 1))
        }
        let sphere = MeshResource.generateSphere(radius: 1)
        flame = ModelEntity(mesh: sphere, materials: [color(0xFF6A1A)])
        let hull = HomerunMoonMesh.shell(radius: 1, rings: 12, segments: 24).outline(scale: 1.12)
        var d = MeshDescriptor(name: "fireOutline")
        d.positions = MeshBuffer(hull.positions)
        d.normals = MeshBuffer(hull.normals)
        d.primitives = .triangles(hull.indices)
        outline = ModelEntity(mesh: (try? MeshResource.generate(from: [d])) ?? sphere, materials: [color(0x2B2634)])
        core = ModelEntity(mesh: sphere, materials: [color(0xFFE45C)])
        // 火の尾: 芯に近いほど橙、遠いほど赤。
        let tail: [UInt32] = [0xFF8A1E, 0xFF7418, 0xF65A16, 0xE84414, 0xD43212, 0xBC2410]
        trail = (0..<HomerunMoonShot.trailCount).map { ModelEntity(mesh: sphere, materials: [color(tail[$0 % tail.count])]) }
        for e in [outline, flame, core] + trail { entity.addChild(e) }
        entity.isEnabled = false
    }

    func apply(_ fire: HomerunMoonShot.Fireball?, camera: SIMD3<Float>) {
        guard let fire else {
            entity.isEnabled = false
            return
        }
        entity.isEnabled = true
        let r = fire.radius
        let toCamera = simd_normalize(camera - fire.center)
        flame.position = fire.center
        flame.scale = SIMD3(repeating: r)
        outline.position = fire.center
        outline.scale = SIMD3(repeating: r)
        // 黄色い芯は炎の手前（カメラ側）に寄せて、炎の中に明るい芯が見えるようにする。
        core.position = fire.center + toCamera * r * 0.5
        core.scale = SIMD3(repeating: r * (0.55 + 0.1 * fire.flicker))
        for (i, e) in trail.enumerated() {
            let k = Float(i + 1)
            let wobble = (i % 2 == 0 ? 1 : -1) * 0.15 * (fire.flicker - 0.5)
            let side = simd_normalize(simd_cross(fire.trail, [1, 0, 0]))
            e.position = fire.center + fire.trail * r * 1.15 * k + side * r * wobble
            e.scale = SIMD3(repeating: r * max(0.85 - 0.13 * k, 0.12))
        }
    }
}
#endif
