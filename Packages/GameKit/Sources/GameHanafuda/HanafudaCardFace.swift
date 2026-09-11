import SwiftUI
import Core

/// 札 1 枚の絵柄（#495）。
///
/// **図案はすべて `Canvas` 1 枚に描く**。部品ごとに `Shape` の View を作って `ZStack` に積むと
/// iOS で一部の部品だけが枠いっぱいに広がって図案が潰れる（#462 のチェス駒で実測）。
/// 部品を 1 本の `Path` にまとめるのも不可で、巻き方向が逆の箇所が nonZero 塗りで
/// 打ち消し合って穴が開く（#397 のジョーカー）。**「部品ごとに別 Path・重ねる先は Canvas」**が
/// 両方を避けられる唯一の形。
///
/// 座標はすべて 0...1 の正規化値で書き、`point(_:_:)` で実寸へ写す。
/// 既存メーカーの札は一切参照しておらず、公有の伝統モチーフを単純化したオリジナル図案。
public struct HanafudaCardFace: View {
    public let card: HanafudaCard
    /// 取れない・選べない札を暗く落とす。
    public let isDimmed: Bool
    /// 選択中・合わせ先候補の強調。
    public let isHighlighted: Bool

    public init(card: HanafudaCard, isDimmed: Bool = false, isHighlighted: Bool = false) {
        self.card = card
        self.isDimmed = isDimmed
        self.isHighlighted = isHighlighted
    }

    public var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.12
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(CardStyle.faceFill)
                Canvas { context, size in
                    HanafudaCardFace.draw(card, in: &context, size: size)
                }
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(HanafudaCardArt.ink.opacity(0.35), lineWidth: 1)
                if isHighlighted {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Theme.coral, lineWidth: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .opacity(isDimmed ? 0.45 : 1)
        }
        .aspectRatio(1 / HanafudaCardArt.aspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(HanafudaSpeech.label(for: card))
    }

    // MARK: - 描画

    static func draw(_ card: HanafudaCard, in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        // 図案は帯の下だけに描く。正規化座標のまま `artRect` を渡すので、地・植物・主役・短冊が
        // まとめて下へ寄り、帯に食われる部品が出ない。
        let art = artRect(in: rect)
        drawGround(card, in: &context, rect: art)
        drawPlant(month: card.month, in: &context, rect: art)
        if let motif = HanafudaCardArt.motif(for: card) {
            drawMotif(motif, in: &context, rect: art)
        }
        if let ribbon = card.ribbon {
            drawRibbon(ribbon, in: &context, rect: art)
        }
        drawBand(card, in: &context, rect: rect)
    }

    /// 上端の帯（月と種別）が占める高さの割合（#602）。
    static let bandRatio: Double = 0.15

