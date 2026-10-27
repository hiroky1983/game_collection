import Core
import SwiftUI

/// 図入りの遊び方（#2044）の 2048 の図。文言は `HowToPlayGuide.game2048.items`（Core）と同じ順。
/// タイルは本番と同じ `TileView`。
@MainActor
enum Game2048HowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(SlideFigure()) },
        { AnyView(MergeFigure()) },
        { AnyView(GoalFigure()) },
    ]

    static let tile: CGFloat = 28

    /// スライドの図の 1 行（左へスワイプする前 → 後）。はじめての遊び方（#2826）のテストが `Game2048Logic` で確かめる。
    static let slideRow = (before: [0, 2, 0, 4], after: [2, 4, 0, 0])
    /// 合体の図の 1 行（左へスワイプする前 → 後）。
    static let mergeRow = (before: [2, 2, 8, 8], after: [4, 16, 0, 0])

    /// 1 行ぶんの盤（0 は空き）。
    struct Row: View {
        let values: [Int]
        var body: some View {
            HStack(spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    TileView(value: v, size: Game2048HowToFigures.tile)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                .fill(Color(hex: 0xBBADA0)))
        }
    }

    /// 左へスワイプ → 全部が左へ寄る。
    struct SlideFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                RuleFrames(count: 2, spacing: 8) { index in
                    Row(values: index == 0 ? Game2048HowToFigures.slideRow.before : Game2048HowToFigures.slideRow.after)
                }
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw.fill")
                        .scaledFont(13, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.coralText)
                    RuleFigureLabel(tr("左へスワイプ"), color: Theme.coralText)
                }
            }
        }
    }

    /// 同じ数字がぶつかると合体して 2 倍。
    struct MergeFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 8) { index in
                Row(values: index == 0 ? Game2048HowToFigures.mergeRow.before : Game2048HowToFigures.mergeRow.after)
            }
        }
    }

    /// 2048 を作ればクリア。
    struct GoalFigure: View {
        var body: some View {
            HStack(spacing: 10) {
                TileView(value: 1024, size: 40)
                Image(systemName: "plus")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                TileView(value: 1024, size: 40)
                Image(systemName: "arrow.right")
                    .scaledFont(12, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.inkSubText)
                VStack(spacing: 4) {
                    TileView(value: 2048, size: 48)
                    RuleFigureLabel(tr("クリア！"), color: Theme.coralText)
                }
            }
        }
    }
}
