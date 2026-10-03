#if canImport(RealityKit)
import Foundation
import RealityKit

/// Meshy で作った 3D の打者おじさん（試作）。`Resources/HomerunBatter.usdz` を読み、打席の打者と打席前のおじさんに使う。
///
/// 素材は Blender で作った 1 本の右打ちスイング（IK を焼き込み、会長決裁の速め方で 44 コマ = 約 1.43 秒に詰めたもの）。
/// その後ろ（45 コマ目〜）に、空振りで回って倒れる演出（#1681・`HomerunWhiffGag`）の動きを同じクリップの続きとして足してある。
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
///
/// 実体の組み立て: `entity`（置き場所・向きは呼び出し側）→ 回転の支点 → 読み込んだモデル（支点の分だけ戻して置く）。
/// 支点は空振りの演出（#1681）で体全体を回す・後ろへ傾けるためだけのもので、ふだんは向きを変えない。
@MainActor
final class HomerunBatterRig {
    let entity: Entity
    /// 読み込んだモデル（骨の動きはここで流す）。
    private let model: Entity
    /// 回転・傾きの支点（`HomerunWhiffGag.pivot`）。
    private let turnPivot = Entity()
    private let stanceAnimation: AnimationResource?
    private let loadAnimation: AnimationResource?
    private let swingAnimation: AnimationResource?
    /// 空振りの演出（20 コマ目〜最後のコマ）。
    private let whiffGagAnimation: AnimationResource?
    private var controller: AnimationPlaybackController?
    /// 本番の振りで速めに流している間の予定（`HomerunBatterMotion.swingOffset`）。追いついたら nil。
    private var catchUp: (start: Date, from: Date)?
    /// いま流している段階。
    private(set) var motion: HomerunBatterMotion = .stance
    /// ぐるぐる目・頭上の星（演出で初めて要るときに作る）。
    private var whiffGagOverlay: HomerunWhiffGagOverlay?

    /// スイング 1 本（踏み込み〜フォロースルー・44 コマ）の長さ（秒）。
    let fullDuration: TimeInterval = HomerunBatPath.duration
    /// 素材のクリップ全体（スイング + 空振りの演出）の長さ（秒）。
    let clipDuration: TimeInterval

    init?() {
        guard let e = HomerunBatterAsset.makeEntity() else { return nil }
        model = e
        entity = Entity()
        entity.addChild(turnPivot)
        turnPivot.position = HomerunWhiffGag.pivot
        turnPivot.addChild(e)
        e.position = -HomerunWhiffGag.pivot
        // 再生は読み込んだ根の実体の「default subtree animation」（骨の動き 1 本）で行う。
        guard let source = e.availableAnimations.first?.definition else { return nil }
        clipDuration = source.duration
        func segment(_ start: TimeInterval, _ end: TimeInterval) -> AnimationResource? {
            var d = source.trimmed(start: start, end: min(end, source.duration))
            d.fillMode = .forwards
            return try? AnimationResource.generate(with: d)
        }
        stanceAnimation = segment(0, 1.0 / 60)
        loadAnimation = segment(0, HomerunBatterMotion.loadDuration)
        swingAnimation = segment(HomerunBatterMotion.loadDuration, HomerunBatPath.duration)
        whiffGagAnimation = source.duration > HomerunWhiffGag.clipEnd - 0.01
            ? segment(HomerunBatterMotion.loadDuration, HomerunWhiffGag.clipEnd) : nil
        // 振り抜きの初回再生の準備コストを打席の前に払っておく（最初の 1 球だけ当たる瞬間の描画が 0.1 秒ほど止まった）。
        for animation in [loadAnimation, swingAnimation, whiffGagAnimation] {
            if let animation { model.playAnimation(animation, transitionDuration: 0, startsPaused: true).stop() }
        }
        show(.stance, now: Date())
    }

