import Foundation
import CoreGraphics
import simd

/// 月へ飛ぶ球の火の玉（#1687・会長 QA 2026-10-02「もうちょっと火の玉っぽく」）の絵と並べ方（純粋な値・テストで固定する）。
///
/// カメラの方を向く板（ビルボード）を重ねて作る。パーティクルは使わず、板は全部で `spriteCount` 枚。
/// - 光の輪（後ろ・半透明の橙と黄の円 2 枚）: 夜空で発光して見える
/// - 長い火の尾（先細り・縁が波打つ・時間で長さと向きが揺らぐ）
/// - 舌状の炎 3 枚（球を包むように向きをずらし、長さ・幅を別々の速さで揺らす）
/// - 内側の炎（白〜黄）と芯（白）
/// - 火の粉 5 粒（尾に沿って流れて小さくなる）
/// 色はトゥーン調の段（中心から 白 → 黄 → 橙 → 赤 と縁の濃い赤の細い線）。陰影は付けない（Unlit）。
enum HomerunFireballArt {
    // MARK: 炎の形（画像）

    /// 炎の画像の段（中心から外へ）。
    static let palette: [(UInt8, UInt8, UInt8)] = [
        (0xFF, 0xFB, 0xE6),   // 白
        (0xFF, 0xE1, 0x4A),   // 黄
        (0xFF, 0x96, 0x1E),   // 橙
        (0xF0, 0x4A, 0x1A),   // 赤
    ]
    /// 縁の細い線（インクの代わりの濃い赤）。
    static let rim: (UInt8, UInt8, UInt8) = (0xB0, 0x1E, 0x0E)
    /// 内側の炎は外側の段を使わず、白と黄だけで描く。
    enum Style: Equatable, Sendable { case outer, inner, tail }

    /// 炎の板の縦横比（長さ / 幅）。頭は丸く、幅いっぱいの円（半径 = 幅 / 2）になる。
    static func aspect(_ style: Style) -> Double {
        switch style {
        case .outer: 2.4
        case .inner: 2.0
        case .tail: 5.5
        }
    }

    /// 炎の幅の半分（中心線から縁まで・幅を 1 とした割合）。`y` は頭の端から尾の先までの 0〜1、`side` は −1（左）/ +1（右）。
    /// 頭は円、そこから先は先細りで、縁を左右で別の位相の波にして舌のようにゆらめく形にする。外は nil（描かない）。
    static func halfWidth(y: Double, side: Double, style: Style, phase: Double = 0) -> Double? {
        guard (0...1).contains(y) else { return nil }
        let h = 0.5 / aspect(style)   // 頭の円の半径（長さの割合）
        if y < h {
            let k = (h - y) / h
            return 0.5 * (1 - k * k).squareRoot()
        }
        let u = (y - h) / (1 - h)
        let taper = pow(1 - u, style == .tail ? 1.6 : 1.15)
        let waves = style == .tail ? 3.0 : 2.0
        let wave = 1 + 0.18 * sin((u * waves + (side > 0 ? 0.0 : 0.37)) * 2 * .pi + phase) * u
        return max(0, 0.5 * taper * wave)
    }

    /// 画像の 1 点の色の段（`palette` の番号・`palette.count` は縁の線）。外は nil。
    /// `x` は −0.5〜0.5（幅の割合・中心が 0）、`y` は 0〜1（頭の端 → 尾の先）。
    static func band(x: Double, y: Double, style: Style, phase: Double = 0) -> Int? {
        guard let w = halfWidth(y: y, side: x < 0 ? -1 : 1, style: style, phase: phase), abs(x) <= w, w > 0 else { return nil }
        if w - abs(x) < 0.035 { return palette.count }
        let m = 0.62 * abs(x) / w + 0.6 * y
        let edges: [Double] = switch style {
        case .outer: [0.28, 0.48, 0.72]
        case .inner: [0.5, 2, 2]          // 白と黄だけ
        case .tail: [0.12, 0.32, 0.6]
        }
        return edges.firstIndex { m < $0 } ?? palette.count - 1
    }

    static let textureWidth = 64

