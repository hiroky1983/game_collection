import SwiftUI
import Core
import HomerunCore

/// 打席（`31-at-bat-3D` の 2D 仮絵）。全画面でバナー無し。
///
/// 上端: 球数 / 今回の合計 / 柵越え本数・方向メーター（直前 2 球のチップは置かない・#1613）。中央やや上: 9 分割のゾーン・的・縮む輪・
/// ミートカーソル。下 1/3: 押せる帯（受け口の円は置かない）と案内 1 本・押している指の残像。
///
/// ゾーン・的・カーソルは画面の上寄り（高さの 45%）に置き、押せる帯（下 1/3）と重ねない = 指で的を隠さない。
struct HomerunAtBatView: View {
    let model: HomerunModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 押している指の位置（残像の描画用・押せる帯の座標）。
    @State private var fingerPoint: CGPoint?
    /// 振った球の結果に入ってから、打球（当たり以上は打球を追うカメラで止まるまで・#1613）を見せ終えたか（結果のカードをそれまで待つ）。
    @State private var swingShown = false
    /// 結果フェーズ中の素振り（`practiceSwingAt`）が振り終えたか。振り終えた後は `TimelineView` を止める（CodeRabbit 指摘）。
    @State private var practiceSwingExpired = false
    /// 一時停止から「途中でやめる」を押したときの確認（#1550）。
    @State private var confirmsQuit = false
    /// 一時停止の画面の「遊び方」ボタンが開く（#1617。ヘッダー右上の `?` は打席中は隠すため、
    /// ここから同じシートを開く）。
    @Environment(\.howToPlayTrigger) private var howToPlay

