import SwiftUI
import Core
import HomerunCore

/// 打席（`31-at-bat-3D` の 2D 仮絵）。全画面でバナー無し。
///
/// 上端: 球数 / 今回の合計 / 柵越え本数 + 直前 2 球のチップ・方向メーター。中央やや上: 9 分割のゾーン・的・縮む輪・
/// ミートカーソル。下 1/3: 押せる帯（受け口の円は置かない）と案内 1 本・押している指の残像。
///
/// ゾーン・的・カーソルは画面の上寄り（高さの 45%）に置き、押せる帯（下 1/3）と重ねない = 指で的を隠さない。
struct HomerunAtBatView: View {
    let model: HomerunModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 押している指の位置（残像の描画用・押せる帯の座標）。
    @State private var fingerPoint: CGPoint?
    /// 振った球の結果に入ってから、打者の振り抜きを見せ終えたか（外野カメラへの切り替えと結果のカードをそれまで待つ・試作）。
    @State private var swingShown = false

    /// 振り抜きを見せる時間（秒）。踏み込みの後の 21〜30 コマ目（約 0.33 秒）＋フォロースルーの入り。
    static let swingShowDuration: TimeInterval = 0.55

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // 3D の背景は安全域の外まで（画面全体に）広がるので、ゾーンの位置は全画面の高さで割り、ここの座標（安全域の内側）に直す。
            let inset = geo.safeAreaInsets
            let fullHeight = size.height + inset.top + inset.bottom
            let zoneCenter = CGPoint(x: size.width / 2, y: fullHeight * HomerunAtBatLayout.zoneScreenFraction - inset.top)
            let padHeight = size.height / 3
            // 型名で書く（`.animation(` は素のアニメーション API と見分けが付かず、Reduce Motion の走査に掛かる）。
            TimelineView(AnimationTimelineSchedule(minimumInterval: nil, paused: model.phase != .pitching || model.isHeld)) { timeline in
                let now = timeline.date
                ZStack(alignment: .top) {
                    if showsOutfield, let ball = model.lastBall {
                        HomerunOutfieldScene3DView(ball: ball).ignoresSafeArea()
                    } else {
                        HomerunAtBatBackdrop(zoneCenter: zoneCenter,
                                             batterPose: HomerunAtBatLayout.batterPose(phase: model.phase, lastKind: model.lastBall?.kind),
                                             pitcherPose: HomerunAtBatLayout.pitcherPose(phase: model.phase, elapsed: model.pitchElapsed(at: now)),
                                             batterMotion: batterMotion(at: now))
                        HomerunZoneCanvas(
                            zoneCenter: zoneCenter,
                            ball: model.phase == .pitching ? model.ballPoint : nil,
                            cursor: model.cursor,
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
                    // 振った球は、振り抜きを見せ終えてから結果のカードを出す（先に出すと打者に重なってスイングが隠れる・試作）。
                    if model.phase == .ballResult, !model.didSwingLastBall || swingShown, let ball = model.lastBall {
                        HomerunBallResultCard(ball: ball, number: model.pitchNumber)
                            .padding(.horizontal, Theme.pad)
                            .padding(.top, size.height * 0.2)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    touchPad(height: padHeight)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .gameAnimation(.easeOut(duration: 0.2), value: model.phase)
        // 振った球は、外野カメラへ切り替える前に打席で振り抜きを見せる（離した瞬間に切り替えるとスイングが見えない）。
        .task(id: model.step) {
            swingShown = false
            guard model.phase == .ballResult, model.didSwingLastBall else { return }
            try? await Task.sleep(for: .seconds(Self.swingShowDuration))
            guard !Task.isCancelled else { return }
            withGameAnimation(.easeOut(duration: 0.2)) { swingShown = true }
        }
    }

    /// Meshy の打者の動きの段階（試作）。投球中は輪が的に重なる少し前から踏み込み、振った球の結果の間は振り抜き（振るたびに頭から）。
    private func batterMotion(at now: Date) -> HomerunBatterMotion {
        switch model.phase {
        case .pitching: HomerunBatterMotion.beforeSwing(elapsed: model.pitchElapsed(at: now), travel: HomerunModel.travel)
        case .ballResult where model.didSwingLastBall: .swing(model.swingCount)
        default: .stance
        }
    }

    /// 当たり以上（外野へ飛んだ）の結果は外野カメラの静止ショットに切り替える（README §3.2）。
    private var showsOutfield: Bool {
        guard model.phase == .ballResult, let kind = model.lastBall?.kind else { return false }
        if model.didSwingLastBall, !swingShown { return false }
        return kind == .inPlay || kind == .fenceHit || kind == .homer
    }

    private var zoneLabel: String {
        guard model.phase == .pitching, let pitch = model.currentPitch else { return "ストライクゾーン" }
        let rows = ["高め", "真ん中の高さ", "低め"]
        let cols = ["左", "真ん中", "右"]
        return "ストライクゾーン。ボールは\(rows[pitch.zone / 3])の\(cols[pitch.zone % 3])"
    }

    // MARK: 上端の HUD

    private var topHUD: some View {
        let challenge = model.challenge
        let results = challenge?.results ?? []
        return VStack(spacing: 6) {
            HStack(alignment: .center) {
                hudPill(systemImage: "baseball.fill",
                        text: "\(max(model.pitchNumber, 1)) / \(HomerunChallenge.pitchCount) 球")
                Spacer()
                VStack(spacing: 0) {
                    Text("今回").themeCaption(11).foregroundStyle(.white.opacity(0.9))
                    Text(verbatim: HomerunText.meters(challenge?.totalDistance ?? 0))
                        .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
                Spacer()
                hudPill(systemImage: "flag.checkered", text: "柵越え \(challenge?.homerCount ?? 0)")
            }
            HStack(spacing: 6) {
                ForEach(Array(results.enumerated().suffix(2)), id: \.offset) { index, ball in
                    Text(verbatim: "\(index + 1) 球目 \(HomerunText.headline(ball))")
                        .themeCaption(11)
                        .lineLimit(1)
                        .foregroundStyle(ball.kind == .homer ? Theme.onAccent : Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(ball.kind == .homer ? Theme.Fill.yellow : Theme.surface.opacity(0.9)))
                }
            }
            .accessibilityElement(children: .combine)
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
                .onChanged { value in
                    // 押し直し（一時停止で指が外れた後など）は今の指の位置を基準にする。最初に押した位置を
                    // 基準にすると、それまでの移動量ぶんカーソルが跳ぶ。
                    if !model.isHolding { model.press(at: value.location) }
                    model.drag(to: value.location)
                    fingerPoint = model.isHolding ? value.location : nil
                }
                .onEnded { value in
                    fingerPoint = nil
                    withGameAnimation(.easeOut(duration: 0.2)) {
                        _ = model.release(at: value.location, now: value.time)
                    }
                }
        )
        // VoiceOver では押したままずらす操作ができないので、カーソルを真ん中に置いたまま「今振る」を用意する。
        .accessibilityElement()
        .accessibilityLabel("打つ場所")
        .accessibilityHint("押したままずらしてねらい、離して振ります。操作メニューから今すぐ振ることもできます")
        .accessibilityAction(named: "今振る") {
            let center = CGPoint(x: 0, y: 0)
            model.press(at: center)
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
    var pitcherPose: HomerunOjisanPose3 = .pitch
    var batterMotion: HomerunBatterMotion = .stance

    var body: some View {
        #if os(iOS) && canImport(RealityKit)
        HomerunAtBatScene3DView(batterPose: batterPose, pitcherPose: pitcherPose, batterMotion: batterMotion).ignoresSafeArea()
        #else
        HomerunFieldBackdrop(zoneCenter: zoneCenter)
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

            // ミートカーソル（水色の輪 + 十字）。
            let p = CGPoint(x: zoneCenter.x + cursor.x, y: zoneCenter.y + cursor.y)
            let cr = HomerunJudge.coreRadius
            let cursorPath = Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2))
            ctx.stroke(cursorPath, with: .color(Theme.teal), lineWidth: 3)
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

    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: HomerunText.kind(ball.kind))
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(ball.kind == .homer ? Theme.coral : Theme.ink)
            if ball.distance > 0 {
                Text(verbatim: "\(HomerunText.meters(ball.distance))　\(HomerunSector(direction: ball.direction).label)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.ink)
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
        .accessibilityLabel(HomerunText.spoken(ball, number: number))
        .accessibilityAddTraits(.updatesFrequently)
    }
}
