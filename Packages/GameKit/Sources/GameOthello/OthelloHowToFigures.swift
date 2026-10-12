import Core
import SwiftUI

/// 図入りの遊び方（#2044）のオセロの図。文言は `HowToPlayGuide.othello.items`（Core）と同じ順。
@MainActor
enum OthelloHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(HintFigure()) },
        { AnyView(FlipFigure()) },
        { AnyView(CountFigure()) },
    ]

    private static let cell: CGFloat = 28

    /// 置けるマスの半透明の○。
    private struct HintFigure: View {
        private let hints: Set<[Int]> = [[0, 1], [1, 0], [2, 3], [3, 2]]

        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 4, cols: 4, cell: cell, style: .green) { row, col in
                    ZStack {
                        if hints.contains([row, col]) {
                            Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2).frame(width: 18, height: 18)
                        }
                        if row == 1, col == 1 || col == 2 { RuleStone(col == 1 ? .white : .black, size: cell) }
                        if row == 2, col == 1 || col == 2 { RuleStone(col == 1 ? .black : .white, size: cell) }
                    }
                }
                RuleFigureLabel("○ のマスに置ける", color: Theme.coral)
            }
        }
    }

    /// 黒ではさむと、あいだの白が黒に裏返る。
    private struct FlipFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 1, cols: 4, cell: cell, style: .green) { _, col in
                        ZStack {
                            if col == 0 { RuleStone(.black, size: cell) }
                            if col == 1 || col == 2 { RuleStone(index == 0 ? .white : .black, size: cell) }
                            if col == 3 {
                                if index == 0 {
                                    Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2).frame(width: 18, height: 18)
                                } else {
                                    RuleStone(.black, size: cell)
                                }
                            }
                        }
                    }
                    RuleFigureLabel(index == 0 ? "黒を置くと…" : "はさんだ白が黒に",
                                    color: index == 0 ? Theme.coral : Theme.inkSub)
                }
            }
        }
    }

    /// 石の数で勝負が決まる。
    private struct CountFigure: View {
        var body: some View {
            HStack(spacing: 22) {
                tally(.black, "黒 36", isWinner: true)
                tally(.white, "白 28", isWinner: false)
            }
        }

        private func tally(_ tone: RuleStone.Tone, _ label: String, isWinner: Bool) -> some View {
            VStack(spacing: 4) {
                RuleStone(tone, size: 34)
                RuleFigureLabel(label, color: isWinner ? Theme.coral : Theme.inkSub)
                if isWinner { RuleFigureLabel("多い方の勝ち", color: Theme.coral) }
            }
        }
    }
}
