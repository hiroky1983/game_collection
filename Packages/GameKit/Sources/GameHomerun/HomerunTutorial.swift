import SwiftUI
import Core
import HomerunCore

// MARK: - 操作の説明（#1763）

/// 打席の「操作の説明」の文言と寸法。説明画のカード（ねらう → 振る → ？？？の 3 ページ）が使う。
/// 初回は 1 球目の前に自動で出し、一時停止の画面の「操作の説明」ボタンからも開ける。
enum HomerunTutorial {
    static let pageCount = 3

    /// ねらう・振るの文言。
    static let steps: [(title: String, body: String)] = [
        ("ねらう", "画面の下の帯を押したまま動かす。カーソルが同じように動く"),
        ("振る", "カーソルを球に合わせ、輪が的に重なった瞬間に指を離す"),
    ]
    /// 隠し要素の匂わせ（3 ページ目）。答え・条件の数値は書かない。
    static let teaser: (title: String, body: String) = ("？？？", "ど真ん中を、ジャストで打ち抜くと……？")

    /// 図解で球を置くマス（真ん中の高さの左）。
    static let figureZone = 3

    static func text(page: Int) -> (title: String, body: String) {
        page < steps.count ? steps[page] : teaser
    }
}

// MARK: - カード

/// 打席画面の上にカードを出し、その中に説明用の絵（打席のスクショに指・矢印・カーソル・球を描き足した図解）を置く。
/// ねらう → 振る → ？？？の 3 ページ。ページ送りは横スワイプと「次へ」ボタン（VoiceOver ではボタンで送る）。
/// 図の指が動くループは Reduce Motion では止め絵にする。
struct HomerunTutorialCards: View {
    let size: CGSize
    @Binding var page: Int
    let onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // 打席上端のバナーの下に収める。図の高さは、文言とボタンが残りに収まるように決める（SE でも切れない）。
        let top = BannerSlot.height
        let large = typeSize.isAccessibilitySize
        let figureWidth = min(size.width - 64, 340)
        let room = max(size.height - top - 300, 120)
        let figureHeight = min(figureWidth / HomerunTutorialFigure.aspect, large ? min(room, 120) : room)
        let shownWidth = figureHeight * HomerunTutorialFigure.aspect
        ZStack {
            Rectangle().fill(.black.opacity(0.6)).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}  // 下の帯に触れないよう受ける
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                HStack {
                    Text("あそびかた").themeBody(18, weight: .black).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("とばす") { onFinish() }
                        .themeCaption(13).foregroundStyle(Theme.inkSub)
                        .buttonStyle(.pop)
                }
                if large {
                    // 文字が大きいときは、いまのページだけを縦にスクロールできる枠に入れる。
                    ScrollView {
                        pageView(page, figureSize: CGSize(width: shownWidth, height: figureHeight))
                            .frame(width: size.width - 64)
                    }
                } else {
                    TabView(selection: $page) {
                        ForEach(0..<HomerunTutorial.pageCount, id: \.self) { i in
                            pageView(i, figureSize: CGSize(width: shownWidth, height: figureHeight)).tag(i)
                                .accessibilityHidden(i != page)  // いまのページだけを読み上げる
                        }
                    }
                    #if os(iOS)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    #endif
                    .frame(height: figureHeight + 96)
                }
                HStack(spacing: 6) {
                    ForEach(0..<HomerunTutorial.pageCount, id: \.self) { i in
                        Circle().fill(i == page ? Theme.Fill.coral : Theme.inkSub.opacity(0.35)).frame(width: 7, height: 7)
                    }
                }
                .accessibilityHidden(true)
                Button {
                    if page + 1 < HomerunTutorial.pageCount {
                        withGameAnimation(.easeOut(duration: 0.2)) { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    let isLast = page + 1 >= HomerunTutorial.pageCount
                    Label(isLast ? "はじめる" : "次へ", systemImage: isLast ? "play.fill" : "arrow.right")
                        .themeBody(17)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.Fill.coral, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.pop)
            }
            .padding(16)
            .popCard()
            .padding(.horizontal, 16)
            .padding(.top, top)
        }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private func pageView(_ i: Int, figureSize: CGSize) -> some View {
        let text = HomerunTutorial.text(page: i)
        let isTeaser = i >= HomerunTutorial.steps.count
        VStack(spacing: 10) {
            Group {
                switch i {
                case 0: HomerunTutorialFigure(kind: .aim)
                case 1: HomerunTutorialFigure(kind: .swing)
                default: HomerunMoonTeaserFigure()
                }
            }
            .frame(width: figureSize.width, height: figureSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerSmall))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerSmall).stroke(Theme.inkSub.opacity(0.25), lineWidth: 1))
            .accessibilityHidden(true)
            HStack(spacing: 8) {
                if isTeaser {
                    Image(systemName: "moon.stars.fill").foregroundStyle(Theme.purple).accessibilityHidden(true)
                } else {
                    Text("\(i + 1)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.Fill.coral))
                        .accessibilityHidden(true)
                }
                Text(text.title).themeBody(16, weight: .black).foregroundStyle(isTeaser ? Theme.purple : Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            Text(text.body).themeBody(14, weight: .semibold).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 図解（ねらう・振る）

/// 説明用の絵。打席のスクショ（`Resources/HomerunTutorialShot.jpg`・iPhone 17 で撮り、ゾーンの少し上から帯の下端まで
/// 切り出した 2x 相当・打席のカメラ）の上に、帯の光・指・矢印・カーソル・球を描き足す。スクショが読めなければ
/// 2D の仮絵（`HomerunFieldBackdrop`）の上に描く。
struct HomerunTutorialFigure: View {
    enum Kind { case aim, swing }
    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// スクショを撮った画面の幅（pt）。ゾーン・カーソルの寸法はこれで割って図の幅に合わせる。
    static let shotWidth: CGFloat = 402
    /// 切り出した絵の 幅 / 高さ。
    static let aspect: CGFloat = 402.0 / 460.0
    /// ゾーン中心の高さ（絵の高さの割合）と、押せる帯の上端（同）。
    static let zoneFraction: CGFloat = 0.1637
    static let padFraction: CGFloat = 0.610

    #if canImport(UIKit)
    static let shot: Image? = Bundle.module.url(forResource: "HomerunTutorialShot", withExtension: "jpg")
        .flatMap { UIImage(contentsOfFile: $0.path) }
        .map { Image(uiImage: $0) }
    #else
    static let shot: Image? = nil
    #endif

    /// ループの長さ（秒）。
    private var period: TimeInterval { kind == .aim ? 2.4 : 2.8 }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                if let shot = Self.shot {
                    shot.resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
                } else {
                    HomerunFieldBackdrop(zoneCenter: CGPoint(x: size.width / 2, y: size.height * Self.zoneFraction))
                        .frame(width: size.width, height: size.height).clipped()
                }
                if reduceMotion {
                    // 止め絵の代表のコマ: ねらうは指が右へ寄った所、振るは輪が的に重なった瞬間。
                    marks(size: size, t: kind == .aim ? 0.6 : 1.2)
                } else {
                    TimelineView(.animation) { timeline in
                        marks(size: size, t: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period))
                    }
                }
            }
        }
    }

    private func marks(size: CGSize, t: TimeInterval) -> some View {
        Canvas { ctx, _ in
            let s = size.width / Self.shotWidth
            let zone = CGPoint(x: size.width / 2, y: size.height * Self.zoneFraction)
            let padTop = size.height * Self.padFraction
            let pad = CGPoint(x: size.width / 2, y: (padTop + size.height) / 2)
            // ゾーン（9 分割）。元のスクショはゾーン・カーソル無しで撮ってある。
            let half = HomerunZoneGeometry.zoneSize / 2 * s
            let zoneRect = CGRect(x: zone.x - half, y: zone.y - half, width: half * 2, height: half * 2)
            ctx.fill(Path(zoneRect), with: .color(.white.opacity(0.12)))
            ctx.stroke(Path(zoneRect), with: .color(.white.opacity(0.85)), lineWidth: 1.5 * s)
            var grid = Path()
            for k in 1...2 {
                let d = CGFloat(k) * HomerunZoneGeometry.cellSize * s
                grid.move(to: CGPoint(x: zoneRect.minX + d, y: zoneRect.minY)); grid.addLine(to: CGPoint(x: zoneRect.minX + d, y: zoneRect.maxY))
                grid.move(to: CGPoint(x: zoneRect.minX, y: zoneRect.minY + d)); grid.addLine(to: CGPoint(x: zoneRect.maxX, y: zoneRect.minY + d))
            }
            ctx.stroke(grid, with: .color(.white.opacity(0.45)), lineWidth: 0.75 * s)
            // 押せる帯を光らせる（スクショでは透明なので、ここで見せる）。
            let band = Path(roundedRect: CGRect(x: 6, y: padTop + 4, width: size.width - 12, height: size.height - padTop - 10),
                            cornerRadius: 16 * s)
            ctx.fill(band, with: .color(Theme.yellow.opacity(0.18)))
            ctx.stroke(band, with: .color(Theme.yellow.opacity(0.9)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            switch kind {
            case .aim:
                // 指は左右に揺れ、カーソルが同じだけ動く（指 1 pt = カーソル 1 pt）。
                let swing = sin(t / 2.4 * 2 * .pi) * 70 * s
                let finger = CGPoint(x: pad.x + swing, y: pad.y - 4 * s)
                for k in 1...3 {
                    let ghost = CGPoint(x: pad.x + sin((t - Double(k) * 0.12) / 2.4 * 2 * .pi) * 70 * s, y: finger.y)
                    let r = 30 * s
                    ctx.fill(Path(ellipseIn: CGRect(x: ghost.x - r, y: ghost.y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.14)))
                }
                let r = 30 * s
                let ring = Path(ellipseIn: CGRect(x: finger.x - r, y: finger.y - r, width: r * 2, height: r * 2))
                ctx.fill(ring, with: .color(.white.opacity(0.25)))
                ctx.stroke(ring, with: .color(.white.opacity(0.8)), lineWidth: 2)
                Self.doubleArrow(&ctx, from: CGPoint(x: pad.x - 110 * s, y: pad.y + 52 * s),
                                 to: CGPoint(x: pad.x + 110 * s, y: pad.y + 52 * s), color: Theme.yellow, lineWidth: 4 * s)
                ctx.draw(Text(Image(systemName: "hand.point.up.left.fill")).font(.system(size: 44 * s)).foregroundColor(.white),
                         at: CGPoint(x: finger.x + 10 * s, y: finger.y + 12 * s))
                Self.cursor(&ctx, at: CGPoint(x: zone.x + swing, y: zone.y), scale: s)
                Self.doubleArrow(&ctx, from: CGPoint(x: zone.x - 62 * s, y: zone.y + 64 * s),
                                 to: CGPoint(x: zone.x + 62 * s, y: zone.y + 64 * s), color: Theme.teal, lineWidth: 3 * s)
            case .swing:
                let p = HomerunZoneGeometry.ballPoint(zone: HomerunTutorial.figureZone)
                let ball = CGPoint(x: zone.x + p.x * s, y: zone.y + p.y * s)
                // 0〜1.2 秒: 輪が縮む。1.2 秒: 離す（指が上がり、球のまわりが光る）。その後は止めて見せる。
                let shrink = min(t, 1.2)
                let released = t > 1.2
                let ring = HomerunZoneGeometry.ringDiameter(elapsed: shrink)
                Self.arrow(&ctx, from: CGPoint(x: zone.x + 10 * s, y: zone.y - 8 * s),
                           to: CGPoint(x: ball.x + 22 * s, y: ball.y + 20 * s),
                           color: Theme.teal.opacity(0.9), lineWidth: 3 * s, dash: [6 * s, 5 * s])
                Self.target(&ctx, at: ball, ringDiameter: ring, scale: s)
                Self.cursor(&ctx, at: ball, scale: s)
                if released {
                    let k = min((t - 1.2) / 0.4, 1)
                    let fr = (40 + 50 * k) * s
                    ctx.stroke(Path(ellipseIn: CGRect(x: ball.x - fr, y: ball.y - fr, width: fr * 2, height: fr * 2)),
                               with: .color(Theme.yellow.opacity(1 - k)), lineWidth: 6 * s * (1 - k) + 1)
                }
                let lift = released ? CGFloat(min((t - 1.2) / 0.3, 1)) * 34 * s : 0
                let finger = CGPoint(x: pad.x, y: pad.y - 4 * s)
                if !released {
                    let r = 30 * s
                    let ring = Path(ellipseIn: CGRect(x: finger.x - r, y: finger.y - r, width: r * 2, height: r * 2))
                    ctx.fill(ring, with: .color(.white.opacity(0.25)))
                    ctx.stroke(ring, with: .color(.white.opacity(0.8)), lineWidth: 2)
                }
                ctx.draw(Text(Image(systemName: "hand.point.up.fill")).font(.system(size: 44 * s)).foregroundColor(.white),
                         at: CGPoint(x: finger.x + 6 * s, y: finger.y + 14 * s - lift))
                Self.arrow(&ctx, from: CGPoint(x: finger.x - 36 * s, y: finger.y + 26 * s),
                           to: CGPoint(x: finger.x - 36 * s, y: finger.y - 36 * s), color: Theme.yellow, lineWidth: 4 * s, dash: [])
                ctx.draw(Text(released ? "離す！" : "離す").font(.system(size: 15 * s, weight: .black, design: .rounded)).foregroundColor(.white),
                         at: CGPoint(x: finger.x + 50 * s, y: finger.y - 30 * s))
            }
        }
    }

    // MARK: 描画の部品

    /// ミートカーソル（打席のカーソルと同じ寸法・`scale` は図の縮尺）。
    private static func cursor(_ ctx: inout GraphicsContext, at p: CGPoint, scale: CGFloat) {
        let cr = HomerunJudge.contactRadius * scale
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2)),
                   with: .color(Theme.teal), lineWidth: 3 * scale)
        let core = HomerunJudge.coreRadius * scale
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                   with: .color(Theme.teal.opacity(0.7)), lineWidth: 1.5 * scale)
        var cross = Path()
        let t = 4 * scale
        cross.move(to: CGPoint(x: p.x - cr - t, y: p.y)); cross.addLine(to: CGPoint(x: p.x - cr + t, y: p.y))
        cross.move(to: CGPoint(x: p.x + cr - t, y: p.y)); cross.addLine(to: CGPoint(x: p.x + cr + t, y: p.y))
        cross.move(to: CGPoint(x: p.x, y: p.y - cr - t)); cross.addLine(to: CGPoint(x: p.x, y: p.y - cr + t))
        cross.move(to: CGPoint(x: p.x, y: p.y + cr - t)); cross.addLine(to: CGPoint(x: p.x, y: p.y + cr + t))
        ctx.stroke(cross, with: .color(Theme.teal), lineWidth: 2 * scale)
    }

    /// 球（白）・的（白い細い輪）・縮む輪（コーラル・`ringDiameter`）。
    private static func target(_ ctx: inout GraphicsContext, at c: CGPoint, ringDiameter: Double, scale: CGFloat) {
        let ballR = 7.0 * scale
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - ballR, y: c.y - ballR, width: ballR * 2, height: ballR * 2)), with: .color(.white))
        let t = HomerunZoneGeometry.targetDiameter / 2 * scale
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - t, y: c.y - t, width: t * 2, height: t * 2)),
                   with: .color(.white), lineWidth: max(1, HomerunZoneGeometry.targetLineWidth * scale))
        let r = ringDiameter / 2 * scale
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(Theme.coral), lineWidth: HomerunZoneGeometry.ringLineWidth * scale)
    }

    private static func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, lineWidth: CGFloat, dash: [CGFloat]) {
        var line = Path()
        line.move(to: a); line.addLine(to: b)
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: dash))
        head(&ctx, at: b, from: a, color: color, size: lineWidth * 3.2)
    }

    private static func doubleArrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, color: Color, lineWidth: CGFloat) {
        var line = Path()
        line.move(to: a); line.addLine(to: b)
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        head(&ctx, at: b, from: a, color: color, size: lineWidth * 3.2)
        head(&ctx, at: a, from: b, color: color, size: lineWidth * 3.2)
    }

    private static func head(_ ctx: inout GraphicsContext, at tip: CGPoint, from: CGPoint, color: Color, size: CGFloat) {
        let ang = atan2(tip.y - from.y, tip.x - from.x)
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - size * cos(ang - 0.5), y: tip.y - size * sin(ang - 0.5)))
        p.addLine(to: CGPoint(x: tip.x - size * cos(ang + 0.5), y: tip.y - size * sin(ang + 0.5)))
        p.closeSubpath()
        ctx.fill(p, with: .color(color))
    }
}

