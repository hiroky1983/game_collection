import SwiftUI

/// 10 回勝負の最後の回を示す「ラスト」のバッジ（#2592）。ポーカーとブラックジャックの上の帯で共有する。
///
/// 面は差し色の黄で、載せる文字は `onAccent`（#220）。帯を押し広げないよう 1 行・拡大の上限つきにする。
public struct FinalRoundBadge: View {
    public init() {}

    public var body: some View {
        Text(tr("ラスト"))
            .themeCaption(11, weight: .heavy, maxScale: 1.3)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(Theme.Fill.yellow))
            .accessibilityLabel(tr("最後の勝負"))
    }
}

public enum FinalRoundBar {
    /// 最初の拡大の倍率と、1 往復にかける長さ（秒）。仮置きで、会長 QA で調整する。
    static let pulseScale: CGFloat = 1.04
    static let pulseDuration: TimeInterval = 0.25

    /// 帯の読み上げ文の頭に「最後の勝負」を足す（例: "最後の勝負、10回目 / 10、…"）。
    public static func accessibilityLabel(_ base: String, isFinal: Bool) -> String {
        isFinal ? tr("最後の勝負、%@", base) : base
    }
}

public extension View {
    /// 最後の回だけ帯の縁を黄色にし、`isFinal` が偽から真になった瞬間（と、最初から真で出たとき）に
    /// 1 回だけ軽く膨らませる。Reduce Motion では縁だけで動かさない。偽のあいだは何も足さない。
    func finalRoundBar(_ isFinal: Bool, corner: CGFloat = Theme.cornerSmall) -> some View {
        modifier(FinalRoundBarModifier(isFinal: isFinal, corner: corner))
    }
}

private struct FinalRoundBarModifier: ViewModifier {
    let isFinal: Bool
    let corner: CGFloat
    @State private var swelled = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFinal {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Theme.Fill.yellow, lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(swelled ? FinalRoundBar.pulseScale : 1)
            .gameAnimation(.easeOut(duration: FinalRoundBar.pulseDuration / 2), value: swelled)
            .onChange(of: isFinal, initial: true) { _, now in
                guard now else { return }
                swelled = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(FinalRoundBar.pulseDuration / 2))
                    swelled = false
                }
            }
    }
}