    /// 帯を敷く領域。
    static func bandRect(in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * bandRatio)
    }

    /// 図案を描く領域。帯のぶんだけ下げる。
    static func artRect(in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX, y: rect.minY + rect.height * bandRatio,
            width: rect.width, height: rect.height * (1 - bandRatio)
        )
    }

    /// 正規化座標 → 実寸。
    static func point(_ x: Double, _ y: Double, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }

    /// 線の太さ。札の幅に比例させる（小さく描いても線が潰れない）。
    static func stroke(_ ratio: Double, in rect: CGRect) -> CGFloat {
        max(rect.width * ratio, 0.6)
    }

    private static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
                               in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(
            x: rect.minX + rect.width * (cx - rx),
            y: rect.minY + rect.height * (cy - ry),
            width: rect.width * rx * 2,
            height: rect.height * ry * 2
        ))
    }

    private static func line(_ points: [(Double, Double)], in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: point(first.0, first.1, in: rect))
        for p in points.dropFirst() { path.addLine(to: point(p.0, p.1, in: rect)) }
        return path
    }

    private static func polygon(_ points: [(Double, Double)], in rect: CGRect) -> Path {
        var path = line(points, in: rect)
        path.closeSubpath()
        return path
    }

    private static func curve(from: (Double, Double), to: (Double, Double),
                              control: (Double, Double), in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(from.0, from.1, in: rect))
        path.addQuadCurve(to: point(to.0, to.1, in: rect),
                          control: point(control.0, control.1, in: rect))
        return path
    }

    // MARK: 地

    /// 下端の季節の地。月の主色を薄く敷いて、同じ図案でも月が違えば色で分かるようにする。
    private static func drawGround(_ card: HanafudaCard, in ctx: inout GraphicsContext, rect: CGRect) {
        var path = Path()
        path.move(to: point(0, 1, in: rect))
        path.addLine(to: point(0, 0.74, in: rect))
        path.addQuadCurve(to: point(1, 0.74, in: rect), control: point(0.5, 0.64, in: rect))
        path.addLine(to: point(1, 1, in: rect))
        path.closeSubpath()
        ctx.fill(path, with: .color(HanafudaCardArt.groundColor(card.month)))
    }

    // MARK: 月の植物

    static func drawPlant(month: Int, in ctx: inout GraphicsContext, rect: CGRect) {
        let color = HanafudaCardArt.monthColor(month)
        let ink = HanafudaCardArt.ink
        let branch = StrokeStyle(lineWidth: stroke(0.035, in: rect), lineCap: .round)
        let twig = StrokeStyle(lineWidth: stroke(0.022, in: rect), lineCap: .round)

        switch month {
        case 1: // 松
            ctx.stroke(curve(from: (0.24, 1.02), to: (0.58, 0.60), control: (0.30, 0.78), in: rect),
                       with: .color(ink), style: branch)
            for (cx, cy, r) in [(0.34, 0.86, 0.13), (0.50, 0.72, 0.11), (0.62, 0.60, 0.09)] {
                ctx.fill(polygon([(cx - r, cy + r * 0.7), (cx, cy - r), (cx + r, cy + r * 0.7)], in: rect),
                         with: .color(color))
            }
        case 2: // 梅
            ctx.stroke(curve(from: (0.12, 1.02), to: (0.80, 0.62), control: (0.30, 0.70), in: rect),
                       with: .color(ink), style: branch)
            for (cx, cy) in [(0.30, 0.86), (0.52, 0.74), (0.74, 0.64)] {
                blossom(at: (cx, cy), petalCount: 5, radius: 0.075, petal: 0.036,
                        color: color, in: &ctx, rect: rect)
            }
        case 3: // 桜
            ctx.stroke(curve(from: (0.08, 1.02), to: (0.92, 0.68), control: (0.45, 0.72), in: rect),
                       with: .color(ink), style: branch)
            for (cx, cy) in [(0.22, 0.88), (0.44, 0.80), (0.66, 0.74), (0.86, 0.70)] {
                blossom(at: (cx, cy), petalCount: 5, radius: 0.078, petal: 0.040,
                        color: color, in: &ctx, rect: rect)
            }
        case 4: // 藤（垂れ下がる房）
            ctx.stroke(line([(0.10, 0.66), (0.90, 0.62)], in: rect), with: .color(ink), style: branch)
            for x in [0.26, 0.50, 0.74] {
                for (i, y) in stride(from: 0.70, through: 0.96, by: 0.065).enumerated() {
                    let r = 0.055 - Double(i) * 0.008
                    ctx.fill(ellipse(x, y, r, r * 0.8, in: rect), with: .color(color))
                }
            }
        case 5: // 菖蒲
            for x in [0.28, 0.42, 0.72] {
                ctx.stroke(curve(from: (x, 1.02), to: (x + 0.06, 0.58), control: (x - 0.04, 0.78), in: rect),
                           with: .color(HanafudaCardArt.monthColor(1)), style: twig)
            }
            blossom(at: (0.56, 0.72), petalCount: 3, radius: 0.10, petal: 0.052,
                    color: color, in: &ctx, rect: rect)
        case 6: // 牡丹
            for r in [0.16, 0.11, 0.06] {
                ctx.fill(ellipse(0.50, 0.80, r, r * 0.82, in: rect),
                         with: .color(color.opacity(r == 0.16 ? 0.55 : 1)))
            }
            ctx.fill(ellipse(0.22, 0.92, 0.10, 0.055, in: rect),
                     with: .color(HanafudaCardArt.monthColor(1)))
            ctx.fill(ellipse(0.78, 0.92, 0.10, 0.055, in: rect),
                     with: .color(HanafudaCardArt.monthColor(1)))
        case 7: // 萩
            for (x0, x1) in [(0.18, 0.44), (0.56, 0.86)] {
                ctx.stroke(curve(from: (x0, 1.02), to: (x1, 0.64), control: (x0, 0.74), in: rect),
                           with: .color(ink), style: twig)
                for (i, t) in [0.25, 0.5, 0.75].enumerated() {
                    let cx = x0 + (x1 - x0) * t
                    let cy = 1.0 - (1.0 - 0.66) * t - 0.03
                    ctx.fill(ellipse(cx + (i % 2 == 0 ? -0.06 : 0.06), cy, 0.05, 0.032, in: rect),
                             with: .color(color))
                }
            }
        case 8: // 芒
            var hill = Path()
            hill.move(to: point(0, 1.02, in: rect))
            hill.addQuadCurve(to: point(1, 1.02, in: rect), control: point(0.5, 0.72, in: rect))
            hill.closeSubpath()
            ctx.fill(hill, with: .color(HanafudaCardArt.ink.opacity(0.65)))
            for (i, x) in [0.16, 0.30, 0.46, 0.62, 0.78, 0.90].enumerated() {
                let tip = x + (i % 2 == 0 ? -0.10 : 0.10)
                ctx.stroke(curve(from: (x, 0.96), to: (tip, 0.58), control: (x, 0.72), in: rect),
                           with: .color(HanafudaCardArt.monthColor(9).opacity(0.9)), style: twig)
            }
        case 9: // 菊
            blossom(at: (0.50, 0.80), petalCount: 12, radius: 0.13, petal: 0.036,
                    color: color, in: &ctx, rect: rect)
            ctx.fill(ellipse(0.50, 0.80, 0.05, 0.033, in: rect), with: .color(color.opacity(0.6)))
        case 10: // 紅葉
            for (cx, cy, s) in [(0.26, 0.86, 0.13), (0.54, 0.76, 0.16), (0.80, 0.88, 0.11)] {
                ctx.fill(mapleLeaf(at: (cx, cy), size: s, in: rect), with: .color(color))
            }
        case 11: // 柳
            ctx.stroke(line([(0.06, 0.10), (0.94, 0.16)], in: rect), with: .color(ink), style: branch)
            for x in [0.14, 0.30, 0.46, 0.62, 0.78, 0.90] {
                ctx.stroke(curve(from: (x, 0.14), to: (x + 0.05, 0.72), control: (x - 0.08, 0.44), in: rect),
                           with: .color(color), style: twig)
            }
        default: // 12 桐
            for (cx, cy) in [(0.24, 0.88), (0.50, 0.80), (0.76, 0.88)] {
                ctx.fill(polygon([(cx, cy - 0.13), (cx + 0.11, cy + 0.02), (cx, cy + 0.10),
                                  (cx - 0.11, cy + 0.02)], in: rect),
                         with: .color(HanafudaCardArt.monthColor(1).opacity(0.85)))
            }
            for (cx, cy) in [(0.38, 0.66), (0.50, 0.60), (0.62, 0.66)] {
                ctx.fill(ellipse(cx, cy, 0.05, 0.035, in: rect), with: .color(color))
            }
        }
    }

    /// 花 1 輪。花弁を**別々の Path** として同じ Canvas に重ねる（1 本の Path にまとめない）。
    private static func blossom(at center: (Double, Double), petalCount: Int,
                                radius: Double, petal: Double, color: Color,
                                in ctx: inout GraphicsContext, rect: CGRect) {
        for i in 0..<petalCount {
            let angle = Double(i) / Double(petalCount) * 2 * .pi - .pi / 2
            let cx = center.0 + cos(angle) * radius * 0.62
            let cy = center.1 + sin(angle) * radius * 0.62
            ctx.fill(ellipse(cx, cy, petal, petal * 0.9, in: rect), with: .color(color))
        }
        ctx.fill(ellipse(center.0, center.1, petal * 0.55, petal * 0.5, in: rect),
                 with: .color(Color(hex: 0xF6D66B)))
    }

    /// 楓の葉（5 裂）。1 本の閉じた輪郭で描き切れる形なので Path 1 つでよい。
    private static func mapleLeaf(at center: (Double, Double), size: Double, in rect: CGRect) -> Path {
        var points: [(Double, Double)] = []
        let lobes = 5
        for i in 0..<(lobes * 2) {
            let angle = Double(i) / Double(lobes * 2) * 2 * .pi - .pi / 2
            let r = i % 2 == 0 ? size : size * 0.42
            points.append((center.0 + cos(angle) * r, center.1 + sin(angle) * r * 0.95))
        }
        return polygon(points, in: rect)
    }

    // MARK: 主役

    static func drawMotif(_ motif: HanafudaMotif, in ctx: inout GraphicsContext, rect: CGRect) {
        let ink = HanafudaCardArt.ink
        let thin = StrokeStyle(lineWidth: stroke(0.024, in: rect), lineCap: .round)
        let hair = StrokeStyle(lineWidth: stroke(0.016, in: rect), lineCap: .round)

        switch motif {
        case .crane:
            ctx.fill(ellipse(0.46, 0.34, 0.19, 0.10, in: rect), with: .color(.white))
            ctx.stroke(ellipse(0.46, 0.34, 0.19, 0.10, in: rect), with: .color(ink), style: hair)
            ctx.stroke(curve(from: (0.60, 0.30), to: (0.72, 0.12), control: (0.72, 0.24), in: rect),
                       with: .color(ink), style: thin)
            ctx.fill(ellipse(0.73, 0.11, 0.05, 0.035, in: rect), with: .color(.white))
            ctx.fill(ellipse(0.73, 0.08, 0.028, 0.018, in: rect), with: .color(Color(hex: 0xD64545)))
            ctx.fill(polygon([(0.78, 0.11), (0.86, 0.12), (0.78, 0.13)], in: rect), with: .color(ink))
            ctx.fill(polygon([(0.28, 0.32), (0.14, 0.44), (0.30, 0.41)], in: rect), with: .color(ink))
        case .warbler:
            ctx.fill(ellipse(0.52, 0.34, 0.13, 0.085, in: rect),
                     with: .color(HanafudaCardArt.monthColor(1)))
            ctx.fill(ellipse(0.64, 0.27, 0.055, 0.05, in: rect),
                     with: .color(HanafudaCardArt.monthColor(1)))
            ctx.fill(polygon([(0.69, 0.26), (0.77, 0.28), (0.69, 0.30)], in: rect), with: .color(ink))
            ctx.fill(polygon([(0.40, 0.33), (0.26, 0.26), (0.40, 0.39)], in: rect), with: .color(ink))
        case .curtain:
            var band = Path()
            band.move(to: point(0.04, 0.06, in: rect))
            band.addLine(to: point(0.96, 0.06, in: rect))
            band.addLine(to: point(0.96, 0.26, in: rect))
            for i in stride(from: 0.96, to: 0.04, by: -0.115) {
                band.addQuadCurve(to: point(i - 0.115, 0.26, in: rect),
                                  control: point(i - 0.058, 0.36, in: rect))
            }
            band.closeSubpath()
            ctx.fill(band, with: .color(Color(hex: 0xD64545)))
            for x in [0.20, 0.43, 0.66] {
                ctx.fill(polygon([(x, 0.06), (x + 0.09, 0.06), (x + 0.09, 0.28), (x, 0.28)], in: rect),
                         with: .color(.white.opacity(0.85)))
            }
            ctx.stroke(line([(0.30, 0.30), (0.30, 0.50)], in: rect), with: .color(ink), style: hair)
            ctx.stroke(line([(0.70, 0.30), (0.70, 0.50)], in: rect), with: .color(ink), style: hair)
        case .cuckoo:
            ctx.fill(ellipse(0.50, 0.26, 0.15, 0.075, in: rect), with: .color(ink))
            ctx.fill(polygon([(0.44, 0.22), (0.34, 0.06), (0.56, 0.19)], in: rect), with: .color(ink))
            ctx.fill(polygon([(0.36, 0.27), (0.18, 0.34), (0.40, 0.31)], in: rect), with: .color(ink))
            ctx.fill(polygon([(0.64, 0.24), (0.74, 0.26), (0.64, 0.28)], in: rect),
                     with: .color(Color(hex: 0xE8A33D)))
        case .bridge:
            for (i, y) in [0.46, 0.38, 0.30].enumerated() {
                let x0 = 0.10 + Double(i) * 0.22
                ctx.fill(polygon([(x0, y), (x0 + 0.42, y - 0.05), (x0 + 0.42, y - 0.01),
                                  (x0, y + 0.04)], in: rect),
                         with: .color(Color(hex: 0x9A6B4A)))
            }
            ctx.stroke(line([(0.16, 0.50), (0.16, 0.60)], in: rect), with: .color(ink), style: hair)
            ctx.stroke(line([(0.80, 0.34), (0.80, 0.46)], in: rect), with: .color(ink), style: hair)
        case .butterfly:
            for (dx, sign) in [(-1.0, -1.0), (1.0, 1.0)] {
                ctx.fill(ellipse(0.50 + dx * 0.15, 0.24, 0.13, 0.10, in: rect),
                         with: .color(Color(hex: 0xE8A33D)))
                ctx.fill(ellipse(0.50 + dx * 0.12, 0.40, 0.10, 0.085, in: rect),
                         with: .color(HanafudaCardArt.monthColor(6)))
                ctx.stroke(line([(0.50, 0.22), (0.50 + sign * 0.10, 0.10)], in: rect),
                           with: .color(ink), style: hair)
            }
            ctx.fill(ellipse(0.50, 0.32, 0.028, 0.14, in: rect), with: .color(ink))
        case .boar:
            ctx.fill(ellipse(0.48, 0.34, 0.21, 0.115, in: rect), with: .color(Color(hex: 0x5B463A)))
            ctx.fill(polygon([(0.66, 0.26), (0.86, 0.34), (0.66, 0.42)], in: rect),
                     with: .color(Color(hex: 0x5B463A)))
            ctx.fill(polygon([(0.78, 0.36), (0.88, 0.30), (0.80, 0.39)], in: rect), with: .color(.white))
            for x in [0.34, 0.46, 0.56, 0.64] {
                ctx.stroke(line([(x, 0.44), (x, 0.54)], in: rect), with: .color(ink), style: thin)
            }
            ctx.stroke(line([(0.28, 0.30), (0.18, 0.22)], in: rect), with: .color(ink), style: hair)
        case .moon:
            ctx.fill(ellipse(0.50, 0.26, 0.21, 0.14, in: rect), with: .color(Color(hex: 0xF2C14E)))
            ctx.stroke(ellipse(0.50, 0.26, 0.21, 0.14, in: rect),
                       with: .color(Color(hex: 0xD9542B).opacity(0.7)), style: hair)
        case .geese:
            for (cx, cy) in [(0.30, 0.16), (0.50, 0.28), (0.70, 0.18)] {
                ctx.fill(ellipse(cx, cy, 0.055, 0.032, in: rect), with: .color(ink))
                ctx.stroke(line([(cx - 0.05, cy - 0.05), (cx, cy - 0.01), (cx + 0.05, cy - 0.05)], in: rect),
                           with: .color(ink), style: hair)
            }
        case .sakeCup:
            ctx.fill(polygon([(0.28, 0.22), (0.72, 0.22), (0.62, 0.38), (0.38, 0.38)], in: rect),
                     with: .color(Color(hex: 0xD64545)))
            ctx.fill(ellipse(0.50, 0.22, 0.22, 0.045, in: rect), with: .color(Color(hex: 0xE8A33D)))
            ctx.fill(polygon([(0.46, 0.38), (0.54, 0.38), (0.54, 0.46), (0.46, 0.46)], in: rect),
                     with: .color(Color(hex: 0xD64545)))
            ctx.fill(ellipse(0.50, 0.48, 0.13, 0.030, in: rect), with: .color(Color(hex: 0xD64545)))
        case .deer:
            ctx.fill(ellipse(0.44, 0.38, 0.19, 0.095, in: rect), with: .color(Color(hex: 0xA9764B)))
            ctx.fill(ellipse(0.68, 0.28, 0.075, 0.055, in: rect), with: .color(Color(hex: 0xA9764B)))
            for sign in [-1.0, 1.0] {
                ctx.stroke(line([(0.68 + sign * 0.03, 0.23), (0.68 + sign * 0.09, 0.10)], in: rect),
                           with: .color(ink), style: hair)
                ctx.stroke(line([(0.68 + sign * 0.06, 0.165), (0.68 + sign * 0.14, 0.15)], in: rect),
                           with: .color(ink), style: hair)
            }
            for x in [0.32, 0.42, 0.52, 0.58] {
                ctx.stroke(line([(x, 0.46), (x, 0.56)], in: rect), with: .color(ink), style: thin)
            }
        case .rainMan:
            var umbrella = Path()
            umbrella.move(to: point(0.20, 0.30, in: rect))
            umbrella.addQuadCurve(to: point(0.80, 0.30, in: rect), control: point(0.50, 0.04, in: rect))
            umbrella.closeSubpath()
            ctx.fill(umbrella, with: .color(Color(hex: 0x3A6EA5)))
            ctx.stroke(line([(0.50, 0.16), (0.50, 0.52)], in: rect), with: .color(ink), style: thin)
            for x in [0.12, 0.26, 0.74, 0.88] {
                ctx.stroke(line([(x, 0.10), (x - 0.05, 0.40)], in: rect),
                           with: .color(Color(hex: 0x6E8FB5)), style: hair)
            }
        case .swallow:
            ctx.fill(ellipse(0.50, 0.28, 0.14, 0.062, in: rect), with: .color(Color(hex: 0x2B3A4A)))
            ctx.fill(polygon([(0.46, 0.26), (0.30, 0.10), (0.52, 0.22)], in: rect),
                     with: .color(Color(hex: 0x2B3A4A)))
            ctx.fill(polygon([(0.46, 0.30), (0.28, 0.44), (0.52, 0.33)], in: rect),
                     with: .color(Color(hex: 0x2B3A4A)))
            ctx.fill(polygon([(0.62, 0.26), (0.84, 0.20), (0.72, 0.29), (0.84, 0.36)], in: rect),
                     with: .color(Color(hex: 0x2B3A4A)))
        case .lightning:
            ctx.fill(polygon([(0.58, 0.06), (0.34, 0.34), (0.48, 0.34), (0.36, 0.60),
                              (0.66, 0.28), (0.50, 0.28)], in: rect),
                     with: .color(Color(hex: 0xF2C14E)))
        case .phoenix:
            ctx.fill(ellipse(0.44, 0.30, 0.15, 0.085, in: rect), with: .color(Color(hex: 0xE8A33D)))
            ctx.fill(ellipse(0.58, 0.20, 0.055, 0.045, in: rect), with: .color(Color(hex: 0xE8A33D)))
            ctx.fill(polygon([(0.63, 0.19), (0.72, 0.21), (0.63, 0.23)], in: rect),
                     with: .color(Color(hex: 0xD64545)))
            for (i, dy) in [0.0, 0.07, 0.14].enumerated() {
                ctx.stroke(curve(from: (0.32, 0.32 + dy), to: (0.06, 0.14 + dy * 1.6),
                                 control: (0.16, 0.36 + dy), in: rect),
                           with: .color(Color(hex: i == 1 ? 0xD64545 : 0xE8A33D)), style: thin)
            }
        }
    }

    // MARK: 短冊

    static func drawRibbon(_ ribbon: HanafudaRibbon, in ctx: inout GraphicsContext, rect: CGRect) {
        let color = HanafudaCardArt.ribbonColor(ribbon)
        let body = CGRect(
            x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.10,
            width: rect.width * 0.24, height: rect.height * 0.52
        )
        let path = Path(roundedRect: body, cornerRadius: rect.width * 0.05)
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(HanafudaCardArt.ink.opacity(0.5)),
                   style: StrokeStyle(lineWidth: stroke(0.012, in: rect)))
        // 赤短だけ「文字入り」を表す横線を 3 本入れる（青短・無地は入れない）。
        guard ribbon == .redPoem else { return }
        for i in 0..<3 {
            let y = 0.20 + Double(i) * 0.11
            ctx.stroke(line([(0.35, y), (0.49, y)], in: rect), with: .color(.white.opacity(0.9)),
                       style: StrokeStyle(lineWidth: stroke(0.018, in: rect), lineCap: .round))
        }
    }

    // MARK: 帯（月と種別）

    /// 上端に「月」と「種別」を並べた帯を敷く（#602）。
    ///
    /// **こいこいで打つ手を決めるのに要る情報はこの 2 つだけ**で、合わせは月でしか起きず、
    /// 役は種別の枚数で決まる。どちらも図案からしか読めない状態では、鶴と鶯の描き分けを
    /// 知らない人が光札とタネ札を区別できない（会長 QA・2026-09-10）。
    /// 帯の色そのものが種別を表すので、取り札の帯のように文字が潰れる小ささでも読み取れる。
    static func drawBand(_ card: HanafudaCard, in ctx: inout GraphicsContext, rect: CGRect) {
        let backgroundHex = HanafudaCardArt.kindHex(for: card)
        let band = bandRect(in: rect)
        ctx.fill(Path(band), with: .color(Color(hex: backgroundHex)))
        let label = Color(hex: HanafudaCardArt.bandLabelHex(on: backgroundHex))
        // 帯の高さに収まる大きさにする。下限を設けて逃がすと、小さく描いたときに文字だけが
        // 帯からはみ出して図案に被る。
        let size = min(rect.width * 0.21, band.height * 0.82)
        func text(_ string: String) -> Text {
            Text(verbatim: string)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(label)
        }
        let inset = band.width * 0.07
        ctx.draw(text("\(card.month)"),
                 at: CGPoint(x: band.minX + inset, y: band.midY), anchor: .leading)
        ctx.draw(text(card.kind.badgeLabel),
                 at: CGPoint(x: band.maxX - inset, y: band.midY), anchor: .trailing)
    }
}

/// 裏面（相手の手札・山札）。
public struct HanafudaCardBack: View {
    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let corner = geo.size.width * 0.12
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(hex: 0x8E2C33), Color(hex: 0x5E1B21)],
                        startPoint: .top, endPoint: .bottom
                    ))
                RoundedRectangle(cornerRadius: max(corner - 3, 2), style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                    .padding(3)
            }
        }
        .aspectRatio(1 / HanafudaCardArt.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
