// あそびば アプリアイコン v2 — 質感強化版（ソフトシャドウ・ベジェ曲線スペード・重量バランス調整）
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let S: CGFloat = 1024
let half = S / 2

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let coral   = color(0xF0625D)
let teal    = color(0x2BA89A)
let mustard = color(0xF4B942)
let navy    = color(0x303B5C)
let cream   = color(0xFBF3E2)
let ink     = color(0x3A2E28)
let stoneW  = color(0xFCF8EF)
let stoneB  = color(0x2E2C2A)
let flagRed = color(0xE8483F)
let shadowC = color(0x000000, 0.22)

let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

func withShadow(_ draw: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: shadowC)
    draw()
    ctx.restoreGState()
}

// ---- 4色の全面クアドラント ----
ctx.setFillColor(coral);   ctx.fill(CGRect(x: 0, y: 0, width: half, height: half))
ctx.setFillColor(teal);    ctx.fill(CGRect(x: half, y: 0, width: half, height: half))
ctx.setFillColor(mustard); ctx.fill(CGRect(x: 0, y: half, width: half, height: half))
ctx.setFillColor(navy);    ctx.fill(CGRect(x: half, y: half, width: half, height: half))

// ---- 左上: 将棋駒 ----
let koma = CGMutablePath()
koma.move(to: CGPoint(x: 256, y: 112))
koma.addLine(to: CGPoint(x: 348, y: 202))
koma.addLine(to: CGPoint(x: 372, y: 408))
koma.addLine(to: CGPoint(x: 140, y: 408))
koma.addLine(to: CGPoint(x: 164, y: 202))
koma.closeSubpath()
withShadow {
    ctx.addPath(koma)
    ctx.setFillColor(cream)
    ctx.fillPath()
}
// 駒の縁ライン（内側に細く。木駒の面取り表現）
let komaInner = CGMutablePath()
komaInner.move(to: CGPoint(x: 256, y: 152))
komaInner.addLine(to: CGPoint(x: 322, y: 218))
komaInner.addLine(to: CGPoint(x: 341, y: 378))
komaInner.addLine(to: CGPoint(x: 171, y: 378))
komaInner.addLine(to: CGPoint(x: 190, y: 218))
komaInner.closeSubpath()
ctx.addPath(komaInner)
ctx.setStrokeColor(color(0xD9C6A0))
ctx.setLineWidth(10)
ctx.setLineJoin(.round)
ctx.strokePath()

// ---- 右上: 碁石 ----
withShadow {
    ctx.setFillColor(stoneB)
    ctx.fillEllipse(in: CGRect(x: 592, y: 118, width: 200, height: 200))
}
// 黒石のハイライト
ctx.setStrokeColor(color(0xFFFFFF, 0.35))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
ctx.strokeEllipse(in: CGRect(x: 622, y: 146, width: 90, height: 90))
ctx.setFillColor(stoneB)
ctx.fillEllipse(in: CGRect(x: 616, y: 154, width: 150, height: 150)) // ハイライトを三日月に削る
withShadow {
    ctx.setFillColor(stoneW)
    ctx.fillEllipse(in: CGRect(x: 728, y: 232, width: 200, height: 200))
}

// ---- 左下: スペード（MDN 古典ハート曲線を上下反転） ----
// 元座標系: x 20..130, y 25..120（点は下）→ 反転・スケールして点を上に
func spadePoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    let s: CGFloat = 2.75
    let cx: CGFloat = 256, topY: CGFloat = 566
    return CGPoint(x: cx + (x - 75) * s, y: topY + (120 - y) * s)
}
let sp = CGMutablePath()
sp.move(to: spadePoint(75, 120))
sp.addCurve(to: spadePoint(20, 62.5), control1: spadePoint(40, 102), control2: spadePoint(20, 80))
sp.addCurve(to: spadePoint(50, 25),   control1: spadePoint(20, 62.5), control2: spadePoint(20, 25))
sp.addCurve(to: spadePoint(75, 40),   control1: spadePoint(70, 25),   control2: spadePoint(75, 37))
sp.addCurve(to: spadePoint(100, 25),  control1: spadePoint(75, 37),   control2: spadePoint(80, 25))
sp.addCurve(to: spadePoint(130, 62.5), control1: spadePoint(130, 25), control2: spadePoint(130, 62.5))
sp.addCurve(to: spadePoint(75, 120),  control1: spadePoint(130, 80),  control2: spadePoint(110, 102))
sp.closeSubpath()
withShadow {
    ctx.addPath(sp)
    ctx.setFillColor(navy)
    ctx.fillPath()
    // 茎（フレア付き）
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 256, y: 830))
    stem.addCurve(to: CGPoint(x: 206, y: 948),
                  control1: CGPoint(x: 252, y: 900), control2: CGPoint(x: 228, y: 934))
    stem.addQuadCurve(to: CGPoint(x: 306, y: 948), control: CGPoint(x: 256, y: 962))
    stem.addCurve(to: CGPoint(x: 256, y: 830),
                  control1: CGPoint(x: 284, y: 934), control2: CGPoint(x: 260, y: 900))
    stem.closeSubpath()
    ctx.addPath(stem)
    ctx.setFillColor(navy)
    ctx.fillPath()
}

// ---- 右下: マインスイーパーの旗（風になびく三角旗） ----
withShadow {
    // ポール
    let pole = CGPath(roundedRect: CGRect(x: 754, y: 608, width: 24, height: 300),
                      cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.addPath(pole)
    ctx.setFillColor(cream)
    ctx.fillPath()
}
withShadow {
    let flag = CGMutablePath()
    flag.move(to: CGPoint(x: 778, y: 612))
    flag.addQuadCurve(to: CGPoint(x: 916, y: 682), control: CGPoint(x: 866, y: 622))
    flag.addQuadCurve(to: CGPoint(x: 778, y: 752), control: CGPoint(x: 866, y: 742))
    flag.closeSubpath()
    ctx.addPath(flag)
    ctx.setFillColor(flagRed)
    ctx.fillPath()
}
withShadow {
    let base = CGPath(roundedRect: CGRect(x: 700, y: 892, width: 132, height: 36),
                      cornerWidth: 18, cornerHeight: 18, transform: nil)
    ctx.addPath(base)
    ctx.setFillColor(cream)
    ctx.fillPath()
}

// ---- 出力 ----
let img = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon2.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("written: \(out.path)")
