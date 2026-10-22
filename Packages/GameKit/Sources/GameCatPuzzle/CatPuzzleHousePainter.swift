import SwiftUI
import Core

/// 家具の描き方（ドールハウス風。色付きの面＋こげ茶の輪郭＋影。モック `house.js` の doll 案）。
/// 画像は使わず図形だけで描く。`box` はマスの箱を 0.14 マス内側に縮めた矩形（pt）。
/// 横長に設計した小物は、箱が縦長なら 90° 回して置く。
enum CatPuzzleFurniturePainter {
    static func draw(_ kind: CatPuzzleHouse.Furniture, in box: CGRect, cellSide: CGFloat, context: inout GraphicsContext) {
        let landscape = !kind.isSquare
        let rotate = landscape && box.height > box.width
        let width = rotate ? box.height : box.width
        let height = rotate ? box.width : box.height
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.28), radius: cellSide * 0.025, x: 0, y: cellSide * 0.03))
            if rotate {
                layer.translateBy(x: box.maxX, y: box.minY)
                layer.rotate(by: .degrees(90))
            } else {
                layer.translateBy(x: box.minX, y: box.minY)
            }
            // 文脈の写しは描く先を共有する（変換・クリップだけが独立）。
            var painter = Painter(context: layer, w: width, h: height, small: min(width, height) < cellSide * 0.8)
            painter.draw(kind)
        }
    }

    /// 1 つの小物を、原点が左上・幅 `w`・高さ `h` の座標で描く。
    private struct Painter {
        var context: GraphicsContext
        let w: CGFloat
        let h: CGFloat
        /// 1×1（箱が 0.8 マスより小さい）。部品を減らす。
        let small: Bool
        var rr: CGFloat { min(w, h) * 0.12 }
        var m: CGFloat { min(w, h) }

        /// 色の面＋輪郭。
        mutating func piece(_ path: Path, _ fill: Color, stroke: Color = CatPuzzleHouse.Palette.outline, width: CGFloat = 1.3, opacity: Double = 0.85) {
            context.fill(path, with: .color(fill))
            context.stroke(path, with: .color(stroke.opacity(opacity)), lineWidth: width)
        }

        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerRadius: r)
        }

        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y0))
            p.addLine(to: CGPoint(x: x1, y: y1))
            return p
        }

        mutating func draw(_ kind: CatPuzzleHouse.Furniture) {
            switch kind {
            case .kotatsu:
                // 布団＋天板＋みかん。
                let inset = small ? 0 : m * 0.08
                piece(rect(inset, inset, w - inset * 2, h - inset * 2, r: rr * 1.6), Color(hex: 0xF08A5B))
                var seams = line(inset + rr, h * 0.5, w - inset - rr, h * 0.5)
                seams.addPath(line(w * 0.5, inset + rr, w * 0.5, h - inset - rr))
                context.stroke(seams, with: .color(Color(hex: 0xD9704A).opacity(0.8)), lineWidth: 1)
                let t: CGFloat = 0.52
                piece(rect(w * (1 - t) / 2, h * (1 - t) / 2, w * t, h * t, r: rr), Color(hex: 0xB98753))
                piece(circle(w * 0.6, h * 0.42, m * 0.07), Color(hex: 0xF7A823))
            case .oshiire:
                // 棚板と畳んだ布団（2 段）。
                piece(rect(0, 0, w, h, r: 2), Color(hex: 0xE8D2B0))
                context.stroke(line(0, h / 2, w, h / 2), with: .color(Color(hex: 0x7A5A3C).opacity(0.8)), lineWidth: 1.5)
                let fh = h * 0.3
                for (y, color) in [(h * 0.1, Color(hex: 0x9FC3E8)), (h * 0.6, Color(hex: 0xF3B5C0))] {
                    piece(rect(w * 0.12, y, w * 0.76, fh, r: fh * 0.35), color)
                    context.stroke(line(w * 0.12 + fh * 0.35, y + fh / 2, w * 0.88 - fh * 0.35, y + fh / 2),
                                   with: .color(Color(hex: 0x5B4634).opacity(0.5)), lineWidth: 0.8)
                }
            case .futon:
                // 枕＋掛け布団。1×1 は座布団＋枕。
                if small {
                    piece(rect(w * 0.08, h * 0.08, w * 0.84, h * 0.84, r: 3), Color(hex: 0xF3B5C0))
                    piece(rect(w * 0.25, h * 0.25, w * 0.5, h * 0.22, r: 3), Color(hex: 0xFFF8EE))
                } else {
                    piece(rect(0, 0, w, h, r: rr), Color(hex: 0xFFF8EE))
                    piece(rect(w * 0.06, h * 0.18, w * 0.18, h * 0.64, r: rr * 0.8), .white)
                    piece(rect(w * 0.3, h * 0.06, w * 0.66, h * 0.88, r: rr), Color(hex: 0x9FC3E8))
                    context.stroke(line(w * 0.3, h * 0.4, w * 0.96, h * 0.4), with: .color(.white.opacity(0.7)), lineWidth: 1.5)
                }
            case .shelf:
                // 本棚（上辺に沿う）＋文机。1×1 は本棚だけ。
                let sh = small ? h : h * 0.46
                piece(rect(0, 0, w, sh, r: 2), Color(hex: 0xC79A62))
                let books: [UInt32] = [0xE26D5A, 0x5B9BD5, 0x8BC34A, 0xF2C94C, 0x9B6BD6, 0xE26D5A, 0x5B9BD5]
                let bw = w / 9
                for i in 0..<8 {
                    let hh = sh * (0.6 + CGFloat((i * 7) % 3) * 0.1)
                    piece(rect(bw * 0.5 + CGFloat(i) * bw, sh - hh - sh * 0.1, bw * 0.8, hh, r: 1),
                          Color(hex: books[i % books.count]), width: 0.8, opacity: 0.7)
                }
                if !small {
                    piece(rect(w * 0.15, h * 0.6, w * 0.7, h * 0.34, r: 2), Color(hex: 0xB98753))
                    piece(rect(w * 0.3, h * 0.66, w * 0.22, h * 0.2, r: 1), Color(hex: 0xFFF8EE))
                    piece(circle(w * 0.7, h * 0.77, m * 0.05), Color(hex: 0xF0E7D5))
                }
            case .bath:
                // 浴槽（外枠＋湯＋波）と桶。
                piece(rect(0, 0, w, h, r: m * 0.28), .white)
                piece(rect(w * 0.12, h * 0.14, w * 0.76, h * 0.72, r: m * 0.2), Color(hex: 0x9ED8E2))
                var wave = Path()
                wave.move(to: CGPoint(x: w * 0.25, y: h * 0.45))
                wave.addQuadCurve(to: CGPoint(x: w * 0.41, y: h * 0.45), control: CGPoint(x: w * 0.33, y: h * 0.37))
                wave.addQuadCurve(to: CGPoint(x: w * 0.57, y: h * 0.45), control: CGPoint(x: w * 0.49, y: h * 0.53))
                context.stroke(wave, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
                context.stroke(circle(w * 0.78, h * 0.5, m * 0.06), with: .color(Color(hex: 0x5B4634).opacity(0.7)), lineWidth: 0.8)
                if !small { piece(circle(w * 0.06, h * 0.5, m * 0.09), Color(hex: 0xF7E7A1)) }
            case .kitchen:
                // 流し台＋コンロ。
                piece(rect(0, 0, w, h, r: 2), Color(hex: 0xD7D9DC))
                let sinkW = small ? w * 0.7 : w * 0.4
                piece(rect(w * 0.06, h * 0.16, sinkW, h * 0.68, r: 3), Color(hex: 0xEEF2F5))
                context.fill(circle(w * 0.06 + sinkW / 2, h * 0.5, m * 0.05), with: .color(Color(hex: 0x6B7078)))
                if !small {
                    for cx in [0.65, 0.86] as [CGFloat] {
                        piece(circle(w * cx, h * 0.5, m * 0.14), Color(hex: 0x3E3E42))
                        context.fill(circle(w * cx, h * 0.5, m * 0.06), with: .color(Color(hex: 0x8A8F96)))
                    }
                }
            case .genkan:
                // 沓脱石（上の段）と靴。
                piece(rect(0, 0, w, h * 0.42, r: 3), Color(hex: 0xCFC8BC))
                let shoes: [CGFloat] = small ? [0.2, 0.55] : [0.12, 0.3, 0.56, 0.74]
                for sx in shoes {
                    piece(rect(w * sx, h * 0.55, w * (small ? 0.22 : 0.13), h * 0.4, r: w * 0.05), Color(hex: 0x5B4636))
                }
            case .engawa:
                // 座布団＋湯のみ（床の板は床の柄）。
                let z = m * 0.5
                piece(rect(w * 0.12, h * 0.5 - z / 2, z, z, r: 2), Color(hex: 0xF2A65A))
                piece(circle(w * 0.78, h * 0.5, m * 0.11), Color(hex: 0xF0E7D5))
            }
        }
    }
}

