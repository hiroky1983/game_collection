import SwiftUI

/// アプリ共通のデザインシステム（ポップ＝明るく楽しい）。全ゲーム・ハブで共有して統一感を出す。
public enum Theme {
    // 配色
    public static let background = Color(hex: 0xFFF6EC)   // 温かいクリーム
    public static let surface = Color.white
    public static let ink = Color(hex: 0x4A3B33)          // 文字（こげ茶）
    public static let inkSub = Color(hex: 0x9A8A80)       // 補助文字

    // アクセント（ポップな差し色）
    public static let coral = Color(hex: 0xFF6F61)
    public static let teal = Color(hex: 0x22C3BE)
    public static let purple = Color(hex: 0x8C7BE0)
    public static let yellow = Color(hex: 0xFFC24B)
    public static let pink = Color(hex: 0xFF8FB1)

    /// ゲームごとの差し色を順番に割り当てる用。
    public static let palette: [Color] = [coral, teal, purple, yellow, pink]

    // 形状・余白
    public static let corner: CGFloat = 20
    public static let cornerSmall: CGFloat = 12
    public static let pad: CGFloat = 16

    // フォント（丸ゴシックで楽しく）
    public static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    public static func body(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
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
}

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
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
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
}
