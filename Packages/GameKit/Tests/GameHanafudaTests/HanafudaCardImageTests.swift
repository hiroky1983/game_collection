import CoreGraphics
import Foundation
import Testing
@testable import GameHanafuda

/// 札の絵の画像（#2188）が 48 枚そろっていて、帯の下に主役が隠れないことの検査。
@Suite("花札: 札の画像（#2188）")
struct HanafudaCardImageTests {

    @Test("48 枚すべての画像が同梱されていて読める")
    func allImagesLoad() {
        for card in HanafudaCard.fullDeck {
            #expect(HanafudaCardImages.image(for: card) != nil, "\(card.name)（id \(card.id)）の画像が無い")
        }
    }

    /// 札の枠いっぱいに敷くので、画像は札と同じ 2:3 でないと図案が歪む（`aspectRatio(contentMode: .fill)` で端が切れる）。
    @Test("画像は札と同じ縦横比（2:3）")
    func imagesHaveCardAspect() {
        for card in HanafudaCard.fullDeck {
            guard let image = HanafudaCardImages.image(for: card) else { continue }
            let ratio = Double(image.height) / Double(image.width)
            #expect(abs(ratio - HanafudaCardArt.aspectRatio) < 0.01, "\(card.name) が \(image.width)×\(image.height)")
        }
    }

    /// 上端 20% は「月と種別の帯」が重なる（`HanafudaCardFace.bandRatio`）。ここに主役があると帯に食われるので、
    /// 帯の下の行はほぼ和紙色（地）であることを固定する。幕・雨の線のような一様な背景は許す（9 割で判定）。
    @Test("帯が重なる上端 20% には図案が無い")
    func topBandIsBlank() throws {
        for card in HanafudaCard.fullDeck {
            guard let image = HanafudaCardImages.image(for: card) else { continue }
            let share = try paperShare(ofTop: HanafudaCardFace.bandRatio, in: image)
            #expect(share >= 0.9, "\(card.name) の上端 20% の和紙色の割合が \(Int(share * 100))%")
        }
    }

    /// 画像の上端 `ratio` の行で、和紙色（#F2E6C9 ± 許容差）の画素が占める割合。
    private func paperShare(ofTop ratio: Double, in image: CGImage) throws -> Double {
        let width = image.width, rows = max(1, Int(Double(image.height) * ratio))
        var pixels = [UInt8](repeating: 0, count: width * rows * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try #require(CGContext(
            data: &pixels, width: width, height: rows, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space, bitmapInfo: info
        ))
        // CGContext は原点が左下なので、画像の上端 `rows` 行が収まるよう上へずらして描く。
        context.draw(image, in: CGRect(x: 0, y: rows - image.height, width: image.width, height: image.height))
        let paper: [Int] = [0xF2, 0xE6, 0xC9]
        let tolerance = 40
        var count = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            if (0..<3).allSatisfy({ abs(Int(pixels[i + $0]) - paper[$0]) <= tolerance }) { count += 1 }
        }
        return Double(count) / Double(width * rows)
    }
}