    /// 段階を切り替える（呼ぶたびにその段階を頭から流す）。振り抜きは `start`（20 コマ目を置く実時刻）が `now` より前なら
    /// その分だけ進めた所から流す（離した瞬間に打点のコマへ合わせ直すため）。踏み込みも `start`（1 コマ目の実時刻）が
    /// 過去ならその分だけ進める（素振りの振り抜きから戻ったとき）。空振りの演出は振り抜きと同じ流し方で最後のコマまで。
    func show(_ motion: HomerunBatterMotion, now: Date) {
        controller?.stop()
        catchUp = nil
        self.motion = motion
        whiffGagClipTime = nil
        tankobuPose = nil
        switch motion {
        case .stance:
            controller = stanceAnimation.map { model.playAnimation($0, transitionDuration: 0, startsPaused: false) }
        case .load(let start):
            controller = loadAnimation.map { model.playAnimation($0, transitionDuration: 0, startsPaused: false) }
            let ahead = now.timeIntervalSince(start)
            if ahead > 0 { controller?.time = min(ahead, HomerunBatterMotion.loadDuration) }
        case .swing(let start, let catchUpFrom), .whiffGag(let start, let catchUpFrom), .tankobu(let start, let catchUpFrom):
            let animation = isWhiffGag || isTankobu ? (whiffGagAnimation ?? swingAnimation) : swingAnimation
            controller = animation.map { model.playAnimation($0, transitionDuration: 0, startsPaused: false) }
            let ahead = HomerunBatterMotion.swingOffset(start: start, catchUpFrom: catchUpFrom, at: now)
            if ahead > 0 { controller?.time = min(ahead, segmentLength) }
            if let from = catchUpFrom, ahead < now.timeIntervalSince(start) {
                catchUp = (start, from)
                controller?.speed = Float(HomerunBatterMotion.catchUpSpeed)
            }
        }
        if !isWhiffGag { turnPivot.orientation = simd_quatf(angle: 0, axis: [0, 1, 0]) }
        if !isTankobu { turnPivot.position = HomerunWhiffGag.pivot }
        whiffGagOverlay?.isEnabled = isWhiffGag
    }

    /// 毎コマ呼ぶ。速めに流している振りが予定に追いついたら等速に戻す。
    /// `clockHeld`（ジャストミートの演出・#1775）: `now` が実時刻より遅れている間は、再生に任せず振りの再生位置を毎コマ `now` から
    /// 決め直す（再生は実時間で進むので、止めた時間の中でも振りが先へ進んでしまう）。
    func tick(now: Date, clockHeld: Bool = false) {
        if clockHeld, case .swing(let start, let catchUpFrom) = motion, let controller {
            catchUp = nil
            controller.speed = 0
            controller.time = min(HomerunBatterMotion.swingOffset(start: start, catchUpFrom: catchUpFrom, at: now), segmentLength)
            return
        }
        // たんこぶ（#1793）は振り終わり以降の再生位置を `applyTankobu` が毎コマ決める。
        if case .tankobu(let start, let from) = motion,
           HomerunBatterMotion.swingOffset(start: start, catchUpFrom: from, at: now) >= HomerunBatterMotion.swingDuration { return }
        guard let catchUp, let controller else { return }
        let scheduled = now.timeIntervalSince(catchUp.start)
        if controller.time >= scheduled {
            controller.speed = 1
            controller.time = min(scheduled, segmentLength)
            self.catchUp = nil
        }
    }

    /// いま流している振り（振り抜き〜）の段の長さ（秒・20 コマ目から）。
    private var segmentLength: TimeInterval {
        ((isWhiffGag || isTankobu) && whiffGagAnimation != nil ? HomerunWhiffGag.clipEnd : fullDuration) - HomerunBatterMotion.loadDuration
    }

    var isTankobu: Bool {
        if case .tankobu = motion { return true }
        return false
    }

