import SwiftUI

// MARK: - A′: 2D の限界（回転体を「行ごとの円筒シェーディング」で描く）

/// 光源は左上手前（既存の碁石・立体駒と同じ向き）。
private struct V3 { var x, y, z: Double
    var len: Double { (x*x + y*y + z*z).squareRoot() }
    var unit: V3 { let l = len; return V3(x: x/l, y: y/l, z: z/l) }
    func dot(_ o: V3) -> Double { x*o.x + y*o.y + z*o.z }
}
private struct RGB { var r, g, b: Double
    func mixed(_ o: RGB, _ t: Double) -> RGB { RGB(r: r+(o.r-r)*t, g: g+(o.g-g)*t, b: b+(o.b-b)*t) }
    var color: Color { Color(.sRGB, red: min(1, max(0, r)), green: min(1, max(0, g)), blue: min(1, max(0, b))) }
}

private let lightDir = V3(x: -0.55, y: 0.65, z: 0.55).unit
private let halfVec = V3(x: lightDir.x, y: lightDir.y, z: lightDir.z + 1).unit

private struct Material2D {
    let albedo: RGB
    let shininess: Double
    let specular: Double
    let envAmount: Double
    static func of(_ c: ChessColor) -> Material2D {
        c == .white
            ? Material2D(albedo: RGB(r: 0.97, g: 0.93, b: 0.83), shininess: 38, specular: 0.30, envAmount: 0.22)
            : Material2D(albedo: RGB(r: 0.19, g: 0.14, b: 0.10), shininess: 70, specular: 0.95, envAmount: 0.60)
    }
}

/// 法線 n の点の色。拡散＋ブリン鏡面＋周縁の写り込み（空の白と盤の照り返しの茶）。
private func shade(_ n: V3, _ m: Material2D) -> RGB {
    let hemi = n.y * 0.5 + 0.5
    let sky = RGB(r: 0.92, g: 0.93, b: 0.96)
    let bounce = RGB(r: 0.50, g: 0.36, b: 0.22)
    let ambient = bounce.mixed(sky, hemi)
    let ndl = max(0, n.dot(lightDir))
    var c = RGB(r: m.albedo.r * (ambient.r * 0.42 + ndl * 0.82),
                g: m.albedo.g * (ambient.g * 0.42 + ndl * 0.82),
                b: m.albedo.b * (ambient.b * 0.42 + ndl * 0.82))
    let spec = pow(max(0, n.dot(halfVec)), m.shininess) * m.specular
    let fres = pow(1 - max(0, n.z), 3)
    let env = bounce.mixed(RGB(r: 1, g: 1, b: 1), hemi)
    c = RGB(r: c.r + spec + env.r * fres * m.envAmount,
            g: c.g + spec + env.g * fres * m.envAmount,
            b: c.b + spec + env.b * fres * m.envAmount)
    return c
}

struct RealPiece2DView: View {
    let piece: ChessPiece
    let size: CGFloat

    private static let groundY: CGFloat = 0.93   // 接地線（セル上端からの比）
    private static let scale: CGFloat = 0.90     // 高さ 1.0 → セル高の 0.90

