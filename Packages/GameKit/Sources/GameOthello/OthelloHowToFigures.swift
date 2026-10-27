import Core
import CoreMiniBoard
import SwiftUI

/// 図入りの遊び方（#2044）のオセロの図。文言は `HowToPlayGuide.othello.items`（Core）と同じ順。
@MainActor
enum OthelloHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(HintFigure()) },
        { AnyView(FlipFigure()) },
        { AnyView(CountFigure()) },
    ]

    static let cell: CGFloat = 28

    /// 置けるマスの半透明の○。
    struct HintFigure: View {
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
                RuleFigureLabel(tr("○ のマスに置ける"), color: Theme.coralText)
            }
        }
    }

    /// 黒ではさむと、あいだの白が黒に裏返る。
    struct FlipFigure: View {
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
                    RuleFigureLabel(index == 0 ? tr("黒を置くと…") : tr("はさんだ白が黒に"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }

    /// 石の数で勝負が決まる。
    struct CountFigure: View {
        var body: some View {
            HStack(spacing: 22) {
                tally(.black, tr("黒 36"), isWinner: true)
                tally(.white, tr("白 28"), isWinner: false)
            }
        }

        private func tally(_ tone: RuleStone.Tone, _ label: String, isWinner: Bool) -> some View {
            VStack(spacing: 4) {
                RuleStone(tone, size: 34)
                RuleFigureLabel(label, color: isWinner ? Theme.coralText : Theme.inkSubText)
                if isWinner { RuleFigureLabel(tr("多い方の勝ち"), color: Theme.coralText) }
            }
        }
    }
}