    /// 離した瞬間から結果のカードへ切り替えるまでの時間（秒）。空振り・見送りは理由を早く読めるよう短く。
    /// 当たり以上は打球を追うカメラで打球が止まるまで待つ（`HomerunSwingPlan.chaseCardAt`・#1613）。ここの値はその時刻が
    /// 分からないとき（振った時刻の記録が無いとき）の控えで、振り抜き（フォロースルーの終わり・0.8 秒）まで。
    static func swingShowDuration(for kind: HomerunKind?) -> TimeInterval {
        switch kind {
        case .inPlay, .fenceHit, .homer, .foul: HomerunBatterMotion.swingDuration
        case .miss, nil: 0.4
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // 3D の背景は安全域の外まで（画面全体に）広がるので、ゾーンの位置は全画面の高さで割り、ここの座標（安全域の内側）に直す。
            let inset = geo.safeAreaInsets
            let fullHeight = size.height + inset.top + inset.bottom
            let zoneCenter = CGPoint(x: size.width / 2, y: fullHeight * HomerunAtBatLayout.zoneScreenFraction - inset.top)
            let padHeight = size.height / 3
            // 型名で書く（`.animation(` は素のアニメーション API と見分けが付かず、Reduce Motion の走査に掛かる）。
            // 投球中と、振った直後に打席で打球を見せている間（`swingShowDuration`）は毎フレーム描く（3D の球は時刻から位置を決める）。
            TimelineView(AnimationTimelineSchedule(minimumInterval: nil, paused: !isAnimating)) { timeline in
                let now = timeline.date
                let plan = HomerunSwingPlan(model: model)
                // 当たり以上は、当たった直後から打席の 3D のカメラを打球の後ろへ回して追う（#1613。外野カメラの静止ショットと
                // 外野手の置き換え）。打席の 3D をそのまま使い、球場・`ARView` を作り足さない。
                let chase = plan.chaseFrame(at: now)
                ZStack(alignment: .top) {
                    HomerunAtBatBackdrop(zoneCenter: zoneCenter,
                                         batterPose: HomerunAtBatLayout.batterPose(phase: model.phase, lastKind: model.lastBall?.kind),
                                         machine: HomerunMachineMotion.state(elapsed: model.pitchElapsed(at: now), now: now),
                                         cameraPreset: model.atBatCamera,
                                         cameraOverride: chase?.camera,
                                         batterMotion: plan.batterMotion(at: now),
                                         ballPosition: chase?.ball
                                            ?? (isAnimating ? plan.ballPosition(at: now, camera: model.atBatCamera.camera) : nil),
                                         ballScale: chase?.ballScale ?? 1,
                                         now: now,
                                         // 1 球目のモーションは打席の 3D が描き始めてから数える（作る・描き始めるまで約 0.6〜1 秒
                                         // 画面が止まり、モーションが見えないまま的が出ていた・画面の E2E の録画で確認）。
                                         onFirstFrame: { model.atBatDidAppear(now: Date()) })
                    // 打球を追っている間は、ゾーン・的・カーソルを出さない。
                    if chase == nil {
                        HomerunZoneCanvas(
                            zoneCenter: zoneCenter,
                            // 打席の 3D が描き始める前（1 球目を数え直す前）は的と輪を出さない。
                            ball: model.phase == .pitching && !model.awaitsAtBat ? model.ballPoint : nil,
                            cursor: model.aimCursor(at: now),
                            elapsed: model.pitchElapsed(at: now),
                            offset: model.timingOffset(at: now),
                            reduceMotion: reduceMotion
                        )
                        .accessibilityElement()
                        .accessibilityLabel(zoneLabel)
                    }
                    VStack(spacing: 8) {
                        topHUD
                        HStack(alignment: .top) {
                            Spacer()
                            if model.phase == .pitching, model.showsDirectionMeter {
                                HomerunDirectionMeter(swing: model.previewSwing(at: now))
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pad)
                    .padding(.top, 8)
                    // 結果のカードは打席の打球を見せ終えてから出す（先に出すと打者に重なってスイングが隠れる・試作）。
                    if model.phase == .ballResult, swingShown, let ball = model.lastBall {
                        HomerunBallResultCard(ball: ball, number: model.pitchNumber, tookPitch: !model.didSwingLastBall,
                                              missNote: Self.missNote(didSwing: model.didSwingLastBall, reason: model.lastMissReason))
                            .padding(.horizontal, Theme.pad)
                            .padding(.top, size.height * 0.2)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    touchPad(height: padHeight)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    // 一時停止は押せる帯（下 1/3）のすぐ上の右端に置く（#1550。帯の中に置くと押す指と取り合う。
                    // ゾーンは横の中央なので重ならない）。以前の「⋯」（カメラの 2 択）はここにあった。
                    if !model.isPaused {
                        pauseButton
                            .padding(.trailing, Theme.pad)
                            .padding(.bottom, padHeight + 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    if model.isPaused {
                        pausedPanel
                    }
                }
            }
        }
        .gameAnimation(.easeOut(duration: 0.2), value: model.phase)
        .gameAnimation(.easeOut(duration: 0.15), value: model.isPaused)
        // 途中でやめる確認。キャンセル（外側のタップで閉じた場合も）は一時停止の画面に戻るだけ。
        .confirmationDialog("この挑戦をやめますか？", isPresented: $confirmsQuit, titleVisibility: .visible) {
            Button("やめる", role: .destructive) { model.quitChallenge() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この挑戦はここで終わり、使った回数は戻りません。")
        }
        // 結果のカードを出す前に、打球（当たり以上は追うカメラで止まるまで・見送り・空振りならミットへ入る球）を見せる。
        .task(id: model.step) {
            swingShown = false
            guard model.phase == .ballResult else { return }
            // 一時停止から戻ったときなど、打球がもう止まっていれば待たずに出す。
            let wait = HomerunSwingPlan(model: model).chaseCardAt?.timeIntervalSinceNow
                ?? Self.swingShowDuration(for: model.lastBall?.kind)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            withGameAnimation(.easeOut(duration: 0.2)) { swingShown = true }
        }
        // 結果フェーズ中の素振りが振り終えたら `isAnimating` を止める（振り終えた後も `TimelineView` が回り続けていた・CodeRabbit 指摘）。
        .task(id: model.ballClock?.practiceSwingAt) {
            practiceSwingExpired = false
            guard let started = model.ballClock?.practiceSwingAt else { return }
            let remaining = started.addingTimeInterval(HomerunBatterMotion.swingDuration).timeIntervalSinceNow
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            practiceSwingExpired = true
        }
    }

    // MARK: 一時停止（#1550）

    private var pauseButton: some View {
        Button {
            fingerPoint = nil
            model.pause(now: Date())
        } label: {
            // 大きさ・形は「⋯」（`GameControlMenu`）と揃える（#1617・同じ役割の UI は同じ見た目）。
            // 寸法はコピーせず `BoardGameControlMetrics.minTapTarget` を直接参照する。
            Image(systemName: "pause.fill")
                .font(.system(size: 18, weight: .bold))
                .frame(width: BoardGameControlMetrics.minTapTarget, height: BoardGameControlMetrics.minTapTarget)
                .background(Circle().fill(Theme.Fill.coral))
                .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(.pop)
        .accessibilityLabel("一時停止")
    }

    /// 一時停止の画面: 再開・カメラの前 / 後ろ・途中でやめる（確認つき）。覆いは他ゲームの一時停止と同じ黒 60%。
    private var pausedPanel: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.6)).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("一時停止").font(.title3.bold()).foregroundStyle(.white)
                GameDeadEndActionButton("再開", systemImage: "play.fill", tint: Theme.Fill.coral) {
                    model.resume(now: Date())
                }
                HStack(spacing: 8) {
                    ForEach(Self.cameraChoices(for: model), id: \.id) { item in
                        let isChecked = item.isChecked == true
                        Button(action: item.action) {
                            Label(item.title, systemImage: isChecked ? "checkmark.circle.fill" : "video")
                                .themeCaption(14)
                                .foregroundStyle(isChecked ? Theme.onAccent : .white)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Capsule().fill(isChecked ? Theme.Fill.teal : .white.opacity(0.18)))
                        }
                        .buttonStyle(.pop)
                        .accessibilityAddTraits(isChecked ? .isSelected : [])
                    }
                }
                // ヘッダー右上の「?」は打席中は隠しているので、同じシートをここから開く（#1617）。
                if let howToPlay {
                    GameDeadEndActionButton("遊び方", systemImage: "questionmark.circle.fill", tint: Theme.Fill.teal) {
                        howToPlay.present()
                    }
                }
                GameDeadEndActionButton("途中でやめる", systemImage: "xmark.circle.fill") {
                    confirmsQuit = true
                }
            }
            .padding(20)
        }
    }

    /// 一時停止の画面のカメラの 2 択（前 / 後ろ・#1506）。選ぶのは見た目だけで、判定・座標は変えない。
    static func cameraChoices(for model: HomerunModel) -> [GameControlMenuItem] {
        HomerunAtBatLayout.CameraPreset.allCases.map { preset in
            GameControlMenuItem(id: "camera.\(preset.rawValue)", title: preset.title, systemImage: "video",
                                isChecked: model.atBatCamera == preset) {
                model.atBatCamera = preset
            }
        }
    }

    /// 3D を時刻で動かしている間（投球中・振った直後の打球・結果の間の素振り）。それ以外は `TimelineView` を止める。
    private var isAnimating: Bool {
        guard !model.isHeld else { return false }
        return model.phase == .pitching
            || (model.phase == .ballResult
                && (!swingShown || (model.ballClock?.practiceSwingAt != nil && !practiceSwingExpired)))
    }

    /// 空振りの結果に添える理由（#1594）。当たり・ファウル・見送りは nil（見送りは見出しそのものを「見送り」にする・
    /// 会長 QA 2026-09-30: 見出し「空振り」と理由「見送り」が同時に出て矛盾していた）。
    static func missNote(didSwing: Bool, reason: HomerunMissReason?) -> String? {
        guard didSwing else { return nil }
        return reason.map(HomerunText.missReason)
    }

    private var zoneLabel: String {
        guard model.phase == .pitching, !model.awaitsAtBat, let pitch = model.currentPitch else { return "ストライクゾーン" }
        let rows = ["高め", "真ん中の高さ", "低め"]
        let cols = ["左", "真ん中", "右"]
        return "ストライクゾーン。ボールは\(rows[pitch.zone / 3])の\(cols[pitch.zone % 3])"
    }

    // MARK: 上端の HUD

    /// 上端の「今回 ◯m」と「柵越え ◯」に数える球。結果のカードを出すまで（打球を追っている間）は直前の球を数えない
    /// （当たった瞬間に数字が増えると、入ったかどうかが先に分かってしまう・会長 QA 2026-09-30・#1613）。
    static func hudTotals(results: [HomerunBattedBall], revealsLast: Bool) -> (distance: Double, homers: Int) {
        let shown = revealsLast ? results[...] : results.dropLast()
        return (shown.reduce(0) { $0 + $1.distance }, shown.filter { $0.kind == .homer }.count)
    }

    /// 上端の HUD。直前 2 球のチップ（「1 球目 柵越え …」）は置かない（当たった直後に結果が分かってしまう・会長 QA 2026-09-30）。
    private var topHUD: some View {
        let totals = Self.hudTotals(results: model.challenge?.results ?? [],
                                    revealsLast: model.phase != .ballResult || swingShown)
        return HStack(alignment: .center) {
            hudPill(systemImage: "baseball.fill",
                    text: "\(max(model.pitchNumber, 1)) / \(HomerunChallenge.pitchCount) 球")
            Spacer()
            VStack(spacing: 0) {
                Text("今回").themeCaption(11).foregroundStyle(.white.opacity(0.9))
                Text(verbatim: HomerunText.meters(totals.distance))
                    .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            Spacer()
            hudPill(systemImage: "flag.checkered", text: "柵越え \(totals.homers)")
        }
    }

    private func hudPill(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(verbatim: text)
        }
        .themeCaption(13)
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }

    // MARK: 下 1/3 の押せる帯

    private func touchPad(height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if let fingerPoint, model.isHolding {
                // 押している指の残像だけ（受け口の円は置かない・4 回目の決裁）。
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
                    .frame(width: 64, height: 64)
                    .position(fingerPoint)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Label("押したままずらし、輪が的に重なった瞬間に離す", systemImage: "hand.point.up.left.fill")
                .themeCaption(12)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(.bottom, 12)
                .allowsHitTesting(false)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                // 時刻は `value.time` ではなく `Date()` で渡す。`value.time` は起動からの経過（タッチの時刻）を基準日に
                // 足した値で、Model の時計（`pitchStart` などの壁時計）と約 8 億秒ずれる。渡すと `timingOffset` が
                // nil（的が出る前）になり、離しても判定されず素振りになっていた（#1594・会長 QA）。
                .onChanged { value in
                    // 押し直し（一時停止で指が外れた後など）は今の指の位置を基準にする。最初に押した位置を
                    // 基準にすると、それまでの移動量ぶんカーソルが跳ぶ。
                    if !model.isHolding { model.press(at: value.location, now: Date()) }
                    model.drag(to: value.location)
                    fingerPoint = model.isHolding ? value.location : nil
                }
                .onEnded { value in
                    fingerPoint = nil
                    withGameAnimation(.easeOut(duration: 0.2)) {
                        _ = model.release(at: value.location, now: Date())
                    }
                }
        )
        // VoiceOver では押したままずらす操作ができないので、カーソルを真ん中に置いたまま「今振る」を用意する。
        .accessibilityElement()
        .accessibilityLabel("打つ場所")
        .accessibilityHint("押したままずらしてねらい、離して振ります。操作メニューから今すぐ振ることもできます")
        .accessibilityAction(named: "今振る") {
            let center = CGPoint(x: 0, y: 0)
            model.press(at: center, now: Date())
            withGameAnimation(.easeOut(duration: 0.2)) {
                _ = model.release(at: center, now: Date())
            }
        }
    }
}

// MARK: - 背景

/// 打席の背景。iOS は 3D（RealityKit）のセンターカメラ、それ以外（macOS の `swift test`）は 2D の仮絵。
struct HomerunAtBatBackdrop: View {
    let zoneCenter: CGPoint
    var batterPose: HomerunOjisanPose3 = .stance
    var machine = HomerunMachineMotion.state(elapsed: nil, now: .distantPast)
    var cameraPreset: HomerunAtBatLayout.CameraPreset = .front
    /// 打球を追うカメラ（#1613）。nil なら `cameraPreset`。
    var cameraOverride: HomerunAtBatLayout.Camera? = nil
    var batterMotion: HomerunBatterMotion = .stance
    var ballPosition: SIMD3<Float>? = nil
    /// 球の拡大率（打球を追う間は大きく見せる）。
    var ballScale: Float = 1
    var now: Date = Date()
    /// 背景を描き始めたときに 1 回だけ呼ぶ（3D は最初の数コマを描いた後）。
    var onFirstFrame: (@MainActor () -> Void)? = nil

