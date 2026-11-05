import SwiftUI
import ImageIO
import Core
import HomerunCore

// ハブ先頭の特別枠（#1761・会長決裁 2026-10-02）。会長提供のロゴ入り横長画像を 2.05:1 のカードに
// 上端合わせで入れ（下を切る。ロゴ・顔・バット・ボールは絵の上 73% に収まり、足元だけが切れる）、
// 右下に札（今日の残り回数の点・自己ベスト）だけを重ねる。タイトル文字は重ねない。

/// 特別枠に載せる値（今日の残り回数・自己ベスト）。台帳と蓄積は打席前の画面と同じ保存先から読む。
struct HomerunHubHeroInfo {
    var remaining: Int
    var allowance: Int
    /// 自己ベスト（1 挑戦の合計飛距離・m）。記録が無ければ nil。
    var bestMeters: Double?

    static func load(now: Date = Date()) -> HomerunHubHeroInfo {
        let ledger = HomerunHubCount.todayLedger(now: now)
        let records = HomerunStorage.loadRecords()
        return HomerunHubHeroInfo(remaining: ledger.remaining, allowance: ledger.allowance,
                                  bestMeters: records.bestTotalTenths > 0 ? Double(records.bestTotalTenths) / 10 : nil)
    }

    var bestText: String? { bestMeters.map { HomerunText.meters($0) } }

    func accessibilityLabel(description: String) -> String {
        var parts = [tr("柵越えおじさん"), description, tr("今日の挑戦 残り %lld 回", remaining)]
        if let bestText { parts.append(tr("自己ベスト %@", bestText)) }
        return parts.joined(separator: tr("、"))
    }
}

/// ハブの横長タイル（アプリの `HubView` の `GameCard`）の右下に出す、今日の残り回数のラベル（#2208）。
/// 数は打席前の「打席に立つ」のボールと同じ台帳の `remaining`（無料 3 回＋月のご褒美）。広告でのプレイは回数を増やさない
/// （`HomerunLedger.consumeAdPlay`）ので数に入らない。読むだけで保存はしない（0:00 の補充の保存は打席前の画面が行う）。
public enum HomerunHubCount {
    /// 保存された台帳を `now` の日付へ進めた（0:00 を越えていたら戻した）ときの残り回数。
    public static func remaining(now: Date = Date(), defaults: UserDefaults = .standard,
                                 calendar: Calendar = .current) -> Int {
        todayLedger(now: now, defaults: defaults, calendar: calendar).remaining
    }

    static func todayLedger(now: Date, defaults: UserDefaults = .standard, calendar: Calendar = .current) -> HomerunLedger {
        var ledger = HomerunStorage.loadLedger(defaults)
        ledger.roll(to: HomerunLedger.dayKey(for: now, calendar: calendar))
        return ledger
    }

    /// 次に回数が戻る時刻（翌 0:00）。打席前の画面と同じ `HomerunReturnPolicy` の境目。
    public static func nextReset(after now: Date, calendar: Calendar = .current) -> Date {
        HomerunReturnPolicy.nextReset(after: now, calendar: calendar)
    }

    /// 今日の残り回数と 1 日の上限（無料 3 回＋月のご褒美）。ハブはボールを上限ぶん並べ、残りだけを白くする（#2273）。
    public struct Tally: Equatable, Sendable {
        public var remaining: Int
        public var allowance: Int

        public init(remaining: Int, allowance: Int) {
            self.remaining = remaining
            self.allowance = allowance
        }

        /// ボールの並べ方。上限ぶん並べて先頭 `lit` 個を残り（白）にする。上限が多すぎて並ばないとき
        /// （打席前の `HomerunCountMeter` と同じ 6 個以上）は nil で、呼び出し側はボール 1 つ＋「×残り」で出す。
        public var dots: (total: Int, lit: Int)? {
            switch HomerunCountDisplay(allowance: allowance, remaining: remaining) {
            case .dots(let total, let lit): return (total, min(lit, total))
            case .number: return nil
            }
        }

        /// VoiceOver で読む数（今までどおり「残り n 回」）。
        public func labelText(language: AppLanguage? = nil) -> String {
            HomerunHubCount.labelText(remaining: remaining, language: language)
        }
    }

    /// 保存された台帳を `now` の日付へ進めたときの残り回数と上限。
    public static func tally(now: Date = Date(), defaults: UserDefaults = .standard,
                             calendar: Calendar = .current) -> Tally {
        let ledger = todayLedger(now: now, defaults: defaults, calendar: calendar)
        return Tally(remaining: ledger.remaining, allowance: ledger.allowance)
    }

