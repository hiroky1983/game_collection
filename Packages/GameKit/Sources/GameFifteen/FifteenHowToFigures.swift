import Core
import SwiftUI

/// 図入りの遊び方（#2044）の 15 パズルの図。文言は `HowToPlayGuide.fifteen.items`（Core）と同じ順。
/// タイルは本番と同じ `FifteenTile`。
@MainActor
enum FifteenHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(SlideFigure()) },
        { AnyView(RowSlideFigure()) },
        { AnyView(SolvedFigure()) },
    ]

    private static let side: CGFloat = 30

    /// 空白のマス。
    private struct Blank: View {
        var body: some View {
            RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                .strokeBorder(Theme.inkSub.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: FifteenHowToFigures.side, height: FifteenHowToFigures.side)
        }
    }

    /// 0 を空白として 1 行を並べる。`hint` の値に枠を付ける。
    private struct Line: View {
        let values: [Int]
        var hint: Int? = nil
        var body: some View {
            HStack(spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    if v == 0 {
                        Blank()
                    } else {
                        FifteenTile(value: v, side: FifteenHowToFigures.side, isHome: false, isHint: v == hint)
                    }
                }
            }
        }
    }

    /// 空白の隣をタップ → 1 枚スライド。
    private struct SlideFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    VStack(spacing: 3) {
                        Line(values: index == 0 ? [5, 0] : [0, 5], hint: index == 0 ? 5 : nil)
                        Line(values: [9, 3])
                    }
                }
                RuleFigureLabel(tr("空白の隣をタップ"), color: Theme.coral)
            }
        }
    }

    /// 同じ行の離れたタイルをタップ → 間ごとまとめて動く。
    private struct RowSlideFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 8) { index in
                    Line(values: index == 0 ? [7, 2, 11, 0] : [0, 7, 2, 11], hint: index == 0 ? 7 : nil)
                }
                RuleFigureLabel(tr("まとめて動く"), color: Theme.coral)
            }
        }
    }

    /// 1〜15 が順に並んだ完成形。
    private struct SolvedFigure: View {
        var body: some View {
            VStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { col in
                            let v = row * 4 + col + 1
                            if v == 16 {
                                Blank()
                            } else {
                                FifteenTile(value: v, side: FifteenHowToFigures.side, isHome: true)
                            }
                        }
                    }
                }
            }
        }
    }
}
