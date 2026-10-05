import SwiftUI
import Core
import HomerunCore
import ImageIO

/// 10 球が終わってから結果画面に移るまでに挟む演出の区分（会長決裁 2026-10-05）。
///
/// | 条件 | 表示名 | おじさんの絵 |
/// |---|---|---|
/// | 柵越え 10 本 | パーフェクト | ガッツポーズ |
/// | 8〜9 本 | エクセレント | 万歳ジャンプ |
/// | 4〜7 本 | グッド | 親指を立てる |
/// | 0〜3 本 | ドンマイ | うずくまって泣く |
/// | 月に 2 回当てて月が割れた（本数を問わない） | 月が割れた | 隕石の下敷き |
///
/// 自己ベストを更新したら、どの区分にも「ニューレコード」を重ねる（`HomerunModel.isNewBest`）。
/// 絵はすべて静止画（動かさない）。素材の出所は `docs/design/homerun/assets-license.md`。
public enum HomerunFinale: Equatable, Sendable {
    case perfect, excellent, good, donmai, moonBroken

    /// 柵越えの本数と、月が割れたかから区分を決める。月が割れたら本数を問わず `.moonBroken`。
    public init(homers: Int, moonBroken: Bool) {
        if moonBroken {
            self = .moonBroken
            return
        }
        switch homers {
        case 10...: self = .perfect
        case 8...9: self = .excellent
        case 4...7: self = .good
        default: self = .donmai
        }
    }

    public init(challenge: HomerunChallenge) {
        self.init(homers: challenge.homerCount, moonBroken: challenge.isMoonBroken)
    }

    /// 大きく出す表示名。
    public var title: String {
        switch self {
        case .perfect: "パーフェクト！"
        case .excellent: "エクセレント！"
        case .good: "グッド！"
        case .donmai: "ドンマイ…"
        case .moonBroken: "月が割れた！"
        }
    }

    /// おじさんの絵（`Resources/Finale` の PNG・長辺 750px・背景透明）。
    var artName: String {
        switch self {
        case .perfect: "HomerunFinalePerfect"
        case .excellent: "HomerunFinaleExcellent"
        case .good: "HomerunFinaleGood"
        case .donmai: "HomerunFinaleDonmai"
        case .moonBroken: "HomerunFinaleMoonBroken"
        }
    }

    /// 背景のグラデーション（上 → 下）。
    var colors: [Color] {
        switch self {
        case .perfect: [Color(red: 1.0, green: 0.86, blue: 0.25), Color(red: 1.0, green: 0.55, blue: 0.1)]
        case .excellent: [Color(red: 1.0, green: 0.6, blue: 0.45), Color(red: 0.93, green: 0.3, blue: 0.4)]
        case .good: [Color(red: 0.45, green: 0.8, blue: 1.0), Color(red: 0.2, green: 0.5, blue: 0.9)]
        case .donmai: [Color(red: 0.55, green: 0.6, blue: 0.7), Color(red: 0.3, green: 0.33, blue: 0.42)]
        case .moonBroken: [Color(red: 0.03, green: 0.04, blue: 0.14), Color(red: 0.16, green: 0.14, blue: 0.34)]
        }
    }

    /// 表示名の影の色。
    var titleShadow: Color {
        switch self {
        case .perfect: Color(red: 0.75, green: 0.2, blue: 0.05)
        case .excellent: Color(red: 0.6, green: 0.08, blue: 0.2)
        case .good: Color(red: 0.05, green: 0.25, blue: 0.6)
        case .donmai: Color(red: 0.2, green: 0.22, blue: 0.3)
        case .moonBroken: Color(red: 0.45, green: 0.3, blue: 0.05)
        }
    }

    /// 背景の放射線を出すか（喜びの区分だけ）。
    var hasRays: Bool { self == .perfect || self == .excellent || self == .good }
}

