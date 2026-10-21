import SwiftUI
import Core

// MARK: - 札の寸法

/// 札 1 枚の寸法（#2369）。幅だけを決めれば、高さ・角丸・白い枠の太さが比で決まる。
///
/// 枠・窓・帯・裏の模様はこのアプリのために起こした図案で、既存製品の楕円の窓・書体・裏面の文字は写していない
/// （#1320 / #2369 の権利面の注意）。
struct ColorRelayCardSize: Equatable {
    let width: CGFloat

    /// 縦横比（トランプに近い 1 : 1.42）。
    static let aspect: CGFloat = 1.42

    var height: CGFloat { (width * Self.aspect).rounded() }
    /// 外形の角丸。
    var corner: CGFloat { width * 0.17 }
    /// 白い枠の太さ。
    var border: CGFloat { max(2, width * 0.045) }
}

// MARK: - 4 色の印

/// 4 色の印（いろがえの図案・山札の裏）。角丸の四角を 2 × 2 に並べる。
struct FourColorMark: View {
    var size: CGFloat
    var spacing: CGFloat = 2

    var body: some View {
        let side = max(0, (size - spacing) / 2)
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                square(.red, side)
                square(.green, side)
            }
            HStack(spacing: spacing) {
                square(.yellow, side)
                square(.purple, side)
            }
        }
        .frame(width: size, height: size)
    }

    private func square(_ color: RelayColor, _ side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.25, style: .continuous)
            .fill(color.color)
            .frame(width: side, height: side)
    }
}

// MARK: - 札の面

/// 札 1 枚の面（#2369 の描き直し）。**白い角丸の枠** + 色の地 + 中央の**角丸の長方形の窓**に大きな数字・記号。
/// 隅は色ごとの形の印だけ（#2387 で四隅の数字・色名の頭文字を外した）。いろがえ系の地は 4 色の斜めの帯。
/// 読み上げは面の文字に頼らず `accessibilityLabel`（`ColorRelayAccessibility.cardName`）で色と種類を伝える。
///
/// 札の面はライト / ダークで色を変えない（盤・駒と同じ扱い）。窓の数字は地の色を濃くした文字色
/// （`RelayColor.glyphHex`）、隅の印は `Theme.onAccent`（どちらも `ColorRelayContrastTests` で固定）。
struct ColorRelayCardView: View {
    let card: RelayCard
    let width: CGFloat
    var selected: Bool = false
    var hint: RelayCardHint = .none

    private var size: ColorRelayCardSize { ColorRelayCardSize(width: width) }

    /// 出せない札は色に頼らず**明度**でも落として区別する。
    private var isDimmed: Bool { hint == .unplayable && !selected }

    /// 窓の中の記号の色。色札は地の色を濃くした文字色、万能札は墨。
    private var glyphInk: Color { card.color?.glyphColor ?? Theme.Fixed.ink }