    var body: some View {
        #if os(iOS) && canImport(RealityKit)
        HomerunAtBatScene3DView(batterPose: batterPose, machine: machine, cameraPreset: cameraPreset,
                                cameraOverride: cameraOverride, batterMotion: batterMotion,
                                ballPosition: ballPosition, ballScale: ballScale, now: now,
                                onFirstFrame: onFirstFrame).ignoresSafeArea()
        #else
        HomerunFieldBackdrop(zoneCenter: zoneCenter)
            .onAppear { onFirstFrame?() }
        #endif
    }
}

// MARK: 2D の仮絵

/// 客席・芝・土・本塁。3D（RealityKit）が描けない環境（macOS）の代わりの絵。
struct HomerunFieldBackdrop: View {
    let zoneCenter: CGPoint

    var body: some View {
        Canvas { ctx, size in
            let horizon = zoneCenter.y - HomerunZoneGeometry.zoneSize * 1.1
            // 客席（上）。
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x3B4A6B), Color(hex: 0x6B7FA8)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            // 客席の粒（固定の並び・乱数なし）。
            let colors = Theme.Fill.palette
            var i = 0
            for y in stride(from: 70.0, to: horizon - 12, by: 16) {
                for x in stride(from: Double(i % 2) * 9, to: size.width, by: 18) {
                    let c = colors[(i * 7 + Int(x / 18)) % colors.count]
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 10, height: 10)), with: .color(c.opacity(0.55)))
                }
                i += 1
            }
            // フェンス。
            ctx.fill(Path(CGRect(x: 0, y: horizon - 10, width: size.width, height: 10)), with: .color(Color(hex: 0x2F5B3A)))
            // 芝。
            ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
                     with: .color(Color(hex: 0x5BAA5B)))
            // 土（打席まわり）。
            let dirt = CGRect(x: -size.width * 0.1, y: zoneCenter.y + HomerunZoneGeometry.zoneSize * 0.7,
                              width: size.width * 1.2, height: size.height * 0.16)
            ctx.fill(Path(ellipseIn: dirt), with: .color(Color(hex: 0xD9A066)))
            // 本塁。
            let plateY = dirt.midY - 6
            var plate = Path()
            plate.move(to: CGPoint(x: zoneCenter.x - 22, y: plateY))
            plate.addLine(to: CGPoint(x: zoneCenter.x + 22, y: plateY))
            plate.addLine(to: CGPoint(x: zoneCenter.x + 22, y: plateY + 8))
            plate.addLine(to: CGPoint(x: zoneCenter.x, y: plateY + 18))
            plate.addLine(to: CGPoint(x: zoneCenter.x - 22, y: plateY + 8))
            plate.closeSubpath()
            ctx.fill(plate, with: .color(.white))
        }
        // 打者（右打席 = 画面の左）: ハブと同じおじさんのマスコット。
        .overlay(alignment: .topLeading) {
            let batterSize = HomerunZoneGeometry.zoneSize * 1.6
            OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
                .frame(width: batterSize, height: batterSize)
                .position(x: zoneCenter.x - HomerunZoneGeometry.zoneSize * 0.5 - batterSize * 0.45,
                          y: zoneCenter.y + batterSize * 0.05)
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - ゾーン・的・輪・カーソル

/// 9 分割のゾーン・的（白い細い輪）・縮む輪（コーラル）・ミートカーソル（水色）を `Canvas` 1 枚に描く。
/// Reduce Motion のときは輪を縮めず、的の色（白 → 黄 → コーラル）でタイミングを知らせる（README §3.1）。
struct HomerunZoneCanvas: View {
    let zoneCenter: CGPoint
    /// 的の位置（ゾーン中心から）。投球中でなければ nil。
    let ball: CGPoint?
    let cursor: CGPoint
    /// 投球開始からの秒（モーション中は負）。
    let elapsed: TimeInterval?
    /// いま離したときのずれ（ミリ秒）。的が出る前は nil。
    let offset: Double?
    let reduceMotion: Bool

    var body: some View {
        Canvas { ctx, _ in
            let g = HomerunZoneGeometry.self
            let half = g.zoneSize / 2
            let zone = CGRect(x: zoneCenter.x - half, y: zoneCenter.y - half, width: g.zoneSize, height: g.zoneSize)
            // ゾーン（9 分割）。
            ctx.fill(Path(zone), with: .color(Color.white.opacity(0.12)))
            ctx.stroke(Path(zone), with: .color(Color.white.opacity(0.85)), lineWidth: 1.5)
            var grid = Path()
            for k in 1...2 {
                let d = Double(k) * g.cellSize
                grid.move(to: CGPoint(x: zone.minX + d, y: zone.minY)); grid.addLine(to: CGPoint(x: zone.minX + d, y: zone.maxY))
                grid.move(to: CGPoint(x: zone.minX, y: zone.minY + d)); grid.addLine(to: CGPoint(x: zone.maxX, y: zone.minY + d))
            }
            ctx.stroke(grid, with: .color(Color.white.opacity(0.45)), lineWidth: 0.75)

            // 的と縮む輪（的は投球開始と同時に出る）。
            if let ball, let elapsed, elapsed >= 0 {
                let c = CGPoint(x: zoneCenter.x + ball.x, y: zoneCenter.y + ball.y)
                let ballR = 7.0
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - ballR, y: c.y - ballR, width: ballR * 2, height: ballR * 2)),
                         with: .color(.white))
                let t = g.targetDiameter / 2
                let target = Path(ellipseIn: CGRect(x: c.x - t, y: c.y - t, width: t * 2, height: t * 2))
                if reduceMotion {
                    let cue = HomerunTargetCue(offsetMilliseconds: offset ?? -.infinity)
                    let color: Color = switch cue {
                    case .far: .white
                    case .near: Theme.yellow
                    case .now: Theme.coral
                    }
                    // 輪が無いので的を太くして色を読みやすくする（重なりの幾何は関係しない）。
                    ctx.stroke(target, with: .color(color), lineWidth: 4)
                } else {
                    ctx.stroke(target, with: .color(.white), lineWidth: g.targetLineWidth)
                    let r = g.ringDiameter(elapsed: elapsed) / 2
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(Theme.coral), lineWidth: g.ringLineWidth)
                }
            }

            // ミートカーソル（水色の輪 + 十字）。外の輪が当たり判定（1 マスぶん・#1594）、内の細い輪が芯。
            let p = CGPoint(x: zoneCenter.x + cursor.x, y: zoneCenter.y + cursor.y)
            let cr = HomerunJudge.contactRadius
            let cursorPath = Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2))
            ctx.stroke(cursorPath, with: .color(Theme.teal), lineWidth: 3)
            let core = HomerunJudge.coreRadius
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                       with: .color(Theme.teal.opacity(0.7)), lineWidth: 1.5)
            var cross = Path()
            cross.move(to: CGPoint(x: p.x - cr - 4, y: p.y)); cross.addLine(to: CGPoint(x: p.x - cr + 4, y: p.y))
            cross.move(to: CGPoint(x: p.x + cr - 4, y: p.y)); cross.addLine(to: CGPoint(x: p.x + cr + 4, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: p.y - cr - 4)); cross.addLine(to: CGPoint(x: p.x, y: p.y - cr + 4))
            cross.move(to: CGPoint(x: p.x, y: p.y + cr - 4)); cross.addLine(to: CGPoint(x: p.x, y: p.y + cr + 4))
            ctx.stroke(cross, with: .color(Theme.teal), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 方向メーター

/// いまのカーソルと、いま振ったときのタイミングで決まる打球方向と、その方向の柵の距離（`31` 右上）。
struct HomerunDirectionMeter: View {
    let swing: HomerunSwing

    var body: some View {
        let direction = HomerunJudge.direction(swing)
        let isFoul = abs(direction) > HomerunJudge.foulLimit
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let home = CGPoint(x: size.width / 2, y: size.height - 2)
                let r = min(size.width / 2 / sin(.pi / 4), size.height) * 0.95
                func at(_ deg: Double, _ k: Double = 1) -> CGPoint {
                    let rad = deg * .pi / 180
                    return CGPoint(x: home.x + r * k * sin(rad), y: home.y - r * k * cos(rad))
                }
                var fan = Path()
                fan.move(to: home)
                for deg in stride(from: -45.0, through: 45.0, by: 5) { fan.addLine(to: at(deg)) }
                fan.closeSubpath()
                ctx.fill(fan, with: .color(Color.white.opacity(0.18)))
                ctx.stroke(fan, with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)
                let shown = min(max(direction, -50), 50)
                var wedge = Path()
                wedge.move(to: home)
                wedge.addLine(to: at(shown - 5))
                wedge.addLine(to: at(shown + 5))
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(isFoul ? Theme.inkSub : Theme.yellow))
            }
            .frame(width: 84, height: 52)
            Text(verbatim: isFoul
                 ? "ファウル"
                 : "\(HomerunSector(direction: direction).label) \(Int(HomerunJudge.fence(atDirection: direction).rounded())) m")
                .themeCaption(11)
                .foregroundStyle(.white)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.cornerSmall).fill(Color.black.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isFoul ? "方向メーター、ファウル" : "方向メーター、\(HomerunSector(direction: direction).label)")
    }
}

