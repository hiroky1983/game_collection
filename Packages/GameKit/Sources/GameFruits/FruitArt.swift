import CoreGraphics
import Foundation
import SwiftUI

/// 果物の絵（#1319）。**すべてこのアプリのオリジナル**で、円と単純な図形の重ね合わせだけで描く。
///
/// 1 つの描画関数（Core Graphics）から SpriteKit のテクスチャと SwiftUI の `Image` の両方を作る。
/// 2 系統で別々に描くと、盤の果物と「つぎ」の果物で絵が食い違う。
/// 顔は付けない（既存の同型ゲームのキャラクターを想起させないため）。
public enum FruitArt {
    /// キャンバスの一辺は果物の直径の何倍か。茎・葉・ヘタが円の外へ出るぶんの余白。
    /// 当たり判定は円のままで、描画だけがこの倍率で大きい。
    public static let canvasScale: CGFloat = 1.3

    /// `kind` の絵を `pixels` 四方の画像にする。失敗（コンテキストが作れない）なら nil。
    public static func image(_ kind: FruitKind, pixels: Int) -> CGImage? {
        guard pixels > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        draw(kind, in: context, canvas: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    /// `kind` の絵を描く。座標系は**下が原点**（Core Graphics の既定・SpriteKit と同じ向き）。
    /// `canvas` の中央に、直径 `canvas.width / canvasScale` の円が来る。
    public static func draw(_ kind: FruitKind, in context: CGContext, canvas: CGRect) {
        let radius = canvas.width / (2 * canvasScale)
        let center = CGPoint(x: canvas.midX, y: canvas.midY)
        var painter = Painter(context: context, center: center, radius: radius)
        painter.body(base: kind.baseColor, shade: kind.shadeColor)
        switch kind {
        case .blueberry:  painter.blueberry(shade: kind.shadeColor)
        case .cherry:     painter.stemAndLeaf(stemTilt: 0.35)
        case .strawberry: painter.strawberry(shade: kind.shadeColor)
        case .lime:       painter.dimples(shade: kind.shadeColor, count: 14, dotScale: 0.05)
                          painter.nub(shade: kind.shadeColor)
        case .mandarin:   painter.dimples(shade: kind.shadeColor, count: 10, dotScale: 0.04)
                          painter.leaf(at: CGPoint(x: 0.18, y: 0.92), angle: -0.5, scale: 0.36)
                          painter.nub(shade: kind.shadeColor)
        case .kiwi:       painter.fuzz()
                          painter.nub(shade: kind.shadeColor)
        case .peach:      painter.peach(shade: kind.shadeColor)
        case .apple:      painter.stemAndLeaf(stemTilt: 0.05)
        case .grape:      painter.grape(base: kind.baseColor, shade: kind.shadeColor)
        case .pineapple:  painter.pineapple(shade: kind.shadeColor)
        case .melon:      painter.melon()
        }
    }

    /// `hex`（RGB）から色を作る。
    static func cgColor(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    // MARK: - 部品

    /// 果物 1 個ぶんの描き手。座標は中心を原点・半径を 1 とした相対値で受ける。
    private struct Painter {
        let context: CGContext
        let center: CGPoint
        let radius: CGFloat

        /// 茎の色（共通）。
        static let stem: UInt32 = 0x6B4A2B
        /// 葉の色（共通）。
        static let leaf: UInt32 = 0x5FAE4A
        static let leafDark: UInt32 = 0x3F8A32

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * radius, y: center.y + y * radius)
        }

        func rect(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
            CGRect(x: center.x + (cx - w / 2) * radius, y: center.y + (cy - h / 2) * radius,
                   width: w * radius, height: h * radius)
        }

        func fillCircle(cx: CGFloat, cy: CGFloat, r: CGFloat, _ color: CGColor) {
            context.setFillColor(color)
            context.fillEllipse(in: rect(cx: cx, cy: cy, w: r * 2, h: r * 2))
        }

        func line(from a: CGPoint, to b: CGPoint, width: CGFloat, _ color: CGColor) {
            context.setStrokeColor(color)
            context.setLineWidth(width * radius)
            context.setLineCap(.round)
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()
        }

        /// 円の内側だけに描くための切り抜き。
        func clipToBody() {
            context.addEllipse(in: rect(cx: 0, cy: 0, w: 2, h: 2))
            context.clip()
        }

        /// 地の円・縁・つや。全種共通。
        mutating func body(base: UInt32, shade: UInt32) {
            fillCircle(cx: 0, cy: 0, r: 1, cgColor(base))
            // 縁を少し濃くして立体感を出す。
            context.setStrokeColor(cgColor(shade, alpha: 0.55))
            context.setLineWidth(0.09 * radius)
            context.strokeEllipse(in: rect(cx: 0, cy: 0, w: 2 - 0.09, h: 2 - 0.09))
            // つや（左上）。
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35))
            context.fillEllipse(in: rect(cx: -0.38, cy: 0.42, w: 0.42, h: 0.26))
        }

