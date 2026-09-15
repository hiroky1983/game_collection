import Core
import GameKitTestSupport
import Testing
@testable import GameRunner

/// チャリンコおじさんのドット絵（走者以外・`RunnerPixelArt`）が壊れていないこと（#956）。
/// `PixelArtTests`（走者）と同じく、縛るのは「格子が揃っている」「パレットに無い文字が無い」
/// 「寸法が決裁どおり」で、絵の良し悪しは撮影で見る。
@Suite("走者以外のドット絵（#956）")
struct RunnerPixelArtTests {
    /// ここに集めた絵をすべて走査する。絵を足したらこの表にも足す。
    private static let sprites: [(name: String, sprite: PixelSprite)] = [
        ("たこ焼き", RunnerPixelArt.takoyaki()),
    ]

    @Test("行の長さが揃い、パレットに無い文字が無く、空でない")
    func spritesAreWellFormed() {
        for (name, s) in Self.sprites {
            #expect(s.width > 0 && s.height > 0, "\(name): 空")
            #expect(s.rows.allSatisfy { $0.count == s.width }, "\(name): 行の長さが揃っていない")
            #expect(s.undefinedKeys.isEmpty, "\(name): パレットに無い文字 \(s.undefinedKeys)")
            #expect(s.opaqueBounds != nil, "\(name): 不透明なドットが無い")
        }
    }

    /// 決裁（#956）: 走者の頭くらい = 高さ 16〜18 ドット（1 ドット ≒ 0.33 単位で 5〜6 単位）。
    /// シーン側は `anchorPoint = (0.5, 0)` で絵の底の中央を置き場に合わせるので、格子に透明な
    /// 余白の行・列が無いこと（不透明部分 = 格子全体）も固定する。
    @Test("たこ焼きは高さ 16〜18 ドットで、格子に余白が無い")
    func takoyakiFitsTheApprovedSize() throws {
        let s = RunnerPixelArt.takoyaki()
        let b = try #require(s.opaqueBounds)
        #expect((16...18).contains(b.height), "高さ \(b.height) ドット")
        #expect(b.x == 0 && b.y == 0 && b.width == s.width && b.height == s.height, "余白: \(b)")
        // 底の行の中央にドットがある（原点 = 底の中央が絵の上に乗る）。
        let bottom = Array(s.rows[s.height - 1])
        #expect(bottom[s.width / 2] != ".", "底の中央が透明")
    }

    /// #929 の規則: 手前の物は暗い縁取りで浮かせる。縁取り `K` はどの色より暗く、格子の外周
    /// （不透明部分の外側に接するドット）はすべて縁取りであること。
    @Test("たこ焼きの外周はすべて縁取りで、縁取りはどの色より暗い")
    func takoyakiIsOutlined() {
        let s = RunnerPixelArt.takoyaki()
        let rows = s.rows.map(Array.init)
        func isTransparent(_ x: Int, _ y: Int) -> Bool {
            x < 0 || y < 0 || y >= s.height || x >= s.width || rows[y][x] == "."
        }
        for y in 0..<s.height {
            for x in 0..<s.width where rows[y][x] != "." {
                let exposed = isTransparent(x - 1, y) || isTransparent(x + 1, y)
                    || isTransparent(x, y - 1) || isTransparent(x, y + 1)
                if exposed { #expect(rows[y][x] == "K", "(\(x), \(y)) の \(rows[y][x]) が外気に触れている") }
            }
        }
        let outline = WCAG.relativeLuminance(RunnerPixelArt.outline)
        for (key, color) in RunnerPixelArt.palette where key != "K" {
            #expect(WCAG.relativeLuminance(color) > outline, "\(key) が縁取りより暗い")
        }
    }
}
