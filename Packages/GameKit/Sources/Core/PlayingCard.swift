import SwiftUI

/// トランプ54枚（実カード52枚 + ジョーカー2枚）の共通描画基盤（#397）。
///
/// ポーカー・ブラックジャック・大富豪・ソリティアはそれぞれ**ルールの都合で別のカード型**を持つ
/// （ポーカーは A=14、大富豪は 3 が最弱、ソリティアはジョーカーが中継札）。モデルを1つに統合すると
/// ルール側が歪むので、**描画に必要な情報だけをこの型へ写して共有する**。
/// 紙・裏面の質感は `CardStyle`（#366）が持ち、ここはその上に載る「面の中身」を受け持つ。
///
/// 神経衰弱は絵柄が独自（トランプではない）ため対象外。

// MARK: - スート

/// トランプ4スート。描画専用なので `Codable` にはしない（保存はゲーム側のカード型が持つ）。
public enum PlayingCardSuit: Int, CaseIterable, Sendable, Equatable {
    case spade = 0, heart = 1, diamond = 2, club = 3

    public var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }

    public var isRed: Bool { self == .heart || self == .diamond }

    /// VoiceOver 用の読み（記号のままだと読み上げが端末設定に左右されるため文字で持つ）。
    public var spokenName: String { ["スペード", "ハート", "ダイヤ", "クラブ"][rawValue] }
}

// MARK: - 面に描くもの

/// カードの表に描く内容。実カード（スート + ランク）か、ジョーカーか。
///
/// `rank` は **1 = A 〜 13 = K** に正規化する。ポーカーのように A を 14 として扱うゲームは
/// 変換して渡す（強さの表現はゲーム側の関心で、面の表記とは別物）。
public enum PlayingCardFigure: Sendable, Equatable {
    case pip(suit: PlayingCardSuit, rank: Int)
    case joker

    /// 面の中央に出す数字・絵札の文字。
    public var rankLabel: String {
        switch self {
        case .joker: return "JOKER"
        case .pip(_, let rank):
            switch rank {
            case 1:  return "A"
            case 11: return "J"
            case 12: return "Q"
            case 13: return "K"
            default: return "\(rank)"
            }
        }
    }

    /// ログ・デバッグ用の短い表記（例: "♠A"）。
    public var label: String {
        switch self {
        case .joker: return "JOKER"
        case .pip(let suit, _): return "\(suit.symbol)\(rankLabel)"
        }
    }

    /// VoiceOver 用の読み上げ文（例: "スペードのA"）。
    public var spokenLabel: String {
        switch self {
        case .joker: return "ジョーカー"
        case .pip(let suit, _): return "\(suit.spokenName)の\(rankLabel)"
        }
    }
}

// MARK: - 寸法

/// カード1枚の寸法と文字サイズ。ゲームごとに札の大きさが違うため、面の中身は
/// この値を受け取って組む（View 側でハードコードしない）。
public struct PlayingCardMetrics: Sendable, Equatable {
    public let width: CGFloat
    public let height: CGFloat
    public let cornerRadius: CGFloat
    public let rankFont: CGFloat
    public let suitFont: CGFloat
    /// ランクとスートの行間。札が小さいほど詰める。
    public let pipSpacing: CGFloat
    /// 裏面中央のスート印の大きさ。表のスートよりわずかに大きく取る。
    public let backMotifFont: CGFloat

    public init(width: CGFloat, height: CGFloat, cornerRadius: CGFloat = 8,
                rankFont: CGFloat, suitFont: CGFloat, pipSpacing: CGFloat,
                backMotifFont: CGFloat) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.rankFont = rankFont
        self.suitFont = suitFont
        self.pipSpacing = pipSpacing
        self.backMotifFont = backMotifFont
    }

    /// ポーカー・ブラックジャックの手札（既存の 62×90）。
    public static let standard = PlayingCardMetrics(
        width: 62, height: 90, rankFont: 22, suitFont: 24, pipSpacing: 2, backMotifFont: 26)

    /// 大富豪の手札・場札（既存の 42×60）。
    public static let compact = PlayingCardMetrics(
        width: 42, height: 60, rankFont: 16, suitFont: 15, pipSpacing: 0, backMotifFont: 17)

    /// 大富豪の拡大表示（既存の 56×78）。
    public static let medium = PlayingCardMetrics(
        width: 56, height: 78, rankFont: 22, suitFont: 20, pipSpacing: 0, backMotifFont: 22)
}

