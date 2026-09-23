import Testing
import CoreGraphics
import Foundation
@testable import GameFruits

/// 果物の絵（Core Graphics）。`SKTexture` の同一性では「どの絵を貼ったか」を確かめられないので、
/// 画素を読んで裏を取る。
@Suite("果物の絵")
@MainActor
struct ArtTests {
    /// `image` の画素（RGBA・premultiplied）を読む。
    private func pixels(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return data
    }

    private func pixel(_ data: [UInt8], width: Int, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let index = (y * width + x) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]), Int(data[index + 3]))
    }

    @Test("全種の絵が描け、中央は不透明で地の色に近く、四隅は透明")
    func everyKindRenders() throws {
        for kind in FruitKind.allCases {
            let image = try #require(FruitArt.image(kind, pixels: 96), "\(kind.name) が描けない")
            #expect(image.width == 96 && image.height == 96)
            let data = pixels(of: image)
            let center = pixel(data, width: 96, x: 48, y: 52)
            #expect(center.a == 255, "\(kind.name) の中央が透明")
            let corner = pixel(data, width: 96, x: 2, y: 2)
            #expect(corner.a == 0, "\(kind.name) の四隅（キャンバスの余白）が塗られている")
            // 中央付近の色相は地の色に近い（模様が乗る種類は多少ずれる）。
            let base = kind.baseColor
            let expected = (r: Int((base >> 16) & 0xFF), g: Int((base >> 8) & 0xFF), b: Int(base & 0xFF))
            let distance = abs(center.r - expected.r) + abs(center.g - expected.g) + abs(center.b - expected.b)
            #expect(distance < 200, "\(kind.name) の中央の色 \(center) が地の色 \(expected) から遠い")
        }
    }

    @Test("種類が違えば絵も違う（同じバイト列にならない）")
    func kindsAreDistinct() throws {
        var seen: [[UInt8]] = []
        for kind in FruitKind.allCases {
            let image = try #require(FruitArt.image(kind, pixels: 48))
            let data = pixels(of: image)
            #expect(!seen.contains(data), "\(kind.name) の絵が別の種類と同じ")
            seen.append(data)
        }
    }

    @Test("茎や葉は円の外（キャンバスの余白）に出るので、キャンバスは直径より大きい")
    func canvasLeavesRoomForStems() throws {
        #expect(FruitArt.canvasScale > 1)
        // りんごの真上（円の外側）に茎の画素がある。
        let image = try #require(FruitArt.image(.apple, pixels: 120))
        let data = pixels(of: image)
        // 上端から 6% の位置（円の頭は 11.5% の位置）。
        let above = pixel(data, width: 120, x: 60, y: 8)
        #expect(above.a > 0, "りんごの茎がキャンバスの余白に描かれていない")
        // 何も描かないブルーベリーの同じ位置は透明。
        let blueberry = try #require(FruitArt.image(.blueberry, pixels: 120))
        #expect(pixel(pixels(of: blueberry), width: 120, x: 60, y: 8).a == 0)
    }

    @Test("同じ寸法の絵は 1 回だけ描いて使い回す")
    func cacheReturnsTheSameImage() throws {
        let first = try #require(FruitArtCache.image(.melon, pixels: 64))
        let second = try #require(FruitArtCache.image(.melon, pixels: 64))
        #expect(first === second)
        let other = try #require(FruitArtCache.image(.melon, pixels: 32))
        #expect(other !== first)
    }

    @Test("寸法 0 では描かない")
    func zeroSizeIsNil() {
        #expect(FruitArt.image(.cherry, pixels: 0) == nil)
    }
}