    var body: some View {
        let mat = Material2D.of(piece.color)
        return Canvas { ctx, sz in
            let W = sz.width, H = sz.height
            func pt(_ dx: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: W * (0.5 + dx * Self.scale), y: H * (Self.groundY - y * Self.scale))
            }
            // 接地影
            let shadowRect = CGRect(x: W * 0.10, y: H * (Self.groundY - 0.045), width: W * 0.80, height: H * 0.10)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: W * 0.022))
                l.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.42)))
            }
            switch piece.type {
            case .knight:
                Self.drawKnight(&ctx, W: W, H: H, mat: mat, pt: pt)
            default:
                Self.drawRevolved(&ctx, type: piece.type, W: W, H: H, mat: mat, pt: pt)
            }
        }
        .frame(width: size, height: size)
    }

    // 回転体: 断面を細かい帯に刻み、帯ごとに円筒のグラデーションを敷く。
    private static func drawRevolved(_ ctx: inout GraphicsContext, type: ChessPieceType, W: CGFloat, H: CGFloat,
                                     mat: Material2D, pt: (CGFloat, CGFloat) -> CGPoint) {
        let prof = RealProfiles.smooth(RealProfiles.profile(type))
        // 輪郭（右側を上へ → 左側を下へ）
        var sil = Path()
        sil.move(to: pt(0, 0))
        for p in prof { sil.addLine(to: pt(p.r, p.y)) }
        for p in prof.reversed() { sil.addLine(to: pt(-p.r, p.y)) }
        sil.closeSubpath()

        var layer = ctx
        layer.clip(to: sil)
        for i in 0..<(prof.count - 1) {
            let a = prof[i], b = prof[i + 1]
            let dr = Double(b.r - a.r), dy = Double(b.y - a.y)
            let len = (dr*dr + dy*dy).squareRoot()
            if len < 1e-6 || abs(dy) < 1e-5 { continue }
            let nx = dy / len, ny = -dr / len
            let rMid = (a.r + b.r) / 2
            var stops: [Gradient.Stop] = []
            let steps = 24
            for k in 0...steps {
                let th = -Double.pi / 2 + Double.pi * Double(k) / Double(steps)
                let n = V3(x: nx * sin(th), y: ny, z: max(0.0001, nx * cos(th)))
                stops.append(.init(color: shade(n.unit, mat).color, location: Double(k) / Double(steps)))
            }
            var slab = Path()
            slab.move(to: pt(-a.r, a.y - 0.002))
            slab.addLine(to: pt(a.r, a.y - 0.002))
            slab.addLine(to: pt(b.r, b.y))
            slab.addLine(to: pt(-b.r, b.y))
            slab.closeSubpath()
            layer.fill(slab, with: .linearGradient(Gradient(stops: stops),
                                                   startPoint: pt(-rMid, 0), endPoint: pt(rMid, 0)))
        }

        // 輪郭より外へ出る飾り（銃眼・玉・十字）はクリップしない ctx へ描く
        switch type {
        case .rook: drawRookCrown(&ctx, W: W, H: H, mat: mat, pt: pt)
        case .bishop:
            var slit = Path()
            slit.move(to: pt(0.075, 0.70)); slit.addLine(to: pt(-0.03, 0.57))
            layer.stroke(slit, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: W * 0.014, lineCap: .round))
        case .queen: drawQueenBalls(&ctx, W: W, H: H, mat: mat, pt: pt)
        case .king: drawKingCross(&ctx, W: W, H: H, mat: mat, pt: pt)
        default: break
        }
        // 上端の細い縁（輪郭線ではなく、面の切れ目に落ちる明暗）
        var rim = ctx
        rim.clip(to: sil)
        rim.stroke(sil, with: .color(.black.opacity(mat.albedo.r > 0.5 ? 0.10 : 0.35)), lineWidth: W * 0.010)
    }

    private static func cylinder(_ ctx: inout GraphicsContext, rect: CGRect, radius: CGFloat, mat: Material2D,
                                 centerX: CGFloat, W: CGFloat) {
        var stops: [Gradient.Stop] = []
        let steps = 24
        for k in 0...steps {
            let th = -Double.pi / 2 + Double.pi * Double(k) / Double(steps)
            stops.append(.init(color: shade(V3(x: sin(th), y: 0, z: cos(th)).unit, mat).color,
                               location: Double(k) / Double(steps)))
        }
        ctx.fill(Path(rect), with: .linearGradient(Gradient(stops: stops),
                                                   startPoint: CGPoint(x: centerX - radius, y: 0),
                                                   endPoint: CGPoint(x: centerX + radius, y: 0)))
    }

    private static func drawRookCrown(_ ctx: inout GraphicsContext, W: CGFloat, H: CGFloat, mat: Material2D,
                                      pt: (CGFloat, CGFloat) -> CGPoint) {
        let r: CGFloat = 0.28
        let a = pt(-r, 0.68), b = pt(r, 0.60)
        cylinder(&ctx, rect: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y), radius: (b.x - a.x) / 2,
                 mat: mat, centerX: W / 2, W: W)
        // 銃眼（奥の内壁が見える）
        let inner = shade(V3(x: 0.3, y: 0.2, z: 1).unit, Material2D(albedo: mat.albedo.mixed(RGB(r: 0, g: 0, b: 0), 0.5),
                                                                    shininess: 10, specular: 0, envAmount: 0))
        for cx: CGFloat in [-0.10, 0.10] {
            let p0 = pt(cx - 0.045, 0.68), p1 = pt(cx + 0.045, 0.635)
            ctx.fill(Path(CGRect(x: p0.x, y: p0.y - 1, width: p1.x - p0.x, height: p1.y - p0.y + 1)), with: .color(inner.color))
        }
    }

    private static func sphere(_ ctx: inout GraphicsContext, c: CGPoint, r: CGFloat, mat: Material2D) {
        var stops: [Gradient.Stop] = []
        let steps = 12
        let lx = lightDir.x, ly = lightDir.y
        let lxy = (lx * lx + ly * ly).squareRoot()
        for k in 0...steps {
            let t = Double(k) / Double(steps)          // 0 = 光を向く点, 1 = 反対側の縁
            let s = 0.92 * (1 - 2 * t)                 // 画面内の傾き（光側 +, 反対側 -）
            let nx = lx / lxy * s, ny = ly / lxy * s
            let nz = max(0.05, (1 - nx * nx - ny * ny).squareRoot())
            stops.append(.init(color: shade(V3(x: nx, y: ny, z: nz).unit, mat).color, location: t))
        }
        // 光を向く点（左上）から反対側の縁（右下）へ。
        let a = CGPoint(x: c.x + CGFloat(lx / lxy) * r * 0.92, y: c.y - CGFloat(ly / lxy) * r * 0.92)
        let b = CGPoint(x: c.x - CGFloat(lx / lxy) * r * 0.92, y: c.y + CGFloat(ly / lxy) * r * 0.92)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .linearGradient(Gradient(stops: stops), startPoint: a, endPoint: b))
    }

    private static func drawQueenBalls(_ ctx: inout GraphicsContext, W: CGFloat, H: CGFloat, mat: Material2D,
                                       pt: (CGFloat, CGFloat) -> CGPoint) {
        for dx: CGFloat in [-0.22, -0.11, 0, 0.11, 0.22] {
            let c = pt(dx, dx == 0 ? 0.80 : 0.785)
            sphere(&ctx, c: c, r: W * 0.032, mat: mat)
        }
        sphere(&ctx, c: pt(0, 0.845), r: W * 0.05, mat: mat)
    }

    private static func drawKingCross(_ ctx: inout GraphicsContext, W: CGFloat, H: CGFloat, mat: Material2D,
                                      pt: (CGFloat, CGFloat) -> CGPoint) {
        let v0 = pt(-0.032, 0.97), v1 = pt(0.032, 0.83)
        cylinder(&ctx, rect: CGRect(x: v0.x, y: v0.y, width: v1.x - v0.x, height: v1.y - v0.y),
                 radius: (v1.x - v0.x) / 2, mat: mat, centerX: W / 2, W: W)
        let h0 = pt(-0.085, 0.925), h1 = pt(0.085, 0.875)
        // 横木は横向きの円柱: 上下方向にグラデーション
        var stops: [Gradient.Stop] = []
        for k in 0...12 {
            let th = -Double.pi / 2 + Double.pi * Double(k) / 12
            stops.append(.init(color: shade(V3(x: 0, y: -sin(th), z: cos(th)).unit, mat).color, location: Double(k) / 12))
        }
        ctx.fill(Path(CGRect(x: h0.x, y: h0.y, width: h1.x - h0.x, height: h1.y - h0.y)),
                 with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: h0.y), endPoint: CGPoint(x: 0, y: h1.y)))
    }

    // ナイト: 回転体にできないので、横顔を面（顔・たてがみ・首）に割って塗る。
    private static func drawKnight(_ ctx: inout GraphicsContext, W: CGFloat, H: CGFloat, mat: Material2D,
                                   pt: (CGFloat, CGFloat) -> CGPoint) {
        // 台座（回転体）
        drawRevolved(&ctx, type: .knight, W: W, H: H, mat: mat, pt: pt)
        // 馬の輪郭
        let unit = ChessKnightShape().path(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        var body = Path()
        unit.forEach { el in
            func m(_ p: CGPoint) -> CGPoint { let (dx, y) = RealProfiles.knightMap(p.x, p.y); return pt(dx, y) }
            switch el {
            case .move(let p): body.move(to: m(p))
            case .line(let p): body.addLine(to: m(p))
            case .quadCurve(let p, let c): body.addQuadCurve(to: m(p), control: m(c))
            case .curve(let p, let c1, let c2): body.addCurve(to: m(p), control1: m(c1), control2: m(c2))
            case .closeSubpath: body.closeSubpath()
            }
        }
        var layer = ctx
        layer.clip(to: body)
        let bb = body.boundingRect
        // 面の基調: 左上から右下へ、円筒風に暗く
        var stops: [Gradient.Stop] = []
        for k in 0...16 {
            let t = Double(k) / 16
            let th = -Double.pi / 2 + Double.pi * t
            stops.append(.init(color: shade(V3(x: sin(th), y: 0.15, z: cos(th)).unit, mat).color, location: t))
        }
        layer.fill(Path(bb), with: .linearGradient(Gradient(stops: stops),
                                                   startPoint: CGPoint(x: bb.minX, y: 0), endPoint: CGPoint(x: bb.maxX, y: 0)))
        // たてがみ: 背側（右）を一段暗い面にする
        var mane = Path()
        let p0 = pt(0.02, 0.86), p1 = pt(0.27, 0.62), p2 = pt(0.31, 0.22), p3 = pt(0.35, 0.09)
        mane.move(to: p0)
        mane.addQuadCurve(to: p1, control: pt(0.20, 0.80))
        mane.addQuadCurve(to: p2, control: pt(0.20, 0.42))
        mane.addLine(to: p3)
        mane.addLine(to: CGPoint(x: bb.maxX + 4, y: p3.y))
        mane.addLine(to: CGPoint(x: bb.maxX + 4, y: bb.minY - 4))
        mane.addLine(to: CGPoint(x: p0.x, y: bb.minY - 4))
        mane.closeSubpath()
        layer.fill(mane, with: .color(Color.black.opacity(mat.albedo.r > 0.5 ? 0.22 : 0.45)))
        // 顔のツヤ（左上の照り）
        layer.drawLayer { l in
            l.addFilter(.blur(radius: W * 0.03))
            var streak = Path()
            streak.move(to: pt(-0.27, 0.60)); streak.addQuadCurve(to: pt(-0.06, 0.74), control: pt(-0.22, 0.70))
            l.stroke(streak, with: .color(.white.opacity(mat.albedo.r > 0.5 ? 0.55 : 0.70)),
                     style: StrokeStyle(lineWidth: W * 0.03, lineCap: .round))
        }
        // 目・鼻
        let e = pt(-0.12, 0.665)
        layer.fill(Path(ellipseIn: CGRect(x: e.x - W * 0.014, y: e.y - W * 0.014, width: W * 0.028, height: W * 0.028)),
                   with: .color(mat.albedo.r > 0.5 ? Color(hex: 0x2A1B10) : Color(hex: 0xE8D9BC)))
        let n = pt(-0.315, 0.55)
        layer.fill(Path(ellipseIn: CGRect(x: n.x - W * 0.012, y: n.y - W * 0.008, width: W * 0.024, height: W * 0.016)),
                   with: .color(.black.opacity(0.5)))
    }
}
