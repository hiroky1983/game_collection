import Testing
import Foundation
import Core

/// ダークモード対応（#187）の配色を数値で検証する。
///
/// 画面の見た目そのものはシミュレータのスクリーンショットで確認しているが、
/// 「あとから誰かが色を1つ差し替えたときに読めなくなる」ことは目視では防げないので、
/// WCAG のコントラスト比をテストとして固定しておく。
struct ThemeContrastTests {

    // MARK: - WCAG コントラスト比

    /// sRGB の相対輝度（WCAG 2.1 の定義）。
    private static func relativeLuminance(_ hex: UInt32) -> Double {
        func channel(_ raw: UInt32) -> Double {
            let v = Double(raw) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    /// 2色のコントラスト比（1.0〜21.0）。
    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 本文テキストの下限（WCAG AA）。
    private static let aa = 4.5

    private static let white: UInt32 = 0xFFFFFF

    // MARK: - 受け入れ条件 3: ライトモードの見た目は現状から変化しない

    /// ライト側の値を固定する。ダーク対応のついでにライトの配色を動かすと、
    /// 公開済みのスクリーンショット（`docs/aso/`）と実機の見た目がずれる。
    @Test func lightPaletteIsUnchanged() {
        #expect(Theme.Hex.background.light == 0xFFF6EC)
        #expect(Theme.Hex.surface.light == 0xFFFFFF)
        #expect(Theme.Hex.ink.light == 0x4A3B33)
        #expect(Theme.Hex.inkSub.light == 0x9A8A80)
        // ink / inkSub をチップの面色として使っていた箇所の置き換え先。
        // ライトでは元の値と同一でなければ見た目が変わる。
        #expect(Theme.Hex.fillStrong.light == Theme.Hex.ink.light)
        #expect(Theme.Hex.fillMuted.light == Theme.Hex.inkSub.light)
        #expect(Theme.Hex.accents == [0xFF6F61, 0x22C3BE, 0x8C7BE0, 0xFFC24B, 0xFF8FB1])
    }

    // MARK: - 受け入れ条件 1 / 2: ダークでもコントラストが不足しない

    @Test func inkIsReadableInBothModes() {
        for (bg, ink) in [
            (Theme.Hex.background.light, Theme.Hex.ink.light),
            (Theme.Hex.background.dark, Theme.Hex.ink.dark),
            (Theme.Hex.surface.light, Theme.Hex.ink.light),
            (Theme.Hex.surface.dark, Theme.Hex.ink.dark),
        ] {
            #expect(Self.contrast(ink, bg) >= Self.aa)
        }
    }

    /// 補助文字はライトでも AA に届いていない（3.11:1）ため、絶対値の下限は AA では引けない。
    /// 代わりに「ダークがライトを下回らないこと」を条件にして、対応で悪化していないことを保証する。
    @Test func subtleInkDoesNotRegressInDarkMode() {
        for (light, dark) in [
            (Theme.Hex.background.light, Theme.Hex.background.dark),
            (Theme.Hex.surface.light, Theme.Hex.surface.dark),
        ] {
            let lightRatio = Self.contrast(Theme.Hex.inkSub.light, light)
            let darkRatio = Self.contrast(Theme.Hex.inkSub.dark, dark)
            #expect(darkRatio >= lightRatio)
            #expect(darkRatio >= Self.aa)
        }
    }

    /// 白文字を載せるチップ・ボタンの面色。ここを `ink` / `inkSub` のまま動的にすると
    /// ダークで面が明るくなり、白文字が消える（#187 の主な事故ケース）。
    ///
    /// ライト側は従来値のまま動かせない（`fillMuted` は 3.32:1 で元から AA を満たしていない）ため、
    /// 下限を課すのはダーク側だけにし、ライトに対しては悪化しないことだけを見る。
    @Test func whiteTextOnFilledChipsIsReadableInDarkMode() {
        for pair in [Theme.Hex.fillStrong, Theme.Hex.fillMuted] {
            #expect(Self.contrast(Self.white, pair.dark) >= Self.aa)
        }
        // 控えめなチップはライトの 3.32:1 より良くなる（9.05:1）。
        #expect(Self.contrast(Self.white, Theme.Hex.fillMuted.dark)
                >= Self.contrast(Self.white, Theme.Hex.fillMuted.light))
    }

    /// 差し色は両モード共通。面色として白文字を載せる用途が大半のため、
    /// ダーク用に明るくすると白文字とのコントラストが下がる。値が1つであることが担保。
    /// そのうえで、ダークの地・面に対して文字色として使っても沈まないことを確認する。
    @Test func accentsStayReadableOnDarkSurfaces() {
        for accent in Theme.Hex.accents {
            let onDarkBackground = Self.contrast(accent, Theme.Hex.background.dark)
            let onDarkSurface = Self.contrast(accent, Theme.Hex.surface.dark)
            #expect(onDarkBackground >= Self.contrast(accent, Theme.Hex.background.light))
            #expect(onDarkSurface >= Self.contrast(accent, Theme.Hex.surface.light))
            // 最小は purple の 4.32:1（面の上）。ライト側の 3.49:1 より良い。
            #expect(onDarkBackground >= 4.0)
            #expect(onDarkSurface >= 4.0)
        }
    }

    /// 面（カード）と地（画面背景）の差は、ポップな見た目を保つためどちらのモードでも小さい
    /// （ライト 1.07:1 / ダーク 1.19:1）。ダークでは黒い影も効かないので、`PopCard` は
    /// 薄い枠（`Theme.cardBorder`）で境界を残す設計にしてある。
    /// ここでは「面だけで境界が付く明るさ差にはなっていない」という前提が変わっていないことを見る
    /// （もし将来この比が上がったなら、枠は不要になったか設計が変わったかのどちらか）。
    @Test func cardRequiresABorderToSeparateFromBackground() {
        #expect(Self.contrast(Theme.Hex.surface.dark, Theme.Hex.background.dark) < 1.5)
        #expect(Theme.Hex.surface.dark != Theme.Hex.background.dark)
    }
}
