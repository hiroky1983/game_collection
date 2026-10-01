#if canImport(RealityKit)
import Foundation
import RealityKit

/// 空振りの演出（#1681）のぐるぐる目と頭上の星。打者の実体（`HomerunBatterRig.entity`）の子に置き、毎コマ
/// `HomerunWhiffGag` の表から頭の骨に合わせて置き直す（骨は読まない）。
/// - ぐるぐる目: 白地に黒の渦巻き・黒の縁の円板を左右の目の上に貼り、時計回りに回す。
/// - 星: 黄色の星（インク色の縁取り）3 つが頭のてっぺんの上を回る。いつもカメラへ向ける。
@MainActor
final class HomerunWhiffGagOverlay {
    let entity = Entity()
    private var eyes: [ModelEntity] = []
    private var stars: [ModelEntity] = []

    var isEnabled: Bool {
        get { entity.isEnabled }
        set { entity.isEnabled = newValue }
    }

    /// 目の絵（1 回だけ作る）。作れない環境では白い円板（縁だけ黒）にしない・白一色。
    private static var eyeTexture: TextureResource?

    init() {
        if Self.eyeTexture == nil, let image = HomerunWhiffGag.eyeImage() {
            Self.eyeTexture = try? TextureResource.generate(from: image, options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll))
        }
        var eyeMaterial = UnlitMaterial(color: .white)
        if let texture = Self.eyeTexture { eyeMaterial.color = .init(tint: .white, texture: .init(texture)) }
        let eyeMesh = Self.disc(radius: HomerunWhiffGag.eyeRadius * HomerunWhiffGag.eyeRimScale)
        for _ in HomerunWhiffGag.eyeMounts {
            let eye = ModelEntity(mesh: eyeMesh, materials: [eyeMaterial])
            entity.addChild(eye)
            eyes.append(eye)
        }
        let ink = HomerunToonModel.ink
        let inkColor = HomerunPlatformColor(red: CGFloat((ink >> 16) & 0xFF) / 255, green: CGFloat((ink >> 8) & 0xFF) / 255,
                                            blue: CGFloat(ink & 0xFF) / 255, alpha: 1)
        let yellow = UnlitMaterial(color: HomerunPlatformColor(red: 1.0, green: 0.86, blue: 0.10, alpha: 1))
        let rim = UnlitMaterial(color: inkColor)
        let face = Self.star(outer: 1, inner: 0.45, z: 0), back = Self.star(outer: 1.28, inner: 0.62, z: -0.05)
        for _ in 0..<HomerunWhiffGag.starCount {
            let star = ModelEntity(mesh: face, materials: [yellow])
            star.addChild(ModelEntity(mesh: back, materials: [rim]))
            entity.addChild(star)
            stars.append(star)
        }
    }

    /// クリップ時刻 `clipTime`・回転と傾き `turn` のときに置き直す。`camera` は描画のカメラの位置（世界座標）。
    func apply(clipTime t: TimeInterval, turn: simd_quatf, back: Bool, camera: SIMD3<Float>) {
        let eyeScale = HomerunWhiffGag.appear(atClipTime: t, from: HomerunWhiffGag.eyeInFrame, grow: HomerunWhiffGag.eyeGrow)
        let spin = simd_quatf(angle: HomerunWhiffGag.eyeSpin(atClipTime: t), axis: [0, 0, 1])
        for (i, eye) in eyes.enumerated() {
            let pose = HomerunWhiffGag.eyePose(atClipTime: t, index: i, turn: turn)
            eye.position = pose.position
            eye.orientation = pose.rotation * spin
            eye.scale = SIMD3(repeating: max(eyeScale, 0.001))
            eye.isEnabled = eyeScale > 0
        }
        let starScale = HomerunWhiffGag.appear(atClipTime: t, from: HomerunWhiffGag.starInFrame, grow: HomerunWhiffGag.starGrow)
            * HomerunWhiffGag.starSize(back: back)
        for (i, star) in stars.enumerated() {
            star.position = HomerunWhiffGag.starCenter(atClipTime: t, index: i, turn: turn)
            star.scale = SIMD3(repeating: max(starScale, 0.0001))
            star.isEnabled = starScale > 0
            // カメラへ向ける（星の +z をカメラへ・上はなるべく世界の上）。
            let at = star.position(relativeTo: nil)
            let z = simd_normalize(camera - at)
            let x = simd_normalize(simd_cross([0, 1, 0], z))
            let y = simd_cross(z, x)
            star.setOrientation(simd_quatf(simd_float3x3(x, y, z)), relativeTo: nil)
        }
    }

    /// 円板（xy 面・+z が表・両面）。絵は円に内接する正方形ではなく、円の外接正方形 = 絵の端が円の縁。
    private static func disc(radius: Float, segments: Int = 40) -> MeshResource {
        var positions: [SIMD3<Float>] = [.zero]
        var uvs: [SIMD2<Float>] = [[0.5, 0.5]]
        for i in 0..<segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            positions.append([radius * cos(a), radius * sin(a), 0])
            uvs.append([0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)])
        }
        var indices: [UInt32] = []
        for i in 0..<segments {
            let a = UInt32(1 + i), b = UInt32(1 + (i + 1) % segments)
            indices += [0, a, b, 0, b, a]
        }
        var d = MeshDescriptor(name: "whiffEye")
        d.positions = MeshBuffer(positions)
        d.textureCoordinates = MeshBuffer(uvs)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generatePlane(width: radius * 2, height: radius * 2)
    }

    /// 5 つ角の星（xy 面・半径 1 の単位・両面）。
    private static func star(outer: Float, inner: Float, z: Float) -> MeshResource {
        var positions: [SIMD3<Float>] = [[0, 0, z]]
        for i in 0..<10 {
            let a = Float.pi / 2 + Float(i) * .pi / 5
            let r = i % 2 == 0 ? outer : inner
            positions.append([r * cos(a), r * sin(a), z])
        }
        var indices: [UInt32] = []
        for i in 0..<10 {
            let a = UInt32(1 + i), b = UInt32(1 + (i + 1) % 10)
            indices += [0, a, b, 0, b, a]
        }
        var d = MeshDescriptor(name: "whiffStar")
        d.positions = MeshBuffer(positions)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateBox(size: outer)
    }
}
#endif