// MARK: - 1 球の結果

/// 1 球ごとの結果（種別・距離・方向・タイミング）と、落下点を扇に 1 点だけ置いたもの（外野カメラの代わり）。
struct HomerunBallResultCard: View {
    let ball: HomerunBattedBall
    let number: Int
    /// 振らずに見送った（見出しを「見送り」にし、理由は付けない）。
    var tookPitch = false
    /// 空振りの理由（「振るのが早い」など・#1594）。見送りでは使わない。
    var missNote: String? = nil

    /// 見出し: 見送りは「見送り」、振って外したら「空振り」、当たりは種別。
    static func headline(_ ball: HomerunBattedBall, tookPitch: Bool) -> String {
        ball.kind == .miss && tookPitch ? "見送り" : HomerunText.kind(ball.kind)
    }

    /// 見出しの下に添える空振りの理由。振って外したときだけ。
    static func reasonLine(_ ball: HomerunBattedBall, tookPitch: Bool, missNote: String?) -> String? {
        ball.kind == .miss && !tookPitch ? missNote : nil
    }

    var body: some View {
        let reason = Self.reasonLine(ball, tookPitch: tookPitch, missNote: missNote)
        VStack(spacing: 6) {
            Text(verbatim: Self.headline(ball, tookPitch: tookPitch))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(ball.kind == .homer ? Theme.coral : Theme.ink)
            if ball.distance > 0 {
                Text(verbatim: "\(HomerunText.meters(ball.distance))　\(HomerunSector(direction: ball.direction).label)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
            if let reason {
                Text(verbatim: reason)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.coral)
            }
            if ball.kind != .miss || ball.timing != .miss {
                Text(verbatim: "タイミング: \(HomerunText.timing(ball.timing))")
                    .themeCaption(12)
                    .foregroundStyle(Theme.inkSub)
            }
            if ball.distance > 0 {
                HomerunSprayChart(balls: [ball], numbered: false)
                    .frame(width: 180, height: 130)
            }
        }
        .padding(16)
        .frame(maxWidth: 300)
        .popCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ball.kind == .miss && tookPitch
            ? "\(number)球目、見送り"
            : [HomerunText.spoken(ball, number: number), reason].compactMap { $0 }.joined(separator: "、"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
