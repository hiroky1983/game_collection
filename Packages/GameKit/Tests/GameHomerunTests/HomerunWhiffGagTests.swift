import Testing
import Foundation
import simd
import HomerunCore
@testable import GameHomerun
#if canImport(RealityKit)
import RealityKit
#endif

/// 空振りで回って倒れて目を回す演出（#1681）: 発生条件（2 回目は必ず・見送りは除く・約 5 回に 1 回）・間合い（演出の間は次の球を
/// 投げない）・見え方（回転の量・顔の向き・影・目と星）。
@Suite("柵越えおじさんの空振りの演出")
@MainActor
struct HomerunWhiffGagTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// 1 テスト 1 つの UserDefaults のモデル（照準の吸い寄せは切る）。`roll` は演出の乱数。
    private func makeModel(roll: Double = 1, forced: Bool = false) -> HomerunModel {
        let defaults = UserDefaults(suiteName: "HomerunWhiffGagTests.\(UUID())")!
        // 鍵（`debugForceWhiffGagKey`）は `HomerunModel+Debug.swift` の #if DEBUG の中だけの宣言（#1705）。
        #if DEBUG
        defaults.set(forced, forKey: HomerunModel.debugForceWhiffGagKey)
        #endif
        let model = HomerunModel(defaults: defaults, aimAssist: .off, now: Self.t0)
        model.whiffGagRoll = { roll }
        model.start(now: Self.t0)
        model.atBatDidAppear(now: Self.t0)
        return model
    }

    /// 早すぎる空振り（輪の 0.3 秒前に離す）。離した時刻を返す。
    @discardableResult
    private func whiff(_ model: HomerunModel) throws -> Date {
        let release = try #require(model.arrival).addingTimeInterval(-0.3)
        model.press(at: CGPoint(x: 150, y: 600), now: release.addingTimeInterval(-0.2))
        let ball = model.release(at: CGPoint(x: 150, y: 600), now: release)
        #expect(ball?.kind == .miss && model.didSwingLastBall)
        return release
    }

    /// ジャストの当たり。
    private func hit(_ model: HomerunModel) throws {
        let release = try #require(model.arrival)
        model.press(at: CGPoint(x: 150, y: 600), now: release.addingTimeInterval(-0.5))
        let ball = model.ballPoint
        let ballHit = model.release(at: CGPoint(x: 150 + ball.x, y: 600 + ball.y + 4), now: release)
        #expect(ballHit?.kind != .miss)
    }

    /// 見送り（押さずに締め切りを過ぎる）。
    private func take(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.nextWake))
        #expect(model.lastBall?.kind == .miss && !model.didSwingLastBall)
    }

    /// 結果を閉じて次の球へ。
    private func next(_ model: HomerunModel) throws {
        model.advance(now: try #require(model.nextWake))
        #expect(model.phase == .pitching)
    }

    // MARK: 発生

    @Test("2 回目の空振りは必ず、それ以外は乱数が 1/5 未満のときだけ")
    func showsRule() {
        #expect(HomerunWhiffGag.shows(whiffNumber: 2, roll: 0.99))
        for n in [1, 3, 4, 7] {
            #expect(HomerunWhiffGag.shows(whiffNumber: n, roll: 0.0))
            #expect(HomerunWhiffGag.shows(whiffNumber: n, roll: 0.19))
            #expect(!HomerunWhiffGag.shows(whiffNumber: n, roll: 1.0 / 5))
            #expect(!HomerunWhiffGag.shows(whiffNumber: n, roll: 0.9))
        }
        // 乱数が一様なら空振り（2 回目以外）の約 5 回に 1 回。
        let rolls = (0..<3000).map { Double($0) / 3000 }
        let rate = Double(rolls.filter { HomerunWhiffGag.shows(whiffNumber: 1, roll: $0) }.count) / Double(rolls.count)
        #expect(abs(rate - 1.0 / 5) < 0.01)
    }

    @Test("1 挑戦の 2 回目の空振りで必ず出る。見送り・当たりは数えず演出も出さない")
    func secondWhiffIsGuaranteed() throws {
        let model = makeModel(roll: 0.9)
        try take(model)
        #expect(!model.showsWhiffGag && model.whiffCount == 0, "見送りは数えない")
        try next(model)
        try whiff(model)
        #expect(!model.showsWhiffGag && model.whiffCount == 1, "1 回目は乱数しだい（0.9 なら出ない）")
        try next(model)
        try hit(model)
        #expect(!model.showsWhiffGag && model.whiffCount == 1, "当たりは数えない")
        try next(model)
        try take(model)
        #expect(!model.showsWhiffGag)
        try next(model)
        try whiff(model)
        #expect(model.showsWhiffGag && model.whiffCount == 2, "2 回目は必ず")
        try next(model)
        try whiff(model)
        #expect(!model.showsWhiffGag && model.whiffCount == 3, "3 回目は乱数しだい")
    }

    @Test("2 回目以外の空振りは乱数が 1/5 未満なら出る。挑戦をやり直すと数え直す")
    func otherWhiffsUseTheRoll() throws {
        let model = makeModel(roll: 0.1)
        try whiff(model)
        #expect(model.showsWhiffGag && model.whiffCount == 1)
        try next(model)
        // 挑戦をやり直す（一時停止 → やめる → 打席に立つ）と 1 回目から。
        model.pause(now: Date(timeIntervalSince1970: 1_800_000_100))
        model.quitChallenge()
        model.whiffGagRoll = { 0.9 }
        model.start(now: Date(timeIntervalSince1970: 1_800_000_100))
        model.atBatDidAppear(now: Date(timeIntervalSince1970: 1_800_000_100))
        try whiff(model)
        #expect(!model.showsWhiffGag && model.whiffCount == 1)
    }

    // 鍵（`debugForceWhiffGagKey`）は `HomerunModel+Debug.swift` の #if DEBUG の中だけの宣言なので、
    // 鍵の効果そのものを確かめるこのテストも同じく #if DEBUG で囲む（出荷ビルドのテストが壊れないように・#1705）。
    #if DEBUG
    @Test("動作確認の起動引数の鍵が立っていれば、振った空振りは毎回出る（見送りは出ない）")
    func debugKeyForcesGag() throws {
        let model = makeModel(roll: 0.99, forced: true)
        try whiff(model)
        #expect(model.showsWhiffGag)
        try next(model)
        try take(model)
        #expect(!model.showsWhiffGag)
    }
    #endif

    // MARK: 間合い

    @Test("演出の空振りは座りきるまで次の球を投げない（約 4.2 秒）。演出の無い空振りは 1.2 秒のまま")
    func gagHoldsTheNextPitch() throws {
        #expect(abs(HomerunWhiffGag.span - (Double(HomerunWhiffGag.lastFrame - 20) / 30)) < 1e-9)
        #expect(HomerunWhiffGag.resultDuration > 3.5 && HomerunWhiffGag.resultDuration < 4.6, "\(HomerunWhiffGag.resultDuration) 秒")
        let plain = makeModel(roll: 0.9)
        let r1 = try whiff(plain)
        #expect(plain.nextWake == r1.addingTimeInterval(HomerunModel.resultDuration(for: .miss)))

        let model = makeModel(roll: 0.0)
        let release = try whiff(model)
        #expect(model.showsWhiffGag)
        let end = release.addingTimeInterval(HomerunWhiffGag.resultDuration)
        #expect(abs((model.resultEnd ?? .distantPast).timeIntervalSince(end)) < 1e-6 && model.nextWake == model.resultEnd)
        // ふだんの空振りの締め切り（1.2 秒）では閉じない。
        model.advance(now: try #require(model.resultUntil))
        #expect(model.phase == .ballResult)
        model.advance(now: end.addingTimeInterval(-0.01))
        #expect(model.phase == .ballResult)
        // 振り抜きの頭（20 コマ目）は離した時刻より前なので、閉じる時刻には最後のコマを過ぎて座りきっている。
        let plan = HomerunSwingPlan(model: model)
        guard case .whiffGag(let start, _) = plan.batterMotion(at: release) else {
            Issue.record("演出の段階になっていない"); return
        }
        #expect(start <= release)
        #expect(start.addingTimeInterval(HomerunWhiffGag.span + HomerunWhiffGag.endHold) <= end)
        model.advance(now: try #require(model.resultEnd))
        #expect(model.phase == .pitching, "座りきったら次の球")
        // 次の球では構えに戻る（マシンが込めている間は構え）。
        #expect(HomerunSwingPlan(model: model).batterMotion(at: end.addingTimeInterval(0.01)) == .stance)
    }

    @Test("結果のカードは座り込んでから出し、次の球まで 1 秒以上読める。演出の無い空振りは 0.4 秒で出す")
    func cardWaitsUntilSeated() {
        #expect(HomerunAtBatView.swingShowDuration(for: .miss, whiffGag: true) == HomerunWhiffGag.cardDelay)
        #expect(HomerunAtBatView.swingShowDuration(for: .miss, whiffGag: false) == 0.4)
        #expect(HomerunAtBatView.swingShowDuration(for: .homer, whiffGag: true) == HomerunBatterMotion.swingDuration)
        #expect(HomerunWhiffGag.resultDuration - HomerunWhiffGag.cardDelay >= 1.0)
        // カードを出す頃（振り抜きの頭は離した時刻以前なので、クリップはそれ以降）には頭が低い = 座り込んでいる。
        let clip = HomerunBatterMotion.loadDuration + HomerunWhiffGag.cardDelay
        #expect(HomerunWhiffGag.head(atClipTime: clip).position.y < 0.7, "カードを出すとき頭の高さ \(HomerunWhiffGag.head(atClipTime: clip).position.y)")
    }

    @Test("演出の間に離しても素振りにしない（演出を切らない）。演出の無い空振りの結果の間は素振りできる")
    func noPracticeSwingDuringGag() throws {
        let model = makeModel(roll: 0.0)
        let release = try whiff(model)
        let later = release.addingTimeInterval(2)
        model.press(at: CGPoint(x: 150, y: 600), now: later)
        model.release(at: CGPoint(x: 150, y: 600), now: later.addingTimeInterval(0.1))
        #expect(model.ballClock?.practiceSwingAt == nil)
        #expect(HomerunSwingPlan(model: model).batterMotion(at: later.addingTimeInterval(0.2)).isWhiffGag)

        let plain = makeModel(roll: 0.9)
        let r = try whiff(plain)
        plain.press(at: CGPoint(x: 150, y: 600), now: r.addingTimeInterval(0.9))
        plain.release(at: CGPoint(x: 150, y: 600), now: r.addingTimeInterval(1.0))
        #expect(plain.ballClock?.practiceSwingAt == r.addingTimeInterval(1.0))
    }

    @Test("一時停止から戻ると、演出の時間は戻った時刻から数え直す（途中で次の球を投げない）")
    func pauseKeepsTheGagLength() throws {
        let model = makeModel(roll: 0.0)
        let release = try whiff(model)
        model.pause(now: release.addingTimeInterval(1))
        let back = release.addingTimeInterval(10)
        model.resume(now: back)
        #expect(abs((model.resultEnd ?? .distantPast).timeIntervalSince(back.addingTimeInterval(HomerunWhiffGag.resultDuration))) < 1e-6)
    }

    @Test("演出の段階は振り抜きと同じ時刻から始まる（20 コマ目の時刻・速めに流す時刻とも同じ）")
    func planUsesTheSameSwingStart() throws {
        let model = makeModel(roll: 0.0)
        let release = try whiff(model)
        let clock = try #require(model.ballClock)
        var plan = HomerunSwingPlan(phase: model.phase, clock: clock, lastBall: model.lastBall)
        let swing = plan.batterMotion(at: release)
        plan.whiffGag = true
        guard case .swing(let s, let c) = swing, case .whiffGag(let gs, let gc) = plan.batterMotion(at: release) else {
            Issue.record("段階が想定外"); return
        }
        #expect(s == gs && c == gc)
        // 当たりのときは演出の印があっても振り抜きのまま。
        let hitModel = makeModel(roll: 0.0)
        try hit(hitModel)
        var hitPlan = HomerunSwingPlan(model: hitModel)
        hitPlan.whiffGag = true
        #expect(!hitPlan.batterMotion(at: try #require(hitModel.ballClock?.releasedAt)).isWhiffGag)
    }

    // MARK: 見え方（表）

    @Test("体全体の回転は振り抜きの 26 コマ目から始まり、前 約 1.8 回転・後ろ 約 2.3 回転で止まる。傾きは 7° まで")
    func spinAndLean() {
        #expect(HomerunWhiffGag.spinYaw(atClipTime: 25.0 / 30, back: false) == 0)
        let frontEnd = HomerunWhiffGag.spinYaw(atClipTime: HomerunWhiffGag.clipEnd, back: false)
        let backEnd = HomerunWhiffGag.spinYaw(atClipTime: HomerunWhiffGag.clipEnd, back: true)
        #expect(abs(frontEnd / (2 * .pi) - 1.8) < 0.1, "前 \(frontEnd / (2 * .pi)) 回転")
        #expect(abs(backEnd / (2 * .pi) - 2.3) < 0.1, "後ろ \(backEnd / (2 * .pi)) 回転")
        // 回り始めは振りの勢い（毎秒 1000° 超）で、止まる手前は遅い（減速）。
        func speed(_ f: Double) -> Float {
            (HomerunWhiffGag.spinYaw(atClipTime: (f + 0.5 - 1) / 30, back: false) - HomerunWhiffGag.spinYaw(atClipTime: (f - 0.5 - 1) / 30, back: false)) * 30
        }
        #expect(speed(40) > 5, "回っている途中の速さ \(speed(40)) rad/秒")
        #expect(speed(50) > abs(speed(79)), "止まる手前は遅い")
        var maxLean: Float = 0
        for f in stride(from: 1.0, through: Double(HomerunWhiffGag.lastFrame), by: 0.5) {
            let l = HomerunWhiffGag.lean(atClipTime: (f - 1) / 30)
            #expect(l >= 0 && l <= HomerunWhiffGag.leanAngle + 1e-6)
            maxLean = max(maxLean, l)
        }
        #expect(abs(maxLean - HomerunWhiffGag.leanAngle) < 1e-6)
        #expect(HomerunWhiffGag.lean(atClipTime: HomerunWhiffGag.clipEnd) == 0)
        // 傾きは頭が捕手側（世界の −z）へ倒れる向き。
        let up = HomerunAtBatLayout.batterWorld(simd_quatf(angle: HomerunWhiffGag.leanAngle, axis: HomerunWhiffGag.leanAxis).act([0, 1, 0]))
            - HomerunAtBatLayout.batterWorld(.zero)
        #expect(up.z < -0.1 && abs(up.x) < 1e-4)
    }

    @Test("座りきったとき、顔（目の向き）はいまのカメラの側を向く（前 = 前のカメラ・後ろ = 後ろのカメラ。試作と同じく斜め 40° ほど）")
    func faceLooksAtTheCamera() {
        for preset in HomerunAtBatLayout.CameraPreset.allCases {
            let back = preset == .back
            let t = HomerunWhiffGag.clipEnd
            let turn = HomerunWhiffGag.turn(atClipTime: t, back: back)
            let batterTurn = simd_quatf(angle: HomerunAtBatLayout.batter.yaw, axis: [0, 1, 0])
            var face = SIMD3<Float>.zero
            for i in 0..<2 { face += batterTurn.act(HomerunWhiffGag.eyePose(atClipTime: t, index: i, turn: turn).rotation.act([0, 0, 1])) }
            let head = HomerunAtBatLayout.batterWorld(HomerunWhiffGag.place(HomerunWhiffGag.head(atClipTime: t).position, turn: turn))
            let toCamera = preset.camera.renderPose.position - head
            let flatFace = simd_normalize(SIMD2(face.x, face.z)), flatCam = simd_normalize(SIMD2(toCamera.x, toCamera.z))
            #expect(simd_dot(flatFace, flatCam) > 0.65, "\(preset): 顔とカメラの向きの内積 \(simd_dot(flatFace, flatCam)) face \(flatFace) cam \(flatCam)")
        }
    }

    @Test("座った後は腰が地面近く（0.35m 未満）まで下がり、頭のてっぺんの上に星が回る")
    func seatedPose() {
        let t = HomerunWhiffGag.clipEnd
        let turn = HomerunWhiffGag.turn(atClipTime: t, back: false)
        let head = HomerunWhiffGag.head(atClipTime: t)
        #expect(head.position.y < 0.8, "頭の高さ \(head.position.y)")
        let top = HomerunWhiffGag.place(head.position + head.rotation.act(HomerunWhiffGag.headTop), turn: turn)
        for i in 0..<HomerunWhiffGag.starCount {
            let s = HomerunWhiffGag.starCenter(atClipTime: t, index: i, turn: turn)
            #expect(abs(simd_distance(s, top) - (HomerunWhiffGag.starOrbitRadius * HomerunWhiffGag.starOrbitRadius
                                                 + HomerunWhiffGag.starLift * HomerunWhiffGag.starLift).squareRoot()) < 0.01)
        }
        // 星は 3 つが等間隔（120°）。
        let a0 = HomerunWhiffGag.starAngle(atClipTime: t, index: 0), a1 = HomerunWhiffGag.starAngle(atClipTime: t, index: 1)
        #expect(abs((a1 - a0) - 2 * .pi / 3) < 1e-4)
        // 目と星は回り終わる手前から出る（振り抜きの最中には出ない）。
        #expect(HomerunWhiffGag.appear(atClipTime: 40.0 / 30, from: HomerunWhiffGag.eyeInFrame, grow: HomerunWhiffGag.eyeGrow) == 0)
        #expect(HomerunWhiffGag.appear(atClipTime: t, from: HomerunWhiffGag.starInFrame, grow: HomerunWhiffGag.starGrow) == 1)
    }

    @Test("体とバットの影: 振り抜きの頭では振りの影と同じ所、座った後は回転・倒れた体に付いて動く")
    func shadowsFollowTheGag() {
        let origin = HomerunAtBatLayout.batter.position
        let eye = HomerunAtBatLayout.CameraPreset.front.camera.renderPose.position
        let t20 = HomerunBatterMotion.loadDuration
        let plain = HomerunFigureShadow.batter(origin: origin, camera: eye)
        let atStart = HomerunFigureShadow.whiffGagBatter(origin: origin, clipTime: t20, turn: HomerunWhiffGag.turn(atClipTime: t20, back: false), camera: eye)
        #expect(simd_distance(plain.center, atStart.center) < 1e-4)
        let t = HomerunWhiffGag.clipEnd
        let seated = HomerunFigureShadow.whiffGagBatter(origin: origin, clipTime: t, turn: HomerunWhiffGag.turn(atClipTime: t, back: false), camera: eye)
        #expect(simd_distance(seated.center, plain.center) > 0.1, "座った体に影が付いて動かない")
        // 座った体の中心（腰・頭・足の平均）の真下。
        let turn = HomerunWhiffGag.turn(atClipTime: t, back: false)
        let head = HomerunWhiffGag.head(atClipTime: t).position
        let headWorld = HomerunAtBatLayout.batterWorld(HomerunWhiffGag.place(head, turn: turn))
        #expect(simd_distance(SIMD2(seated.center.x, seated.center.z), SIMD2(headWorld.x, headWorld.z)) < 0.8)
        // バット: 26 コマ目（回り始め）までは振りの表と同じ。回った後は回転を掛けた所。
        let t25 = 25.0 / 30
        let a = HomerunFigureShadow.whiffGagBat(clipTime: t25, turn: HomerunWhiffGag.turn(atClipTime: t25, back: false))
        let b = HomerunBatPath.segment(atClipTime: t25)
        #expect(simd_distance(a.grip, b.grip) < 1e-4 && simd_distance(a.tip, b.tip) < 1e-4)
        let late = HomerunFigureShadow.whiffGagBat(clipTime: 60.0 / 30, turn: HomerunWhiffGag.turn(atClipTime: 60.0 / 30, back: false))
        let raw = HomerunWhiffGag.bat(atClipTime: 60.0 / 30)
        #expect(simd_distance(late.tip, raw.tip) > 0.05)
        // 表の振りの部分（44 コマ目まで）は振りの表と同じ骨から測った値。
        let g = HomerunWhiffGag.bat(atClipTime: 30.0 / 30), p = HomerunBatPath.segment(atClipTime: 30.0 / 30)
        #expect(simd_distance(g.grip, p.grip) < 0.005 && simd_distance(g.tip, p.tip) < 0.005)
    }

    @Test("ぐるぐる目の絵: 縁は黒・渦の帯は黒・帯の間は白")
    func eyeTexture() {
        #expect(HomerunWhiffGag.isInk(x: 1.1, y: 0))
        let pixels = HomerunWhiffGag.eyePixels()
        let dark = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 128 }.count
        let total = pixels.count / 4
        #expect(dark > total / 5 && dark < total * 4 / 5, "黒の割合 \(dark)/\(total)")
        // 中心から外へ向かうと白と黒が何度も入れ替わる（渦）。
        var flips = 0
        var last = HomerunWhiffGag.isInk(x: 0, y: 0)
        for k in 1...200 {
            let ink = HomerunWhiffGag.isInk(x: Float(k) / 200, y: 0)
            if ink != last { flips += 1 }
            last = ink
        }
        #expect(flips >= 4, "渦の帯の切り替わり \(flips)")
        #expect(HomerunWhiffGag.eyeImage() != nil)
    }

    #if canImport(RealityKit)
    @Test("USDZ はスイング 44 コマの後ろに演出のコマを足した 1 本のクリップ（モデルは 1 つ）。演出を流しきると座っている")
    func rigPlaysTheGagClip() throws {
        let rig = try #require(HomerunBatterRig())
        #expect(abs(rig.clipDuration - HomerunWhiffGag.clipEnd) < 0.02, "クリップの長さ \(rig.clipDuration) 秒")
        #expect(abs(rig.fullDuration - 43.0 / 30) < 1e-9)
        let now = Date()
        rig.show(.whiffGag(start: now.addingTimeInterval(-(HomerunWhiffGag.span + 0.5))), now: now)
        #expect(abs((rig.swingClipTime ?? 0) - HomerunWhiffGag.clipEnd) < 0.02)
        guard #available(macOS 15.0, iOS 18.0, *) else { return }
        let renderer = try RealityRenderer()
        renderer.entities.append(rig.entity)
        // 再生を終えた後も（`controller.time` は頭に戻る）回転は最後のまま（座った後に回転だけ外れて体が飛んだ不具合）。
        for _ in 0..<6 { try renderer.update(0.5) }
        rig.applyWhiffGag(now: now, back: false, camera: [0, 4.5, 28])
        #expect(abs((rig.whiffGagClipTime ?? 0) - HomerunWhiffGag.clipEnd) < 1e-6)
        let yaw = HomerunWhiffGag.spinYaw(atClipTime: HomerunWhiffGag.clipEnd, back: false)
        let expected = simd_quatf(angle: yaw, axis: [0, 1, 0])
        #expect(abs(simd_dot(rig.turnOrientation.vector, expected.vector)) > 0.999)
        #expect(rig.overlay?.isEnabled == true)
        // 腰の骨は地面近く。
        let hips = try #require(jointPosition(rig, suffix: "Hips"))
        #expect(hips.y < 0.35, "腰の高さ \(hips.y)")
        // 構えに戻すと回転を外し、目と星を隠す。
        rig.show(.stance, now: now)
        #expect(abs(rig.turnOrientation.angle) < 1e-5 && rig.overlay?.isEnabled == false)
    }

    @MainActor
    private func jointPosition(_ rig: HomerunBatterRig, suffix: String) -> SIMD3<Float>? {
        func find(_ e: Entity) -> ModelEntity? {
            if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
            for c in e.children { if let m = find(c) { return m } }
            return nil
        }
        guard let model = find(rig.entity), let i = model.jointNames.firstIndex(where: { $0 == suffix || $0.hasSuffix("/" + suffix) }) else { return nil }
        return model.jointTransforms[i].translation
    }
    #endif
}

private extension HomerunBatterMotion {
    var isWhiffGag: Bool {
        if case .whiffGag = self { return true }
        return false
    }
}
