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
        GameSetupSheet(kind: .solo, howToPlay: howToPlay, onStart: onStart, onCancel: onCancel) {
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

    /// 選んでいるモードの図入りの遊び方（会長指示 2026-10-12「荷運びモードが分からない」）。
    /// ヘッダーの「？」と同じ中身を開く。閉じると開始シートに戻り、選んだモードはそのまま。
    private var howToPlay: GameSetupHowToPlay {
        GameSetupHowToPlay(mode.howToPlayGuide, label: "\(mode.title)の遊び方を見る")
    }
}

extension OjisanPuzzleMode {
    /// このモードの図入りの遊び方。ヘッダーの「？」と開始シートの「遊び方を見る」で同じものを開く。
    @MainActor
    var howToPlayGuide: HowToPlayGuide {
        switch self {
        case .backpain: .ojisanPuzzleBackpain.illustrated(OjisanPuzzleHowToFigures.backpain)
        case .puzzle: .ojisanPuzzlePuzzle.illustrated(OjisanPuzzleHowToFigures.puzzle)
        }
    }
}
