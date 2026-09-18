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

    /// 実際に `rows` で使われている文字だけに絞ったパレットの複製。
    ///
    /// 合成（`overlaying`）は部品ごとのパレットを 1 枚にまとめるので、使っていない色まで
    /// 持ち込むと文字が早く枯れる。部品は共有パレット（`OjisanPixel.palette` など数十色）から
    /// 作られるのが常なので、重ねる前にここで落とす。
    public func trimmingPalette() -> PixelSprite {
        var used = Set<Character>()
        for row in rows { for ch in row where ch != "." { used.insert(ch) } }
        return PixelSprite(rows: rows, palette: palette.filter { used.contains($0.key) })
    }

    /// 1 ドットを `factor` 角に複製した複製（`cgImage(scale:)` と違い、格子のまま大きくする）。
    ///
    /// 合成（`overlaying`）は**ドットの格子が同じ大きさ**であることを前提にしているので、
    /// 小さい部品（16×15 の顔など）を大きく見せたいときは、描くときの倍率ではなく
    /// ここで格子ごと拡げてから重ねる。
    public func scaled(_ factor: Int) -> PixelSprite {
        let f = max(1, factor)
        guard f > 1 else { return self }
        var out = [String]()
        out.reserveCapacity(height * f)
        for row in rows {
            let wide = String(row.flatMap { ch in [Character](repeating: ch, count: f) })
            for _ in 0..<f { out.append(wide) }
        }
        return PixelSprite(rows: out, palette: palette)
    }

    /// 単色で塗りつぶした格子（場面の空・海・地面など、重ねる土台に使う）。
    public static func solid(width: Int, height: Int, color: UInt32) -> PixelSprite {
        PixelSprite(
            rows: [String](repeating: String(repeating: "#", count: max(1, width)), count: max(1, height)),
            palette: ["#": color]
        )
    }

    /// 別のドット絵を左上 `(x, y)` に重ねた複製（`.` は下を透かす）。枠からはみ出た部分は捨てる。
    ///
    /// **パレットの文字は自動で付け替える**。部品は `OjisanPixel` / `RunnerPixelArt` / 世界の配色など
    /// 別々のパレットから来るので、同じ文字が別の色を指すのが普通で、素朴に辞書を統合すると
    /// 片方の色が黙って化ける。ここでは重ねる側の文字を「同じ色が既にあればその文字・無ければ
    /// 空いている文字」へ写してから焼き込むので、**色は 1 つも変わらない**。
    public func overlaying(_ other: PixelSprite, x: Int, y: Int) -> PixelSprite {
        let top = trimmingPalette(), add = other.trimmingPalette()
        var palette = top.palette
        var keyForColor = [UInt32: Character](palette.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        var remap = [Character: Character]()
        for (ch, rgb) in add.palette {
            if let existing = keyForColor[rgb] { remap[ch] = existing; continue }
            guard let free = Self.paletteKeyPool.first(where: { palette[$0] == nil }) else {
                preconditionFailure("ドット絵の合成でパレットの文字が枯れた（色数 \(palette.count + 1)）")
            }
            palette[free] = rgb
            keyForColor[rgb] = free
            remap[ch] = free
        }
        var out = rows.map { Array($0) }
        for (dy, row) in add.rows.enumerated() {
            let ty = y + dy
            guard ty >= 0, ty < out.count else { continue }
            for (dx, ch) in row.enumerated() {
                let tx = x + dx
                guard ch != ".", tx >= 0, tx < out[ty].count, let key = remap[ch] else { continue }
                out[ty][tx] = key
            }
        }
        // 枠の外へ落ちた部品の色は 1 ドットも残っていないので、最後にもう一度落とす
        // （残すと「重ねたのに見えない色」がパレットに溜まり、合成を重ねるほど文字が枯れる）。
        return PixelSprite(rows: out.map { String($0) }, palette: palette).trimmingPalette()
    }

    /// 合成で色に割り当てる文字の在庫（`.` は透明なので含めない）。
    ///
    /// 順番に意味は無いが**決まった順**に配るので、同じ部品を同じ順に重ねれば毎回同じ格子になる
    /// （テストが `rows` をそのまま比べられる）。
    static let paletteKeyPool: [Character] = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-*/=#@$%&!?<>[]{}()~^_|"
    )

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