    var body: some View {
        let s = size
        ZStack {
            // 外枠: 白い角丸。
            RoundedRectangle(cornerRadius: s.corner, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(selected ? 0.35 : 0.22), radius: selected ? 6 : 3, y: 2)
            // 地（色）。万能札は 4 色の斜めの帯。
            faceFill
                .clipShape(RoundedRectangle(cornerRadius: max(0, s.corner - s.border), style: .continuous))
                .padding(s.border)
            // 窓: 角丸の長方形（楕円は使わない）。
            RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, width * 0.17)
                .padding(.vertical, s.height * 0.24)
            glyph(size: width * 0.62)
            cornerMarks
        }
        .frame(width: s.width, height: s.height)
        .overlay(
            RoundedRectangle(cornerRadius: s.corner, style: .continuous)
                .strokeBorder(selected ? Theme.Fixed.ink : Color.black.opacity(0.28), lineWidth: selected ? 3 : 1)
        )
        .opacity(isDimmed ? 0.5 : 1)
        // 面の文字を外しても読み上げは落とさない（#2387）。手札・場は親が状態つきの文で上書きする。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ColorRelayAccessibility.cardName(card))
    }

    @ViewBuilder
    private var faceFill: some View {
        if card.isWild {
            FourColorStripes()
        } else {
            card.color?.color ?? Theme.Fixed.ink
        }
    }

    /// 窓の中の記号。
    @ViewBuilder
    private func glyph(size: CGFloat) -> some View {
        switch card.kind {
        case .number(let n):
            Text(verbatim: "\(n)")
                .font(.system(size: size, weight: .black, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(glyphInk)
        case .skip:
            Image(systemName: "circle.slash")
                .font(.system(size: size * 0.78, weight: .black)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(glyphInk)
        case .reverse:
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: size * 0.7, weight: .black)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(glyphInk)
        case .drawTwo:
            Text(verbatim: "+2")
                .font(.system(size: size * 0.72, weight: .black, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(glyphInk)
        case .wild:
            FourColorMark(size: size * 0.95, spacing: max(2, size * 0.06))
        case .wildDrawFour:
            VStack(spacing: 1) {
                FourColorMark(size: size * 0.6, spacing: 2)
                Text(verbatim: "+4")
                    .font(.system(size: size * 0.46, weight: .black, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                    .foregroundStyle(glyphInk)
            }
        }
    }

    /// 隅の色の印（左上と、180 度回した右下）。#2387 で四隅の数字・色名の頭文字を外し、**文字なしの形**だけを残した。
    /// 色が見分けにくい人にも、形で札の色が分かる（#2007 の手がかりを文字から形へ置き換え）。万能札には置かない。
    @ViewBuilder
    private var cornerMarks: some View {
        if let color = card.color {
            let f = width * 0.16
            let s = size
            VStack {
                HStack {
                    colorShape(color, f)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    colorShape(color, f)
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(.horizontal, s.border + width * 0.07)
            .padding(.vertical, s.border + width * 0.06)
        }
    }

    private func colorShape(_ color: RelayColor, _ f: CGFloat) -> some View {
        Image(systemName: color.shapeSymbol)
            .font(.system(size: f, weight: .black)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
            .foregroundStyle(Theme.onAccent)
            .frame(width: f * 1.1, height: f * 1.1)
    }
}

/// いろがえ系の地。4 色を斜めの帯にする。
private struct FourColorStripes: View {
    var body: some View {
        let order: [RelayColor] = [.red, .yellow, .green, .purple]
        let stops = order.enumerated().flatMap { i, color in
            [Gradient.Stop(color: color.color, location: CGFloat(i) / 4),
             Gradient.Stop(color: color.color, location: CGFloat(i + 1) / 4)]
        }
        LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 裏面

/// 札の裏（山札・相手の手札）。白い枠は表と同じ。墨の地に内枠と 4 色の印で、**文字は置かない**。
/// トランプの裏（`PlayingCardBack`）とは別の図案。
struct ColorRelayCardBack: View {
    let width: CGFloat

    var body: some View {
        let s = ColorRelayCardSize(width: width)
        ZStack {
            RoundedRectangle(cornerRadius: s.corner, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            RoundedRectangle(cornerRadius: max(0, s.corner - s.border), style: .continuous)
                .fill(Theme.Fixed.ink)
                .padding(s.border)
            RoundedRectangle(cornerRadius: s.corner * 0.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: max(1, width * 0.03))
                .padding(s.border + width * 0.08)
            FourColorMark(size: width * 0.4, spacing: max(1.5, width * 0.04))
        }
        .frame(width: s.width, height: s.height)
        .overlay(
            RoundedRectangle(cornerRadius: s.corner, style: .continuous)
                .strokeBorder(Color.black.opacity(0.28), lineWidth: 1)
        )
    }
}

/// 裏向きの札を横に重ねた束（相手の手札）。枚数が多いときは `maxShown` 枚で止める（枚数は文字で出す）。
struct ColorRelayBackFan: View {
    let count: Int
    let cardWidth: CGFloat
    var maxShown: Int = 5

    var body: some View {
        let shown = max(1, min(count, maxShown))
        let step = cardWidth * 0.42
        let height = ColorRelayCardSize(width: cardWidth).height
        ZStack(alignment: .leading) {
            ForEach(0..<shown, id: \.self) { i in
                ColorRelayCardBack(width: cardWidth)
                    .offset(x: CGFloat(i) * step)
            }
        }
        .frame(width: cardWidth + step * CGFloat(shown - 1), height: height, alignment: .leading)
        .opacity(count == 0 ? 0 : 1)
    }
}

// MARK: - 相手のアイコン

/// 相手 3 人のアイコン（#2369 会長決裁: おじさんの絵は使わず、シンプルな印で見分ける）。
///
/// **色違いの丸 + 形の違う記号**の 2 つで見分ける（色だけに頼らない）。丸の色は札の 4 色（あか・みどり・
/// むらさき・きいろ）と取り違えないよう、札に無い色（桃・墨・生成り）にしている。
enum ColorRelayOpponentStyle {
    /// `index`（1〜3）の人の記号（SF Symbols）。
    static func symbol(for index: Int) -> String {
        switch index {
        case 1:  return "star.fill"
        case 2:  return "moon.fill"
        default: return "cloud.fill"
        }
    }

    /// 丸の色と記号の色（`0xRRGGBB`）。卓の上に置くのでライト / ダークで変えない。
    static func colors(for index: Int) -> (disc: UInt32, mark: UInt32) {
        switch index {
        case 1:  return (Theme.Hex.Fill.pink, Theme.Hex.onAccent)
        case 2:  return (Theme.Hex.ink.light, 0xFFFFFF)
        default: return (Theme.Hex.background.light, Theme.Hex.onAccent)
        }
    }
}

/// 相手 1 人のアイコン。手番の人は黄色の太い輪で囲む。
struct ColorRelayOpponentIcon: View {
    let index: Int
    let diameter: CGFloat
    var isCurrent: Bool = false

    var body: some View {
        let colors = ColorRelayOpponentStyle.colors(for: index)
        ZStack {
            Circle()
                .fill(Color(hex: colors.disc))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            Image(systemName: ColorRelayOpponentStyle.symbol(for: index))
                .font(.system(size: diameter * 0.46, weight: .bold)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                .foregroundStyle(Color(hex: colors.mark))
            Circle()
                .strokeBorder(isCurrent ? Theme.Fill.yellow : Color.white.opacity(0.75),
                              lineWidth: isCurrent ? max(3, diameter * 0.08) : 2)
            if isCurrent {
                Circle()
                    .strokeBorder(Theme.Fill.yellow.opacity(0.45), lineWidth: max(3, diameter * 0.09))
                    .padding(-max(3, diameter * 0.09))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
