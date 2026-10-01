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
/// 燃えている球（#1680・#1687 会長 QA「もっと火の玉っぽく」）: カメラを向く板（`HomerunFireballArt.sprites`）を重ねた火の玉。
/// 光の輪 2 枚（半透明）・長い火の尾・舌状の炎 3 枚・内側の炎・芯・火の粉 5 粒の計 `HomerunFireballArt.spriteCount` 枚で、
/// パーティクルは使わない。炎は陰影なしの段の画像（白 → 黄 → 橙 → 赤・縁は濃い赤の細い線）を、画像の外を切り抜いて貼る。
@MainActor
final class HomerunFireballRig {
    let entity = Entity()
    private var sprites: [HomerunFireballArt.Layer: ModelEntity] = [:]

    init() {
        let plane = MeshResource.generatePlane(width: 1, height: 1)
        let disc = MeshResource.generatePlane(width: 1, height: 1, cornerRadius: 0.5)
        func flame(_ style: HomerunFireballArt.Style, phase: Double = 0) -> UnlitMaterial {
            var m = UnlitMaterial()
            if let image = HomerunFireballArt.image(style, phase: phase),
               let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) {
                m.color = .init(tint: .white, texture: .init(texture))
                // 画像の外（赤が 0）を切り抜く。炎の中の色は赤の成分が 0.69 以上。
                m.blending = .transparent(opacity: .init(scale: 1, texture: .init(texture)))
                m.opacityThreshold = 0.5
            } else {
                m.color = .init(tint: Self.color(0xFF8A1E))
            }
            return m
        }
        func glow(_ v: UInt32, _ opacity: Float) -> UnlitMaterial {
            var m = UnlitMaterial(color: Self.color(v))
            m.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return m
        }
        // 1 式で連結すると型推論が重くなる（CI のタイムアウト・#1680）ので、1 枚ずつ足す。
        var layers: [(HomerunFireballArt.Layer, MeshResource, UnlitMaterial)] = []
        layers.append((.glowOuter, disc, glow(0xFFA040, 0.32)))
        layers.append((.glowInner, disc, glow(0xFFE27A, 0.5)))
        layers.append((.tail, plane, flame(.tail)))
        for i in 0..<HomerunFireballArt.tongueCount {
            layers.append((.tongue(i), plane, flame(.outer, phase: Double(i) * 2.1)))
        }
        layers.append((.inner, plane, flame(.inner)))
        layers.append((.core, disc, UnlitMaterial(color: Self.color(0xFFFBE6))))
        for i in 0..<HomerunFireballArt.sparkCount {
            let spark: UInt32 = i % 2 == 0 ? 0xFFD23A : 0xFF8A1E
            layers.append((.spark(i), disc, UnlitMaterial(color: Self.color(spark))))
        }
        for (layer, mesh, material) in layers {
            let e = ModelEntity(mesh: mesh, materials: [material])
            entity.addChild(e)
            sprites[layer] = e
        }
        entity.isEnabled = false
    }

    private static func color(_ v: UInt32) -> HomerunPlatformColor {
        HomerunPlatformColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                             blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    func apply(_ fire: HomerunMoonShot.Fireball?, camera: SIMD3<Float>) {
        guard let fire else {
            entity.isEnabled = false
            return
        }
        entity.isEnabled = true
        for s in HomerunFireballArt.sprites(fire, camera: camera) {
            guard let e = sprites[s.layer] else { continue }
            // 板（xy 面・+z が表）の +z をカメラへ、+y を尾の向きへ。
            let z = simd_normalize(camera - s.center)
            let y = simd_normalize(s.axis - z * simd_dot(s.axis, z))
            let x = simd_cross(y, z)
            e.orientation = simd_quatf(simd_float3x3(columns: (x, y, z)))
            e.position = s.center
            e.scale = [s.size.x, s.size.y, 1]
        }
    }
}
#endif
