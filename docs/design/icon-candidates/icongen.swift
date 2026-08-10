// あそびば アプリアイコン生成（2×2 全面分割: 将棋駒・碁石・スペード・マインスイーパー旗）
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let S: CGFloat = 1024
let half = S / 2

func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// パレット
let coral  = color(0xEF5350)
let teal   = color(0x26A69A)
let mustard = color(0xF2B33D)
let navy   = color(0x2E3A59)
let cream  = color(0xF7EDD8)
let ink    = color(0x33291F)
let white  = color(0xFAF7EF)
let black  = color(0x2B2B2B)
let flagRed = color(0xE94F44)

let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// 上原点に変換（以下すべて「上から」の座標で書く）
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

// ---- 4色の全面クアドラント ----
ctx.setFillColor(coral);   ctx.fill(CGRect(x: 0, y: 0, width: half, height: half))          // 左上
ctx.setFillColor(teal);    ctx.fill(CGRect(x: half, y: 0, width: half, height: half))       // 右上
ctx.setFillColor(mustard); ctx.fill(CGRect(x: 0, y: half, width: half, height: half))       // 左下
ctx.setFillColor(navy);    ctx.fill(CGRect(x: half, y: half, width: half, height: half))    // 右下

// ---- 左上: 将棋駒（五角形） ----
let koma = CGMutablePath()
koma.move(to: CGPoint(x: 256, y: 104))    // 頂点
koma.addLine(to: CGPoint(x: 344, y: 194)) // 右肩
koma.addLine(to: CGPoint(x: 366, y: 404)) // 右底
koma.addLine(to: CGPoint(x: 146, y: 404)) // 左底
koma.addLine(to: CGPoint(x: 168, y: 194)) // 左肩
koma.closeSubpath()
ctx.addPath(koma)
ctx.setFillColor(cream)
ctx.fillPath()
ctx.addPath(koma)
ctx.setStrokeColor(ink)
ctx.setLineWidth(18)
ctx.setLineJoin(.round)
ctx.strokePath()

// ---- 右上: 碁石（黒・白） ----
ctx.setFillColor(black)
ctx.fillEllipse(in: CGRect(x: 604, y: 128, width: 176, height: 176))
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: 736, y: 236, width: 176, height: 176))
ctx.setStrokeColor(black)
ctx.setLineWidth(12)
ctx.strokeEllipse(in: CGRect(x: 742, y: 242, width: 164, height: 164))

// ---- 左下: スペード ----
let cx: CGFloat = 256, top: CGFloat = 600
let spade = CGMutablePath()
spade.move(to: CGPoint(x: cx, y: top))                                  // 先端
spade.addCurve(to: CGPoint(x: 130, y: 810),
               control1: CGPoint(x: 200, y: 680), control2: CGPoint(x: 130, y: 730))
spade.addArc(center: CGPoint(x: 193, y: 822), radius: 64,
             startAngle: .pi, endAngle: 0, clockwise: true)
spade.addLine(to: CGPoint(x: cx, y: 800))
spade.addLine(to: CGPoint(x: 256 + (256 - 257), y: 800))
spade.addArc(center: CGPoint(x: 319, y: 822), radius: 64,
             startAngle: .pi, endAngle: 0, clockwise: true)
spade.addCurve(to: CGPoint(x: cx, y: top),
               control1: CGPoint(x: 382, y: 730), control2: CGPoint(x: 312, y: 680))
spade.closeSubpath()
ctx.addPath(spade)
ctx.setFillColor(navy)
ctx.fillPath()
// 茎
let stem = CGMutablePath()
stem.move(to: CGPoint(x: 256, y: 840))
stem.addCurve(to: CGPoint(x: 210, y: 946),
              control1: CGPoint(x: 250, y: 900), control2: CGPoint(x: 232, y: 930))
stem.addLine(to: CGPoint(x: 302, y: 946))
stem.addCurve(to: CGPoint(x: 256, y: 840),
              control1: CGPoint(x: 280, y: 930), control2: CGPoint(x: 262, y: 900))
stem.closeSubpath()
ctx.addPath(stem)
ctx.setFillColor(navy)
ctx.fillPath()

// ---- 右下: マインスイーパーの旗 ----
ctx.setFillColor(cream)
ctx.fill(CGRect(x: 758, y: 620, width: 20, height: 290))                 // ポール
let flag = CGMutablePath()
flag.move(to: CGPoint(x: 778, y: 620))
flag.addLine(to: CGPoint(x: 908, y: 684))
flag.addLine(to: CGPoint(x: 778, y: 748))
flag.closeSubpath()
ctx.addPath(flag)
ctx.setFillColor(flagRed)
ctx.fillPath()
let base = CGPath(roundedRect: CGRect(x: 706, y: 896, width: 124, height: 34),
                  cornerWidth: 14, cornerHeight: 14, transform: nil)
ctx.addPath(base)
ctx.setFillColor(cream)
ctx.fillPath()

// ---- 出力 ----
let img = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("written: \(out.path)")
