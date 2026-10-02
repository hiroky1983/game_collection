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
    /// 結果の記号（#1760）: キラキラ目の星（左右の目の上）・頭の横のきらめき・怒りマーク。ぐるぐる目・星とは同時に出さない。
    private var sparkleEyes: [ModelEntity] = []
    private var sparkles: [ModelEntity] = []
    private var angry: ModelEntity?

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
        let eyeStar = Self.star(outer: 1, inner: 0.45, z: 0), eyeStarRim = Self.star(outer: 1.3, inner: 0.62, z: -0.02)
        for _ in HomerunWhiffGag.eyeMounts {
            let s = ModelEntity(mesh: eyeStar, materials: [yellow])
            s.addChild(ModelEntity(mesh: eyeStarRim, materials: [rim]))
            entity.addChild(s)
            sparkleEyes.append(s)
        }
        for _ in 0..<2 {
            let s = ModelEntity(mesh: face, materials: [yellow])
            s.addChild(ModelEntity(mesh: back, materials: [rim]))
            entity.addChild(s)
            sparkles.append(s)
        }
        let red = UnlitMaterial(color: HomerunPlatformColor(red: 0.92, green: 0.15, blue: 0.12, alpha: 1))
        let mark = ModelEntity(mesh: Self.angryMark(grow: 0), materials: [red])
        mark.addChild(ModelEntity(mesh: Self.angryMark(grow: 0.16), materials: [rim]))
        entity.addChild(mark)
        angry = mark
        hideMarks()
        isEnabled = false
    }

    private func hideMarks() {
        for e in sparkleEyes + sparkles { e.isEnabled = false }
        angry?.isEnabled = false
    }

    private func hideGag() {
        for e in eyes + stars { e.isEnabled = false }
    }

    /// 結果の記号（キラキラ目・怒りマーク）を置く。回って倒れる演出ではない振りの間に毎コマ呼ぶ。`poseClip` は頭の骨の置き場所を
    /// 引くクリップ時刻（フォロースルーの最後のコマで止める）、`animClip` は出始め・明滅を数える時刻（止まった後も進める）。
    func applyMark(_ mark: HomerunFaceMark, poseClip: TimeInterval, animClip: TimeInterval, back: Bool, camera: SIMD3<Float>) {
        hideGag()
        hideMarks()
        let since = max(animClip - (HomerunFaceMark.appearFrame - 1) / HomerunWhiffGag.frameRate, 0)
        let grow = HomerunWhiffGag.appear(atClipTime: animClip, from: HomerunFaceMark.appearFrame, grow: HomerunFaceMark.appearGrow)
        guard grow > 0, mark != .none else { return }
        let turn = simd_quatf(angle: 0, axis: [0, 1, 0])
        let head = HomerunWhiffGag.head(atClipTime: poseClip)
        let top = head.position + head.rotation.act(HomerunWhiffGag.headTop)
        let up = simd_normalize(head.rotation.act(HomerunWhiffGag.headUp))
        // 頭の横（カメラから見て右）と上。記号はいつもカメラへ向ける。
        let toCamera = simd_normalize(camera - top)
        let side = simd_normalize(simd_cross(up, toCamera))
        switch mark {
        case .none, .waitingSparkle:
            break
        case .sparkle:
            for (i, s) in sparkleEyes.enumerated() {
                let pose = HomerunWhiffGag.eyePose(atClipTime: poseClip, index: i, turn: turn)
                s.position = pose.position
                s.orientation = pose.rotation
                s.scale = SIMD3(repeating: max(grow * HomerunFaceMark.sparkleEyeRadius, 0.0001))
                s.isEnabled = true
            }
            for (i, s) in sparkles.enumerated() {
                let sign: Float = i == 0 ? 1 : -1
                // 2 つは明滅の位相をずらす。
                let phase = HomerunFaceMark.pulse(since: since + (i == 0 ? 0 : 0.5 / HomerunFaceMark.twinkleRate),
                                                  rate: HomerunFaceMark.twinkleRate, depth: HomerunFaceMark.twinkleDepth)
                s.position = top + side * (sign * HomerunFaceMark.sparkleSide) + up * HomerunFaceMark.sparkleLift * (i == 0 ? 1 : 0.4)
                s.scale = SIMD3(repeating: max(grow * HomerunFaceMark.sparkleSize(back: back) * phase * (i == 0 ? 1 : 0.8), 0.0001))
                Self.faceCamera(s, camera: camera)
                s.isEnabled = true
            }
        case .angry:
            guard let a = angry else { return }
            let pulse = HomerunFaceMark.pulse(since: since, rate: HomerunFaceMark.angryPulseRate, depth: HomerunFaceMark.angryPulseDepth)
            a.position = top + side * HomerunFaceMark.angrySide + up * HomerunFaceMark.angryLift
            a.scale = SIMD3(repeating: max(grow * HomerunFaceMark.angrySize(back: back) * pulse, 0.0001))
            Self.faceCamera(a, camera: camera)
            a.isEnabled = true
        }
    }

    /// 構えのキラキラ目（#1762）: 左右の目の上に星を置く。`poseClip` は構え・踏み込みの頭の骨を引くクリップ時刻、`now` は明滅の位相。
    /// 目の飾りは顔に貼るので後ろのカメラでは顔が見えない。後ろのときだけ、結果のキラキラ目（#1760）と同じ頭の横のきらめきを足す。
    func applyWaitingEyes(poseClip: TimeInterval, now: Date, back: Bool, camera: SIMD3<Float>) {
        hideGag()
        hideMarks()
        let twinkle = HomerunFaceMark.pulse(since: now.timeIntervalSinceReferenceDate, rate: HomerunFaceMark.waitingTwinkleRate,
                                            depth: HomerunFaceMark.waitingTwinkleDepth)
        for (i, s) in sparkleEyes.enumerated() {
            let pose = HomerunWhiffGag.preSwingEyePose(atClipTime: poseClip, index: i)
            s.position = pose.position
            s.orientation = pose.rotation
            s.scale = SIMD3(repeating: HomerunFaceMark.sparkleEyeRadius * twinkle)
            s.isEnabled = true
        }
        guard back else { return }
        let head = HomerunWhiffGag.preSwingHead(atClipTime: poseClip)
        let top = head.position + head.rotation.act(HomerunWhiffGag.headTop)
        let up = simd_normalize(head.rotation.act(HomerunWhiffGag.headUp))
        // 頭の位置は打者の局所なので、カメラ（世界）も局所へ直してから横を決める。
        let side = simd_normalize(simd_cross(up, simd_normalize(entity.convert(position: camera, from: nil) - top)))
        for (i, s) in sparkles.enumerated() {
            let sign: Float = i == 0 ? 1 : -1
            let phase = HomerunFaceMark.pulse(since: now.timeIntervalSinceReferenceDate + (i == 0 ? 0 : 0.5 / HomerunFaceMark.twinkleRate),
                                              rate: HomerunFaceMark.twinkleRate, depth: HomerunFaceMark.twinkleDepth)
            s.position = top + side * (sign * HomerunFaceMark.sparkleSide) + up * HomerunFaceMark.sparkleLift * (i == 0 ? 1 : 0.4)
            s.scale = SIMD3(repeating: HomerunFaceMark.sparkleSize(back: true) * phase * (i == 0 ? 1 : 0.8))
            Self.faceCamera(s, camera: camera)
            s.isEnabled = true
        }
    }

    /// 記号の +z をカメラへ向ける（上はなるべく世界の上）。
    private static func faceCamera(_ e: ModelEntity, camera: SIMD3<Float>) {
        let at = e.position(relativeTo: nil)
        let z = simd_normalize(camera - at)
        let x = simd_normalize(simd_cross([0, 1, 0], z))
        let y = simd_cross(z, x)
        e.setOrientation(simd_quatf(simd_float3x3(x, y, z)), relativeTo: nil)
    }

    /// クリップ時刻 `clipTime`・回転と傾き `turn` のときに置き直す。`camera` は描画のカメラの位置（世界座標）。
    func apply(clipTime t: TimeInterval, turn: simd_quatf, back: Bool, camera: SIMD3<Float>) {
        hideMarks()
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

    /// 怒りマーク（xy 面・外側の半径 1・両面）: 4 本の太い弧が、中心を空けて十字の隙間を挟み向かい合う。`grow` は縁取り用の太らせ幅。
    private static func angryMark(grow: Float, segments: Int = 8) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let z: Float = grow > 0 ? -0.05 : 0
        // 弧の中心は四隅の外側。弧が中心側を向いて凹む（怒りマークの形）。
        let centerOffset: Float = 1.05, radius: Float = 0.95, width: Float = 0.30 + grow * 2
        for corner in 0..<4 {
            let base = Float(corner) * .pi / 2 + .pi / 4
            let c: SIMD3<Float> = [centerOffset * cos(base), centerOffset * sin(base), z]
            // 中心の向き（base + π）を軸に ±35°。
            let facing = base + .pi
            let first = UInt32(positions.count)
            for i in 0...segments {
                let a = facing - 0.61 + 1.22 * Float(i) / Float(segments)
                let outer = radius + width / 2, inner = radius - width / 2
                positions.append(c + [outer * cos(a), outer * sin(a), 0])
                positions.append(c + [inner * cos(a), inner * sin(a), 0])
            }
            for i in 0..<segments {
                let o0 = first + UInt32(i * 2), i0 = o0 + 1, o1 = o0 + 2, i1 = o0 + 3
                indices += [o0, i0, o1, o1, i0, o0, i0, i1, o1, o1, i1, i0]
            }
        }
        var d = MeshDescriptor(name: "angryMark")
        d.positions = MeshBuffer(positions)
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateBox(size: 1)
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