    /// 炎の画像（RGBA・左上から行ごと）。**上の行が尾の先・下の行が頭**（板の +y を尾の向きに置く）。外は透明。
    static func pixels(_ style: Style, phase: Double = 0) -> (bytes: [UInt8], width: Int, height: Int) {
        let width = textureWidth, height = Int((Double(width) * aspect(style)).rounded())
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let y = 1 - (Double(row) + 0.5) / Double(height)
            for col in 0..<width {
                let x = (Double(col) + 0.5) / Double(width) - 0.5
                guard let b = band(x: x, y: y, style: style, phase: phase) else { continue }
                let c = b < palette.count ? palette[b] : rim
                let o = (row * width + col) * 4
                bytes[o] = c.0; bytes[o + 1] = c.1; bytes[o + 2] = c.2; bytes[o + 3] = 255
            }
        }
        return (bytes, width, height)
    }

    static func image(_ style: Style, phase: Double = 0) -> CGImage? {
        let p = pixels(style, phase: phase)
        let provider = CGDataProvider(data: Data(p.bytes) as CFData)
        return provider.flatMap {
            CGImage(width: p.width, height: p.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: p.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    // MARK: 並べ方（1 コマ）

    /// 板の種類（描く順 = 奥から手前）。
    enum Layer: Hashable, Sendable {
        case glowOuter, glowInner, tail, tongue(Int), inner, core, spark(Int)
    }

    /// 1 枚の板。`center` は板の中心、`axis` は板の +y（尾の向き・画面の面の中）、`size` は (幅, 長さ)（m）。
    struct Sprite: Equatable {
        var layer: Layer
        var center: SIMD3<Float>
        var axis: SIMD3<Float>
        var size: SIMD2<Float>
    }

    static let tongueCount = 3
    static let sparkCount = 5
    static var spriteCount: Int { 2 + 1 + tongueCount + 2 + sparkCount }

    /// 火の玉の板の並び。`camera` に向ける面の中で、尾の向き（`fire.trail` を画面の面に写した向き）を軸にする。
    static func sprites(_ fire: HomerunMoonShot.Fireball, camera: SIMD3<Float>) -> [Sprite] {
        let r = fire.radius
        let t = fire.time
        let toCamera = simd_normalize(camera - fire.center)
        var down = fire.trail - toCamera * simd_dot(fire.trail, toCamera)
        if simd_length(down) < 1e-4 { down = simd_cross(toCamera, [1, 0, 0]) }
        down = simd_normalize(down)
        let side = simd_normalize(simd_cross(down, toCamera))
        /// 画面の面の中で尾の向きを `angle` だけ回した向き。
        func turned(_ angle: Float) -> SIMD3<Float> { down * cos(angle) + side * sin(angle) }
        /// 奥行きの順を保つため、手前の板ほどカメラ側へ少し寄せる。
        func lift(_ k: Float) -> SIMD3<Float> { toCamera * r * k }
        func wave(_ speed: Double, _ phase: Double) -> Float { Float(sin(t * speed + phase)) }

        var out: [Sprite] = []
        // 光の輪（奥）。
        out.append(Sprite(layer: .glowOuter, center: fire.center + lift(-0.4), axis: down,
                          size: SIMD2(repeating: r * (4.6 + 0.3 * wave(11, 0)))))
        out.append(Sprite(layer: .glowInner, center: fire.center + lift(-0.35), axis: down,
                          size: SIMD2(repeating: r * (3.0 + 0.2 * wave(13, 1)))))
        // 火の尾: 頭の円の中心を球に合わせ、長さと向きを揺らす。
        let tailAxis = turned(0.07 * wave(6.5, 0.4))
        let tailWidth = r * 2.3
        let tailLength = tailWidth * Float(aspect(.tail)) * (1 + 0.1 * wave(8.3, 2))
        out.append(Sprite(layer: .tail, center: fire.center + tailAxis * (tailLength / 2 - tailWidth / 2) + lift(-0.3),
                          axis: tailAxis, size: SIMD2(tailWidth, tailLength)))
        // 舌状の炎: 尾の向きを中心に左右へ開き、長さ・幅を別々に揺らす。
        let spread: [Float] = [0, -0.42, 0.42]
        for i in 0..<tongueCount {
            let axis = turned(spread[i] + 0.12 * wave(9 + Double(i) * 2.3, Double(i) * 1.9))
            let width = r * (2.9 - 0.4 * Float(i > 0 ? 1 : 0)) * (1 + 0.08 * wave(17 + Double(i), Double(i)))
            let length = width * Float(aspect(.outer)) * (1 + 0.22 * wave(12 + Double(i) * 3.1, Double(i) * 2.7))
            out.append(Sprite(layer: .tongue(i), center: fire.center + axis * (length / 2 - width / 2) + lift(-0.2 + 0.03 * Float(i)),
                              axis: axis, size: SIMD2(width, length)))
        }
        // 内側の炎（白〜黄）と芯。
        let innerAxis = turned(0.1 * wave(15, 0.8))
        let innerWidth = r * 1.55 * (1 + 0.1 * wave(19, 0.3))
        let innerLength = innerWidth * Float(aspect(.inner)) * (1 + 0.15 * wave(14, 1.1))
        out.append(Sprite(layer: .inner, center: fire.center + innerAxis * (innerLength / 2 - innerWidth / 2) + lift(0.05),
                          axis: innerAxis, size: SIMD2(innerWidth, innerLength)))
        out.append(Sprite(layer: .core, center: fire.center + lift(0.1), axis: down,
                          size: SIMD2(repeating: r * (1.15 + 0.1 * wave(23, 0)))))
        // 火の粉: 尾に沿って流れ、遠くへ行くほど小さくなる（1 周期ごとに頭へ戻る）。
        for i in 0..<sparkCount {
            let phase = (t * 1.7 + Double(i) / Double(sparkCount)).truncatingRemainder(dividingBy: 1)
            let p = Float(phase)
            let sway = Float(sin(Double(i) * 2.17 + t * 5)) * r * (0.4 + 1.6 * p)
            let center = fire.center + tailAxis * r * (1.4 + 7 * p) + side * sway + lift(-0.25)
            out.append(Sprite(layer: .spark(i), center: center, axis: down,
                              size: SIMD2(repeating: r * (0.42 - 0.3 * p))))
        }
        return out
    }
}
