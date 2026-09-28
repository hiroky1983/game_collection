#if canImport(RealityKit)
import Foundation
import RealityKit

/// Meshy で作った 3D の打者おじさん（試作）。`Resources/HomerunBatter.usdz` を読み、打席の打者と打席前のおじさんに使う。
///
/// 素材は Blender で作った 1 本の右打ちスイング（IK を焼き込み、会長決裁の速め方で 44 コマ = 約 1.43 秒に詰めたもの）。
/// バットは右手の骨の子の骨「Bat」に 100% で付いている。輪郭線は同じ骨で動く反転ハル（`Outline`）。
/// 向き: 構え（1 コマ目）で**胸が +z・左肩（投手側）が +x**、足元が y = 0、身長 1.72m。
///
/// マテリアルは読み込み後に `UnlitMaterial` へ置き換える（テクスチャの色をそのまま出す = 陰影ランプの
/// トゥーン調の球場と同じ「光に左右されない」塗り。PBR のままだと照明しだいで暗く沈む）。
@MainActor
enum HomerunBatterAsset {
    nonisolated static let resourceName = "HomerunBatter"
    /// パッケージの素材の中の USDZ。
    nonisolated static var url: URL? { Bundle.module.url(forResource: resourceName, withExtension: "usdz") }
    /// テクスチャの色に掛ける明るさ（球場の陰影ランプの明るい段に合わせて少しだけ落とす）。
    static let textureBrightness: CGFloat = 0.96

    private static var template: Entity?
    private static var didTryLoading = false

    /// 読み込んだ原本の複製（読めなければ nil → 呼び出し側は旧モデルに落とす）。
    static func makeEntity() -> Entity? {
        if !didTryLoading {
            didTryLoading = true
            if let e = try? Entity.load(named: resourceName, in: .module) {
                unlitMaterials(e)
                template = e
            }
        }
        return template?.clone(recursive: true)
    }

    private static func unlitMaterials(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map(unlit)
            entity.components.set(model)
        }
        for child in entity.children { unlitMaterials(child) }
    }

    private static func unlit(_ material: any Material) -> any Material {
        guard let pbr = material as? PhysicallyBasedMaterial else { return material }
        var m = UnlitMaterial()
        if let texture = pbr.baseColor.texture {
            let b = textureBrightness
            m.color = .init(tint: HomerunPlatformColor(red: b, green: b, blue: b, alpha: 1), texture: texture)
        } else {
            m.color = .init(tint: pbr.baseColor.tint)
        }
        return m
    }
}

/// 打者の動きの段階（試作）。1 本のスイングを 3 つに切って使う。
///
/// USDZ のスイングは、1〜20 コマ目（0.63 秒）が**踏み込み**（バットはほとんど動かない）、21〜30 コマ目で振り抜き、
/// 31〜44 コマ目がフォロースルー。離した瞬間に頭から流すと、バットが動き出すのが 0.67 秒後になり、
/// その前に結果（外野カメラ・次の球）へ切り替わって「振らない」ように見える（会長 QA 2026-09-28）。
/// そこで踏み込みは投球中（輪が的に重なる 0.63 秒前から）に流し、離した瞬間は振り抜きから流す。
enum HomerunBatterMotion: Equatable {
    /// 構え（1 コマ目で止める）。
    case stance
    /// 踏み込み（1〜20 コマ目を流して止める）。
    case load
    /// 振り抜き〜フォロースルー（20 コマ目から最後まで流して止める）。値は振った回数（変わるたびに頭から）。
    case swing(Int)

    /// 踏み込みの長さ（秒・20 コマ目 = 19/30 秒）。振り抜きはここから始まる。
    static let loadDuration: TimeInterval = 19.0 / 30

    /// 投球中の経過（`HomerunModel.pitchElapsed`）から、構えか踏み込みかを決める。輪が的に重なる（`travel` 秒）ときに
    /// 踏み込み終わるように、その `loadDuration` 秒前から踏み込む。
    static func beforeSwing(elapsed: TimeInterval?, travel: TimeInterval) -> HomerunBatterMotion {
        guard let elapsed, elapsed >= travel - loadDuration else { return .stance }
        return .load
    }
}

/// 打者 1 人ぶんの実体と動きの再生（どの段階も 1 回だけ流して最後のコマで止める）。
@MainActor
final class HomerunBatterRig {
    let entity: Entity
    private let stanceAnimation: AnimationResource?
    private let loadAnimation: AnimationResource?
    private let swingAnimation: AnimationResource?
    private var controller: AnimationPlaybackController?

    /// スイング 1 本（踏み込み〜フォロースルー）の長さ（秒）。
    let fullDuration: TimeInterval

    init?() {
        guard let e = HomerunBatterAsset.makeEntity() else { return nil }
        entity = e
        // 再生は読み込んだ根の実体の「default subtree animation」（骨の動き 1 本）で行う。
        guard let source = e.availableAnimations.first?.definition else { return nil }
        fullDuration = source.duration
        func segment(_ start: TimeInterval, _ end: TimeInterval) -> AnimationResource? {
            var d = source.trimmed(start: start, end: end)
            d.fillMode = .forwards
            return try? AnimationResource.generate(with: d)
        }
        stanceAnimation = segment(0, 1.0 / 60)
        loadAnimation = segment(0, HomerunBatterMotion.loadDuration)
        swingAnimation = segment(HomerunBatterMotion.loadDuration, source.duration)
        show(.stance)
    }

    /// 段階を切り替える（呼ぶたびにその段階を頭から流す）。
    func show(_ motion: HomerunBatterMotion) {
        let animation: AnimationResource?
        switch motion {
        case .stance: animation = stanceAnimation
        case .load: animation = loadAnimation
        case .swing: animation = swingAnimation
        }
        controller?.stop()
        controller = animation.map { entity.playAnimation($0, transitionDuration: 0, startsPaused: false) }
    }
}
#endif
