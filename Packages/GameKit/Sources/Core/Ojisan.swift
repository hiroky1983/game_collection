import SwiftUI
import CoreGraphics

// MARK: - おじさん（共通キャラクター）
//
// 「あそびば」のマスコット。チャリンコおじさんの走者であり、ハブのカードや LP の顔でもある。
// おじさんシリーズ（2本目以降のゲーム）でも**同じ顔**にするため、定義はゲーム側ではなく
// ここ（Core）に置く（#700）。
//
// 設定の正典は**ドット絵版の `OjisanPixel`**（2026-09-15 の「SFC 級の 2D に統一する」決裁で
// 主役が移った）。**メガネは無し・ヒゲ有り**で、人物像とストーリーはあちらの冒頭に書いてある。
// ここのベクター版は#700 当時の造形で、**現在どこからも描画に使われていない**
// （ハブのアイコンもリザルトの顔も `OjisanPixel` 経由）。下のメガネを描く部品もその名残なので、
// 見た目を語るときはこのファイルではなく `OjisanPixel` を見ること。
//
// 会長採用の B3 案（3D 風カジュアルゲーム調）を、**2D のパス＋グラデーション**で再現する
// （麻雀卓・チェス駒と同じ路線。3D は不採用・2026-09-13 決裁）。参考にした既存作品は
// 絵のタッチだけで、見た目・服装は寄せない（#494 の権利チェックと同じ線）。
//
// 描画は **`Canvas` 1 枚**に部品を順に敷く（`ZStack` に `Shape` を積むと iOS で部品ごとの
// レイアウトがずれる。チェス駒 #462・神経衰弱 #601 の教訓）。部品は 100×100 の設計座標で
// 持ち、描く矩形に合わせて一様に拡縮する。**顔の座標をゲーム側に書かない**——ポーズや
// 表情を足すときはここに追加する。

/// 顔の向き。走者は進行方向（右）を向く。左向きは呼び出し側で反転する。
public enum OjisanFacing: String, CaseIterable, Sendable {
    /// 正面（ハブのカード・LP・リザルト）。
    case front
    /// 3/4（走者。真横だと目や眉が片方しか見えず、おじさんらしさが落ちる）。
    case threeQuarter
    /// 真横（モデルシート用。走者には使わない）。
    case side

    /// 0 = 正面、1 = 真横。目・鼻・口の位置をこの割合で前へ寄せる。
    var turn: Double {
        switch self {
        case .front:        return 0
        case .threeQuarter: return 0.45
        case .side:         return 1
        }
    }
}

/// 表情。
public enum OjisanExpression: String, CaseIterable, Sendable {
    /// 歯を見せた笑顔（基本）。
    case smile
    /// しかめ面（ミスのリザルト）。
    case frown
    /// 目が回っている（コケた後）。
    case dizzy
}

/// 全身のポーズ。#700 で持つのは正面のマスコットだけ。走者のポーズ（漕ぐ・跳ぶ・コケる）は
/// #701、喜び・しかめ面のリザルトは #702 で足す。
public enum OjisanPose: String, CaseIterable, Sendable {
    /// 正面で立っているマスコット。
    case mascotFront
}

/// 配色。走者（`RunnerPalette`）はこの値を参照して服の色を合わせる。
public enum OjisanPalette {
    public static let skin      = Color(hex: 0xF5CCA3)
    public static let skinLight = Color(hex: 0xFFE6C7)
    public static let skinShade = Color(hex: 0xDB9E75)
    public static let cheek     = Color(hex: 0xF97366)
    public static let hair      = Color(hex: 0x2E2B33)
    public static let hairGray  = Color(hex: 0x9E9EA8)
    public static let glasses   = Color(hex: 0x1F1A1F)
    public static let mouth     = Color(hex: 0x8C2E33)
    public static let teeth     = Color(hex: 0xFFFDF7)
    /// ポロシャツ。`RunnerPalette.shirt` と同じ値にする。
    public static let shirt      = Color(hex: 0xF9C233)
    public static let shirtShade = Color(hex: 0xCC8F1A)
    public static let pants      = Color(hex: 0x5B6B8C)
    public static let shoes      = Color(hex: 0x3B3540)
}

// MARK: - 部品

