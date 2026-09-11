import SwiftUI
import Core

/// 神経衰弱のカードの絵柄（#601）。
///
/// **OS の絵文字は使わない**。v1.1.3 までは `"🍎"` のような絵文字の文字列をそのまま
/// `Text` で描いていたため、意匠が iOS のバージョンで変わり、将来の改変・削除にも
/// 追随できなかった（App Store のスクリーンショットと実機の見た目がずれる経路でもある）。
/// 碁石・将棋駒・チェス駒・花札で確立した「自前のベクター図案」の流儀に揃える。
///
/// `rawValue` は**中断データに書く識別子**なので、一度出した値は変えない
/// （変えると、その版をまたいだ中断データが復元できなくなる）。
public enum ConcentrationFigure: String, CaseIterable, Sendable {
    case circle, square, triangle, heart, star, crescent, droplet, leaf
    case diamond, flower, ring, sun, note, bolt, house, cloud, cross, arrow

    /// VoiceOver の読み上げ文。絵文字をやめると読み上げも消えるため、ここで言葉を持ち直す。
    public var displayName: String {
        switch self {
        case .circle:   return "まる"
        case .square:   return "しかく"
        case .triangle: return "さんかく"
        case .heart:    return "ハート"
        case .star:     return "ほし"
        case .crescent: return "つき"
        case .droplet:  return "しずく"
        case .leaf:     return "はっぱ"
        case .diamond:  return "ひしがた"
        case .flower:   return "はな"
        case .ring:     return "わ"
        case .sun:      return "たいよう"
        case .note:     return "おんぷ"
        case .bolt:     return "いなずま"
        case .house:    return "いえ"
        case .cloud:    return "くも"
        case .cross:    return "じゅうじ"
        case .arrow:    return "やじるし"
        }
    }

    /// 図案の色。**形が似ている組は色を遠ざける**（まる↔わ・しかく↔ひしがた・
    /// さんかく↔やじるし・ほし↔はな・くも↔はっぱ・しずく↔ハート）。逆に色が近い組は
    /// 形を大きく変えてあるので、片方の手掛かりが効かない場面でも見分けが付く。
    ///
    /// 明度は中くらいに揃える。カードの表は常に紙色（`CardStyle.faceFill`）だが、
    /// 獲得済みの札はティールの半透明になり、ダークモードでは暗く沈むため、
    /// 明るすぎても暗すぎても片方で読めなくなる。
    var color: Color {
        switch self {
        case .circle:   return Color(hex: 0xE24A3C)
        case .square:   return Color(hex: 0xF08A2E)
        case .triangle: return Color(hex: 0xE5B733)
        case .heart:    return Color(hex: 0xD9426E)
        case .star:     return Color(hex: 0x8DBF3F)
        case .crescent: return Color(hex: 0x8D6BE0)
        case .droplet:  return Color(hex: 0x2FA391)
        case .leaf:     return Color(hex: 0x39A85B)
        case .diamond:  return Color(hex: 0x5A76DC)
        case .flower:   return Color(hex: 0xE5679E)
        case .ring:     return Color(hex: 0x3596D4)
        case .sun:      return Color(hex: 0xF2C230)
        case .note:     return Color(hex: 0x5E7D93)
        case .bolt:     return Color(hex: 0xEE9A1F)
        case .house:    return Color(hex: 0xA2714A)
        case .cloud:    return Color(hex: 0x7C8FA6)
        case .cross:    return Color(hex: 0xD9534F)
        case .arrow:    return Color(hex: 0xB657C4)
        }
    }

    /// v1.1.3 まで中断データに書かれていた絵文字。
    ///
    /// 更新をまたいで中断が消えないよう、この対応で読み替えて復元する
    /// （読み替えられないと盤面ごと捨てて新しい局になる）。並びは当時の
    /// `concentrationSymbols` の先頭 18 個そのままで、盤で使われるのは最大 18 種
    /// （18 ペア）なので、ここに無い残りの絵文字が中断データに現れることはない。
    var legacyEmoji: String {
        switch self {
        case .circle:   return "🍎"
        case .square:   return "🍊"
        case .triangle: return "🍋"
        case .heart:    return "🍇"
        case .star:     return "🍓"
        case .crescent: return "🍒"
        case .droplet:  return "🍑"
        case .leaf:     return "🥝"
        case .diamond:  return "🌸"
        case .flower:   return "🌻"
        case .ring:     return "🌈"
        case .sun:      return "⭐"
        case .note:     return "🎵"
        case .bolt:     return "🎃"
        case .house:    return "🎄"
        case .cloud:    return "🎁"
        case .cross:    return "🐶"
        case .arrow:    return "🐱"
        }
    }

    /// 中断データの文字列を図案に戻す。現行の識別子を先に見て、無ければ旧版の絵文字を引く。
    /// どちらでもない文字列は**読み替えず nil**（既定へ倒すと、対を成さない盤面が
    /// 「復元成功」として通ってしまう）。
    static func decode(_ raw: String) -> ConcentrationFigure? {
        if let figure = ConcentrationFigure(rawValue: raw) { return figure }
        return legacyByEmoji[raw]
    }