// MARK: - 隠し要素の匂わせ（夜空・月のシルエット・？？？）

/// 夜空（`HomerunMoonArt.stars`）・月（`HomerunMoonArt` の地の色とクレーターを円板に投影）・地上のシルエット（おじさん）・
/// 月へ向かう球の点線。答え（月まで飛ぶ）も条件の数値も書かない。
struct HomerunMoonTeaserFigure: View {
    private static let skyTop = Color(red: 0.03, green: 0.04, blue: 0.14)
    private static let skyBottom = Color(red: 0.16, green: 0.18, blue: 0.40)
    private static let ground = Color(red: 0.04, green: 0.05, blue: 0.10)

    private static func color(_ c: (UInt8, UInt8, UInt8)) -> Color {
        Color(red: Double(c.0) / 255, green: Double(c.1) / 255, blue: Double(c.2) / 255)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let r = min(size.width, size.height) * 0.26
            let moon = CGPoint(x: size.width * 0.64, y: size.height * 0.30)
            ZStack {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(Gradient(colors: [Self.skyTop, Self.skyBottom]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    for star in HomerunMoonArt.stars {
                        let sr = star.radius
                        ctx.fill(Path(ellipseIn: CGRect(x: star.x * size.width - sr, y: star.y * size.height * 0.8 - sr, width: sr * 2, height: sr * 2)),
                                 with: .color(Color(red: 1, green: 0.97, blue: 0.85)))
                    }
                    // 月: 地の色とクレーター（正面を向くものを円板に投影）。夜空の色を薄く重ねてシルエット寄りに。
                    let disc = Path(ellipseIn: CGRect(x: moon.x - r, y: moon.y - r, width: r * 2, height: r * 2))
                    ctx.drawLayer { layer in
                        layer.clip(to: disc)
                        layer.fill(disc, with: .color(Self.color(HomerunMoonArt.surface)))
                        for crater in HomerunMoonArt.craters where crater.direction.z > 0.3 {
                            let p = CGPoint(x: moon.x + CGFloat(crater.direction.x) * r, y: moon.y - CGFloat(crater.direction.y) * r)
                            let cr = CGFloat(sin(crater.radius)) * r
                            let c = Path(ellipseIn: CGRect(x: p.x - cr, y: p.y - cr, width: cr * 2, height: cr * 2))
                            layer.fill(c, with: .color(Self.color(HomerunMoonArt.craterFill)))
                            layer.stroke(c, with: .color(Self.color(HomerunMoonArt.craterRim)), lineWidth: max(1, r * 0.035))
                        }
                        layer.fill(disc, with: .color(Self.skyTop.opacity(0.42)))
                    }
                    ctx.stroke(disc, with: .color(Self.color(HomerunMoonArt.crack)), lineWidth: 2.5)
                    // 地上: 黒いスタンドの稜線。
                    var ground = Path()
                    ground.move(to: CGPoint(x: 0, y: size.height))
                    ground.addLine(to: CGPoint(x: 0, y: size.height * 0.80))
                    ground.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.80))
                    ground.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.84))
                    ground.addLine(to: CGPoint(x: size.width, y: size.height * 0.84))
                    ground.addLine(to: CGPoint(x: size.width, y: size.height))
                    ground.closeSubpath()
                    ctx.fill(ground, with: .color(Self.ground))
                    // 球の点線（左下の打者から月へ）と、途中の球。
                    let from = CGPoint(x: size.width * 0.24, y: size.height * 0.70)
                    var arc = Path()
                    arc.move(to: from)
                    arc.addQuadCurve(to: CGPoint(x: moon.x - r * 0.75, y: moon.y + r * 0.55),
                                     control: CGPoint(x: size.width * 0.30, y: size.height * 0.28))
                    ctx.stroke(arc, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 7]))
                    let b = CGPoint(x: size.width * 0.33, y: size.height * 0.40)
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - 9, y: b.y - 9, width: 18, height: 18)), with: .color(.white.opacity(0.18)))
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - 5, y: b.y - 5, width: 10, height: 10)), with: .color(.white))
                }
                // 打者のシルエット（ハブと同じおじさん）。
                OjisanCanvas(parts: OjisanArt.poseParts(.mascotFront))
                    .colorMultiply(Self.ground)
                    .frame(width: size.height * 0.34, height: size.height * 0.34)
                    .position(x: size.width * 0.20, y: size.height * 0.70)
                Text("？？？")
                    .font(.system(size: r * 0.62, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .position(moon)
            }
        }
    }
}
