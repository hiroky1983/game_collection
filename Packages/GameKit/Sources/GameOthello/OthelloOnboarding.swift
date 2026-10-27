import Core
import CoreMiniBoard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2825）のオセロ。
///
/// 置けるマス・はさんで返る形は遊び方の図（`OthelloHowToFigures`）の部品を使い回す。パスの図は `passRow` を
/// そのまま描いたもので、`OthelloOnboardingTests` が同じ並びを `OthelloBoard` に読み込み、黒は置けず白は置けることを確かめる。
@MainActor
enum OthelloOnboarding {
    /// パスの図の 1 行（`W` 白・`B` 黒・`.` 空き）。黒の番で、黒の置けるマスが無い。
    static let passRow = "WB."

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "othello",
            title: tr("オセロのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("盤の上の石を、自分の色でたくさん増やすゲームです。"),
                        tr("終わったとき、石が多い方が勝ちです。"),
                    ],
                    figure: { AnyView(GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("半透明の○が、いま置けるマスです。"),
                        tr("○のマスをタップして、自分の石を置きます。"),
                    ],
                    figure: { AnyView(OthelloHowToFigures.HintFigure()) }
                ),
                OnboardingPage(
                    heading: tr("はさむと裏返る"),
                    lines: [
                        tr("自分の石で相手の石をはさめるマスにだけ置けます。"),
                        tr("はさんだ相手の石は、すべて自分の色に裏返ります。"),
                    ],
                    figure: { AnyView(OthelloHowToFigures.FlipFigure()) }
                ),
                OnboardingPage(
                    heading: tr("置けないとき"),
                    lines: [
                        tr("置けるマスが無いときは、自動でパスになります。"),
                        tr("パスをすると、相手の番になります。"),
                    ],
                    figure: { AnyView(PassFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("盤が埋まるか、どちらも置けなくなると終わりです。"),
                        tr("石が多い方の勝ち。同じ数なら引き分けです。"),
                        tr("空きマスを残して終わったら、空きマスは勝った方の得点になります。"),
                    ],
                    figure: { AnyView(OthelloHowToFigures.CountFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    private static let cell = OthelloHowToFigures.cell

    /// はじめの 4 個 → 終わりには自分の色が多い。
    private struct GoalFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    RuleMiniBoard(rows: 4, cols: 4, cell: cell, style: .green) { row, col in
                        stone(index: index, row: row, col: col)
                    }
                    RuleFigureLabel(index == 0 ? tr("はじめ") : tr("おわり"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }

        @ViewBuilder
        private func stone(index: Int, row: Int, col: Int) -> some View {
            if index == 0 {
                if (1...2).contains(row), (1...2).contains(col) {
                    RuleStone(row == col ? .white : .black, size: cell)
                }
            } else if (row + col) % 5 == 4 {
                RuleStone(.white, size: cell)
            } else {
                RuleStone(.black, size: cell)
            }
        }
    }

    /// 黒の番。黒は置けるマスが無いのでパス（白の番になる）。
    private struct PassFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                RuleMiniBoard(rows: 1, cols: OthelloOnboarding.passRow.count, cell: 44, style: .green) { _, col in
                    let c = Array(OthelloOnboarding.passRow)[col]
                    ZStack {
                        if c == "W" { RuleStone(.white, size: 44) }
                        if c == "B" { RuleStone(.black, size: 44) }
                    }
                }
                RuleFigureLabel(tr("黒は置けるマスが無い → パス"), color: Theme.coralText)
            }
        }
    }
}