    /// ラベルの文字。0 回も隠さず「残り 0 回」（打席前のボタンも 0 を消さずに灰色のボールで見せる）。広告の案内は付けない。
    public static func labelText(remaining: Int, language: AppLanguage? = nil) -> String {
        tr("残り %lld 回", max(0, remaining), language: language)
    }
}

/// ハブの特別枠。遷移は呼び出し側の `NavigationLink(value:)` に任せる（グリッドのカードと同じ作法）。
public struct HomerunHubHeroCard: View {
    private let info: HomerunHubHeroInfo
    /// 下の白い帯に出すゲームの説明（`HomerunModule.description`。ハブの `GameCard` と同じ文）。
    private let description: String

    public init(description: String) {
        self.description = description
        info = .load()
    }

    public var body: some View {
        HomerunHeroLogoImageCard(info: info, description: description)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(info.accessibilityLabel(description: description))
            .accessibilityHint(tr("柵越えおじさんを開きます"))
    }
}

// MARK: - 部品

/// 今日の残り回数の点表示。打席前の `HomerunCountMeter` と同じ見せ方（野球のボール・残りだけ色付き）を小さくしたもの。
struct HomerunHeroCountDots: View {
    let allowance: Int
    let remaining: Int
    var size: CGFloat = 14
    var lit: Color = Theme.coralText
    var dim: Color = Theme.inkSub.opacity(0.35)

    var body: some View {
        switch HomerunCountDisplay(allowance: allowance, remaining: remaining) {
        case .dots(let total, let litCount):
            HStack(spacing: size * 0.3) {
                ForEach(0..<total, id: \.self) { i in
                    Image(systemName: "baseball.fill")
                        .font(.system(size: size)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                        .foregroundStyle(i < litCount ? lit : dim)
                }
            }
        case .number(let remaining):
            HStack(spacing: 4) {
                Image(systemName: "baseball.fill").font(.system(size: size)).foregroundStyle(remaining > 0 ? lit : dim) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                Text(verbatim: "×\(remaining)")
                    .font(.system(size: size, weight: .heavy, design: .rounded).monospacedDigit()) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
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
                Text(tr("・"))
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

/// ロゴが絵に描き込まれているので、重ねるのは右下の札だけ（ロゴ = 上 30%・顔 = 左の中段・ボール = 右の中段に
/// 重ねない）。絵の部分は比率 2.05:1 で**上端を合わせて下を切る**（カード全体の上 80%）。
/// その下に `GameCard` と同じ白い面の帯（カード全体の下 20%）を足し、ゲームの説明を `GameCard` の説明文と同じ書体・色で入れる。
struct HomerunHeroLogoImageCard: View {
    let info: HomerunHubHeroInfo
    let description: String
    @Environment(\.adaptiveLayout) private var adaptive

    private static let ink = Color(red: 0x2B / 255, green: 0x26 / 255, blue: 0x34 / 255)
    // GameKit は macOS でもビルドされる（`swift test`）ので UIImage は使わず ImageIO で読む。
    private static let image: CGImage? = Bundle.module.url(forResource: "HomerunHubHeroArtLogo", withExtension: "jpg")
        .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    /// 絵の比率（1536 × 1024 の縮小版）。
    private static let imageAspect: CGFloat = 1536 / 1024

    var body: some View {
        VStack(spacing: 0) {
            art
            band
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    /// 上 80%: ロゴ入りの絵・右下の札。
    private var art: some View {
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
                HStack(alignment: .bottom) { Spacer(minLength: 0); HomerunHeroCompactPill(info: info) }
                .padding(12)
                .frame(width: w, height: h, alignment: .bottom)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(AdaptiveLayout.hubHeroAspect, contentMode: .fit)
    }

    /// 下 20%: `GameCard` と同じ白い面に、説明を `GameCard` の説明文と同じ書体・色・1 行（縮小）で。
    /// 高さは絵の 1/4（= カード全体の 20%）を下限にし、Dynamic Type で文字が伸びたぶんだけ増える。
    private var band: some View {
        GeometryReader { geo in
            Text(description)
                .themeCaption(adaptive.scaled(11))
                .foregroundStyle(Theme.inkSubText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, adaptive.scaled(10))
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .aspectRatio(AdaptiveLayout.hubHeroAspect / AdaptiveLayout.hubHeroBandRatio, contentMode: .fit)
        .background(Theme.surface)
    }
}
