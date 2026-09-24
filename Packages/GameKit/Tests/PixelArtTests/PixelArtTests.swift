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
    @Test("走者のコマは 40×37、正面顔は 32×30 で、行の長さが揃いパレットに無い文字が無い")
    func spritesAreWellFormed() {
        for frame in OjisanPixel.RiderFrame.allCases {
            let s = OjisanPixel.rider(frame)
            #expect(s.width == 40 && s.height == 37, "\(frame): \(s.width)×\(s.height)")
            #expect(s.undefinedKeys.isEmpty, "\(frame): パレットに無い文字 \(s.undefinedKeys)")
            #expect(s.opaqueBounds != nil)
        }
        for face in OjisanPixel.Face.allCases {
            let s = OjisanPixel.face(face)
            #expect(s.width == 32 && s.height == 30, "\(face): \(s.width)×\(s.height)")
            #expect(s.undefinedKeys.isEmpty, "\(face): パレットに無い文字 \(s.undefinedKeys)")
            #expect(s.opaqueBounds != nil, "\(face): 何も描かれていない")
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
        #expect(icon.width == 48 && icon.height == 48)
        #expect(OjisanPixel.mascotFaceImage?.width == 96)
    }

    // MARK: 合成（#1092 のストーリーの場面が使う）

    @Test("塗りつぶしと格子ごとの拡大は、寸法どおりで色を混ぜない")
    func solidAndScale() {
        let s = PixelSprite.solid(width: 3, height: 2, color: 0x112233)
        #expect(s.width == 3 && s.height == 2)
        #expect(s.undefinedKeys.isEmpty)
        #expect(Set(s.palette.values) == [0x112233])

        let big = PixelSprite(rows: ["KY"], palette: ["K": 0x102030, "Y": 0xF0C030]).scaled(3)
        #expect(big.width == 6 && big.height == 3)
        #expect(big.rows == ["KKKYYY", "KKKYYY", "KKKYYY"])
        #expect(big.scaled(1) == big, "1 倍は素通し")
        #expect(big.scaled(0) == big, "0 以下でも壊れない")
    }

    @Test("使っていない色はパレットから落ちる")
    func trimmingPaletteDropsUnusedColors() {
        let s = PixelSprite(rows: ["K."], palette: ["K": 0x102030, "Y": 0xF0C030, "Z": 0x000000])
        let t = s.trimmingPalette()
        #expect(t.rows == s.rows)
        #expect(t.palette == ["K": 0x102030])
    }

    /// 合成のいちばんの落とし穴は「同じ文字が別の色を指す 2 枚を重ねると、片方の色が黙って化ける」こと。
    /// 部品は `OjisanPixel` / `RunnerPixelArt` / 世界の配色から来るので、この衝突は例外ではなく普通に起きる。
    @Test("重ねても色は 1 つも変わらない（同じ文字が別の色を指していても）")
    func overlayingKeepsEveryColor() {
        let base = PixelSprite(rows: ["KK", "KK"], palette: ["K": 0x111111])
        // 重ねる側の "K" は**別の色**。素朴に辞書を統合すると、この赤が下地の黒に化ける。
        let top = PixelSprite(rows: ["K"], palette: ["K": 0xFF0000])
        let merged = base.overlaying(top, x: 1, y: 0)
        #expect(merged.width == 2 && merged.height == 2)
        #expect(merged.undefinedKeys.isEmpty)
        func color(_ x: Int, _ y: Int) -> UInt32? {
            let ch = Array(merged.rows[y])[x]
            return ch == "." ? nil : merged.palette[ch]
        }
        #expect(color(0, 0) == 0x111111)
        #expect(color(1, 0) == 0xFF0000, "重ねた側の色が下地の色に化けた")
        #expect(color(0, 1) == 0x111111)
        #expect(color(1, 1) == 0x111111)
    }

    @Test("重ねる側の透明は下を透かし、枠からはみ出た分は捨てる")
    func overlayingClipsAndKeepsTransparency() {
        let base = PixelSprite.solid(width: 3, height: 3, color: 0x111111)
        // 右へ 1 ドットはみ出す置き方。左上は透明なので、そこは下地が残るはず。
        let top = PixelSprite(rows: [".Y", "YY"], palette: ["Y": 0xF0C030])
        let merged = base.overlaying(top, x: 2, y: 1)
        #expect(merged.width == 3 && merged.height == 3, "はみ出しても枠は変わらない")
        func color(_ x: Int, _ y: Int) -> UInt32? { merged.palette[Array(merged.rows[y])[x]] }
        #expect(color(2, 1) == 0x111111, "透明のところは下地のまま")
        #expect(color(2, 2) == 0xF0C030, "枠内に入った分は描かれる")
        // まるごと枠の外（左上）へ置いても落ちず、絵もパレットも増えない。
        #expect(base.overlaying(top, x: -5, y: -5) == base)
    }

    /// 枠の外の部品にまで文字を配ると、在庫（`paletteKeyPool`）を使い切って落ちる（CodeRabbit 指摘・#1092）。
    @Test("色数の多い部品をまるごと枠の外へ置いても、文字を使い切らない")
    func overlayingOutOfBoundsDoesNotConsumeKeys() {
        let base = PixelSprite.solid(width: 4, height: 4, color: 0x111111)
        // 在庫の総数を超える色数の部品（1 ドット 1 色）。
        let pool = PixelSprite.paletteKeyPool
        let keys = pool + ["A"]   // 在庫より 1 多い（同じ文字は色を上書きするので数は在庫ぶん）
        var palette = [Character: UInt32]()
        for (i, ch) in keys.enumerated() { palette[ch] = UInt32(0x010000 + i) }
        let wide = PixelSprite(rows: [String(palette.keys.sorted())], palette: palette)
        #expect(wide.palette.count > pool.count - 1, "テストの部品の色数が在庫より少ない（空振り）")
        // 枠の外なら 1 ドットも描かれないので、文字は 1 つも減らない。
        #expect(base.overlaying(wide, x: 100, y: 100) == base)
        #expect(base.overlaying(wide, x: 0, y: -10) == base)
    }

    @Test("同じ色は 1 つの文字にまとめる（文字を無駄に使わない）")
    func overlayingReusesKeysForTheSameColor() {
        let base = PixelSprite(rows: ["K"], palette: ["K": 0x102030])
        let top = PixelSprite(rows: ["Z"], palette: ["Z": 0x102030])
        let merged = base.overlaying(top, x: 0, y: 0)
        #expect(merged.palette.count == 1, "同じ色に 2 つ目の文字を配っている")
    }

    /// リザルト用の顔（#702）は表情ぶんを起動後 1 回だけビットマップ化する。
    @Test("リザルト用の正面顔は 1 ドット = 4px で 1 回だけ作られ、比率 16:15（32×30）を保つ")
    func faceImagesAreCachedOnce() throws {
        #expect(OjisanPixel.faceDotSize.width == 32 && OjisanPixel.faceDotSize.height == 30)
        #expect(OjisanPixel.faceImages.count == OjisanPixel.Face.allCases.count)
        for face in OjisanPixel.Face.allCases {
            let img = try #require(OjisanPixel.faceImages[face], "\(face)")
            #expect(img.width == 128 && img.height == 120, "\(face): \(img.width)×\(img.height)")
            // `static let` なので 2 度引いても同じビットマップ（作り直していない）。
            #expect(OjisanPixel.faceImages[face] === img, "\(face)")
        }
        #expect(OjisanPixel.faceImages[.smile] !== OjisanPixel.faceImages[.frown], "表情ごとに別のビットマップ")
    }

    /// レビュー用: OJISAN_PIXEL_OUT にディレクトリを渡すと、全コマを 5 倍で並べた PNG を書き出す。
    @Test("レビュー用のシートを書き出す（環境変数があるときだけ）")
    func writeReviewSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["OJISAN_PIXEL_OUT"] else { return }
        let scale = 5
        let frames = OjisanPixel.RiderFrame.allCases.map { OjisanPixel.rider($0) }
        let faces = OjisanPixel.Face.allCases.map { OjisanPixel.face($0) }
        let w = (40 * scale + 10) * frames.count + 10
        let h = 37 * scale + 15 * scale + 40
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
