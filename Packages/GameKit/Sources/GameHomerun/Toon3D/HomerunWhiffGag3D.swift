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
    /// 怒りマーク（#1797）: 吹き出し（白地・輪郭・尾）と中の 💢 を 1 つの根にまとめる。根を脈打たせ弾ませる。
    private var angry: Entity?
    /// 怒りが溜まった段階②: 顔の赤い円・両頬・湯気（左右の塊 = 小さな円 3 つ）。
    private var flush: [ModelEntity] = []
    private var steam: [Entity] = []

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
        angry = Self.makeAngryBubble(rim: rim)
        entity.addChild(angry!)
        let redTint = { (opacity: Float) -> UnlitMaterial in
            var m = UnlitMaterial(color: HomerunPlatformColor(red: 0.95, green: 0.18, blue: 0.14, alpha: 1))
            m.blending = .transparent(opacity: .init(floatLiteral: opacity))
            return m
        }
        let flushDisc = Self.disc(radius: 1, segments: 32)
        for opacity in [HomerunFaceMark.flushOpacity, HomerunFaceMark.cheekOpacity, HomerunFaceMark.cheekOpacity] {
            let d = ModelEntity(mesh: flushDisc, materials: [redTint(opacity)])
            entity.addChild(d)
            flush.append(d)
        }
        let steamWhite = UnlitMaterial(color: HomerunPlatformColor(red: 0.97, green: 0.97, blue: 1, alpha: 1))
        let puff = Self.disc(radius: 1, segments: 24)
        for _ in 0..<2 {
            let cluster = Entity()
            // 「プンッ」と弾ける 3 つの丸（大きい 1 つと小さい 2 つ）。輪郭は黒の縁（少し大きい円を後ろに）。
            for (offset, r) in [(SIMD3<Float>(0, 0, 0), Float(1)), ([0.9, 0.45, 0], 0.6), ([-0.8, 0.55, 0], 0.5)] as [(SIMD3<Float>, Float)] {
                let body = ModelEntity(mesh: puff, materials: [steamWhite])
                body.position = offset
                body.scale = SIMD3(repeating: r)
                let edge = ModelEntity(mesh: puff, materials: [rim])
                edge.position = [0, 0, -0.02]
                edge.scale = SIMD3(repeating: 1.2)
                body.addChild(edge)
                cluster.addChild(body)
            }
            entity.addChild(cluster)
            steam.append(cluster)
        }
        hideMarks()
        isEnabled = false
    }

    private func hideMarks() {
        for e in sparkleEyes + sparkles + flush { e.isEnabled = false }
        for e in steam { e.isEnabled = false }
        angry?.isEnabled = false
    }

    private func hideGag() {
        for e in eyes + stars { e.isEnabled = false }
    }

    /// 結果の記号（キラキラ目・怒りマーク）を置く。回って倒れる演出ではない振りの間に毎コマ呼ぶ。`poseClip` は頭の骨の置き場所を
    /// 引くクリップ時刻（フォロースルーの最後のコマで止める）、`animClip` は出始め・明滅を数える時刻（止まった後も進める）。
    func applyMark(_ mark: HomerunFaceMark, poseClip: TimeInterval, animClip: TimeInterval, camera: SIMD3<Float>) {
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
        case .none, .waitingSparkle, .waitingAngry, .waitingAngryHot:
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
                s.scale = SIMD3(repeating: max(grow * HomerunFaceMark.sparkleSize * phase * (i == 0 ? 1 : 0.8), 0.0001))
                Self.faceCamera(s, camera: camera)
                s.isEnabled = true
            }
        }
    }

    /// 構えのキラキラ目（#1762）: 左右の目の上に星を置く。`poseClip` は構え・踏み込みの頭の骨を引くクリップ時刻、`now` は明滅の位相。
    func applyWaitingEyes(poseClip: TimeInterval, now: Date) {
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
    }

    /// 構えの怒りマーク（#1769・#1797）: 頭の左横に吹き出しを置き、脈打たせて弾ませる。`hot` なら顔の赤みと湯気も出す（段階②）。
    /// `poseClip` は構え・踏み込みの頭の骨を引くクリップ時刻、`now` は動きの位相。
    func applyWaitingAngry(poseClip: TimeInterval, now: Date, camera: SIMD3<Float>, hot: Bool = false) {
        hideGag()
        hideMarks()
        guard let a = angry else { return }
        let head = HomerunWhiffGag.preSwingHead(atClipTime: poseClip)
        let top = head.position + head.rotation.act(HomerunWhiffGag.headTop)
        let up = simd_normalize(head.rotation.act(HomerunWhiffGag.headUp))
        // 頭の位置は打者の局所なので、カメラ（世界）も局所へ直してから横を決める。
        let toCamera = simd_normalize(entity.convert(position: camera, from: nil) - top)
        let side = simd_normalize(simd_cross(up, toCamera))   // カメラから見て右
        let t = now.timeIntervalSinceReferenceDate
        let pulse = HomerunFaceMark.pulse(since: t, rate: HomerunFaceMark.angryPulseRate, depth: HomerunFaceMark.angryPulseDepth)
        a.position = top - side * HomerunFaceMark.angrySide + toCamera * HomerunFaceMark.angryForward
            + up * (HomerunFaceMark.angryLift + HomerunFaceMark.angryBounce(since: t))
        a.scale = SIMD3(repeating: max(HomerunFaceMark.angryBubbleRadius * pulse, 0.0001))
        Self.faceCamera(a, camera: camera)
        a.isEnabled = true
        guard hot else { return }
        // 顔の赤み: 顔の円と両頬を、頭の骨の局所に貼る（顔の外 = +z）。
        let spots: [(SIMD3<Float>, Float)] = [
            (HomerunFaceMark.flushCenter, HomerunFaceMark.flushRadius),
            ([-HomerunFaceMark.cheekOffset.x, HomerunFaceMark.cheekOffset.y, HomerunFaceMark.cheekOffset.z], HomerunFaceMark.cheekRadius),
            (HomerunFaceMark.cheekOffset, HomerunFaceMark.cheekRadius),
        ]
        for (i, d) in flush.enumerated() {
            d.position = head.position + head.rotation.act(spots[i].0)
            d.orientation = head.rotation
            d.scale = SIMD3(repeating: spots[i].1)
            d.isEnabled = true
        }
        // 湯気: 左右の塊が時間をずらして「プンッ」と弾け、少し立ち上って消える。
        for (i, cluster) in steam.enumerated() {
            let sign: Float = i == 0 ? -1 : 1
            let phase = t / HomerunFaceMark.steamPeriod + (i == 0 ? 0 : 0.5)
            let puff = HomerunFaceMark.steamPuff(phase: phase)
            let p = Float(phase - phase.rounded(.down))
            cluster.position = top + side * (sign * HomerunFaceMark.steamSide) + up * (HomerunFaceMark.steamLift + HomerunFaceMark.steamRise * p)
                + toCamera * HomerunFaceMark.angryForward
            cluster.scale = SIMD3(repeating: max(HomerunFaceMark.steamSize * puff, 0.0001))
            Self.faceCamera(cluster, camera: camera)
            cluster.isEnabled = puff > 0.001
        }
    }

    /// 記号の +z をカメラへ向ける（上はなるべく世界の上）。
    private static func faceCamera(_ e: Entity, camera: SIMD3<Float>) {
        let at = e.position(relativeTo: nil)
        let z = simd_normalize(camera - at)
        let x = simd_normalize(simd_cross([0, 1, 0], z))
        let y = simd_cross(z, x)
        e.setOrientation(simd_quatf(simd_float3x3(x, y, z)), relativeTo: nil)
    }

    /// クリップ時刻 `clipTime`・回転と傾き `turn` のときに置き直す。`camera` は描画のカメラの位置（世界座標）。
    func apply(clipTime t: TimeInterval, turn: simd_quatf, camera: SIMD3<Float>) {
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
            * HomerunWhiffGag.starSize
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

    /// 吹き出し（半径 1）とその中の 💢 の根。白地・黒の輪郭・頭の方（+x）へ向く尾。奥から 輪郭 → 白地 → 💢 の順に重ねる。
    private static func makeAngryBubble(rim: UnlitMaterial) -> Entity {
        let white = UnlitMaterial(color: HomerunPlatformColor(red: 1, green: 1, blue: 1, alpha: 1))
        let red = UnlitMaterial(color: HomerunPlatformColor(red: 0.92, green: 0.15, blue: 0.12, alpha: 1))
        let grow = 1 + HomerunFaceMark.angryBubbleRim
        let tip = HomerunFaceMark.angryTailTip
        let root = Entity()
        func layer(_ mesh: MeshResource, _ material: UnlitMaterial, z: Float) {
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.position = [0, 0, z]
            root.addChild(e)
        }
        layer(polygon(bubbleOutline(grow: grow, tip: tip, tipGrow: HomerunFaceMark.angryBubbleRim)), rim, z: -0.04)
        layer(polygon(bubbleOutline(grow: 1, tip: tip, tipGrow: 0)), white, z: 0)
        let scale = HomerunFaceMark.angrySize / HomerunFaceMark.angryBubbleRadius
        let mark = ModelEntity(mesh: angryStrokesMesh(), materials: [red])
        mark.position = [0, 0, 0.04]
        mark.scale = SIMD3(repeating: scale)
        root.addChild(mark)
        return root
    }

    /// 吹き出しの輪郭（凸でなくなるので扇ではなく三角形の集合で作る）: 円 + 尾。尾は円の右下から先端 `tip` へ。
    /// 返すのは三角形の頂点列（3 つずつ）。`grow` は円の半径、`tipGrow` は輪郭用に尾を太らせる幅。
    private static func bubbleOutline(grow: Float, tip: SIMD2<Float>, tipGrow: Float, segments: Int = 40) -> [SIMD2<Float>] {
        var tris: [SIMD2<Float>] = []
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi, a1 = Float(i + 1) / Float(segments) * 2 * .pi
            tris += [.zero, SIMD2(cos(a0), sin(a0)) * grow, SIMD2(cos(a1), sin(a1)) * grow]
        }
        // 尾: 円の内側に潜る 2 点（-40°・+5°）と先端。輪郭は先端を外へ、根元を広げて太らせる。
        let b0 = SIMD2<Float>(cos(-0.7), sin(-0.7)) * 0.9, b1 = SIMD2<Float>(cos(0.09), sin(0.09)) * 0.9
        let k = 1 + tipGrow
        tris += [b0 * k, b1 * k, tip * k]
        return tris
    }

    /// 三角形の頂点列（xy 面・両面）。
    private static func polygon(_ triangles: [SIMD2<Float>]) -> MeshResource {
        var d = MeshDescriptor(name: "angryBubble")
        d.positions = MeshBuffer(triangles.map { SIMD3<Float>($0.x, $0.y, 0) })
        var indices: [UInt32] = []
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let a = UInt32(i)
            indices += [a, a + 1, a + 2, a + 2, a + 1, a]
        }
        d.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [d])) ?? .generateBox(size: 1)
    }

    /// 💢（xy 面・外側の半径 1・両面）: 太さ一定・端が丸い「く」の字 4 本。腕 2 本の帯と、曲がり角・先の丸い端（円）を重ねる。
    private static func angryStrokesMesh(capSegments: Int = 14) -> MeshResource {
        let half = HomerunFaceMark.angryStrokeWidth / 2
        var tris: [SIMD2<Float>] = []
        func disc(_ c: SIMD2<Float>) {
            for i in 0..<capSegments {
                let a0 = Float(i) / Float(capSegments) * 2 * .pi, a1 = Float(i + 1) / Float(capSegments) * 2 * .pi
                tris += [c, c + SIMD2(cos(a0), sin(a0)) * half, c + SIMD2(cos(a1), sin(a1)) * half]
            }
        }
        for stroke in HomerunFaceMark.angryStrokes {
            disc(stroke.corner)
            for tip in stroke.tips {
                disc(tip)
                let dir = simd_normalize(tip - stroke.corner)
                let n = SIMD2(-dir.y, dir.x) * half
                tris += [stroke.corner + n, stroke.corner - n, tip + n, tip + n, stroke.corner - n, tip - n]
            }
        }
        return polygon(tris)
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
