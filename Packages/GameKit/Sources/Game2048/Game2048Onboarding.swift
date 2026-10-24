import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）の 2048。
///
/// タイルは本番と同じ `TileView`、スライド・合体・2048 の図は遊び方の図（`Game2048HowToFigures`）の部品を使い回す。
/// 図の盤は定数（`Game2048HowToFigures.slideRow` / `mergeRow`・`spawnRow`・`stuckBoard`）で持ち、
/// `Game2048OnboardingTests` が `Game2048Logic` と `Game2048Model` に読み込んで、図のとおりになることを確かめる。
@MainActor
enum Game2048Onboarding {
    /// 新しいタイルの図の「後」の 1 行。スライドの図の「後」（`slideRow.after`）の空きに 2 が 1 枚出たところ。
    static let spawnRow = [2, 4, 0, 2]
    /// ゲームオーバーの図の盤。空きが無く、上下左右に同じ数字が並んでいない（どこにも動かせない）。
    static let stuckBoard: [[Int]] = [
        [2, 8, 2, 4],
        [4, 16, 4, 2],
        [2, 8, 32, 4],
        [4, 2, 4, 2],
    ]

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "2048",
            title: tr("2048 のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("同じ数字のタイルを合体させて、大きな数字を作るゲームです。"),
                        tr("2048 のタイルを作れたらクリアです。"),
                    ],
                    figure: { AnyView(Game2048HowToFigures.GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("上下左右のどれかへスワイプします。"),
                        tr("すべてのタイルが、その向きへ寄ります。"),
                    ],
                    figure: { AnyView(Game2048HowToFigures.SlideFigure()) }
                ),
                OnboardingPage(
                    heading: tr("同じ数字で合体"),
                    lines: [
                        tr("同じ数字どうしがぶつかると、合体して 2 倍になります。"),
                        tr("合体してできた数字が、スコアに入ります。"),
                    ],
                    figure: { AnyView(Game2048HowToFigures.MergeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("新しいタイル"),
                    lines: [
                        tr("動かすたびに、空いたマスに新しいタイルが 1 枚出ます。"),
                        tr("新しいタイルは 2 か 4 です。"),
                    ],
                    figure: { AnyView(SpawnFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("2048 を作ったらクリア。そのまま続けることもできます。"),
                        tr("どこにも動かせなくなったら、ゲームオーバーです。"),
                        tr("広告を見ると、1 回だけ続きから遊べます。"),
                    ],
                    figure: { AnyView(StuckFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 左へスワイプ → 寄ったあとの空きに新しいタイルが 1 枚出る。
    private struct SpawnFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                RuleFrames(count: 2, spacing: 8) { index in
                    Game2048HowToFigures.Row(values: index == 0
                                             ? Game2048HowToFigures.slideRow.before
                                             : Game2048Onboarding.spawnRow)
                }
                RuleFigureLabel(tr("新しいタイルが 1 枚出る"), color: Theme.coralText)
            }
        }
    }

    /// 空きが無く、となりに同じ数字も無い盤 → ゲームオーバー。
    private struct StuckFigure: View {
        private let tile: CGFloat = Game2048HowToFigures.tile

        var body: some View {
            VStack(spacing: 6) {
                VStack(spacing: 4) {
                    ForEach(Array(Game2048Onboarding.stuckBoard.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 4) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, v in
                                TileView(value: v, size: tile)
                            }
                        }
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                    .fill(Color(hex: 0xBBADA0)))
                RuleFigureLabel(tr("どこにも動かせない → ゲームオーバー"), color: Theme.coralText)
            }
        }
    }
}
