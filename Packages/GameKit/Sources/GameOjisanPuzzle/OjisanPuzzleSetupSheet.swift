import SwiftUI
import Core

/// 始める前に遊び方（腰痛モード / パズルモード・#1920）を選ぶシート。共通の `GameSetupSheet` に節を 1 つ足すだけ。
struct OjisanPuzzleSetupSheet: View {
    /// 選んだ遊び方。`onStart` で局に焼き込まれる。
    @Binding var mode: OjisanPuzzleMode
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        GameSetupSheet(kind: .solo, onStart: onStart, onCancel: onCancel) {
            GameSetupSection("遊び方") {
                HStack(spacing: 12) {
                    ForEach(OjisanPuzzleMode.allCases) { option in
                        GameSetupChooser(
                            title: option.title, subtitle: "",
                            selected: mode == option, accent: Theme.Fill.coral,
                            metrics: .init(title: .title(18), titleMinimumScale: 0.7)
                        ) { mode = option }
                    }
                }
                Text(mode.summary)
                    .scaledFont(12, weight: .medium, design: .rounded)
                    .foregroundStyle(Theme.inkSub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
