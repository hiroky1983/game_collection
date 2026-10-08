import SwiftUI

/// 荷物 5 種の絵（#1909。会長決定 2026-10-07/08: 色はぷよぷよに準えた 5 色、四角の中に絵ではなく
/// **ピースそのものが荷物の形**に見えるようにする）。
///
/// 形で見分けが付くので、色の見え方に個人差があっても 5 種を取り違えにくい。
/// 図形を `Shape` の ZStack で積むと iOS で潰れることがあるため、`Canvas` 1 枚に描く。
/// 寸法は 1 マスを 1×1 とした比で持ち、`side` が変わっても（盤 30pt 前後・「つぎ」26pt）同じ形に描ける。
struct OjisanPuzzleLuggageArt: View {
    /// 盤の番号（1...5）。範囲外は何も描かない。
    let value: Int

    /// 色（会長決定 2026-10-08）。1 = 座布団の山（紫）… 5 = ビールケース（黄）。
    static func base(_ value: Int) -> Color {
        switch value {
        case 1: Color(red: 0xB4 / 255, green: 0x97 / 255, blue: 0xF0 / 255) // 紫
        case 2: Color(red: 0x62 / 255, green: 0xD2 / 255, blue: 0x66 / 255) // 緑
        case 3: Color(red: 0x1F / 255, green: 0x4F / 255, blue: 0xC2 / 255) // 青
        case 4: Color(red: 0xCC / 255, green: 0x2E / 255, blue: 0x24 / 255) // 赤
        case 5: Color(red: 0xF7 / 255, green: 0xC5 / 255, blue: 0x31 / 255) // 黄
        default: .clear
        }
    }

    /// 縁取り・影の色（地色を暗くしたもの）。
    private static func dark(_ value: Int) -> Color {
        switch value {
        case 1: Color(red: 0x5E / 255, green: 0x45 / 255, blue: 0x9C / 255)
        case 2: Color(red: 0x1F / 255, green: 0x6B / 255, blue: 0x2C / 255)
        case 3: Color(red: 0x0B / 255, green: 0x22 / 255, blue: 0x6B / 255)
        case 4: Color(red: 0x6B / 255, green: 0x12 / 255, blue: 0x0C / 255)
        case 5: Color(red: 0x8A / 255, green: 0x62 / 255, blue: 0x00 / 255)
        default: .clear
        }
    }

    private static let light = Color.white.opacity(0.55)

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            guard s > 0, (1...OjisanPuzzleBoard.kindCount).contains(value) else { return }
            let base = Self.base(value)
            let dark = Self.dark(value)
            let line = max(1, s * 0.055)

            func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            func round(_ r: CGRect, _ radius: Double) -> Path {
                Path(roundedRect: r, cornerRadius: radius * s, style: .continuous)
            }
            func solid(_ path: Path, _ fill: Color, outline: Color = dark) {
                ctx.fill(path, with: .color(fill))
                ctx.stroke(path, with: .color(outline), lineWidth: line)
            }

            switch value {
            case 1: // 座布団の山: 3 枚を少しずらして重ね、いちばん上に房
                solid(round(rect(0.05, 0.64, 0.90, 0.30), 0.12), base)
                solid(round(rect(0.12, 0.36, 0.80, 0.30), 0.12), base.opacity(0.78))
                solid(round(rect(0.07, 0.09, 0.84, 0.29), 0.12), base)
                for x in [0.15, 0.83] {
                    ctx.fill(Path(ellipseIn: rect(x - 0.045, 0.19, 0.09, 0.09)), with: .color(dark))
                }
            case 2: // スイカ: 丸い玉に縦の縞、ヘタ
                let body = Path(ellipseIn: rect(0.04, 0.14, 0.92, 0.82))
                solid(body, base)
                for w in [0.56, 0.24] {
                    ctx.stroke(Path(ellipseIn: rect(0.5 - w / 2, 0.14, w, 0.82)),
                               with: .color(dark.opacity(0.8)), lineWidth: line * 0.9)
                }
                solid(round(rect(0.44, 0.03, 0.12, 0.15), 0.04), Color(red: 0.42, green: 0.27, blue: 0.13))
            case 3: // クーラーボックス: 本体 + 白いふた + 持ち手
                var handle = Path()
                handle.move(to: CGPoint(x: 0.30 * s, y: 0.24 * s))
                handle.addLine(to: CGPoint(x: 0.30 * s, y: 0.10 * s))
                handle.addLine(to: CGPoint(x: 0.70 * s, y: 0.10 * s))
                handle.addLine(to: CGPoint(x: 0.70 * s, y: 0.24 * s))
                ctx.stroke(handle, with: .color(dark), style: StrokeStyle(lineWidth: line * 1.7, lineCap: .round, lineJoin: .round))
                solid(round(rect(0.04, 0.34, 0.92, 0.60), 0.10), base)
                solid(round(rect(0.02, 0.22, 0.96, 0.20), 0.08), .white)
                solid(round(rect(0.42, 0.48, 0.16, 0.13), 0.04), .white)
            case 4: // 灯油のポリタンク: 角張った缶 + 注ぎ口 + 持ち手の穴
                var can = Path()
                can.move(to: CGPoint(x: 0.14 * s, y: 0.30 * s))
                can.addLine(to: CGPoint(x: 0.46 * s, y: 0.30 * s))
                can.addLine(to: CGPoint(x: 0.56 * s, y: 0.20 * s))
                can.addLine(to: CGPoint(x: 0.86 * s, y: 0.20 * s))
                can.addLine(to: CGPoint(x: 0.90 * s, y: 0.94 * s))
                can.addLine(to: CGPoint(x: 0.10 * s, y: 0.94 * s))
                can.closeSubpath()
                solid(can, base)
                solid(round(rect(0.64, 0.05, 0.16, 0.17), 0.04), Color(red: 0.98, green: 0.80, blue: 0.20))
                solid(round(rect(0.17, 0.38, 0.24, 0.13), 0.06), Color(red: 0.25, green: 0.05, blue: 0.04), outline: dark)
                ctx.fill(round(rect(0.22, 0.62, 0.56, 0.20), 0.04), with: .color(Self.light))
            case 5: // ビールケース: 黄色い箱 + 並んだ瓶の頭
                for x in [0.17, 0.41, 0.65] {
                    solid(round(rect(x, 0.05, 0.18, 0.40), 0.05), Color(red: 0.42, green: 0.25, blue: 0.10))
                    ctx.fill(round(rect(x + 0.02, 0.07, 0.14, 0.07), 0.02), with: .color(Color(red: 0.98, green: 0.92, blue: 0.62)))
                }
                solid(round(rect(0.04, 0.38, 0.92, 0.58), 0.08), base)
                for x in [0.13, 0.55] {
                    solid(round(rect(x, 0.54, 0.32, 0.26), 0.05), dark.opacity(0.85), outline: dark)
                }
            default: break
            }
        }
    }
}
