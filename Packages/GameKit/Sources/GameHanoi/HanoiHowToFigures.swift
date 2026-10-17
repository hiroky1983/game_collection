import Core
import SwiftUI

/// 図入りの遊び方（#2044）のハノイの塔の図。文言は `HowToPlayGuide.hanoi.items`（Core）と同じ順。
/// 円盤は本番と同じ `HanoiDisk`。
@MainActor
enum HanoiHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(TakeAndPlaceFigure()) },
        { AnyView(NoLargerOnSmallerFigure()) },
        { AnyView(GoalFigure()) },
    ]

    private static let columnWidth: CGFloat = 40
    private static let diskHeight: CGFloat = 11

    /// 小さな盤。`pegs` は本番と同じく各柱の下から上。`lifted` の柱は一番上を浮かせる。
    private struct MiniBoard: View {
        let pegs: [[Int]]
        var lifted: Int? = nil
        var totalDisks = 3
        var body: some View {
            HStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { peg in
                    HanoiPegColumn(
                        disks: pegs[peg], totalDisks: totalDisks, isSelected: lifted == peg,
                        columnWidth: HanoiHowToFigures.columnWidth, diskHeight: HanoiHowToFigures.diskHeight
                    )
                    .frame(width: HanoiHowToFigures.columnWidth, height: HanoiHowToFigures.diskHeight * CGFloat(totalDisks + 3) + 12)
                }
            }
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.cornerSmall / 4, style: .continuous)
                    .fill(Theme.fillStrong)
                    .frame(height: 8)
            }
        }
    }

    /// 柱をタップして取る → 別の柱をタップして置く。
    private struct TakeAndPlaceFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 6) { index in
                    MiniBoard(pegs: index == 0 ? [[3, 2, 1], [], []] : [[3, 2], [], [1]],
                              lifted: index == 0 ? 0 : nil)
                }
                RuleFigureLabel(tr("取って、別の柱に置く"), color: Theme.coral)
            }
        }
    }

    /// 小さい円盤の上に大きい円盤は置けない。
    private struct NoLargerOnSmallerFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    MiniBoard(pegs: [[3], [2], [1]], lifted: 1)
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(20, weight: .bold, maxScale: 1.2)
                        .foregroundStyle(Theme.coralText)
                        .accessibilityHidden(true)
                }
                RuleFigureLabel(tr("2 は 1 の上に置けない"), color: Theme.coral)
            }
        }
    }

    /// 全部が右の柱に揃った完成形。
    private struct GoalFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleFrames(count: 2, spacing: 6) { index in
                    MiniBoard(pegs: index == 0 ? [[3, 2, 1], [], []] : [[], [], [3, 2, 1]])
                }
                RuleFigureLabel(tr("3 枚なら最少 7 手"), color: Theme.teal)
            }
        }
    }
}