/// ドア・窓・玄関戸の描き方（壁の上に重ねる）。寸法は `scale`（本番の盤で 1、遊び方の小さな図では縮む）で揃える。
enum CatPuzzleOpeningPainter {
    /// 壁に開けるドアの口の長さ（マスの何倍か）。両脇に 0.2 マスずつ壁が残る。
    static let doorOpening: CGFloat = 0.6

    /// 木の扉（蝶番は口の上端／左端）と、開く軌跡の点線、敷居。
    static func drawDoor(_ door: CatPuzzleHouseLayout.Door, cellSide: CGFloat, scale: CGFloat, context: inout GraphicsContext) {
        let s = door.segment
        let stub = cellSide * (1 - doorOpening) / 2
        let len = cellSide * doorOpening
        let vertical = s.orientation == .vertical
        let x0 = CGFloat(s.col) * cellSide, y0 = CGFloat(s.row) * cellSide
        // 口の始まり（蝶番）。
        let hinge = vertical ? CGPoint(x: x0 + cellSide, y: y0 + stub) : CGPoint(x: x0 + stub, y: y0 + cellSide)
        let dir: CGFloat = door.opensTowardB ? 1 : -1
        let thickness = 4.4 * scale
        // 扉の板。
        let leaf: CGRect = vertical
            ? CGRect(x: min(hinge.x, hinge.x + dir * len), y: hinge.y - thickness / 2, width: len, height: thickness)
            : CGRect(x: hinge.x - thickness / 2, y: min(hinge.y, hinge.y + dir * len), width: thickness, height: len)
        let leafPath = Path(roundedRect: leaf, cornerRadius: 1.5 * scale)
        context.fill(leafPath, with: .color(CatPuzzleHouse.Palette.doorLeaf))
        context.stroke(leafPath, with: .color(CatPuzzleHouse.Palette.outline), lineWidth: 1 * scale)
        // 開く軌跡（蝶番を中心に 1/4 円。扉の先端から口の反対側の端へ）。
        let from: CGFloat = vertical ? (dir > 0 ? 0 : .pi) : (dir > 0 ? .pi / 2 : -.pi / 2)
        let to: CGFloat = vertical ? .pi / 2 : 0
        var arc = Path()
        let steps = 12
        for i in 0...steps {
            let t = from + (to - from) * CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: hinge.x + cos(t) * len, y: hinge.y + sin(t) * len)
            if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
        }
        context.stroke(arc, with: .color(CatPuzzleHouse.Palette.doorArc.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.2 * scale, dash: [2 * scale, 2 * scale]))
        // 敷居（口を埋める明るい板）。
        let sill: CGRect = vertical
            ? CGRect(x: hinge.x - 2 * scale, y: hinge.y, width: 4 * scale, height: len)
            : CGRect(x: hinge.x, y: hinge.y - 2 * scale, width: len, height: 4 * scale)
        context.fill(Path(sill), with: .color(CatPuzzleHouse.Palette.threshold.opacity(0.9)))
    }

    /// 外周の壁の上の窓（水色のガラス・白い枠・真ん中の桟）。玄関は木の戸と取っ手。
    static func drawWindow(_ window: CatPuzzleHouseLayout.Window, side n: Int, cellSide: CGFloat, wallWidth ow: CGFloat, scale: CGFloat, context: inout GraphicsContext) {
        let len = cellSide * (window.isEntrance ? 0.6 : 0.5)
        let r = window.cell / n, c = window.cell % n
        let board = cellSide * CGFloat(n)
        let horizontal = window.side == .top || window.side == .bottom
        let along = (horizontal ? CGFloat(c) : CGFloat(r)) * cellSide + (cellSide - len) / 2
        let rect: CGRect
        switch window.side {
        case .top: rect = CGRect(x: along, y: 0, width: len, height: ow)
        case .bottom: rect = CGRect(x: along, y: board - ow, width: len, height: ow)
        case .left: rect = CGRect(x: 0, y: along, width: ow, height: len)
        case .right: rect = CGRect(x: board - ow, y: along, width: ow, height: len)
        }
        if window.isEntrance {
            context.fill(Path(rect), with: .color(CatPuzzleHouse.Palette.entranceDoor))
            context.stroke(Path(rect), with: .color(CatPuzzleHouse.Palette.wall), lineWidth: 1.2 * scale)
            let knob = horizontal ? CGPoint(x: rect.minX + len * 0.75, y: rect.midY) : CGPoint(x: rect.midX, y: rect.minY + len * 0.75)
            let kr = 1.3 * scale
            context.fill(Path(ellipseIn: CGRect(x: knob.x - kr, y: knob.y - kr, width: kr * 2, height: kr * 2)),
                         with: .color(CatPuzzleHouse.Palette.outline))
        } else {
            context.fill(Path(rect), with: .color(CatPuzzleHouse.Palette.glass))
            context.stroke(Path(rect), with: .color(CatPuzzleHouse.Palette.windowFrame), lineWidth: 1.5 * scale)
            var bar = Path()
            if horizontal {
                bar.move(to: CGPoint(x: rect.midX, y: rect.minY)); bar.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            } else {
                bar.move(to: CGPoint(x: rect.minX, y: rect.midY)); bar.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
            context.stroke(bar, with: .color(CatPuzzleHouse.Palette.windowFrame), lineWidth: 1.5 * scale)
        }
    }
}