// MARK: - 面の色

/// 面に載せるインクの色。地は常に `CardStyle.faceFill`（紙）なので、
/// ライト / ダークで振らず固定値を使う（#187 の追従対象は地と文字であってカード面ではない）。
public enum PlayingCardInk {
    /// 赤スート（♥♦）。
    public static let red = Color(hex: 0xC0392B)
    /// 黒スート（♠♣）とジョーカーの文字。
    public static let black = Color(hex: 0x1A1A1A)
    /// ジョーカーの図案。トランプのジョーカーは赤黒どちらでもないので差し色を当てる。
    public static let joker = Theme.purple

    public static func color(for suit: PlayingCardSuit) -> Color {
        suit.isRed ? red : black
    }
}

// MARK: - ジョーカーの図案

/// ジョーカーの図案（#397・完全オリジナル）の寸法。0...1 の正規化空間で持つ。
///
/// 既存のトランプ製品・他アプリの絵柄は一切参照せず、**道化帽（とんがり帽 + つば + 鈴3つ）**を
/// ゼロから起こしている（会長指示 2026-09-01「ジョーカーの図案はオリジナルで起こす」）。
/// 大富豪の最小札は幅 42pt しかないため、線画や表情のような細部は持たせず、
/// **単色の面3種（帽子・つば・鈴）の重ね**だけで成立する形にしている。
public enum JesterCapGeometry {
    /// とんがり帽の頂点。
    public static let apex = CGPoint(x: 0.50, y: 0.07)
    /// とんがり帽の裾（左端・右端）。
    public static let brimLeft = CGPoint(x: 0.20, y: 0.66)
    public static let brimRight = CGPoint(x: 0.80, y: 0.66)

    /// つば（頭に載る帯）。
    public static let band = CGRect(x: 0.13, y: 0.62, width: 0.74, height: 0.16)

    /// 鈴の半径。
    public static let bellRadius: CGFloat = 0.105

    /// 鈴の中心。左 → 上 → 右。左右対称で、上の鈴がいちばん高いことが図案の要件。
    /// 左右は**つばの高さより下**に置く（真上に3本立てると王冠に見え、K の札と紛らわしくなる）。
    public static let bells: [CGPoint] = [
        CGPoint(x: 0.11, y: 0.83),
        CGPoint(x: 0.50, y: 0.11),
        CGPoint(x: 0.89, y: 0.83),
    ]

    /// 図案全体が占める範囲（はみ出し・縮みすぎの検証用）。
    public static var bounds: CGRect {
        var rect = band
        for bell in bells {
            rect = rect.union(CGRect(x: bell.x - bellRadius, y: bell.y - bellRadius,
                                     width: 2 * bellRadius, height: 2 * bellRadius))
        }
        return rect.union(CGRect(x: brimLeft.x, y: apex.y,
                                 width: brimRight.x - brimLeft.x, height: brimLeft.y - apex.y))
    }
}

/// とんがり帽の三角（`JesterCapMark` の部品）。
public struct JesterCapShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        func p(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
        }
        var path = Path()
        path.move(to: p(JesterCapGeometry.brimLeft))
        path.addQuadCurve(to: p(JesterCapGeometry.apex),
                          control: p(CGPoint(x: 0.30, y: 0.24)))
        path.addQuadCurve(to: p(JesterCapGeometry.brimRight),
                          control: p(CGPoint(x: 0.70, y: 0.24)))
        path.closeSubpath()
        return path
    }
}

