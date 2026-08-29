import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// アプリ共通のデザインシステム（ポップ＝明るく楽しい）。全ゲーム・ハブで共有して統一感を出す。
///
/// 配色は**システムのライト / ダーク設定に追従する**（#187）。追従させるのは
/// 「地と文字」（`background` / `surface` / `ink` / `inkSub`）だけで、差し色（`coral` 等）は
/// 両モードで同じ値を使う。差し色はほぼ全ての箇所で**白文字を載せる面色**として使われており、
/// ダーク用に明るくすると白文字とのコントラストが落ちて、いまライトモードで確保できている
/// 可読性を下げてしまうため。値を動かさなくてもダークの地・面に対するコントラストは
/// ライト時より必ず良くなる（最小は面の上の `purple` で 4.32:1。ライト時は同じ組み合わせで 3.49:1）。
public enum Theme {
    /// ライト / ダークで切り替える色の実体（0xRRGGBB）。
    ///
    /// `Color` は生成後に成分を取り出せないため、コントラスト比を検証する `ThemeTests` が
    /// 参照できるよう数値のままここに置く。ライト側はすべて従来値のままで、ダーク側だけが新規。
    public enum Hex {
        public typealias Pair = (light: UInt32, dark: UInt32)

        public static let background: Pair = (0xFFF6EC, 0x1B1613)   // 温かいクリーム / 温かい暗色
        public static let surface: Pair = (0xFFFFFF, 0x2C2522)      // カードの面
        public static let ink: Pair = (0x4A3B33, 0xF4ECE5)          // 文字（こげ茶 / 生成り）
        public static let inkSub: Pair = (0x9A8A80, 0xB9ABA2)       // 補助文字

        /// 白文字を載せる「濃い」チップ・ボタンの面色（将棋の先手番・囲碁の黒番など）。
        /// `ink` はダークで明るく反転するため面色には使えない。
        public static let fillStrong: Pair = (0x4A3B33, 0x6F5B4E)
        /// 同じく白文字を載せる「控えめな」チップ・ボタンの面色（パス・フォールド・後手など）。
        public static let fillMuted: Pair = (0x9A8A80, 0x504742)

        // 差し色（両モード共通）。
        public static let coral: UInt32 = 0xFF6F61
        public static let teal: UInt32 = 0x22C3BE
        public static let purple: UInt32 = 0x8C7BE0
        public static let yellow: UInt32 = 0xFFC24B
        public static let pink: UInt32 = 0xFF8FB1

        /// 差し色の一覧（コントラスト検証用）。
        public static let accents: [UInt32] = [coral, teal, purple, yellow, pink]
    }

    // 地と文字（システムのライト / ダーク設定に追従する）
    public static let background = Color(Hex.background)
    public static let surface = Color(Hex.surface)
    public static let ink = Color(Hex.ink)
    public static let inkSub = Color(Hex.inkSub)
    public static let fillStrong = Color(Hex.fillStrong)
    public static let fillMuted = Color(Hex.fillMuted)

    // アクセント（ポップな差し色。両モード共通）
    public static let coral = Color(hex: Hex.coral)
    public static let teal = Color(hex: Hex.teal)
    public static let purple = Color(hex: Hex.purple)
    public static let yellow = Color(hex: Hex.yellow)
    public static let pink = Color(hex: Hex.pink)

    /// ゲームごとの差し色を順番に割り当てる用。
    public static let palette: [Color] = [coral, teal, purple, yellow, pink]

    /// 盤・駒・牌・トランプなど、**モードによらず色が変わらない面**の上に置く文字色。
    /// 面が明るいまま固定なので、ここで `ink` / `inkSub` を使うとダークで文字だけ反転して読めなくなる。
    public enum Fixed {
        public static let ink = Color(hex: Hex.ink.light)
    }

    /// カードの縁取り。ライトでは影だけで浮かせるので透明、ダークでは面と地の差が
    /// 小さくなるぶん薄い明色の枠を足して境界を残す。
    public static let cardBorder = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0, darkAlpha: 0.10)
    /// カードの影。ダークでは黒い影がほとんど効かないぶん濃くする。
    public static let cardShadow = Color(light: 0x000000, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.45)

    // 形状・余白
    public static let corner: CGFloat = 20
    public static let cornerSmall: CGFloat = 12
    public static let pad: CGFloat = 16

    // フォント（丸ゴシックで楽しく）は `View.themeTitle(_:)` / `View.themeBody(_:)` /
    // `View.themeCaption(_:weight:)` で当てる。実体は `ScaledThemeFont`。
    //
    // かつては `Theme.title(_:)` / `Theme.body(_:)` が `Font` を返していたが、
    // `Font.system(size:)` は固定 pt で文字サイズ設定（Dynamic Type）を無視するため廃止した（#189）。
    // 盤面の駒・カードの数字など「図形のジオメトリに従うべき文字」は拡大させたくないので、
    // 従来どおり呼び出し側で `.font(.system(size:))` を直接指定する。
}