/// 盤の外側の庭（芝生の面に草と小さな花）。`CatPuzzleView` の盤のカードの背景。
/// 草の位置は固定の種から決める（開くたびに変わらない）。
struct CatPuzzleGarden: View {
    /// カード全体の一辺。
    let side: CGFloat
    /// 盤までの余白（この帯に草を描く）。
    let inset: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(CatPuzzleHouse.Palette.grass)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
            Canvas { context, size in
                Self.drawBlades(&context, total: size.width, inset: inset)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// 草 70 本（うち 2 割は花）を 4 辺の帯にばらまく。
    static func drawBlades(_ context: inout GraphicsContext, total: CGFloat, inset: CGFloat) {
        guard inset > 4 else { return }
        var rng = SeededRandom(seed: 7)
        var blades = Path()
        var yellow = Path(), pink = Path()
        for _ in 0..<70 {
            let t = rng.next() * 4, p = rng.next() * total
            let depth = rng.next() * (inset - 4)
            let x: CGFloat, y: CGFloat
            if t < 1 { x = p; y = 2 + depth } else if t < 2 { x = p; y = total - 2 - depth }
            else if t < 3 { y = p; x = 2 + depth } else { y = p; x = total - 2 - depth }
            if rng.next() < 0.18 {
                let dot = CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)
                if rng.next() < 0.5 { yellow.addEllipse(in: dot) } else { pink.addEllipse(in: dot) }
            } else {
                blades.move(to: CGPoint(x: x, y: y)); blades.addLine(to: CGPoint(x: x - 1.2, y: y - 2.2))
                blades.move(to: CGPoint(x: x, y: y)); blades.addLine(to: CGPoint(x: x + 1.2, y: y - 2.2))
            }
        }
        context.stroke(blades, with: .color(CatPuzzleHouse.Palette.grassBlade), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        context.fill(yellow, with: .color(CatPuzzleHouse.Palette.flowerYellow))
        context.fill(pink, with: .color(CatPuzzleHouse.Palette.flowerPink))
    }

    /// 決まった並びを返す小さな乱数（モックの mulberry32 と同じ）。
    struct SeededRandom {
        private var state: UInt32
        init(seed: UInt32) { state = seed }
        mutating func next() -> CGFloat {
            state = state &+ 0x6D2B79F5
            var t = (state ^ (state >> 15)) &* (1 | state)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return CGFloat(t ^ (t >> 14)) / 4294967296
        }
    }
}
