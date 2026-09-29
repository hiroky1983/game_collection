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

/// 打者 1 人ぶんの実体と動きの再生（どの段階も 1 回だけ流して最後のコマで止める）。段階の定義は `HomerunBatterMotion`、
/// 打点の同期は `HomerunSwingContact`（どちらも RealityKit に依らない `HomerunSwingContact.swift`）。
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
        // 振り抜きの初回再生の準備コストを打席の前に払っておく（最初の 1 球だけ当たる瞬間の描画が 0.1 秒ほど止まった）。
        for animation in [loadAnimation, swingAnimation] {
            if let animation { entity.playAnimation(animation, transitionDuration: 0, startsPaused: true).stop() }
        }
        show(.stance, now: Date())
    }

    /// 段階を切り替える（呼ぶたびにその段階を頭から流す）。振り抜きは `start`（20 コマ目を置く実時刻）が `now` より前なら
    /// その分だけ進めた所から流す（離した瞬間に打点のコマへ合わせ直すため）。踏み込みも `start`（1 コマ目の実時刻）が
    /// 過去ならその分だけ進める（素振りの振り抜きから戻ったとき）。
    func show(_ motion: HomerunBatterMotion, now: Date) {
        controller?.stop()
        switch motion {
        case .stance:
            controller = stanceAnimation.map { entity.playAnimation($0, transitionDuration: 0, startsPaused: false) }
        case .load(let start):
            controller = loadAnimation.map { entity.playAnimation($0, transitionDuration: 0, startsPaused: false) }
            let ahead = now.timeIntervalSince(start)
            if ahead > 0 { controller?.time = min(ahead, HomerunBatterMotion.loadDuration) }
        case .swing(let start):
            controller = swingAnimation.map { entity.playAnimation($0, transitionDuration: 0, startsPaused: false) }
            let ahead = now.timeIntervalSince(start)
            if ahead > 0 { controller?.time = min(ahead, fullDuration - HomerunBatterMotion.loadDuration) }
        }
    }

    /// 振り抜きの再生位置（クリップ秒・20 コマ目 = 19/30）。テスト用。
    var swingClipTime: TimeInterval? { controller.map { HomerunBatterMotion.loadDuration + $0.time } }
    /// いま流している段階の頭からの再生位置（秒）。テスト用。
    var playbackTime: TimeInterval? { controller?.time }
}
#endif
