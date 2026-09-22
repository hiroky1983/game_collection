import SwiftUI
import Core

// MARK: - 立てた牌（麻雀刷新 #735）
//
// 四人打ち麻雀の卓を斜め上から見る新しい見た目（`docs/ui-review/mahjong-3d/mock-v12.png`）で、
// CPU の手牌を「立てた牌のブロック」として描くための部品。寝かせた牌（`MahjongTileView`）とは
// 別物で、**卓の遠近に沿った四角形**（footprint の4隅）を外から受け取り、そこに
// 上面と裏地（背）の面を組む。遠近の写像そのものは卓側（`GameMahjong`）が持つ。
//
// 麻雀ソリティアと共有している `MahjongTileView` には手を入れない（#735 の受け入れ条件）。

/// 裏地（背）の3色。左右の壁も対面の列も同じ値を使う（会長指示 2026-09-13「同じ色に」）。
/// 色は**青系**。緑だとフェルトの色に被って壁が見えなかった（会長指摘 2026-09-13）。
/// 寝かせた牌（`MahjongTileView`）の下端の背も同じ系統（`MahjongTileArt.backGreen*`）。
public enum MahjongBackPalette {
    /// 膨らみの頂点（照り）。
    public static let top = Color(hex: 0xC7DDFF)
    /// 中間。
    public static let mid = Color(hex: 0x6494E8)
    /// 縁（暗い側）。
    public static let edge = Color(hex: 0x2B4FA3)
    /// 上面（象牙）の照り。
    public static let ivoryLight = Color(hex: 0xFFFFFB)
    /// 上面の地。
    public static let ivory = Color(hex: 0xFFFCF2)   // `MahjongTileArt.faceColor` と同じ値（View の static は主アクタ隔離で参照できない）
    /// 手前の断面（隣の牌に隠れる面）。
    public static let ivoryCut = Color(hex: 0xE6DCC6)
    /// 上面の稜線。
    public static let ridge = Color(hex: 0xC9BC9F)
}

/// 立てた牌のどの面が見えるか。
public enum MahjongTileBlockFacing: Sendable {
    /// 対面の家: 手前（画面下）を向いた裏地が見える。
    case viewer
    /// 左の家: 右（卓の中央）を向いた裏地が見える。
    case centerOnRight
    /// 右の家: 左（卓の中央）を向いた裏地が見える。
    case centerOnLeft
}

/// 立てた牌1枚の幾何。座標はすべて**描く側の座標系**（親ビュー上の pt）。
///
/// `top` は上面の4隅（a: 奥左, b: 奥右, c: 手前右, d: 手前左 の順。「奥」「手前」は
/// 卓の奥行き方向で、対面の列なら画面上が奥）。`drop` は上面の隅から地面へ落ちる
/// 画面上の距離。`lean` は裏地の足元を中央側へずらす量（カメラが中央寄りにある見え方。
/// 真横に近い角度で裏地の面が細くなりすぎるのを防ぐ）。`bulge` は裏地の輪郭を
/// 外へ膨らませる量（樹脂の背の丸み）。
public struct MahjongTileBlockGeometry: Sendable {
    public var a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint
    public var drop: CGFloat
    public var lean: CGFloat
    public var bulge: CGFloat

    public init(a: CGPoint, b: CGPoint, c: CGPoint, d: CGPoint, drop: CGFloat, lean: CGFloat = 0, bulge: CGFloat = 0) {
        self.a = a; self.b = b; self.c = c; self.d = d
        self.drop = drop; self.lean = lean; self.bulge = bulge
    }

    /// 地面側の隅（上面の隅を `drop` だけ下ろし、`lean` だけ横へずらす）。
    func ground(_ p: CGPoint, leanSign: CGFloat) -> CGPoint {
        CGPoint(x: p.x + lean * leanSign, y: p.y + drop)
    }
}

/// 立てた牌のブロックの図案。部品（パス＋塗り）を順に返す。**塗りは `Canvas` 1 枚に描く**
/// （チェス駒・神経衰弱・おじさんと同じ流儀。`ZStack` に `Shape` を積むと iOS で部品ごとの
/// レイアウトがずれる）。
public enum MahjongTileBlockArt {
    public struct Part: Sendable {
        public var path: Path
        public var shading: Shading
        public var strokeWidth: CGFloat?
    }

    public enum Shading: Sendable {
        case solid(Color)
        case linear(colors: [Color], start: CGPoint, end: CGPoint)
        case radial(colors: [Color], center: CGPoint, endRadius: CGFloat)

        var graphics: GraphicsContext.Shading {
            switch self {
            case let .solid(c): return .color(c)
            case let .linear(colors, s, e): return .linearGradient(Gradient(colors: colors), startPoint: s, endPoint: e)
            case let .radial(colors, c, r): return .radialGradient(Gradient(colors: colors), center: c, startRadius: 0, endRadius: r)
            }
        }
    }

    /// 部品列（下から順に敷く）。
    public static func parts(_ g: MahjongTileBlockGeometry, facing: MahjongTileBlockFacing) -> [Part] {
        switch facing {
        case .viewer: return viewerParts(g)
        case .centerOnRight: return sideParts(g, centerOnRight: true)
        case .centerOnLeft: return sideParts(g, centerOnRight: false)
        }
    }