/// 塗り方。座標は部品と同じ設計座標で持ち、部品ごと拡縮する。
public enum OjisanShading: Sendable {
    case solid(Color)
    case radial(colors: [Color], center: CGPoint, startRadius: Double, endRadius: Double)
    case linear(colors: [Color], start: CGPoint, end: CGPoint)

    /// アフィン変換を掛ける（一様拡縮＋平行移動を想定。半径は x の拡大率で伸ばす）。
    func applying(_ t: CGAffineTransform) -> OjisanShading {
        switch self {
        case .solid:
            return self
        case let .radial(colors, center, s, e):
            return .radial(colors: colors, center: center.applying(t), startRadius: s * t.a, endRadius: e * t.a)
        case let .linear(colors, start, end):
            return .linear(colors: colors, start: start.applying(t), end: end.applying(t))
        }
    }

    var graphicsShading: GraphicsContext.Shading {
        switch self {
        case let .solid(color):
            return .color(color)
        case let .radial(colors, center, s, e):
            return .radialGradient(Gradient(colors: colors), center: center, startRadius: s, endRadius: e)
        case let .linear(colors, start, end):
            return .linearGradient(Gradient(colors: colors), startPoint: start, endPoint: end)
        }
    }
}

/// 絵の部品 1 つ。`strokeWidth` が nil なら塗り、あれば線。
public struct OjisanPart: Sendable {
    public var path: Path
    public var shading: OjisanShading
    public var strokeWidth: Double?

    public init(_ path: Path, _ shading: OjisanShading, stroke: Double? = nil) {
        self.path = path
        self.shading = shading
        self.strokeWidth = stroke
    }

    public func applying(_ t: CGAffineTransform) -> OjisanPart {
        OjisanPart(path.applying(t), shading.applying(t), stroke: strokeWidth.map { $0 * t.a })
    }
}

// MARK: - 図案

/// 顔と全身の図案。**すべて 100×100 の設計座標**（y は下向き）。
public enum OjisanArt {
    /// 設計座標の一辺。
    public static let designSize: Double = 100

    // MARK: 頭