    /// たんこぶの演出の間に毎コマ呼ぶ（#1793）: 振り終わりで球を待ち、頭に当たったら尻もちのクリップへ移し、座る位置を本塁から外し、
    /// ヘルメットの上のたんこぶを膨らませ、座ってからはぐるぐる目・星を出す。骨の再生位置は予定（`HomerunTankobuGag.segmentTime`）から
    /// 毎コマ決める（再生を終えた後の `controller.time` は読まない・`applyWhiffGag` と同じ）。
    func applyTankobu(now: Date, camera: SIMD3<Float>) {
        guard case .tankobu(let start, let catchUpFrom) = motion else { return }
        let offset = HomerunBatterMotion.swingOffset(start: start, catchUpFrom: catchUpFrom, at: now)
        let e = HomerunTankobuGag.effective(offset)
        let segment = HomerunTankobuGag.segmentTime(effective: e)
        if offset >= HomerunBatterMotion.swingDuration, let controller {
            catchUp = nil
            controller.speed = 0
            controller.time = min(segment, segmentLength)
        }
        let clip = HomerunBatterMotion.loadDuration + min(segment, segmentLength)
        let correction = HomerunTankobuGag.sitCorrection(effective: e)
        tankobuPose = (clip, correction)
        whiffGagClipTime = nil
        turnPivot.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        turnPivot.position = HomerunWhiffGag.pivot + correction
        if whiffGagOverlay == nil {
            let overlay = HomerunWhiffGagOverlay()
            entity.addChild(overlay.entity)
            whiffGagOverlay = overlay
        }
        whiffGagOverlay?.isEnabled = true
        // 目・星は座りきった後も回し続ける（骨のクリップは最後のコマで止める）。
        whiffGagOverlay?.applyTankobu(clipTime: HomerunTankobuGag.overlayClipTime(effective: e), since: e - HomerunTankobuGag.impactDelay,
                                      correction: correction, camera: camera)
    }

    var isWhiffGag: Bool {
        if case .whiffGag = motion { return true }
        return false
    }

    /// 空振りの演出の間に毎コマ呼ぶ: 骨の再生位置に合わせて体全体を回し・傾け、ぐるぐる目と頭上の星を置く。
    /// `camera` は描画のカメラの位置（星をカメラへ向ける）。
    func applyWhiffGag(now: Date, camera: SIMD3<Float>) {
        guard case .whiffGag(let start, let catchUpFrom) = motion else { return }
        // 骨の再生位置は流し方の予定（速めに流す振り抜きの頭を含む）から決める。再生を終えた後の `controller.time` は
        // 最後のコマに留まらない（頭に戻る）ので読まない（読むと座った後に回転だけ外れて体が飛んだ・シミュレータの録画で確認）。
        let clip = HomerunBatterMotion.loadDuration
            + min(HomerunBatterMotion.swingOffset(start: start, catchUpFrom: catchUpFrom, at: now), segmentLength)
        whiffGagClipTime = clip
        let turn = HomerunWhiffGag.turn(atClipTime: clip)
        turnPivot.orientation = turn
        // 目・星は止まった後も回し続けるので、最後のコマで止めずに実時刻から数える。
        let overlayClip = HomerunBatterMotion.loadDuration + max(now.timeIntervalSince(start), clip - HomerunBatterMotion.loadDuration)
        if whiffGagOverlay == nil {
            let overlay = HomerunWhiffGagOverlay()
            entity.addChild(overlay.entity)
            whiffGagOverlay = overlay
        }
        whiffGagOverlay?.isEnabled = true
        whiffGagOverlay?.apply(clipTime: overlayClip, turn: HomerunWhiffGag.turn(atClipTime: overlayClip), camera: camera)
    }

    /// 結果に応じて頭に重ねる記号（#1760）。モデルが決めた値を毎コマの更新で受け取る。振っていない間（構え・踏み込み）は出さない。
    var faceMark: HomerunFaceMark = .none {
        // 結果が閉じても素振りの段階が続くことがある。前の球の記号を残さない（結果の記号から構えの記号に替わった素振り中も同じ）（空振りの演出の間は演出を消さない）。
        didSet { if !showsFaceMark, !isWhiffGag, !isTankobu { whiffGagOverlay?.isEnabled = false } }
    }

