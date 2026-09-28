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

/// 打者 1 人ぶんの実体とスイングの再生。構え = スイングの 1 コマ目で止めた姿勢、スイング = 1 回だけ再生して最後のコマで止める。
@MainActor
final class HomerunBatterRig {
    let entity: Entity
    private let swingAnimation: AnimationResource?
    private let stanceAnimation: AnimationResource?
    private var controller: AnimationPlaybackController?

    /// スイング 1 本の長さ（秒）。
    var swingDuration: TimeInterval { swingAnimation?.definition.duration ?? 0 }

    init?() {
        guard let e = HomerunBatterAsset.makeEntity() else { return nil }
        entity = e
        if let source = e.availableAnimations.first {
            var swing = source.definition
            swing.fillMode = .forwards
            swingAnimation = try? AnimationResource.generate(with: swing)
            var stance = source.definition.trimmed(start: 0, end: 1.0 / 60)
            stance.fillMode = .forwards
            stanceAnimation = try? AnimationResource.generate(with: stance)
        } else {
            swingAnimation = nil
            stanceAnimation = nil
        }
        showStance()
    }

    /// 構え（1 コマ目）で止める。
    func showStance() {
        controller?.stop()
        controller = stanceAnimation.map { entity.playAnimation($0, transitionDuration: 0, startsPaused: false) }
    }

    /// スイングを頭から 1 回再生し、最後のコマで止める。
    func playSwing() {
        controller?.stop()
        controller = swingAnimation.map { entity.playAnimation($0, transitionDuration: 0, startsPaused: false) }
    }
}
#endif
