#if canImport(RealityKit)
import Foundation
import CoreGraphics
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
typealias HomerunPlatformColor = UIColor
#else
import AppKit
typealias HomerunPlatformColor = NSColor
#endif

/// `HomerunToonModel`（純粋な頂点データ）を RealityKit の実体にする。
///
/// トゥーン陰影: 頂点の u（法線・光の向きの内積）で **明・中・暗の 3 段の階段状ランプ画像**を引き、部品の色（tint）を掛ける。
/// 輪郭線: 大きくした殻の三角形の巻きを逆にして（`HomerunToonMesh.flipped()`）インク色で塗る。どちらも `UnlitMaterial` と
/// 既定の背面カリングだけで出るので、iOS 17 / macOS 14 で動き、`.metal` も要らない。
@MainActor
enum HomerunToonScene {
    /// ランプ画像（ふつう 1 本・ジャージの縞つき 1 本）。作れない環境（Metal の無い CI など）では nil で、色は陰影なしの単色になる。
    private static var plainTexture: TextureResource?
    private static var stripedTexture: TextureResource?
    private static var materials: [UInt32: UnlitMaterial] = [:]
    private static var stripedMaterial: UnlitMaterial?
    private static var inkMaterial: UnlitMaterial?

    static func entity(for model: HomerunToonModel, scale: Float = 1) -> Entity {
        let root = Entity()
        for part in model.parts {
            if let e = modelEntity(part.mesh, material: part.striped ? striped() : material(part.color)) { root.addChild(e) }
            if let outline = part.outline, let e = modelEntity(outline, material: ink()) { root.addChild(e) }
        }
        root.scale = SIMD3(repeating: scale)
        return root
    }

    static func meshResource(_ mesh: HomerunToonMesh) -> MeshResource? {
        var d = MeshDescriptor(name: "toon")
        d.positions = MeshBuffer(mesh.positions)
        d.normals = MeshBuffer(mesh.normals)
        d.textureCoordinates = MeshBuffer(zip(mesh.shade, mesh.stripe).map { SIMD2<Float>($0, $1) })
        d.primitives = .triangles(mesh.indices)
        return try? MeshResource.generate(from: [d])
    }

    private static func modelEntity(_ mesh: HomerunToonMesh, material: UnlitMaterial) -> ModelEntity? {
        guard let resource = meshResource(mesh) else { return nil }
        return ModelEntity(mesh: resource, materials: [material])
    }

    private static func material(_ color: UInt32) -> UnlitMaterial {
        if let m = materials[color] { return m }
        var m = UnlitMaterial()
        m.color = .init(tint: platformColor(color), texture: plainRamp().map { .init($0) })
        materials[color] = m
        return m
    }

    private static func striped() -> UnlitMaterial {
        if let m = stripedMaterial { return m }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: stripedRamp().map { .init($0) })
        stripedMaterial = m
        return m
    }

    private static func ink() -> UnlitMaterial {
        if let m = inkMaterial { return m }
        let m = UnlitMaterial(color: platformColor(HomerunToonModel.ink))
        inkMaterial = m
        return m
    }

    private static func platformColor(_ v: UInt32) -> HomerunPlatformColor {
        HomerunPlatformColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    // MARK: ランプ画像

    private static func plainRamp() -> TextureResource? {
        if let t = plainTexture { return t }
        plainTexture = texture(HomerunToonRamp.image(stripes: 0))
        return plainTexture
    }

    private static func stripedRamp() -> TextureResource? {
        if let t = stripedTexture { return t }
        stripedTexture = texture(HomerunToonRamp.image(stripes: HomerunToonRamp.jerseyStripes))
        return stripedTexture
    }

    private static func texture(_ image: CGImage?) -> TextureResource? {
        guard let image else { return nil }
        return try? TextureResource.generate(from: image, options: .init(semantic: .color))
    }
}

/// 階段状ランプ画像の生成（横 = 陰影の u・縦 = 縞の v）。
enum HomerunToonRamp {
    static let width = 256
    static let jerseyStripes = 9
    private static let rowsPerStripe = 32

    /// `stripes` が 0 なら 1 行のグレーのランプ。1 以上なら白地に紺の縦線を `stripes` 本入れたランプ（白のジャージ用）。
    static func image(stripes: Int) -> CGImage? {
        let height = max(stripes, 1) * (stripes == 0 ? 1 : rowsPerStripe)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let navy: (Float, Float, Float) = (0.243, 0.306, 0.502)
        for y in 0..<height {
            let inStripe = stripes > 0 && (14..<18).contains(y % rowsPerStripe)
            for x in 0..<width {
                let b = HomerunToonMesh.brightness(forShade: Float(x) / Float(width - 1))
                let c: (Float, Float, Float) = inStripe ? navy : (1, 1, 1)
                let o = (y * width + x) * 4
                bytes[o] = UInt8((c.0 * b * 255).rounded()); bytes[o + 1] = UInt8((c.1 * b * 255).rounded()); bytes[o + 2] = UInt8((c.2 * b * 255).rounded())
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)
        return provider.flatMap {
            CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }
}
#endif