    private static let legacyByEmoji: [String: ConcentrationFigure] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.legacyEmoji, $0) })
}

// MARK: - 図案

/// 図案を組む部品。塗る部品と線で引く部品の2種だけで全 18 種を作る。
struct ConcentrationFigurePart {
    let path: Path
    /// 線の太さ（図案の一辺に対する比）。`nil` なら塗りつぶし。
    let strokeWidth: Double?
}

/// 図案の形（#601）。
///
/// **部品ごとに別 `Path` を作り、重ねる先は `Canvas` 1 枚**にする。1 本の `Path` に
/// 部品を足すと nonZero 塗りで打ち消し合って穴が開き（#397 のジョーカー）、部品を
/// `Shape` の View にして `ZStack` に積むと iOS で一部だけ枠いっぱいに広がって潰れる
/// （#462 のチェス駒。macOS の `ImageRenderer` では再現しない）。
///
/// 座標はすべて 0...1 の正規化値で書き、与えられた正方形へ写す。
enum ConcentrationFigureArt {

    static func parts(of figure: ConcentrationFigure, in r: CGRect) -> [ConcentrationFigurePart] {
        switch figure {
        case .circle:
            return [fill(ellipse(0.5, 0.5, 0.42, 0.42, r))]

        case .square:
            return [fill(polygon([(0.10, 0.10), (0.90, 0.10), (0.90, 0.90), (0.10, 0.90)], r))]

        case .triangle:
            return [fill(polygon([(0.50, 0.06), (0.95, 0.86), (0.05, 0.86)], r))]

        case .diamond:
            return [fill(polygon([(0.50, 0.04), (0.94, 0.50), (0.50, 0.96), (0.06, 0.50)], r))]

        case .heart:
            var p = Path()
            p.move(to: pt(0.50, 0.93, r))
            p.addCurve(to: pt(0.04, 0.36, r), control1: pt(0.28, 0.76, r), control2: pt(0.04, 0.58, r))
            p.addCurve(to: pt(0.50, 0.30, r), control1: pt(0.04, 0.11, r), control2: pt(0.36, 0.10, r))
            p.addCurve(to: pt(0.96, 0.36, r), control1: pt(0.64, 0.10, r), control2: pt(0.96, 0.11, r))
            p.addCurve(to: pt(0.50, 0.93, r), control1: pt(0.96, 0.58, r), control2: pt(0.72, 0.76, r))
            p.closeSubpath()
            return [fill(p)]

        case .star:
            return [fill(starPath(points: 5, outer: 0.47, inner: 0.20, r))]

        case .crescent:
            // 外側のふくらみと内側のえぐりを1本で描く。円を2つ重ねて引き算する形は
            // nonZero 塗りでは作れない（#397 のジョーカーと同じ理由）。
            var p = Path()
            p.move(to: pt(0.85, 0.04, r))
            p.addCurve(to: pt(0.85, 0.96, r), control1: pt(-0.05, 0.12, r), control2: pt(-0.05, 0.88, r))
            p.addCurve(to: pt(0.85, 0.04, r), control1: pt(0.35, 0.88, r), control2: pt(0.35, 0.12, r))
            p.closeSubpath()
            return [fill(p)]

        case .droplet:
            var p = Path()
            p.move(to: pt(0.50, 0.03, r))
            p.addQuadCurve(to: pt(0.90, 0.60, r), control: pt(0.80, 0.26, r))
            p.addQuadCurve(to: pt(0.50, 0.97, r), control: pt(0.90, 0.88, r))
            p.addQuadCurve(to: pt(0.10, 0.60, r), control: pt(0.10, 0.88, r))
            p.addQuadCurve(to: pt(0.50, 0.03, r), control: pt(0.20, 0.26, r))
            p.closeSubpath()
            return [fill(p)]

        case .leaf:
            var blade = Path()
            blade.move(to: pt(0.12, 0.88, r))
            blade.addQuadCurve(to: pt(0.88, 0.12, r), control: pt(0.14, 0.14, r))
            blade.addQuadCurve(to: pt(0.12, 0.88, r), control: pt(0.86, 0.86, r))
            blade.closeSubpath()
            return [fill(blade), stroke(line([(0.16, 0.84), (0.76, 0.24)], r), 0.055)]

        case .flower:
            var parts = (0..<6).map { i -> ConcentrationFigurePart in
                let a = Double(i) / 6 * 2 * .pi - .pi / 2
                return fill(ellipse(0.5 + cos(a) * 0.28, 0.5 + sin(a) * 0.28, 0.20, 0.20, r))
            }
            parts.append(fill(ellipse(0.5, 0.5, 0.17, 0.17, r)))
            return parts

        case .ring:
            return [stroke(ellipse(0.5, 0.5, 0.35, 0.35, r), 0.17)]

        case .sun:
            var parts = [fill(ellipse(0.5, 0.5, 0.26, 0.26, r))]
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi
                parts.append(stroke(line([
                    (0.5 + cos(a) * 0.34, 0.5 + sin(a) * 0.34),
                    (0.5 + cos(a) * 0.44, 0.5 + sin(a) * 0.44),
                ], r), 0.085))
            }
            return parts

        case .note:
            return [
                fill(ellipse(0.34, 0.78, 0.21, 0.155, r)),
                stroke(line([(0.55, 0.76), (0.55, 0.08)], r), 0.075),
                fill(polygon([(0.55, 0.06), (0.92, 0.20), (0.92, 0.38), (0.55, 0.24)], r)),
            ]

        case .bolt:
            return [fill(polygon([
                (0.64, 0.04), (0.24, 0.56), (0.46, 0.56),
                (0.36, 0.96), (0.78, 0.42), (0.56, 0.42),
            ], r))]

        case .house:
            return [
                fill(polygon([(0.50, 0.06), (0.96, 0.46), (0.04, 0.46)], r)),
                fill(polygon([(0.16, 0.44), (0.84, 0.44), (0.84, 0.94), (0.16, 0.94)], r)),
            ]

        case .cloud:
            // つなぎの矩形は3つの円の内側に収める。外へはみ出すと、下の角が尖って
            // 雲ではなく丘に見える（実機のスクリーンショットで確認）。
            return [
                fill(ellipse(0.30, 0.56, 0.22, 0.22, r)),
                fill(ellipse(0.52, 0.44, 0.27, 0.27, r)),
                fill(ellipse(0.76, 0.58, 0.20, 0.20, r)),
                fill(polygon([(0.30, 0.50), (0.76, 0.50), (0.76, 0.78), (0.30, 0.78)], r)),
            ]

        case .cross:
            return [fill(polygon([
                (0.34, 0.05), (0.66, 0.05), (0.66, 0.34), (0.95, 0.34),
                (0.95, 0.66), (0.66, 0.66), (0.66, 0.95), (0.34, 0.95),
                (0.34, 0.66), (0.05, 0.66), (0.05, 0.34), (0.34, 0.34),
            ], r))]

        case .arrow:
            return [fill(polygon([
                (0.04, 0.36), (0.54, 0.36), (0.54, 0.14), (0.96, 0.50),
                (0.54, 0.86), (0.54, 0.64), (0.04, 0.64),
            ], r))]
        }
    }

    // MARK: - 部品づくり

    private static func fill(_ path: Path) -> ConcentrationFigurePart {
        ConcentrationFigurePart(path: path, strokeWidth: nil)
    }

    private static func stroke(_ path: Path, _ width: Double) -> ConcentrationFigurePart {
        ConcentrationFigurePart(path: path, strokeWidth: width)
    }

    /// 正規化座標 → 実寸。
    private static func pt(_ x: Double, _ y: Double, _ r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
    }

    private static func ellipse(_ cx: Double, _ cy: Double,
                                _ rx: Double, _ ry: Double, _ r: CGRect) -> Path {
        Path(ellipseIn: CGRect(
            x: r.minX + r.width * (cx - rx),
            y: r.minY + r.height * (cy - ry),
            width: r.width * rx * 2,
            height: r.height * ry * 2
        ))
    }

    private static func line(_ points: [(Double, Double)], _ r: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: pt(first.0, first.1, r))
        for p in points.dropFirst() { path.addLine(to: pt(p.0, p.1, r)) }
        return path
    }

    private static func polygon(_ points: [(Double, Double)], _ r: CGRect) -> Path {
        var path = line(points, r)
        path.closeSubpath()
        return path
    }

    private static func starPath(points: Int, outer: Double, inner: Double, _ r: CGRect) -> Path {
        let vertices = (0..<(points * 2)).map { i -> (Double, Double) in
            let radius = i.isMultiple(of: 2) ? outer : inner
            let a = Double(i) / Double(points * 2) * 2 * .pi - .pi / 2
            return (0.5 + cos(a) * radius, 0.5 + sin(a) * radius)
        }
        return polygon(vertices, r)
    }
}

// MARK: - 表示

/// 絵柄 1 つぶん。**すべての部品を `Canvas` 1 枚に描く**（理由は `ConcentrationFigureArt`）。
struct ConcentrationFigureView: View {
    let figure: ConcentrationFigure

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let shading = GraphicsContext.Shading.color(figure.color)
            for part in ConcentrationFigureArt.parts(of: figure, in: rect) {
                guard let width = part.strokeWidth else {
                    ctx.fill(part.path, with: shading)
                    continue
                }
                ctx.stroke(part.path, with: shading,
                           style: StrokeStyle(lineWidth: max(rect.width * width, 1),
                                              lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)  // 読み上げ文はカード側（`CardView`）が持つ
    }
}
