import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）の 15 パズル。
///
/// タイルは本番と同じ `FifteenTile`、スライド・まとめて動く・完成形の図は遊び方の図（`FifteenHowToFigures`）の
/// 部品を使い回す。図の盤は定数（`startBoard`・`FifteenHowToFigures.slide` / `rowSlide`）で持ち、
/// `FifteenOnboardingTests` が `FifteenLogic` と `FifteenModel` に読み込んで、図のとおりになることを確かめる。
@MainActor
enum FifteenOnboarding {
    /// 目的の図の「はじめ」の盤（行優先・0 が空白）。揃っていないが、空白を動かして揃えられる並び。
    static let startBoard = [
        5, 1, 2, 4,
        9, 6, 3, 8,
        0, 10, 7, 11,
        13, 14, 15, 12,
    ]

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "fifteen",
            title: tr("15パズルのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("バラバラのタイルを動かして、1〜15 を順に並べるパズルです。"),
                        tr("空白は 1 マスだけ。そこへタイルを動かしていきます。"),
                    ],
                    figure: { AnyView(GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("空白の隣にあるタイルをタップします。"),
                        tr("タップしたタイルが、空白へスライドします。"),
                    ],
                    figure: { AnyView(FifteenHowToFigures.SlideFigure()) }
                ),
                OnboardingPage(
                    heading: tr("まとめて動かせる"),
                    lines: [
                        tr("空白と同じ行・列のタイルなら、離れていてもタップできます。"),
                        tr("間のタイルごと、まとめてスライドします。"),
                    ],
                    figure: { AnyView(FifteenHowToFigures.RowSlideFigure()) }
                ),
                OnboardingPage(
                    heading: tr("動かせないタイル"),
                    lines: [
                        tr("空白と同じ行・列にないタイルは、タップしても動きません。"),
                        tr("まず空白を、動かしたいタイルの行か列へ運びましょう。"),
                    ],
                    figure: { AnyView(BlockedFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("1〜15 を左上から順に並べたらクリアです。"),
                        tr("動かしたタイルの枚数が手数です。少ないほど良い記録です。"),
                        tr("負けはありません。困ったらヒントで次の 1 手が分かります。"),
                    ],
                    figure: { AnyView(FifteenHowToFigures.SolvedFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// バラバラの盤 → 1〜15 が順に並んだ盤。
    private struct GoalFigure: View {
        private let side: CGFloat = 20

        var body: some View {
            RuleFrames(count: 2, spacing: 10) { index in
                VStack(spacing: 4) {
                    board(index == 0 ? FifteenOnboarding.startBoard : FifteenLogic.solved)
                    RuleFigureLabel(index == 0 ? tr("はじめ") : tr("おわり"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }

        private func board(_ tiles: [Int]) -> some View {
            let n = FifteenLogic.defaultSize
            return VStack(spacing: 2) {
                ForEach(0..<n, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<n, id: \.self) { col in
                            let index = row * n + col
                            let value = tiles[index]
                            if value == 0 {
                                FifteenHowToFigures.Blank(side: side)
                            } else {
                                FifteenTile(value: value, side: side, isHome: index == value - 1)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 1 枚スライドの図の「前」の盤で、空白とななめの位置にある 9 は動かない。
    private struct BlockedFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                VStack(spacing: 3) {
                    ForEach(Array(FifteenHowToFigures.slide.before.enumerated()), id: \.offset) { _, row in
                        FifteenHowToFigures.Line(values: row)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    RuleVerdictMark(false)
                        .frame(width: FifteenHowToFigures.side, height: FifteenHowToFigures.side)
                }
                RuleFigureLabel(tr("同じ行・列にないと動かない"), color: Theme.coralText)
            }
        }
    }
}
