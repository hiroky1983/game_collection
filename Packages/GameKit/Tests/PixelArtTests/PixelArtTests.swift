import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Core

/// ドット絵の器（`PixelSprite`）とおじさんのコマ（`OjisanPixel`）が壊れていないこと。
/// 絵の良し悪しは機械では測れないので、ここで縛るのは「格子が揃っている」「パレットに無い文字が無い」
/// 「拡大は整数倍で、色が混ざらない」の 3 点。
@Suite("ドット絵")
struct PixelArtTests {
    @Test("走者のコマは 40×36、正面顔は 16×15 で、行の長さが揃いパレットに無い文字が無い")
    func spritesAreWellFormed() {
        for frame in OjisanPixel.RiderFrame.allCases {
            let s = OjisanPixel.rider(frame)
            #expect(s.width == 40 && s.height == 36, "\(frame): \(s.width)×\(s.height)")
            #expect(s.undefinedKeys.isEmpty, "\(frame): パレットに無い文字 \(s.undefinedKeys)")
            #expect(s.opaqueBounds != nil)
        }
        for face in OjisanPixel.Face.allCases {
            let s = OjisanPixel.face(face)
            #expect(s.width == 16 && s.height == 15, "\(face): \(s.width)×\(s.height)")
            #expect(s.undefinedKeys.isEmpty, "\(face): パレットに無い文字 \(s.undefinedKeys)")
        }
    }

    @Test("整数倍の拡大は 1 ドットを scale×scale の同じ色にし、透明は透明のまま")
    func integerScaleDoesNotBlend() throws {
        let s = PixelSprite(rows: ["K.", ".Y"], palette: ["K": 0x102030, "Y": 0xF0C030])
        let img = try #require(s.cgImage(scale: 3))
        #expect(img.width == 6 && img.height == 6)
        let data = try #require(img.dataProvider?.data as Data?)
        func pixel(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
            let i = (y * img.bytesPerRow) + x * 4
            return (data[i], data[i + 1], data[i + 2], data[i + 3])
        }
        #expect(pixel(0, 0) == (0x10, 0x20, 0x30, 255))
        #expect(pixel(2, 2) == (0x10, 0x20, 0x30, 255))
        #expect(pixel(3, 0).3 == 0, "右上は透明")
        #expect(pixel(5, 5) == (0xF0, 0xC0, 0x30, 255))
    }

    @Test("左右反転は幅・高さを保ち、2 回で元に戻る")
    func flipRoundTrips() {
        let s = OjisanPixel.rider(.ride0)
        let f = s.flippedHorizontally()
        #expect(f.width == s.width && f.height == s.height)
        #expect(f.flippedHorizontally() == s)
    }

    @Test("余白付けは中央に寄せ、元の絵を変えない")
    func paddingCentersSprite() {
        let s = PixelSprite(rows: ["KY", "YK"], palette: ["K": 0x102030, "Y": 0xF0C030])
        let p = s.padded(width: 6, height: 4)
        #expect(p.width == 6 && p.height == 4)
        #expect(p.rows == ["......", "..KY..", "..YK..", "......"])
        #expect(s.padded(width: 1, height: 1) == s, "小さい寸法なら元のまま")
        let icon = OjisanPixel.face(.smile).padded(width: OjisanPixel.iconCanvasDots, height: OjisanPixel.iconCanvasDots)
        #expect(icon.width == 24 && icon.height == 24)
        #expect(OjisanPixel.mascotFaceImage?.width == 96)
    }

    /// レビュー用: OJISAN_PIXEL_OUT にディレクトリを渡すと、全コマを 5 倍で並べた PNG を書き出す。
    @Test("レビュー用のシートを書き出す（環境変数があるときだけ）")
    func writeReviewSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["OJISAN_PIXEL_OUT"] else { return }
        let scale = 5
        let frames = OjisanPixel.RiderFrame.allCases.map { OjisanPixel.rider($0) }
        let faces = OjisanPixel.Face.allCases.map { OjisanPixel.face($0) }
        let w = (40 * scale + 10) * frames.count + 10
        let h = 36 * scale + 15 * scale + 40
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.93, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        var x = 10
        for f in frames {
            let img = try #require(f.cgImage(scale: scale))
            ctx.draw(img, in: CGRect(x: x, y: h - 10 - img.height, width: img.width, height: img.height))
            x += 40 * scale + 10
        }
        x = 10
        for f in faces {
            let img = try #require(f.cgImage(scale: scale))
            ctx.draw(img, in: CGRect(x: x, y: 10, width: img.width, height: img.height))
            x += 16 * scale + 20
        }
        let image = try #require(ctx.makeImage())
        let url = URL(fileURLWithPath: out).appendingPathComponent("ojisan-pixel-sheet.png")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}
