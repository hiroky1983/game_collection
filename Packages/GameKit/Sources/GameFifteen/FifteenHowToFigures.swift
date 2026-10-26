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

    static let side: CGFloat = 30

    /// 1 枚スライドの図の盤（2×2・行の順）。空白の左の 5 をタップすると、5 が空白へ動く。
    /// 図で見る「はじめての遊び方」（#2826）の「動かせないタイル」の図も `slide.before` を使う。
    static let slide = (before: [[5, 0], [9, 3]], after: [[0, 5], [9, 3]], tapped: 5)
    /// まとめて動く図の 1 行。離れた 7 をタップすると、空白までの 3 枚がまとめて動く。
    static let rowSlide = (before: [7, 2, 11, 0], after: [0, 7, 2, 11], tapped: 7)

    /// 空白のマス。
    struct Blank: View {
        var side: CGFloat = FifteenHowToFigures.side
        var body: some View {
            RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                .strokeBorder(Theme.inkSub.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                .frame(width: side, height: side)
        }
    }

    /// 0 を空白として 1 行を並べる。`hint` の値に枠を付ける。
    struct Line: View {
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
    struct SlideFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 10) { index in
                    let slide = FifteenHowToFigures.slide
                    VStack(spacing: 3) {
                        ForEach(Array((index == 0 ? slide.before : slide.after).enumerated()), id: \.offset) { _, row in
                            Line(values: row, hint: index == 0 ? slide.tapped : nil)
                        }
                    }
                }
                RuleFigureLabel(tr("空白の隣をタップ"), color: Theme.coralText)
            }
        }
    }

    /// 同じ行の離れたタイルをタップ → 間ごとまとめて動く。
    struct RowSlideFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 8) { index in
                    let row = FifteenHowToFigures.rowSlide
                    Line(values: index == 0 ? row.before : row.after, hint: index == 0 ? row.tapped : nil)
                }
                RuleFigureLabel(tr("まとめて動く"), color: Theme.coralText)
            }
        }
    }

    /// 1〜15 が順に並んだ完成形。
    struct SolvedFigure: View {
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