    /// 記号を毎コマ置くか（回って倒れる演出の間は演出のぐるぐる目・星を優先して置かない）。
    var showsFaceMark: Bool {
        guard faceMark != .none, !isWhiffGag, !isTankobu else { return false }
        switch motion {
        case .swing: return !faceMark.isWaiting
        case .stance, .load: return faceMark.isWaiting
        case .whiffGag, .tankobu: return false
        }
    }

    /// 結果の記号（キラキラ目・怒りマーク）を置く。頭の骨は振り抜きのフォロースルーの最後のコマで止め、出始め・明滅は実時刻から数える。
    func applyFaceMark(now: Date, camera: SIMD3<Float>) {
        if faceMark.isWaiting { applyWaitingMark(now: now, camera: camera); return }
        guard case .swing(let start, let catchUpFrom) = motion else { return }
        let segment = fullDuration - HomerunBatterMotion.loadDuration
        let offset = HomerunBatterMotion.swingOffset(start: start, catchUpFrom: catchUpFrom, at: now)
        let poseClip = HomerunBatterMotion.loadDuration + min(offset, segment)
        let animClip = HomerunBatterMotion.loadDuration + max(now.timeIntervalSince(start), min(offset, segment))
        if whiffGagOverlay == nil {
            let overlay = HomerunWhiffGagOverlay()
            entity.addChild(overlay.entity)
            whiffGagOverlay = overlay
        }
        whiffGagOverlay?.isEnabled = true
        whiffGagOverlay?.applyMark(faceMark, poseClip: poseClip, animClip: animClip, camera: camera)
    }

    /// 構えのキラキラ目（#1762）を置く。構えは 1 コマ目で止まり、踏み込みは 1〜20 コマ目を実時刻から数える。
    private func applyWaitingMark(now: Date, camera: SIMD3<Float>) {
        let clip: TimeInterval
        switch motion {
        case .stance: clip = 0
        case .load(let start): clip = min(max(now.timeIntervalSince(start), 0), HomerunBatterMotion.loadDuration)
        default: return
        }
        if whiffGagOverlay == nil {
            let overlay = HomerunWhiffGagOverlay()
            entity.addChild(overlay.entity)
            whiffGagOverlay = overlay
        }
        whiffGagOverlay?.isEnabled = true
        if faceMark == .waitingAngry {
            whiffGagOverlay?.applyWaitingAngry(poseClip: clip, now: now, camera: camera)
        } else if faceMark == .waitingLump {
            whiffGagOverlay?.applyWaitingLump(poseClip: clip, now: now)
        } else {
            whiffGagOverlay?.applyWaitingEyes(poseClip: clip, now: now)
        }
    }

    /// たんこぶの演出（#1793）の、最後に置き直したときのクリップ時刻（秒）と座る位置の補正（打者の局所）。演出でなければ nil。影もこれに合わせる。
    private(set) var tankobuPose: (clip: TimeInterval, correction: SIMD3<Float>)?
    /// いまの支点の位置。テスト用。
    var pivotPosition: SIMD3<Float> { turnPivot.position }

    /// 空振りの演出の、最後に置き直したときのクリップ時刻（秒・`applyWhiffGag`）。演出でなければ nil。影もこれに合わせる。
    private(set) var whiffGagClipTime: TimeInterval?

    /// 振り抜き（空振りの演出を含む）のクリップ時刻（秒・20 コマ目 = 19/30）。振り抜きでなければ nil。
    var swingClipTime: TimeInterval? { controller.map { HomerunBatterMotion.loadDuration + $0.time } }
    /// いま流している段階の頭からの再生位置（秒）。テスト用。
    var playbackTime: TimeInterval? { controller?.time }
    /// いまの回転・傾き（支点の向き）。テスト用。
    var turnOrientation: simd_quatf { turnPivot.orientation }
    /// ぐるぐる目・頭上の星（作っていなければ nil）。テスト用。
    var overlay: HomerunWhiffGagOverlay? { whiffGagOverlay }
}
#endif
