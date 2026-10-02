import SwiftUI
import ImageIO
import Core
import HomerunCore

// ハブ先頭の特別枠（#1761・会長決裁 2026-10-02）。会長提供のロゴ入り横長画像を 2.05:1 のカードに
// 上端合わせで入れ（下を切る。ロゴ・顔・バット・ボールは絵の上 73% に収まり、足元だけが切れる）、
// 左下に「体験版」・右下に札（今日の残り回数の点・自己ベスト）だけを重ねる。タイトル文字は重ねない。

/// 特別枠に載せる値（今日の残り回数・自己ベスト）。台帳と蓄積は打席前の画面と同じ保存先から読む。
struct HomerunHubHeroInfo {
    var remaining: Int
    var allowance: Int
    /// 自己ベスト（1 挑戦の合計飛距離・m）。記録が無ければ nil。
    var bestMeters: Double?

    static func load(now: Date = Date()) -> HomerunHubHeroInfo {
        var ledger = HomerunStorage.loadLedger()
        ledger.roll(to: HomerunLedger.dayKey(for: now))
        let records = HomerunStorage.loadRecords()
        return HomerunHubHeroInfo(remaining: ledger.remaining, allowance: ledger.allowance,
                                  bestMeters: records.bestTotalTenths > 0 ? Double(records.bestTotalTenths) / 10 : nil)
    }

    var bestText: String? { bestMeters.map { HomerunText.meters($0) } }

    var accessibilityLabel: String {
        var parts = ["柵越えおじさん", "体験版", "今日の挑戦 残り \(remaining) 回"]
        if let bestText { parts.append("自己ベスト \(bestText)") }
        return parts.joined(separator: "、")
    }
}

/// ハブの特別枠。遷移は呼び出し側の `NavigationLink(value:)` に任せる（グリッドのカードと同じ作法）。
public struct HomerunHubHeroCard: View {
    private let info: HomerunHubHeroInfo

    public init() {
        info = .load()
    }

    public var body: some View {
        HomerunHeroLogoImageCard(info: info)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(info.accessibilityLabel)
            .accessibilityHint("柵越えおじさんを開きます")
    }
}

// MARK: - 部品

/// 「体験版」の印。打席前の画面（`HomerunLobbyView.introCard`）と同じ部品・同じ配色。
struct HomerunHeroTrialBadge: View {
    var body: some View {
        Label("体験版", systemImage: "sparkles")
            .themeCaption(12)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Theme.Fill.purple))
            .fixedSize()
    }
}

/// 今日の残り回数の点表示。打席前の `HomerunCountMeter` と同じ見せ方（野球のボール・残りだけ色付き）を小さくしたもの。
struct HomerunHeroCountDots: View {
    let allowance: Int
    let remaining: Int
    var size: CGFloat = 14
    var lit: Color = Theme.coral
    var dim: Color = Theme.inkSub.opacity(0.35)

    var body: some View {
        switch HomerunCountDisplay(allowance: allowance, remaining: remaining) {
        case .dots(let total, let litCount):
            HStack(spacing: size * 0.3) {
                ForEach(0..<total, id: \.self) { i in
                    Image(systemName: "baseball.fill")
                        .font(.system(size: size))
                        .foregroundStyle(i < litCount ? lit : dim)
                }
            }
        case .number(let remaining):
            HStack(spacing: 4) {
                Image(systemName: "baseball.fill").font(.system(size: size)).foregroundStyle(remaining > 0 ? lit : dim)
                Text(verbatim: "×\(remaining)")
                    .font(.system(size: size, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(remaining > 0 ? lit : dim)
            }
        }
    }
}

/// 残り回数と自己ベストを 1 つの小さな白い札にまとめたもの。絵を主役にするため言葉は省き、点と数字だけ。
/// 言葉は VoiceOver のラベル（`HomerunHubHeroInfo.accessibilityLabel`）が持つ。
struct HomerunHeroCompactPill: View {
    let info: HomerunHubHeroInfo
    @Environment(\.adaptiveLayout) private var adaptive

    var body: some View {
        HStack(spacing: 6) {
            HomerunHeroCountDots(allowance: info.allowance, remaining: info.remaining, size: adaptive.scaled(12),
                                 dim: Color(hex: Theme.Hex.inkSub.light).opacity(0.35))
            if let best = info.bestText {
                Text("・")
                    .themeCaption(adaptive.scaled(11))
                    .foregroundStyle(Color(hex: Theme.Hex.inkSub.light))
                Label(best, systemImage: "chart.bar.fill")
                    .themeCaption(adaptive.scaled(11))
                    .foregroundStyle(Theme.Fixed.ink)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.92)))
        .fixedSize()
    }
}

// MARK: - ロゴ入りの横長の静止画

/// ロゴが絵に描き込まれているので、重ねるのは左下の「体験版」と右下の札だけ（ロゴ = 上 30%・顔 = 左の中段・ボール = 右の中段に
/// 重ねない）。カードの比率（2.05:1）で**上端を合わせて下を切る**。
struct HomerunHeroLogoImageCard: View {
    let info: HomerunHubHeroInfo

    private static let ink = Color(red: 0x2B / 255, green: 0x26 / 255, blue: 0x34 / 255)
    // GameKit は macOS でもビルドされる（`swift test`）ので UIImage は使わず ImageIO で読む。
    private static let image: CGImage? = Bundle.module.url(forResource: "HomerunHubHeroArtLogo", withExtension: "jpg")
        .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    /// 絵の比率（1536 × 1024 の縮小版）。
    private static let imageAspect: CGFloat = 1536 / 1024

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Color(red: 0.16, green: 0.45, blue: 0.86)
                if let image = Self.image {
                    Color.clear.frame(width: w, height: h)
                        .overlay(alignment: .top) {
                            Image(decorative: image, scale: 1).resizable()
                                .frame(width: w, height: w / Self.imageAspect)
                        }
                        .clipped()
                }
                // 下 1/4 だけ少し暗くして札を読めるようにする（ロゴのある上は触らない）。
                LinearGradient(stops: [.init(color: .clear, location: 0.7), .init(color: Self.ink.opacity(0.45), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: w, height: h)
                // Dynamic Type で札が伸びて横に収まらないときは、縦に積む（カードの高さは比率で決まるので折り返しは使えない）。
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom) { badge; Spacer(minLength: 0); HomerunHeroCompactPill(info: info) }
                    VStack(alignment: .leading, spacing: 4) { HomerunHeroCompactPill(info: info); badge }
                }
                .padding(12)
                .frame(width: w, height: h, alignment: .bottom)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(AdaptiveLayout.hubHeroAspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private var badge: some View {
        HomerunHeroTrialBadge()
            .shadow(color: Self.ink.opacity(0.3), radius: 3, y: 2)
    }
}
