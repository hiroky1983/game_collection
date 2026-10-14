import Testing
import GameKitTestSupport
@testable import Game2048

/// タイルの文字と面のコントラスト比（#2233）。白文字 × 明るい橙・黄の面で 1.5〜2.6:1 しか出ていなかった。
@Suite("2048 タイルのコントラスト")
struct Game2048TileContrastTests {
    @Test("全タイル値で文字と面のコントラスト比が 4.5:1 以上")
    func everyTileMeetsAA() {
        for exponent in 1...17 {
            let value = 1 << exponent
            let ratio = WCAG.contrast(TileView.faceHex(for: value), TileView.textHex)
            #expect(ratio >= 4.5, "\(value) のコントラスト比 \(ratio)")
        }
    }
}