    // 対面の列: 裏地は手前（d→c）の面。上面は奥へ細い帯。
    private static func viewerParts(_ g: MahjongTileBlockGeometry) -> [Part] {
        let c0 = g.ground(g.c, leanSign: 0), d0 = g.ground(g.d, leanSign: 0)
        let midX = (g.d.x + g.c.x) / 2
        var back = Path()
        back.move(to: g.d)
        back.addQuadCurve(to: g.c, control: CGPoint(x: midX, y: g.d.y - g.bulge))
        back.addLine(to: c0)
        back.addQuadCurve(to: d0, control: CGPoint(x: midX, y: d0.y + g.bulge * 0.4))
        back.closeSubpath()
        var top = Path()
        top.move(to: g.a); top.addLine(to: g.b); top.addLine(to: g.c)
        top.addQuadCurve(to: g.d, control: CGPoint(x: midX, y: g.d.y - g.bulge))
        top.closeSubpath()
        var shine = Path()
        shine.move(to: g.d)
        shine.addQuadCurve(to: g.c, control: CGPoint(x: midX, y: g.d.y - g.bulge))
        let height = max(g.drop, 1)
        return [
            Part(path: back,
                 shading: .radial(colors: [MahjongBackPalette.top, MahjongBackPalette.mid, MahjongBackPalette.edge],
                                  center: CGPoint(x: midX, y: g.d.y + height * 0.3), endRadius: max(height * 0.8, 6)),
                 strokeWidth: nil),
            Part(path: top,
                 shading: .linear(colors: [MahjongBackPalette.ivoryLight, MahjongBackPalette.ivory],
                                  start: g.a, end: g.d),
                 strokeWidth: nil),
            Part(path: shine, shading: .solid(Color.white.opacity(0.6)), strokeWidth: 0.8),
        ]
    }

    // 左右の家: 裏地は中央を向いた面（左の家なら b→c、右の家なら a→d）。
    private static func sideParts(_ g: MahjongTileBlockGeometry, centerOnRight: Bool) -> [Part] {
        let sign: CGFloat = centerOnRight ? 1 : -1
        let outerTop = centerOnRight ? (g.b, g.c) : (g.a, g.d)
        let outerBot = (g.ground(outerTop.0, leanSign: sign), g.ground(outerTop.1, leanSign: sign))
        let midTop = CGPoint(x: (outerTop.0.x + outerTop.1.x) / 2, y: (outerTop.0.y + outerTop.1.y) / 2)
        let midBot = CGPoint(x: (outerBot.0.x + outerBot.1.x) / 2, y: (outerBot.0.y + outerBot.1.y) / 2)
        let bulge = g.bulge * sign

        var back = Path()
        back.move(to: outerTop.0)
        back.addQuadCurve(to: outerTop.1, control: CGPoint(x: midTop.x + bulge, y: midTop.y))
        back.addLine(to: outerBot.1)
        back.addQuadCurve(to: outerBot.0, control: CGPoint(x: midBot.x + bulge, y: midBot.y))
        back.closeSubpath()

        // 手前の断面（次の牌に隠れる。列の最後の1枚だけ見える）
        var cut = Path()
        cut.move(to: g.d); cut.addLine(to: g.c)
        cut.addLine(to: g.ground(g.c, leanSign: sign)); cut.addLine(to: g.ground(g.d, leanSign: sign))
        cut.closeSubpath()

        var top = Path()
        top.move(to: g.a); top.addLine(to: g.b)
        if centerOnRight {
            top.addQuadCurve(to: g.c, control: CGPoint(x: midTop.x + bulge, y: midTop.y))
            top.addLine(to: g.d)
        } else {
            top.addLine(to: g.c); top.addLine(to: g.d)
            top.addQuadCurve(to: g.a, control: CGPoint(x: midTop.x + bulge, y: midTop.y))
        }
        top.closeSubpath()

        var shine = Path()
        shine.move(to: outerTop.0)
        shine.addQuadCurve(to: outerTop.1, control: CGPoint(x: midTop.x + bulge, y: midTop.y))

        let height = max(g.drop, 1)
        return [
            Part(path: back,
                 shading: .radial(colors: [MahjongBackPalette.top, MahjongBackPalette.mid, MahjongBackPalette.edge],
                                  center: CGPoint(x: midTop.x + bulge * 0.5, y: midTop.y + height * 0.32),
                                  endRadius: max(height * 0.75, 6)),
                 strokeWidth: nil),
            Part(path: cut, shading: .solid(MahjongBackPalette.ivoryCut), strokeWidth: nil),
            Part(path: top,
                 shading: .linear(colors: [MahjongBackPalette.ivoryLight, MahjongBackPalette.ivory],
                                  start: g.a, end: g.d),
                 strokeWidth: nil),
            Part(path: top, shading: .solid(MahjongBackPalette.ridge.opacity(0.9)), strokeWidth: 0.6),
            Part(path: shine, shading: .solid(Color.white.opacity(0.6)), strokeWidth: 0.9),
        ]
    }
}

/// 立てた牌の列を `Canvas` 1 枚に描く。**奥から手前の順**に渡すこと（手前の牌が奥の牌の
/// 手前の断面を隠して「壁」になる）。座標は親ビュー上の pt。
public struct MahjongTileBlockCanvas: View {
    public let blocks: [(MahjongTileBlockGeometry, MahjongTileBlockFacing)]

    public init(blocks: [(MahjongTileBlockGeometry, MahjongTileBlockFacing)]) {
        self.blocks = blocks
    }

    public var body: some View {
        Canvas { ctx, _ in
            for (g, facing) in blocks {
                for part in MahjongTileBlockArt.parts(g, facing: facing) {
                    if let w = part.strokeWidth {
                        ctx.stroke(part.path, with: part.shading.graphics,
                                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                    } else {
                        ctx.fill(part.path, with: part.shading.graphics)
                    }
                }
            }
        }
        .accessibilityHidden(true)   // 読み上げは卓側が「対面の手牌 13 枚」のように持つ
    }
}