/// ジョーカーの図案。帽子・つば・鈴を**別々に塗って重ねる**。
///
/// 1本の Path にまとめると、部品ごとに巻き方向が変わった箇所が nonZero 塗りで打ち消し合って
/// 穴が開く（実測で発生）。同じ色の View を重ねれば単純な和集合になるので、この形を採る。
public struct JesterCapMark: View {
    public let color: Color

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 鈴（つばと帽子より先に敷いて、重なりを隠す）。
                ForEach(Array(JesterCapGeometry.bells.enumerated()), id: \.offset) { _, bell in
                    let r = JesterCapGeometry.bellRadius
                    Circle()
                        .fill(color)
                        .frame(width: 2 * r * w, height: 2 * r * h)
                        .position(x: bell.x * w, y: bell.y * h)
                }
                JesterCapShape().fill(color)
                Capsule()
                    .fill(color)
                    .frame(width: JesterCapGeometry.band.width * w,
                           height: JesterCapGeometry.band.height * h)
                    .position(x: JesterCapGeometry.band.midX * w,
                              y: JesterCapGeometry.band.midY * h)
            }
        }
    }
}

// MARK: - 面 / 裏

/// カードの表に載せる中身（数字 + スート、またはジョーカーの図案）。
/// 外形・影・縁は `PlayingCardSurface` 側の責務なので、ここでは中身だけを返す。
public struct PlayingCardFace: View {
    public let figure: PlayingCardFigure
    public let metrics: PlayingCardMetrics

    public init(figure: PlayingCardFigure, metrics: PlayingCardMetrics) {
        self.figure = figure
        self.metrics = metrics
    }

    public var body: some View {
        switch figure {
        case .pip(let suit, _):
            VStack(spacing: metrics.pipSpacing) {
                Text(figure.rankLabel)
                    .font(.system(size: metrics.rankFont, weight: .black, design: .rounded))
                Text(suit.symbol)
                    .font(.system(size: metrics.suitFont))
            }
            .foregroundStyle(PlayingCardInk.color(for: suit))

        case .joker:
            VStack(spacing: metrics.pipSpacing + 1) {
                JesterCapMark(color: PlayingCardInk.joker)
                    .frame(width: metrics.suitFont * 1.3, height: metrics.suitFont * 1.3)
                // 「JOKER」は5文字あるので、数字1〜2文字のランクより小さく組まないと札からはみ出す。
                Text("JOKER")
                    .font(.system(size: metrics.rankFont * 0.42, weight: .black, design: .rounded))
                    .foregroundStyle(PlayingCardInk.black)
            }
        }
    }
}

/// カードの裏に載せる中身（内枠 + スート印）。表と同じく外形は含まない。
public struct PlayingCardBack: View {
    public let metrics: PlayingCardMetrics

    public init(metrics: PlayingCardMetrics) {
        self.metrics = metrics
    }

    public var body: some View {
        ZStack {
            CardStyle.backFrame(cornerRadius: metrics.cornerRadius)
            Image(systemName: "suit.spade.fill")
                .font(.system(size: metrics.backMotifFont, weight: .bold))
                .foregroundStyle(.white.opacity(CardStyle.backMotifOpacity))
        }
    }
}

/// カードの外形（角丸 + `CardStyle` の紙 / 藍 + 縁 + 影）。
///
/// 選択中の強調やヒント色はゲームごとに違うので、色と太さは呼び出し側から渡す。
public struct PlayingCardSurface: View {
    public let faceUp: Bool
    public let cornerRadius: CGFloat
    public let border: Color
    public let borderWidth: CGFloat
    public let shadowColor: Color
    public let shadowRadius: CGFloat

    public init(faceUp: Bool = true,
                cornerRadius: CGFloat = 8,
                border: Color = Color.gray.opacity(0.2),
                borderWidth: CGFloat = 0.5,
                shadowColor: Color = Color.black.opacity(0.15),
                shadowRadius: CGFloat = 3) {
        self.faceUp = faceUp
        self.cornerRadius = cornerRadius
        self.border = border
        self.borderWidth = borderWidth
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(faceUp ? AnyShapeStyle(CardStyle.faceFill) : AnyShapeStyle(CardStyle.backFill))
            .shadow(color: shadowColor, radius: shadowRadius, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: borderWidth)
            )
    }
}
