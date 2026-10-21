import Testing
import CoreGraphics
import Foundation
@testable import GameFruits

/// 盆栽の絵（#2361・案 B「木を大きく見せる」）。素材が全段そろって読めることと、絵の枠の置き方を確かめる。
@Suite("盆栽の絵")
struct ArtTests {
    @Test("11 段すべての絵が読め、段ごとに違う絵になっている")
    func everyTierHasItsOwnArt() throws {
        var seen: [Data] = []
        for kind in FruitKind.allCases {
            let image = try #require(BonsaiArt.image(kind), "\(kind.name)（\(kind.artName)）が読めない")
            #expect(image.width > 0 && image.height > 0)
            let bytes = try #require(image.dataProvider?.data as Data?)
            #expect(!seen.contains(bytes), "\(kind.name) の絵が別の段と同じ")
            seen.append(bytes)
        }
    }

    @Test("素材は表示の大きさに見合う解像度に縮めてある（小さい段ほど小さい・最大でも 320px）")
    func artIsDownscaled() throws {
        for kind in FruitKind.allCases {
            let image = try #require(BonsaiArt.image(kind))
            #expect(max(image.width, image.height) <= 320, "\(kind.name) が \(image.width)×\(image.height)")
            // 盤の幅 400pt・3x の画面で、絵の枠を 1px 以上の細かさで出せる大きさの 8 割はある。
            let size = BonsaiArt.spriteSize(for: kind)
            let needed = max(size.width, size.height) / FruitField.Metrics.width * 400 * 3 * 0.8
            #expect(Double(max(image.width, image.height)) >= min(needed, 280), "\(kind.name) が粗すぎる")
        }
        #expect(try #require(BonsaiArt.image(.sakura)).width < (try #require(BonsaiArt.image(.kinmatsu))).width)
    }

    @Test("絵の不透明な画素はすべて当たり判定の円の内側に収まり、円いっぱいに大きく描かれる（#2418）")
    func artFitsInsideTheCircle() throws {
        for kind in FruitKind.allCases {
            let image = try #require(BonsaiArt.image(kind))
            let frame = BonsaiArt.spriteFrame(for: kind, x: 40, y: 30)
            let k = BonsaiArt.unitsPerPixel(for: kind)
            #expect(abs(frame.width - Double(image.width) * k) < 1e-9)
            // 不透明な画素の四隅（盤の座標・下が原点）を円と比べる。
            let pixels = try Self.opaqueCorners(of: image)
            var farthest = 0.0
            for (px, py) in pixels {
                let x = frame.minX + px * k
                let y = frame.maxY - py * k
                farthest = max(farthest, ((x - 40) * (x - 40) + (y - 30) * (y - 30)).squareRoot())
            }
            #expect(farthest <= kind.radius + 1e-6, "\(kind.name) の絵が円からはみ出す（\(farthest) > \(kind.radius)）")
            #expect(farthest >= kind.radius * 0.97, "\(kind.name) の絵が円に対して小さすぎる（\(farthest) / \(kind.radius)）")
        }
    }

    @Test("絵の枠の基準点は絵の中（0〜1）で、枠は円の中心を基準に置かれる")
    func spriteFrameIsAnchoredAtTheCircleCenter() {
        for kind in FruitKind.allCases {
            let anchor = BonsaiArt.anchor(for: kind)
            #expect((0...1).contains(anchor.x) && (0...1).contains(anchor.y))
            let frame = BonsaiArt.spriteFrame(for: kind, x: 40, y: 30)
            #expect(abs(frame.minX + anchor.x * frame.width - 40) < 1e-9)
            #expect(abs(frame.minY + anchor.y * frame.height - 30) < 1e-9)
        }
    }

    /// 不透明（α > 16）な画素の四隅。座標は画素・原点は左上・下向きが正。
    private static func opaqueCorners(of image: CGImage) throws -> [(Double, Double)] {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var out: [(Double, Double)] = []
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 16 {
                for (dx, dy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                    out.append((Double(x) + dx, Double(y) + dy))
                }
            }
        }
        return out
    }
}
