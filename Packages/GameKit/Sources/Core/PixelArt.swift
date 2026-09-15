import CoreGraphics
import Foundation

// MARK: - ドット絵の器

/// ドット絵（1 文字 = 1 ドット）の定義。スーパーファミコン級の絵柄に統一する決裁（2026-09-15・会長）に
/// 従い、チャリンコおじさんの走者・背景・障害物はすべてこの形で持つ。
///
/// - 行は文字列、文字はパレットの鍵。`.` は透明。
/// - 描くときは `cgImage(scale:)` で **整数倍**に拡大する（補間しない）。SpriteKit 側は
///   `SKTexture.filteringMode = .nearest` にして、にじませない。
/// - 格子の縦横が揃っていない定義はバグなので `init` で検査する（テストでも全スプライトを走査する）。
public struct PixelSprite: Sendable, Equatable {
    public let rows: [String]
    public let palette: [Character: UInt32]

    public var width: Int { rows.first?.count ?? 0 }
    public var height: Int { rows.count }

    public init(rows: [String], palette: [Character: UInt32]) {
        precondition(!rows.isEmpty, "ドット絵の行が空")
        let w = rows[0].count
        precondition(rows.allSatisfy { $0.count == w }, "ドット絵の行の長さが揃っていない")
        self.rows = rows
        self.palette = palette
    }

    /// 定義に使われている文字がすべてパレットにあるか（`.` は透明）。
    public var undefinedKeys: Set<Character> {
        var keys = Set<Character>()
        for row in rows { for ch in row where ch != "." && palette[ch] == nil { keys.insert(ch) } }
        return keys
    }

    /// 左右反転（走者が左を向く場面用）。
    public func flippedHorizontally() -> PixelSprite {
        PixelSprite(rows: rows.map { String($0.reversed()) }, palette: palette)
    }

    /// 透明な余白を足して `width`×`height` の格子にする（中央寄せ）。元より小さい寸法は元のまま。
    /// アイコンのように「枠いっぱいに伸ばしても絵の周りに余白が残る」形にしたいときに使う。
    public func padded(width: Int, height: Int) -> PixelSprite {
        let w = max(width, self.width), h = max(height, self.height)
        let left = (w - self.width) / 2, top = (h - self.height) / 2
        let blank = String(repeating: ".", count: w)
        var out = [String](repeating: blank, count: top)
        let leftPad = String(repeating: ".", count: left)
        let rightPad = String(repeating: ".", count: w - left - self.width)
        out += rows.map { leftPad + $0 + rightPad }
        out += [String](repeating: blank, count: h - top - self.height)
        return PixelSprite(rows: out, palette: palette)
    }

    /// 不透明なドットの外接矩形（左上原点・ドット単位）。空なら nil。
    public var opaqueBounds: (x: Int, y: Int, width: Int, height: Int)? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// `scale` 倍（整数）に拡大したビットマップ。y は上が 0（CGImage の向きに合わせて描く）。
    public func cgImage(scale: Int = 1) -> CGImage? {
        let s = max(1, scale)
        let w = width * s, h = height * s
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard ch != ".", let rgb = palette[ch] else { continue }
                let r = UInt8((rgb >> 16) & 0xFF), g = UInt8((rgb >> 8) & 0xFF), b = UInt8(rgb & 0xFF)
                for dy in 0..<s {
                    for dx in 0..<s {
                        let i = ((y * s + dy) * w + (x * s + dx)) * 4
                        pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = 255
                    }
                }
            }
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: colorSpace, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
