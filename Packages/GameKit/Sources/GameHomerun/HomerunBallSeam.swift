import Foundation
import CoreGraphics
import simd

/// 3D の球の赤い縫い目（#1656・会長 QA 2026-10-01）。球（`generateSphere`）に貼る正距円筒の画像（白地に赤い 1 本の閉じた曲線）を作る。
/// 縫い目は野球・テニスの球の曲線（球面上の閉じた曲線で、どちらから見ても向かい合う 2 本の C の字に見える）を太い赤の帯で描く
/// （トゥーン調に合わせ、細かい縫い糸は描かない）。画像は 1 回だけ作って使い回し、投球中・打球を追う間（`ballScale`）・
/// ミットで止まった球のどれも同じ球の実体なので同じ見た目になる。回転は球の実体の向きを時刻で回すだけ（`spin`）。
enum HomerunBallSeam {
    /// 曲線の形（0.5 で 2 周する大円、1 で赤道）。野球の球らしい、くびれた 2 つの C の字になる値。
    static let shape: Float = 0.72
    /// 縫い目の帯の太さ（球の中心から見た角の半分・ラジアン）。半径 3.7cm で幅およそ 8mm（遠くの小さな球でも赤が見える太さ）。
    static let halfWidth: Float = 0.11
    /// 曲線の標本の数（帯の縁の凹凸が見えない細かさ）。
    static let samples = 128
    /// 画像の大きさ（正距円筒・横 = 経度・縦 = 緯度）。
    static let textureWidth = 256
    static let textureHeight = 128
    /// 地の白（以前の球の色）と縫い目の赤。
    static let leather: (UInt8, UInt8, UInt8) = (250, 250, 245)
    static let stitch: (UInt8, UInt8, UInt8) = (214, 40, 46)
    /// 回って見える速さ（回/秒）。本物の回転（毎秒 30 回ほど）はコマ落ちして止まって見えるので、目で追える速さにする。
    static let spinRevolutionsPerSecond: Double = 2.5

    /// 曲線の点（単位球面上）。x = a cos t + (1 − a) cos 3t、y = 2√(a(1 − a)) sin 2t、z = a sin t − (1 − a) sin 3t は
    /// どの t でも長さ 1（球面に乗る）。
    static func point(_ t: Float) -> SIMD3<Float> {
        let a = shape, b = 1 - shape
        return [a * cos(t) + b * cos(3 * t), 2 * (a * b).squareRoot() * sin(2 * t), a * sin(t) - b * sin(3 * t)]
    }

    static let curve: [SIMD3<Float>] = (0..<samples).map { point(Float($0) / Float(samples) * 2 * .pi) }

    /// 画像の点（u, v は 0〜1・v = 0 が上 = +y の極）が指す球面の向き。
    static func direction(u: Float, v: Float) -> SIMD3<Float> {
        let lon = u * 2 * .pi, lat = v * .pi
        return [sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon)]
    }

    /// その向きが縫い目の帯の中か。
    static func isSeam(_ direction: SIMD3<Float>) -> Bool {
        let limit = cos(halfWidth)
        return curve.contains { simd_dot($0, direction) > limit }
    }

    /// 画像の画素（RGBA・左上から行ごと）。
    static func pixels() -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: textureWidth * textureHeight * 4)
        for y in 0..<textureHeight {
            for x in 0..<textureWidth {
                let d = direction(u: (Float(x) + 0.5) / Float(textureWidth), v: (Float(y) + 0.5) / Float(textureHeight))
                let c = isSeam(d) ? stitch : leather
                let o = (y * textureWidth + x) * 4
                bytes[o] = c.0; bytes[o + 1] = c.1; bytes[o + 2] = c.2
            }
        }
        return bytes
    }

    static func image() -> CGImage? {
        let provider = CGDataProvider(data: Data(pixels()) as CFData)
        return provider.flatMap {
            CGImage(width: textureWidth, height: textureHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: textureWidth * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                    provider: $0, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        }
    }

    /// 時刻 `now` の球の向き（x 軸まわりに一定の速さで回す）。値の大きい時刻でも角が崩れないよう、回転数の小数部だけを使う。
    static func spin(at now: Date) -> simd_quatf {
        let turns = (now.timeIntervalSinceReferenceDate * spinRevolutionsPerSecond).truncatingRemainder(dividingBy: 1)
        return simd_quatf(angle: Float(turns * 2 * .pi), axis: [1, 0, 0])
    }
}