    /// 頭の部品列（下から順に敷く）。右を向く。
    ///
    /// 顔の輪郭は `faceRect` の楕円。目・鼻・口は `turn`（0=正面, 1=真横）に応じて
    /// 前（右）へ寄せ、奥側の目・耳は縮めて、真横では消す。
    public static func headParts(facing: OjisanFacing, expression: OjisanExpression) -> [OjisanPart] {
        let t = facing.turn
        var parts: [OjisanPart] = []

        // 顔の輪郭。真横では後頭部がやや丸く、横幅が少し狭くなる。
        let face = CGRect(x: 16 - 2 * t, y: 20, width: 68 - 6 * t, height: 64)
        let faceCenter = CGPoint(x: face.midX, y: face.midY)

        // 目・鼻・口の x。正面の x0 を、向きに応じて前へ寄せつつ間隔を詰める。
        func fx(_ x0: Double) -> Double { 50 + (x0 - 50) * (1 - 0.45 * t) + 19 * t }

        // 奥の耳（正面では左）。頭が回るほど顔の中へ入り、真横では後頭部の耳になる。
        // 正面〜3/4 では輪郭の外に出るので顔の下に敷き、真横では顔の上に載せる。
        let backEarX = 16 + 18 * t
        let backEar = ear(at: CGPoint(x: backEarX, y: 54), inner: +1)
        if t < 0.6 { parts += backEar }

        // 顔。中央を明るく、外周を落として丸みを出す（3D 風の要）。
        parts.append(OjisanPart(
            Path(ellipseIn: face),
            .radial(colors: [OjisanPalette.skinLight, OjisanPalette.skin, OjisanPalette.skinShade],
                    center: CGPoint(x: fx(46), y: 44), startRadius: 6, endRadius: 40)
        ))
        // 顎の下の影。
        parts.append(OjisanPart(
            Path(ellipseIn: CGRect(x: face.midX - 22, y: face.maxY - 9, width: 44, height: 8)),
            .radial(colors: [OjisanPalette.skinShade.opacity(0.55), OjisanPalette.skinShade.opacity(0)],
                    center: CGPoint(x: face.midX, y: face.maxY - 5), startRadius: 0, endRadius: 22)
        ))

        if t >= 0.6 { parts += backEar }

        // 手前の耳（正面では右）。3/4 で縮み、真横では見えない。
        if t < 0.6 {
            let scale = 1 - t / 0.6
            let frontEarX = 84 - 10 * t
            parts += ear(at: CGPoint(x: frontEarX, y: 54), inner: -1, scale: scale)
        }

        // 頬の赤み。
        for x0 in [34.0, 66.0] {
            let c = CGPoint(x: fx(x0), y: 60)
            if t > 0.75 && x0 < 50 { continue }   // 真横では奥の頬は見えない
            parts.append(OjisanPart(
                Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 6, width: 18, height: 12)),
                .radial(colors: [OjisanPalette.cheek.opacity(0.5), OjisanPalette.cheek.opacity(0)],
                        center: c, startRadius: 0, endRadius: 9)
            ))
        }

        // 髪。頭頂は薄く、側頭部と後頭部にだけ残る。
        parts += hair(turn: t, face: face)

        // 眉。しかめ面は内側を下げる。
        for (i, x0) in [38.0, 62.0].enumerated() {
            let isBack = i == 0
            if t > 0.75 && isBack { continue }
            let c = CGPoint(x: fx(x0), y: 36)
            let w = 6.5 * (isBack ? (1 - 0.4 * t) : 1)
            var p = Path()
            let dir: Double = isBack ? 1 : -1   // 内側の向き
            // しかめ面は内側を大きく下げ、外側を上げて「ハ」の字にする。
            let innerDrop: Double = expression == .frown ? 5.5 : 0
            let outerDrop: Double = expression == .frown ? -3 : 0.6
            p.move(to: CGPoint(x: c.x - dir * w, y: c.y + outerDrop + 1.2))
            p.addQuadCurve(to: CGPoint(x: c.x + dir * w, y: c.y + innerDrop + 1.0),
                           control: CGPoint(x: c.x, y: c.y - 3.2 + innerDrop * 0.4))
            p.addQuadCurve(to: CGPoint(x: c.x - dir * w, y: c.y + outerDrop + 1.2),
                           control: CGPoint(x: c.x, y: c.y + 0.3 + innerDrop * 0.6))
            p.closeSubpath()
            parts.append(OjisanPart(p, .solid(OjisanPalette.hair)))
        }

        // 鼻。真横では輪郭の外へ出す。
        let noseCenter = CGPoint(x: fx(50) + 12 * t, y: 57)
        parts.append(OjisanPart(
            Path(ellipseIn: CGRect(x: noseCenter.x - 4.6, y: noseCenter.y - 4, width: 9.2, height: 8)),
            .radial(colors: [OjisanPalette.skinLight, OjisanPalette.skin, OjisanPalette.skinShade],
                    center: CGPoint(x: noseCenter.x - 1.5, y: noseCenter.y - 1.5), startRadius: 0.5, endRadius: 5.5)
        ))
        // 小鼻の影。
        for s in [-1.0, 1.0] {
            if t > 0.75 && s < 0 { continue }
            parts.append(OjisanPart(
                Path(ellipseIn: CGRect(x: noseCenter.x + s * 2.6 - 1.1, y: noseCenter.y + 2.2, width: 2.2, height: 1.4)),
                .solid(OjisanPalette.skinShade.opacity(0.5))
            ))
        }

        // 口。
        parts += mouth(expression: expression, center: CGPoint(x: fx(50) + 3 * t, y: 68), width: 30 * (1 - 0.35 * t))

        // 目とメガネ。奥の目は縮める。
        let eyeY = 50.0
        let eyes: [(x: Double, back: Bool)] = [(fx(38), true), (fx(62), false)]
        for eye in eyes {
            if t > 0.75 && eye.back { continue }
            let scale = eye.back ? (1 - 0.35 * t) : 1
            parts += self.eye(at: CGPoint(x: eye.x, y: eyeY), scale: scale, expression: expression)
        }
        parts += glasses(eyes: eyes.filter { !(t > 0.75 && $0.back) }.map { CGPoint(x: $0.x, y: eyeY) },
                         turn: t, backEarX: backEarX, faceCenter: faceCenter)

        // 額のツヤ。
        parts.append(OjisanPart(
            Path(ellipseIn: CGRect(x: fx(44) - 14, y: 26, width: 28, height: 14)),
            .radial(colors: [Color.white.opacity(0.38), Color.white.opacity(0)],
                    center: CGPoint(x: fx(44), y: 33), startRadius: 0, endRadius: 14)
        ))
        return parts
    }

    private static func ear(at c: CGPoint, inner: Double, scale: Double = 1) -> [OjisanPart] {
        let w = 9 * scale, h = 13 * scale
        return [
            OjisanPart(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)),
                       .solid(OjisanPalette.skin)),
            OjisanPart(Path(ellipseIn: CGRect(x: c.x - w * 0.24 + inner * w * 0.1, y: c.y - h * 0.27,
                                              width: w * 0.48, height: h * 0.54)),
                       .solid(OjisanPalette.skinShade.opacity(0.55))),
        ]
    }

    private static func hair(turn t: Double, face: CGRect) -> [OjisanPart] {
        var parts: [OjisanPart] = []
        let grad = OjisanShading.linear(colors: [OjisanPalette.hairGray, OjisanPalette.hair],
                                        start: CGPoint(x: 50, y: 24), end: CGPoint(x: 50, y: 50))
        // 後ろ側（左）の髪。頭が回るほど後頭部を大きく覆う。
        var back = Path()
        let bx = face.minX
        back.move(to: CGPoint(x: bx + 16, y: 26))
        back.addQuadCurve(to: CGPoint(x: bx + 1, y: 40 + 2 * t), control: CGPoint(x: bx + 2, y: 24))
        back.addQuadCurve(to: CGPoint(x: bx + 4 + 6 * t, y: 54 + 4 * t), control: CGPoint(x: bx - 1, y: 50 + 2 * t))
        back.addQuadCurve(to: CGPoint(x: bx + 19 + 6 * t, y: 33), control: CGPoint(x: bx + 12 + 8 * t, y: 44))
        back.closeSubpath()
        parts.append(OjisanPart(back, grad))
        // 前側（右）の髪。真横では見えない。
        if t < 0.6 {
            let k = 1 - t / 0.6
            let fxr = face.maxX
            var front = Path()
            front.move(to: CGPoint(x: fxr - 16 * k, y: 26))
            front.addQuadCurve(to: CGPoint(x: fxr - 1, y: 40), control: CGPoint(x: fxr - 2, y: 24))
            front.addQuadCurve(to: CGPoint(x: fxr - 4, y: 54), control: CGPoint(x: fxr + 1, y: 50))
            front.addQuadCurve(to: CGPoint(x: fxr - 19 * k, y: 33), control: CGPoint(x: fxr - 12, y: 44))
            front.closeSubpath()
            parts.append(OjisanPart(front, grad))
        }
        // 頭頂の名残りの髪（数本）。
        for i in 0..<4 {
            let x = 40 + Double(i) * 6 + 8 * t
            var wisp = Path()
            wisp.move(to: CGPoint(x: x, y: 22.5))
            wisp.addQuadCurve(to: CGPoint(x: x + 3.5, y: 17.5), control: CGPoint(x: x + 0.5, y: 18.5))
            parts.append(OjisanPart(wisp, .solid(OjisanPalette.hair.opacity(0.85)), stroke: 1.1))
        }
        return parts
    }

    private static func eye(at c: CGPoint, scale: Double, expression: OjisanExpression) -> [OjisanPart] {
        let r = 3.9 * scale
        if expression == .dizzy {
            // ×目。
            var x = Path()
            x.move(to: CGPoint(x: c.x - r, y: c.y - r)); x.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
            x.move(to: CGPoint(x: c.x + r, y: c.y - r)); x.addLine(to: CGPoint(x: c.x - r, y: c.y + r))
            return [OjisanPart(x, .solid(OjisanPalette.hair), stroke: 1.8 * scale)]
        }
        return [
            OjisanPart(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                       .solid(OjisanPalette.hair)),
            OjisanPart(Path(ellipseIn: CGRect(x: c.x - r * 0.75, y: c.y - r * 0.8, width: r * 0.6, height: r * 0.6)),
                       .solid(.white)),
            OjisanPart(Path(ellipseIn: CGRect(x: c.x + r * 0.2, y: c.y + r * 0.2, width: r * 0.35, height: r * 0.35)),
                       .solid(Color.white.opacity(0.6))),
        ]
    }

    private static func glasses(eyes: [CGPoint], turn t: Double, backEarX: Double, faceCenter: CGPoint) -> [OjisanPart] {
        var parts: [OjisanPart] = []
        let r = 11.5
        for (i, e) in eyes.enumerated() {
            let isBack = eyes.count == 2 && i == 0
            let rr = r * (isBack ? (1 - 0.3 * t) : 1)
            let rect = CGRect(x: e.x - rr, y: e.y - rr, width: 2 * rr, height: 2 * rr)
            // レンズの反射。
            parts.append(OjisanPart(Path(ellipseIn: rect),
                                    .linear(colors: [Color.white.opacity(0.32), Color.white.opacity(0.02)],
                                            start: CGPoint(x: rect.minX, y: rect.minY),
                                            end: CGPoint(x: rect.maxX, y: rect.maxY))))
            // フレーム。
            parts.append(OjisanPart(Path(ellipseIn: rect), .solid(OjisanPalette.glasses), stroke: 2.0))
            // フレームの照り（左上）。
            var shine = Path()
            shine.addArc(center: e, radius: rr, startAngle: .degrees(200), endAngle: .degrees(250), clockwise: false)
            parts.append(OjisanPart(shine, .solid(Color.white.opacity(0.35)), stroke: 0.7))
        }
        // ブリッジ。
        if eyes.count == 2 {
            let a = eyes[0], b = eyes[1]
            let ra = r * (1 - 0.3 * t)
            var bridge = Path()
            bridge.move(to: CGPoint(x: a.x + ra, y: a.y - 1))
            bridge.addQuadCurve(to: CGPoint(x: b.x - r, y: b.y - 1), control: CGPoint(x: (a.x + b.x) / 2, y: a.y - 4))
            parts.append(OjisanPart(bridge, .solid(OjisanPalette.glasses), stroke: 1.6))
        }
        // つる。奥側は後ろの耳へ、手前側は顔の外へ。
        if let back = eyes.first {
            let ra = eyes.count == 2 ? r * (1 - 0.3 * t) : r
            var temple = Path()
            temple.move(to: CGPoint(x: back.x - ra, y: back.y - 0.5))
            temple.addLine(to: CGPoint(x: backEarX + 3, y: 49.5))
            parts.append(OjisanPart(temple, .solid(OjisanPalette.glasses), stroke: 1.4))
        }
        if t < 0.6, let front = eyes.last, eyes.count == 2 {
            var temple = Path()
            temple.move(to: CGPoint(x: front.x + r, y: front.y - 0.5))
            temple.addLine(to: CGPoint(x: 84 - 10 * t - 3, y: 49.5))
            parts.append(OjisanPart(temple, .solid(OjisanPalette.glasses), stroke: 1.4))
        }
        return parts
    }

    private static func mouth(expression: OjisanExpression, center c: CGPoint, width w: Double) -> [OjisanPart] {
        let half = w / 2
        switch expression {
        case .smile:
            var inside = Path()
            inside.move(to: CGPoint(x: c.x - half, y: c.y))
            inside.addQuadCurve(to: CGPoint(x: c.x + half, y: c.y), control: CGPoint(x: c.x, y: c.y - 2.5))
            inside.addQuadCurve(to: CGPoint(x: c.x - half, y: c.y), control: CGPoint(x: c.x, y: c.y + 15))
            inside.closeSubpath()
            var teeth = Path()
            teeth.move(to: CGPoint(x: c.x - half + 1.2, y: c.y + 0.4))
            teeth.addQuadCurve(to: CGPoint(x: c.x + half - 1.2, y: c.y + 0.4), control: CGPoint(x: c.x, y: c.y - 1))
            teeth.addQuadCurve(to: CGPoint(x: c.x - half + 1.2, y: c.y + 0.4), control: CGPoint(x: c.x, y: c.y + 6.5))
            teeth.closeSubpath()
            var gaps = Path()
            for i in 1..<5 {
                let x = c.x - half + 1.2 + (w - 2.4) * Double(i) / 5
                gaps.move(to: CGPoint(x: x, y: c.y + 0.4)); gaps.addLine(to: CGPoint(x: x, y: c.y + 3.6))
            }
            var lip = Path()
            lip.move(to: CGPoint(x: c.x - half - 0.8, y: c.y - 0.3))
            lip.addQuadCurve(to: CGPoint(x: c.x + half + 0.8, y: c.y - 0.3), control: CGPoint(x: c.x, y: c.y - 3.2))
            var lines = Path()   // 笑いじわ
            for s in [-1.0, 1.0] {
                lines.move(to: CGPoint(x: c.x + s * (half + 2), y: c.y - 3))
                lines.addQuadCurve(to: CGPoint(x: c.x + s * (half + 3), y: c.y + 4),
                                   control: CGPoint(x: c.x + s * (half + 4.5), y: c.y + 0.5))
            }
            return [
                OjisanPart(inside, .solid(OjisanPalette.mouth)),
                OjisanPart(teeth, .solid(OjisanPalette.teeth)),
                OjisanPart(gaps, .solid(Color.gray.opacity(0.3)), stroke: 0.3),
                OjisanPart(lip, .solid(OjisanPalette.skinShade), stroke: 0.7),
                OjisanPart(lines, .solid(OjisanPalette.skinShade.opacity(0.65)), stroke: 0.55),
            ]
        case .frown:
            var p = Path()
            p.move(to: CGPoint(x: c.x - half * 0.7, y: c.y + 2))
            p.addQuadCurve(to: CGPoint(x: c.x + half * 0.7, y: c.y + 2), control: CGPoint(x: c.x, y: c.y - 4))
            return [OjisanPart(p, .solid(OjisanPalette.mouth), stroke: 1.5)]
        case .dizzy:
            var p = Path()
            let steps = 6
            p.move(to: CGPoint(x: c.x - half * 0.7, y: c.y))
            for i in 1...steps {
                let x = c.x - half * 0.7 + (half * 1.4) * Double(i) / Double(steps)
                let y = c.y + (i % 2 == 0 ? 1.6 : -1.6)
                p.addLine(to: CGPoint(x: x, y: y))
            }
            return [OjisanPart(p, .solid(OjisanPalette.mouth), stroke: 1.4)]
        }
    }

    // MARK: 全身

    /// 全身の部品列。頭は `headParts` を縮めて載せる（頭身は約 2 頭身のデフォルメ）。
    public static func poseParts(_ pose: OjisanPose, expression: OjisanExpression = .smile) -> [OjisanPart] {
        switch pose {
        case .mascotFront:
            return mascotFront(expression: expression)
        }
    }

    private static func mascotFront(expression: OjisanExpression) -> [OjisanPart] {
        var parts: [OjisanPart] = []
        // 首。
        parts.append(OjisanPart(Path(roundedRect: CGRect(x: 44, y: 42, width: 12, height: 16), cornerRadius: 3),
                                .solid(OjisanPalette.skinShade)))
        // 脚（ズボン）と靴。
        for x in [39.0, 52.0] {
            parts.append(OjisanPart(Path(roundedRect: CGRect(x: x, y: 82, width: 9, height: 14), cornerRadius: 2.5),
                                    .linear(colors: [OjisanPalette.pants, OjisanPalette.pants.opacity(0.75)],
                                            start: CGPoint(x: x, y: 82), end: CGPoint(x: x + 9, y: 96))))
            parts.append(OjisanPart(Path(ellipseIn: CGRect(x: x - 2, y: 93, width: 13, height: 6)),
                                    .solid(OjisanPalette.shoes)))
        }
        // 胴（ポロシャツ）。上を明るく。
        let torso = CGRect(x: 30, y: 54, width: 40, height: 32)
        parts.append(OjisanPart(Path(roundedRect: torso, cornerRadius: 11),
                                .linear(colors: [OjisanPalette.shirt, OjisanPalette.shirtShade],
                                        start: CGPoint(x: 50, y: 54), end: CGPoint(x: 50, y: 86))))
        // 腕と手。
        for s in [-1.0, 1.0] {
            let shoulder = CGPoint(x: 50 + s * 18, y: 60)
            let hand = CGPoint(x: 50 + s * 25, y: 79)
            var arm = Path()
            arm.move(to: shoulder); arm.addLine(to: hand)
            parts.append(OjisanPart(arm, .solid(OjisanPalette.shirtShade), stroke: 7.5))
            parts.append(OjisanPart(Path(ellipseIn: CGRect(x: hand.x - 4, y: hand.y - 3, width: 8, height: 8)),
                                    .solid(OjisanPalette.skin)))
        }
        // 襟。
        var collar = Path()
        collar.move(to: CGPoint(x: 41, y: 54)); collar.addLine(to: CGPoint(x: 50, y: 63)); collar.addLine(to: CGPoint(x: 59, y: 54))
        collar.addLine(to: CGPoint(x: 56, y: 53)); collar.addLine(to: CGPoint(x: 50, y: 59)); collar.addLine(to: CGPoint(x: 44, y: 53))
        collar.closeSubpath()
        parts.append(OjisanPart(collar, .solid(OjisanPalette.teeth)))
        // 頭。設計座標 100 の頭を 52 に縮めて上に置く。
        let head = CGAffineTransform(translationX: 24, y: -2).scaledBy(x: 0.52, y: 0.52)
        parts += headParts(facing: .front, expression: expression).map { $0.applying(head) }
        return parts
    }
}