/// 結果の演出（打席の上に重ねる全画面）。おじさんは静止画。表示名がはねて入り、本数と合計飛距離を数え上げる。
/// タップで飛ばして結果画面へ（`HomerunModel.skipFinale`）。視差効果を減らす設定では動かさず、最後の姿だけを出す。
struct HomerunFinaleView: View {
    let model: HomerunModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let finale = model.finale ?? .donmai
        let homers = model.challenge?.homerCount ?? 0
        let total = model.challenge?.totalDistance ?? 0
        TimelineView(AnimationTimelineSchedule(minimumInterval: nil, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? HomerunModel.finaleDuration : timeline.date.timeIntervalSince(model.finaleStart ?? timeline.date)
            GeometryReader { geo in
                HomerunFinaleScene(finale: finale, t: t, size: geo.size, homers: homers, total: total,
                                   isNewBest: model.isNewBest, reduceMotion: reduceMotion)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture { withGameAnimation(.easeOut(duration: 0.2)) { model.skipFinale() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(finale, homers: homers, total: total, isNewBest: model.isNewBest))
        .accessibilityHint("タップで結果へ進みます")
        .accessibilityAddTraits(.isButton)
    }

    static func accessibilityText(_ finale: HomerunFinale, homers: Int, total: Double, isNewBest: Bool) -> String {
        "\(finale.title) 柵越え \(homers) 本、合計 \(HomerunText.meters(total))" + (isNewBest ? "、ニューレコード" : "")
    }
}

/// 演出の、時刻 `t`（演出の始まりからの秒）の 1 コマ。モデルを持たない。
struct HomerunFinaleScene: View {
    let finale: HomerunFinale
    let t: TimeInterval
    let size: CGSize
    let homers: Int
    let total: Double
    let isNewBest: Bool
    let reduceMotion: Bool

    var body: some View { content(finale, t: t, size: size, homers: homers, total: total) }

    private func content(_ finale: HomerunFinale, t: TimeInterval, size: CGSize, homers: Int, total: Double) -> some View {
        let bgIn = ease(t / 0.25)
        let ojisanIn = spring((t - 0.1) / 0.45)
        let titleIn = spring((t - 0.3) / 0.4)
        let count = ease((t - 0.6) / 0.9)
        let side = min(size.width * 0.58, 250.0) * 1.15
        return ZStack {
            Color.black.opacity(0.35 * bgIn)
            LinearGradient(colors: finale.colors, startPoint: .top, endPoint: .bottom)
                .opacity(0.92 * bgIn)
            if finale.hasRays {
                HomerunFinaleRays(rays: 16)
                    .fill(.white.opacity(finale == .perfect ? 0.22 : 0.14))
                    .frame(width: size.height * 1.4, height: size.height * 1.4)
                    .rotationEffect(.degrees(t * 18))
                    .position(x: size.width / 2, y: size.height * 0.47)
                    .opacity(bgIn)
            }
            if !reduceMotion, finale == .perfect || finale == .excellent {
                HomerunFinaleConfetti(t: t, size: size, count: finale == .perfect ? 46 : 26)
            }
            if !reduceMotion, finale == .donmai {
                HomerunFinaleRain(t: t, size: size)
            }
            if finale == .moonBroken {
                HomerunFinaleStars(size: size).opacity(bgIn)
            }

            VStack(spacing: 0) {
                Spacer().frame(height: size.height * 0.15)
                Text(verbatim: finale.title)
                    .font(.system(size: finale == .donmai ? 52 : 58, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: finale.titleShadow, radius: 0, x: 0, y: 5)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 6)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: size.width - 48)
                    .scaleEffect(1 + (1 - titleIn) * 1.4)
                    .rotationEffect(.degrees(finale == .donmai ? -4 * titleIn : 0))
                    .opacity(clamp((t - 0.3) / 0.12))
                HomerunFinaleArt(name: finale.artName)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                    // ニューレコードの判子は絵の左下（足元の外側）。どの区分の絵でも顔にかからない（会長指摘 2026-10-05）。
                    .overlay(alignment: .bottomLeading) {
                        if isNewBest {
                            stamp(t: t, appear: spring((t - 1.5) / 0.4), size: 84)
                                .offset(x: -22, y: 6)
                        }
                    }
                    .offset(y: finale == .donmai ? 18 : 0)
                    .scaleEffect(0.55 + 0.45 * ojisanIn)
                    .opacity(clamp((t - 0.1) / 0.15))
                    .padding(.top, 10)
                HStack(spacing: 10) {
                    statChip("柵越え", "\(Int((Double(homers) * count).rounded(.down))) 本")
                    statChip("合計", HomerunText.meters(total * count))
                }
                .opacity(clamp((t - 0.55) / 0.15))
                .padding(.top, 14)
                // ニューレコードの帯は本数・距離の下に水平に（おじさんの絵に重ねない）。
                if isNewBest {
                    band(appear: spring((t - 1.5) / 0.4), width: size.width)
                        .padding(.top, 18)
                }
                Spacer()
                Text("タップで次へ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .opacity(t > 0.9 ? (reduceMotion ? 1 : 0.55 + 0.45 * abs(sin(t * 3))) : 0)
                    .padding(.bottom, size.height * 0.06)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// ニューレコードの帯（本数・距離の下・水平）。右から滑り込む。
    private func band(appear: Double, width: CGFloat) -> some View {
        Text("ニューレコード！")
            .font(.system(size: 24, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .frame(width: width)
            .background(
                LinearGradient(colors: [Color(red: 0.95, green: 0.15, blue: 0.35), Color(red: 1, green: 0.4, blue: 0.2)],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(Rectangle().stroke(.yellow, lineWidth: 3).padding(.vertical, 3))
            .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
            .offset(x: (1 - appear) * width * 1.2)
    }

    /// ニューレコードの「自己ベスト更新」の判子（おじさんの絵の左下・足元の外側）。
    private func stamp(t: TimeInterval, appear: Double, size: CGFloat) -> some View {
        Circle()
            .fill(Color.yellow)
            .overlay(Circle().stroke(Color(red: 0.9, green: 0.2, blue: 0.2), lineWidth: 5).padding(5))
            .overlay(
                VStack(spacing: -2) {
                    Text("自己").font(.system(size: size * 0.16, weight: .black))
                    Text("ベスト").font(.system(size: size * 0.18, weight: .black))
                    Text("更新").font(.system(size: size * 0.16, weight: .black))
                }
                .foregroundStyle(Color(red: 0.85, green: 0.15, blue: 0.15))
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-12))
            .scaleEffect((0.2 + 0.8 * appear) * (reduceMotion ? 1 : 1 + 0.05 * sin(t * 8)))
            .opacity(appear > 0.01 ? 1 : 0)
    }

    private func statChip(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(verbatim: label).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(white: 0.35))
            Text(verbatim: value).font(.system(size: 28, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(white: 0.1))
        }
        .frame(minWidth: 120)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .shadow(color: .black.opacity(0.2), radius: 0, y: 4)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    private func ease(_ x: Double) -> Double {
        let c = clamp(x)
        return 1 - pow(1 - c, 3)
    }

    /// 行き過ぎて戻るばね（0 → 1）。
    private func spring(_ x: Double) -> Double {
        let c = clamp(x)
        return 1 - exp(-6 * c) * cos(c * 9)
    }
}

/// 結果の演出の絵（`Resources/Finale`）。読めなければ何も描かない。
struct HomerunFinaleArt: View {
    let name: String

    var body: some View {
        Group {
            if let image = Self.image(name) {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
    }

    @MainActor private static var cache: [String: CGImage] = [:]

    @MainActor
    static func image(_ name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Finale"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache[name] = image
        return image
    }
}

// MARK: - 背景の飾り（2D）

private struct HomerunFinaleRays: Shape {
    var rays: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = max(rect.width, rect.height)
        let step = .pi * 2 / Double(rays)
        for i in 0..<rays {
            let a = Double(i) * step
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
            p.addLine(to: CGPoint(x: c.x + r * cos(a + step / 2), y: c.y + r * sin(a + step / 2)))
            p.closeSubpath()
        }
        return p
    }
}

private struct HomerunFinaleConfetti: View {
    let t: TimeInterval
    let size: CGSize
    let count: Int
    private static let palette: [Color] = [.red, .yellow, .blue, .green, .pink, .orange, .white]

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let seed = Double(i) * 12.9898
                let x = (sin(seed) * 0.5 + 0.5) * size.width
                let delay = (sin(seed * 3.1) * 0.5 + 0.5) * 0.8
                let speed = 220 + (sin(seed * 7.7) * 0.5 + 0.5) * 220
                let y = -20 + max(0, t - 0.3 - delay) * speed
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.palette[i % Self.palette.count])
                    .frame(width: 9, height: 14)
                    .rotationEffect(.radians(t * (3 + Double(i % 5))))
                    .position(x: x + sin(t * 3 + seed) * 18, y: y)
            }
        }
    }
}

private struct HomerunFinaleRain: View {
    let t: TimeInterval
    let size: CGSize
    var body: some View {
        ZStack {
            ForEach(0..<30, id: \.self) { i in
                let seed = Double(i) * 4.37
                let x = (sin(seed) * 0.5 + 0.5) * size.width
                let y = ((cos(seed * 2.3) * 0.5 + 0.5) * size.height + t * 520).truncatingRemainder(dividingBy: max(size.height, 1))
                Capsule().fill(.white.opacity(0.35)).frame(width: 2, height: 18).position(x: x, y: y)
            }
        }
    }
}

private struct HomerunFinaleStars: View {
    let size: CGSize
    var body: some View {
        ZStack {
            ForEach(0..<40, id: \.self) { i in
                let seed = Double(i) * 7.13
                Circle().fill(.white.opacity(0.4 + 0.5 * (sin(seed * 5) * 0.5 + 0.5)))
                    .frame(width: 2 + 2 * (sin(seed * 9) * 0.5 + 0.5))
                    .position(x: (sin(seed) * 0.5 + 0.5) * size.width, y: (cos(seed * 1.7) * 0.5 + 0.5) * size.height * 0.55)
            }
        }
    }
}
