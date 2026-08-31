import Testing
import Foundation
@testable import GameOthello

/// 合法手ドットの視認性を数値で固定する（#205）。
///
/// 「置ける場所が見えない」は目視だと気づきにくく、あとから不透明度を1つ戻されても
/// シミュレータを立てるまで分からない。`ThemeContrastTests`（#187）と同じやり方で、
/// WCAG のコントラスト比としてテストに落としておく。
struct OthelloBoardStyleTests {

    // MARK: - WCAG コントラスト比（計算方法は ThemeContrastTests と同一）

    /// sRGB の相対輝度（WCAG 2.1 の定義）。
    private static func relativeLuminance(_ rgb: (Double, Double, Double)) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.0) + 0.7152 * channel(rgb.1) + 0.0722 * channel(rgb.2)
    }

    private static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255,
         Double((hex >> 8) & 0xFF) / 255,
         Double(hex & 0xFF) / 255)
    }

    /// `foreground` を `alpha` の不透明度で `background` の上に重ねた見かけの色。
    ///
    /// sRGB 上での合成として見積もる。実際の描画がリニア空間で合成される場合は
    /// 前景（白）の寄与がこれより大きくなる = コントラストは上振れするため、安全側の見積もり。
    private static func composite(_ foreground: UInt32, over background: UInt32,
                                  alpha: Double) -> (Double, Double, Double) {
        let f = components(foreground), b = components(background)
        return (alpha * f.0 + (1 - alpha) * b.0,
                alpha * f.1 + (1 - alpha) * b.1,
                alpha * f.2 + (1 - alpha) * b.2)
    }

    private static func contrast(_ a: (Double, Double, Double),
                                 _ b: (Double, Double, Double)) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 非テキストの図形（WCAG 2.1 SC 1.4.11）の下限。
    private static let nonTextMinimum = 3.0

    private static var dotContrast: Double {
        contrast(
            composite(OthelloBoardStyle.legalMoveDot,
                      over: OthelloBoardStyle.boardGreen,
                      alpha: OthelloBoardStyle.legalMoveDotOpacity),
            components(OthelloBoardStyle.boardGreen)
        )
    }

    // MARK: - 受け入れ条件 1: 合法手ドットの視認性が向上する

    @Test("合法手ドットは盤の緑地に対して 3:1 以上のコントラストを持つ")
    func legalMoveDotMeetsNonTextContrast() {
        #expect(Self.dotContrast >= Self.nonTextMinimum)
    }

    /// 改善前（不透明度 0.38）は 3:1 を下回っていた、という前提そのものを固定する。
    /// これが崩れたらコントラストの計算式か盤の色のどちらかが変わっている。
    @Test("改善前の不透明度 0.38 では 3:1 に届かない")
    func previousOpacityFailedNonTextContrast() {
        let before = Self.contrast(
            Self.composite(OthelloBoardStyle.legalMoveDot,
                           over: OthelloBoardStyle.boardGreen,
                           alpha: 0.38),
            Self.components(OthelloBoardStyle.boardGreen)
        )
        #expect(before < Self.nonTextMinimum)
        #expect(Self.dotContrast > before)
    }

    // MARK: - 受け入れ条件 3: 盤面の見た目とのバランスを崩さない

    /// ドットが「小さい白石」に見えないよう、石の半径の半分未満に留める。
    @Test("合法手ドットは石より十分小さい")
    func legalMoveDotStaysSmallerThanStone() {
        #expect(OthelloBoardStyle.legalMoveDotRadiusRatio > 0)
        #expect(OthelloBoardStyle.legalMoveDotRadiusRatio
                < OthelloBoardStyle.stoneRadiusRatio / 2)
        // 石とグリッド線はマスに収まったまま（半径がマスの半分を超えると隣とぶつかる）。
        #expect(OthelloBoardStyle.stoneRadiusRatio < 0.5)
    }

    // MARK: - 盤の質感（#366）

    /// 盤のグラデーションは暗くする方向にしか振らないこと。
    /// 合法手ドットのコントラスト（上の 3:1 保証）は明るい側 `boardGreen` を背景に測って
    /// いるため、下端が明るくなると盤の一部で保証が崩れる。
    @Test("盤のグラデーション下端は上端より暗い")
    func boardGradientOnlyDarkens() {
        let top    = Self.relativeLuminance(Self.components(OthelloBoardStyle.boardGreen))
        let bottom = Self.relativeLuminance(Self.components(OthelloBoardStyle.boardGreenDeep))
        #expect(bottom < top)
    }

    /// 星が合法手ドットと紛らわしくならないよう、明確に小さく留める。
    @Test("星は合法手ドットより小さい")
    func starPointStaysSmallerThanLegalDot() {
        #expect(OthelloBoardStyle.starPointRadiusRatio > 0)
        #expect(OthelloBoardStyle.starPointRadiusRatio < OthelloBoardStyle.legalMoveDotRadiusRatio)
    }

    // MARK: - 受け入れ条件 2: 終局オーバーレイのトランジション

    @Test("終局オーバーレイのフェードは目に見える長さがある")
    func resultOverlayFadeHasVisibleDuration() {
        #expect(OthelloBoardStyle.resultOverlayFadeDuration > 0)
        // 勝敗の確認を待たせすぎない上限。
        #expect(OthelloBoardStyle.resultOverlayFadeDuration <= 0.4)
    }
}