// MARK: - 表示

/// 部品列を `Canvas` 1 枚に描く。正方形でない矩形には中央に一様拡縮で収める。
public struct OjisanCanvas: View {
    public let parts: [OjisanPart]
    /// 左向きにする（走者が左へ進む場面用）。
    public var flipped = false

    public init(parts: [OjisanPart], flipped: Bool = false) {
        self.parts = parts
        self.flipped = flipped
    }

    public var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width, size.height) / OjisanArt.designSize
            ctx.translateBy(x: (size.width - OjisanArt.designSize * scale) / 2,
                            y: (size.height - OjisanArt.designSize * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            if flipped {
                ctx.translateBy(x: OjisanArt.designSize, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            for part in parts {
                if let width = part.strokeWidth {
                    ctx.stroke(part.path, with: part.shading.graphicsShading,
                               style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                } else {
                    ctx.fill(part.path, with: part.shading.graphicsShading)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// おじさんの顔。
public struct OjisanHead: View {
    public let facing: OjisanFacing
    public let expression: OjisanExpression
    public var flipped = false

    public init(facing: OjisanFacing = .front, expression: OjisanExpression = .smile, flipped: Bool = false) {
        self.facing = facing
        self.expression = expression
        self.flipped = flipped
    }

    public var body: some View {
        OjisanCanvas(parts: OjisanArt.headParts(facing: facing, expression: expression), flipped: flipped)
    }
}

/// おじさんの全身。
public struct OjisanFigure: View {
    public let pose: OjisanPose
    public let expression: OjisanExpression

    public init(pose: OjisanPose = .mascotFront, expression: OjisanExpression = .smile) {
        self.pose = pose
        self.expression = expression
    }

    public var body: some View {
        OjisanCanvas(parts: OjisanArt.poseParts(pose, expression: expression))
    }
}

// MARK: - ビットマップ

/// SpriteKit のテクスチャやハブのアイコンに使うビットマップ。**同じ絵は一度しか描かない**
/// （`ImageRenderer` は毎フレーム呼ぶものではない）。
@MainActor
public enum OjisanBitmap {
    private static var cache: [String: CGImage] = [:]

    /// 顔のビットマップ。`pixels` は一辺のピクセル数。
    public static func head(facing: OjisanFacing = .front, expression: OjisanExpression = .smile,
                            pixels: Int = 256) -> CGImage? {
        render(key: "head-\(facing.rawValue)-\(expression.rawValue)-\(pixels)", pixels: pixels) {
            OjisanHead(facing: facing, expression: expression)
        }
    }

    /// 全身のビットマップ。
    public static func figure(pose: OjisanPose = .mascotFront, expression: OjisanExpression = .smile,
                              pixels: Int = 256) -> CGImage? {
        render(key: "figure-\(pose.rawValue)-\(expression.rawValue)-\(pixels)", pixels: pixels) {
            OjisanFigure(pose: pose, expression: expression)
        }
    }

    /// ハブのカードに出す顔の `Image`。色付きの絵なので `renderingMode(.original)` で
    /// テンプレート着色（`foregroundStyle`）を外し、`resizable` で枠に合わせる。
    public static var hubIcon: Image? {
        head(facing: .front, pixels: 192).map {
            Image(decorative: $0, scale: 1).renderingMode(.original).resizable()
        }
    }

    private static func render<V: View>(key: String, pixels: Int, _ content: () -> V) -> CGImage? {
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: content().frame(width: CGFloat(pixels), height: CGFloat(pixels)))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        cache[key] = image
        return image
    }
}