        /// ブルーベリーの上の星型のガク。
        func blueberry(shade: UInt32) {
            let crown = point(0, 0.5)
            for index in 0..<5 {
                let angle = CGFloat(index) / 5 * 2 * .pi + .pi / 2
                let tip = CGPoint(x: crown.x + cos(angle) * 0.26 * radius, y: crown.y + sin(angle) * 0.22 * radius)
                line(from: crown, to: tip, width: 0.09, cgColor(shade))
            }
            fillCircle(cx: 0, cy: 0.5, r: 0.11, cgColor(shade))
        }

        /// 茎と葉（さくらんぼ・りんご）。`stemTilt` は茎の傾き（右へ）。
        func stemAndLeaf(stemTilt: CGFloat) {
            line(from: point(0, 0.82), to: point(stemTilt, 1.22), width: 0.1, cgColor(Painter.stem))
            leaf(at: CGPoint(x: stemTilt + 0.22, y: 1.05), angle: -0.35, scale: 0.4)
        }

        /// 葉 1 枚。`at` は葉の中心（相対座標）。
        func leaf(at position: CGPoint, angle: CGFloat, scale: CGFloat) {
            context.saveGState()
            let origin = point(position.x, position.y)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: angle)
            context.setFillColor(cgColor(Painter.leaf))
            context.fillEllipse(in: CGRect(x: -scale * radius / 2, y: -scale * radius / 4, width: scale * radius, height: scale * radius / 2))
            context.setStrokeColor(cgColor(Painter.leafDark))
            context.setLineWidth(0.04 * radius)
            context.move(to: CGPoint(x: -scale * radius / 2, y: 0))
            context.addLine(to: CGPoint(x: scale * radius / 2, y: 0))
            context.strokePath()
            context.restoreGState()
        }

        /// いちごの種とヘタ。
        func strawberry(shade: UInt32) {
            context.saveGState()
            clipToBody()
            let seed = cgColor(0xFFE58A)
            for row in -2...2 {
                for column in -2...2 {
                    let x = CGFloat(column) * 0.34 + (row.isMultiple(of: 2) ? 0 : 0.17)
                    let y = CGFloat(row) * 0.3 - 0.1
                    guard x * x + y * y < 0.62 else { continue }
                    context.setFillColor(seed)
                    context.fillEllipse(in: rect(cx: x, cy: y, w: 0.09, h: 0.13))
                }
            }
            context.restoreGState()
            // ヘタ（5 枚）。
            for index in -2...2 {
                let spread = CGFloat(index) * 0.32
                let base = point(spread * 0.6, 0.72)
                let tip = point(spread, 1.15)
                context.setFillColor(cgColor(index == 0 ? Painter.leafDark : Painter.leaf))
                context.move(to: CGPoint(x: base.x - 0.12 * radius, y: base.y))
                context.addLine(to: tip)
                context.addLine(to: CGPoint(x: base.x + 0.12 * radius, y: base.y))
                context.closePath()
                context.fillPath()
            }
        }

        /// 皮の点々（ライム・みかん）。位置は決め打ち（乱数を使わない）。
        func dimples(shade: UInt32, count: Int, dotScale: CGFloat) {
            context.saveGState()
            clipToBody()
            context.setFillColor(cgColor(shade, alpha: 0.35))
            for index in 0..<count {
                let angle = CGFloat(index) * 2.399 // 黄金角で散らす
                let distance = 0.25 + 0.6 * CGFloat(index) / CGFloat(count)
                let x = cos(angle) * distance
                let y = sin(angle) * distance
                context.fillEllipse(in: rect(cx: x, cy: y, w: dotScale * 2, h: dotScale * 2))
            }
            context.restoreGState()
        }

        /// 上の小さいヘタ。
        func nub(shade: UInt32) {
            fillCircle(cx: 0, cy: 0.88, r: 0.1, cgColor(shade))
        }

        /// キウイの毛。
        func fuzz() {
            context.saveGState()
            clipToBody()
            context.setFillColor(cgColor(0xC4A87E, alpha: 0.75))
            for index in 0..<40 {
                let angle = CGFloat(index) * 2.399
                let distance = 0.15 + 0.82 * CGFloat(index) / 40
                context.fillEllipse(in: rect(cx: cos(angle) * distance, cy: sin(angle) * distance, w: 0.07, h: 0.07))
            }
            context.restoreGState()
        }

        /// ももの割れ目と葉、ほお。
        func peach(shade: UInt32) {
            context.saveGState()
            clipToBody()
            context.setFillColor(cgColor(0xFF8FA3, alpha: 0.55))
            context.fillEllipse(in: rect(cx: 0.3, cy: -0.25, w: 0.9, h: 0.9))
            context.setStrokeColor(cgColor(shade, alpha: 0.7))
            context.setLineWidth(0.06 * radius)
            context.setLineCap(.round)
            context.move(to: point(0.05, 0.95))
            context.addQuadCurve(to: point(0.12, -0.35), control: point(-0.25, 0.3))
            context.strokePath()
            context.restoreGState()
            leaf(at: CGPoint(x: -0.3, y: 0.98), angle: 0.5, scale: 0.42)
        }

        /// ぶどう。濃い地の上に粒を房の形に並べる。
        func grape(base: UInt32, shade: UInt32) {
            fillCircle(cx: 0, cy: 0, r: 0.96, cgColor(shade))
            let berry = cgColor(0x9B7BD6)
            let rows: [(y: CGFloat, xs: [CGFloat])] = [
                (0.5, [-0.5, 0, 0.5]),
                (0.05, [-0.72, -0.24, 0.24, 0.72]),
                (-0.4, [-0.5, 0, 0.5]),
                (-0.75, [0]),
            ]
            for row in rows {
                for x in row.xs {
                    fillCircle(cx: x, cy: row.y, r: 0.24, berry)
                    fillCircle(cx: x - 0.07, cy: row.y + 0.08, r: 0.06, CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45))
                }
            }
            line(from: point(0, 0.85), to: point(0.15, 1.22), width: 0.1, cgColor(Painter.stem))
        }

        /// パイナップルの格子と葉。
        func pineapple(shade: UInt32) {
            context.saveGState()
            clipToBody()
            context.setStrokeColor(cgColor(shade, alpha: 0.65))
            context.setLineWidth(0.05 * radius)
            for offset in stride(from: CGFloat(-2.4), through: 2.4, by: 0.42) {
                context.move(to: point(offset - 1.5, -1.5))
                context.addLine(to: point(offset + 1.5, 1.5))
                context.move(to: point(offset + 1.5, -1.5))
                context.addLine(to: point(offset - 1.5, 1.5))
            }
            context.strokePath()
            context.restoreGState()
            for index in -2...2 {
                let spread = CGFloat(index) * 0.22
                let base = point(spread * 0.5, 0.7)
                let tip = point(spread * 1.6, 1.28 - abs(CGFloat(index)) * 0.08)
                context.setFillColor(cgColor(index.isMultiple(of: 2) ? Painter.leafDark : Painter.leaf))
                context.move(to: CGPoint(x: base.x - 0.09 * radius, y: base.y))
                context.addLine(to: tip)
                context.addLine(to: CGPoint(x: base.x + 0.09 * radius, y: base.y))
                context.closePath()
                context.fillPath()
            }
        }

        /// メロンの網目と T 字の茎。
        func melon() {
            context.saveGState()
            clipToBody()
            context.setStrokeColor(cgColor(0xEAF3D6, alpha: 0.9))
            context.setLineWidth(0.05 * radius)
            for offset in stride(from: CGFloat(-2.0), through: 2.0, by: 0.4) {
                context.move(to: point(offset - 1.2, -1.2))
                context.addQuadCurve(to: point(offset + 1.2, 1.2), control: point(offset + 0.5, -0.3))
                context.move(to: point(offset + 1.2, -1.2))
                context.addQuadCurve(to: point(offset - 1.2, 1.2), control: point(offset - 0.5, -0.3))
            }
            context.strokePath()
            context.restoreGState()
            line(from: point(0, 0.86), to: point(0, 1.2), width: 0.1, cgColor(Painter.stem))
            line(from: point(-0.22, 1.2), to: point(0.22, 1.2), width: 0.1, cgColor(Painter.stem))
        }
    }
}

// MARK: - 共有キャッシュ

/// 描いた画像の置き場。盤（SpriteKit）と「つぎ」（SwiftUI）が同じ絵を使う。
@MainActor
public enum FruitArtCache {
    private static var images: [String: CGImage] = [:]

    /// `kind` の絵。同じ寸法は 1 回だけ描く。
    public static func image(_ kind: FruitKind, pixels: Int) -> CGImage? {
        let key = "\(kind.rawValue)@\(pixels)"
        if let cached = images[key] { return cached }
        guard let image = FruitArt.image(kind, pixels: pixels) else { return nil }
        images[key] = image
        return image
    }
}

/// 果物 1 個の絵を出す SwiftUI の部品（「つぎ」の表示・ルールの一覧）。
public struct FruitIcon: View {
    private let kind: FruitKind

    public init(_ kind: FruitKind) {
        self.kind = kind
    }

    public var body: some View {
        if let image = FruitArtCache.image(kind, pixels: 128) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}