/// Dynamic Type（文字サイズ設定）に追従するテーマフォント（#189）。
///
/// `@ScaledMetric` で基準 pt を拡大してから Font を作る。既定の文字サイズ（`.large`）では
/// 倍率が 1.0 になるため、見た目は固定 pt 指定だったときと完全に一致する。
public struct ScaledThemeFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
    }

    public func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .rounded))
    }
}

public extension Color {
    /// 0xRRGGBB 形式から生成。
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// ライト / ダークで別の値を返す動的カラー。
    ///
    /// 解決をプラットフォームの trait に委ねるため、`@Environment(\.colorScheme)` を
    /// 各ビューへ配らなくても切り替わる（＝既存の `Theme.ink` などの呼び出しをそのまま使える）。
    init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(rgb: dark, alpha: darkAlpha)
                : NSColor(rgb: light, alpha: lightAlpha)
        })
        #else
        self.init(hex: light, alpha: lightAlpha)
        #endif
    }

    /// `Theme.Hex.Pair` から生成する糖衣。
    init(_ pair: Theme.Hex.Pair) {
        self.init(light: pair.light, dark: pair.dark)
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32, alpha: Double) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
#endif

/// ポップなカード見た目（白い面・丸角・やわらかい影）。
public struct PopCard: ViewModifier {
    public var fill: Color
    public var corner: CGFloat
    public init(fill: Color = Theme.surface, corner: CGFloat = Theme.corner) {
        self.fill = fill
        self.corner = corner
    }
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(fill)
                    .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1)
                    )
            )
    }
}

public extension View {
    /// ポップなカード背景を付与する。
    func popCard(fill: Color = Theme.surface, corner: CGFloat = Theme.corner) -> some View {
        modifier(PopCard(fill: fill, corner: corner))
    }

    /// 画面全体のポップな背景。
    func popBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }

    /// 見出しを Dynamic Type 追従で適用する（#189）。
    func themeTitle(_ size: CGFloat = 28, weight: Font.Weight = .heavy) -> some View {
        modifier(ScaledThemeFont(size: size, weight: weight, relativeTo: .title))
    }

    /// 本文を Dynamic Type 追従で適用する（#189）。
    func themeBody(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> some View {
        modifier(ScaledThemeFont(size: size, weight: weight, relativeTo: .body))
    }

    /// 記録・バッジなど小さな補助テキストを Dynamic Type 追従で適用する（#189）。
    /// 基準を `.caption` にして本文より拡大幅を抑える（狭い枠に入るテキストのため）。
    func themeCaption(_ size: CGFloat = 11, weight: Font.Weight = .bold) -> some View {
        modifier(ScaledThemeFont(size: size, weight: weight, relativeTo: .caption))
    }

    /// 新規ゲームシートの高さ。アクセシビリティ相当の文字サイズのときだけ `.large` で開く（#189）。
    ///
    /// これらのシートは「選択肢 + 下端の開始ボタン」の固定レイアウトで、文字が拡大されると
    /// 選択肢が縦に伸びて開始ボタンが `.medium` の高さから押し出される。既定の文字サイズでは
    /// 従来どおり `.medium` から始まるため、見た目も操作感も変わらない。
    func gameSheetDetents() -> some View {
        modifier(GameSheetDetents())
    }
}

/// 押下中だけ縮んで沈む、`.plain` の代わりに使うボタンスタイル（#195）。
///
/// `.buttonStyle(.plain)` は装飾を一切付けない代わりに**押下フィードバックも消える**ため、
/// 自前で背景を描いたボタン（各ゲームの操作ボタン）は「押したのか分からない」状態になっていた。
/// 見た目（背景・文字色）はラベル側の指定をそのまま通し、押下時の変形だけをここで足す。
///
/// 縮小は Reduce Motion では動かしたくないので `gameAnimation` 経由にする。
/// ON のときはアニメーションが消えるだけで、押下中に縮む状態そのものは残る（フィードバックは失われない）。
public struct PopButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .gameAnimation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == PopButtonStyle {
    /// 押下フィードバック付きの `.plain` 相当（#195）。
    static var pop: PopButtonStyle { PopButtonStyle() }
}

/// `View.gameSheetDetents()` の実体。
private struct GameSheetDetents: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}
