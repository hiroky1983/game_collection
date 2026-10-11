import SwiftUI
import Core

/// 始める前に遊び方（荷運びモード / パズルモード・#1920）を選ぶシート。共通の `GameSetupSheet` に節を 1 つ足すだけ。
///
/// どちらが何なのか一目で分かるよう、カードには名前とアイコンを並べ、選んだモードの説明は
/// 「目的／ルールの要点／記録」を行ごとに分けて出す（会長指示 2026-10-12。以前は長い1文だけだった）。
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
                            icon: option.setupIcon,
                            metrics: .init(title: .title(18), titleMinimumScale: 0.7)
                        ) { mode = option }
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(mode.summaryLines, id: \.self) { line in
                        Text(line)
                            .scaledFont(12, weight: .medium, design: .rounded)
                            .foregroundStyle(Theme.inkSub)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}
