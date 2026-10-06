#if canImport(UIKit)
import UIKit

/// 怒りの段階②の湯気の絵（#1797・会長確定版 = モック v2「プンッ」）: 薄い水色のもくもくの雲（円の重なり）に、左下へギザギザの尾。
/// 塗りは薄い水色、左下に薄い影、縁は青灰色の線。縁の線は「太らせた形を線の色で塗ってから本体を塗る」で作る
/// （円ごとに線を引くと中に網目が出る）。描画では texture の色が少し沈むので、狙いの薄い水色より明るめに置いてある。
/// 色の絵と不透明度の絵（白 = 不透明）を 1 組で返す。`mirrored` は左右反転（左の湯気用・尾が右下へ）。
enum HomerunAngrySteamArt {
    static let size = 512

    static func images(mirrored: Bool) -> (CGImage, CGImage)? {
        let n = size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let bumps: [(CGFloat, CGFloat, CGFloat)] = [(296, 128, 108), (186, 196, 94), (402, 204, 96), (232, 300, 90), (360, 300, 90), (296, 232, 104)]
        let tailPoints: [(CGFloat, CGFloat)] = [(224, 330), (160, 372), (204, 372), (96, 462), (190, 418), (132, 500), (248, 408), (304, 366)]
        func shape(grow: CGFloat) -> UIBezierPath {
            let path = UIBezierPath()
            for (x, y, r) in bumps {
                path.append(UIBezierPath(ovalIn: CGRect(x: x - r - grow, y: y - r - grow, width: 2 * (r + grow), height: 2 * (r + grow))))
            }
            return path
        }
        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: tailPoints[0].0, y: tailPoints[0].1))
        for pt in tailPoints.dropFirst() { tail.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        tail.close()
        tail.lineJoinStyle = .round
        let lineWidth: CGFloat = 11
        let fill = UIColor(red: 0.93, green: 0.97, blue: 1.0, alpha: 1)
        let light = UIColor.white
        let line = UIColor(red: 0.40, green: 0.54, blue: 0.72, alpha: 1)
        func draw(_ g: CGContext, lineColor: UIColor, fillColor: UIColor, lightColor: UIColor?) {
            if mirrored {
                g.translateBy(x: CGFloat(n), y: 0)
                g.scaleBy(x: -1, y: 1)
            }
            lineColor.setFill(); shape(grow: lineWidth).fill()
            lineColor.setStroke(); tail.lineWidth = lineWidth * 2; tail.stroke(); lineColor.setFill(); tail.fill()
            fillColor.setFill(); shape(grow: 0).fill(); tail.fill()
            if let lightColor {
                g.saveGState()
                let clip = shape(grow: 0)
                clip.append(tail)
                clip.addClip()
                g.translateBy(x: 16, y: -16)
                lightColor.setFill(); shape(grow: 0).fill(); tail.fill()
                g.restoreGState()
            }
        }
        let color = UIGraphicsImageRenderer(size: CGSize(width: n, height: n), format: format).image { ctx in
            draw(ctx.cgContext, lineColor: line, fillColor: fill, lightColor: light)
        }
        let mask = UIGraphicsImageRenderer(size: CGSize(width: n, height: n), format: format).image { ctx in
            UIColor.black.setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: n, height: n))
            draw(ctx.cgContext, lineColor: .white, fillColor: .white, lightColor: nil)
        }
        guard let c = color.cgImage, let m = mask.cgImage else { return nil }
        return (c, m)
    }
}
#endif
