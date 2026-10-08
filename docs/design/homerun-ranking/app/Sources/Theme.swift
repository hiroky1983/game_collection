// release/v1.1.11 の Core/Theme.swift のライト側の値を写したモック用テーマ（本体コードは使わない）。
import SwiftUI

func hexColor(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
          blue: Double(v & 0xFF) / 255, opacity: a)
}

enum Theme {
    static let background = hexColor(0xFFF6EC)
    static let surface = hexColor(0xFFFFFF)
    static let ink = hexColor(0x4A3B33)
    static let inkSub = hexColor(0x9A8A80)
    static let fillStrong = hexColor(0x4A3B33)
    static let fillMuted = hexColor(0x9A8A80)
    static let coral = hexColor(0xFF6F61)
    static let teal = hexColor(0x22C3BE)
    static let purple = hexColor(0x8C7BE0)
    static let yellow = hexColor(0xFFC24B)
    static let pink = hexColor(0xFF8FB1)
    static let onAccent = ink
    enum Fill {
        static let coral = hexColor(0xFF8A7E)
        static let teal = hexColor(0x22C3BE)
        static let purple = hexColor(0xB3A6F0)
        static let yellow = hexColor(0xFFC24B)
        static let pink = hexColor(0xFF8FB1)
    }
    static let cardShadow = Color.black.opacity(0.08)
    static let corner: CGFloat = 20
    static let cornerSmall: CGFloat = 12
    static let pad: CGFloat = 16
}

extension View {
    func popCard(fill: Color = Theme.surface, corner: CGFloat = Theme.corner) -> some View {
        background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(fill)
                .shadow(color: Theme.cardShadow, radius: 10, x: 0, y: 6)
        )
    }
    func popBackground() -> some View { background(Theme.background.ignoresSafeArea()) }
    func themeTitle(_ size: CGFloat = 28, weight: Font.Weight = .heavy) -> some View {
        font(.system(size: size, weight: weight, design: .rounded))
    }
    func themeBody(_ size: CGFloat = 17, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded))
    }
    func themeCaption(_ size: CGFloat = 11, weight: Font.Weight = .bold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded))
    }
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        font(.system(size: size, weight: weight, design: design))
    }
}

/// 差し色のチップ（結果画面の `chip` と同じ見た目）。
struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var fill: Color = Theme.Fill.yellow
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(verbatim: text)
        }
        .themeCaption(12)
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(fill))
    }
}

/// 打席前・結果と同じ「おじさん」の絵（書き出し済み PNG）。
struct OjisanImage: View {
    var body: some View {
        Image(uiImage: bundleImage("HomerunOjisanStance")).resizable().scaledToFit()
    }
}

/// バンドル直下の PNG を読む（アセットカタログ無しのモックなので直接ファイルから）。
func bundleImage(_ name: String) -> UIImage {
    guard let path = Bundle.main.path(forResource: name, ofType: "png"), let img = UIImage(contentsOfFile: path) else {
        return UIImage()
    }
    return img
}
