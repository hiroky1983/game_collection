import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のマインスイーパー。
///
/// 数字・旗・まとめて開く図は遊び方の図（`MinesweeperHowToFigures`）の部品を使い回す。目的の図の盤は
/// `goalMines` / `goalTap` / `goalOpened` の定数で持ち、`MinesweeperOnboardingTests` が同じ盤を
/// `MinesweeperModel` に読み込んで、タップ 1 回で `goalOpened` のとおりに開くことを確かめる。
@MainActor
enum MinesweeperOnboarding {
    /// 目的の図の盤（4×4）の地雷の位置（行・列）。図には出さない（開く前なので伏せたまま）。
    static let goalMines: [(row: Int, col: Int)] = [(0, 3), (2, 3)]
    /// 目的の図で最初にタップするマス。
    static let goalTap = (row: 0, col: 0)
    /// タップ後の盤（数字は開いたマスのまわりの地雷の数・`#` は開いていないマス）。
    static let goalOpened = ["001#", "002#", "001#", "001#"]

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "minesweeper",
            title: tr("マインスイーパーのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("地雷をよけて、地雷の無いマスを開けていくゲームです。"),
                        tr("最初にタップしたマスは、地雷ではありません。"),
                        tr("まわりに地雷が無いマスは、まとめて開きます。"),
                    ],
                    figure: { AnyView(GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("マスをタップして開きます。"),
                        tr("数字は、まわり 8 マスにある地雷の数です。"),
                    ],
                    figure: { AnyView(MinesweeperHowToFigures.NumberFigure()) }
                ),
                OnboardingPage(
                    heading: tr("旗を立てる"),
                    lines: [
                        tr("地雷がありそうなマスは、長押しで旗を立てます。"),
                        tr("旗を立てたマスは、タップしても開きません。"),
                        tr("「⋯」の「旗モード」をオンにすると、タップで旗を立てられます。"),
                    ],
                    figure: { AnyView(MinesweeperHowToFigures.FlagFigure()) }
                ),
                OnboardingPage(
                    heading: tr("まとめて開ける"),
                    lines: [
                        tr("数字と同じ数だけ旗を立てたら、その数字をタップします。"),
                        tr("まわりの残りのマスが、まとめて開きます。"),
                        tr("旗がまちがっていると、地雷を踏んでしまいます。"),
                    ],
                    figure: { AnyView(MinesweeperHowToFigures.ChordFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("地雷以外のマスをすべて開けたらクリアです。"),
                        tr("地雷を踏むと負けです。"),
                        tr("広告を見ると、1 回だけ続きから遊べます。"),
                    ],
                    figure: { AnyView(ResultFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    private typealias Cell = MinesweeperHowToFigures.Cell

    /// 全部伏せた盤の角をタップ → まわりに地雷の無いマスがまとめて開く。
    private struct GoalFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        MinesweeperHowToFigures.Grid(
                            cells: Array(repeating: Array(repeating: Cell.closed, count: 4), count: 4),
                            highlight: [MinesweeperOnboarding.goalTap.row * 10 + MinesweeperOnboarding.goalTap.col]
                        )
                    } else {
                        MinesweeperHowToFigures.Grid(cells: MinesweeperOnboarding.goalOpened.map { line in
                            line.map { ch in ch.wholeNumberValue.map(Cell.open) ?? .closed }
                        })
                    }
                    RuleFigureLabel(index == 0 ? tr("角をタップ") : tr("まとめて開いた"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }

    /// 地雷以外を全部開けたらクリア／地雷を踏んだら負け。
    private struct ResultFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        MinesweeperHowToFigures.Grid(cells: [
                            [.open(1), .flag],
                            [.open(1), .open(1)],
                        ])
                    } else {
                        MinesweeperHowToFigures.Grid(cells: [
                            [.open(1), .mine],
                            [.open(1), .open(1)],
                        ], highlight: [1])
                    }
                    RuleFigureLabel(index == 0 ? tr("クリア！") : tr("ゲームオーバー"),
                                    color: index == 0 ? Theme.coralText : Theme.inkSubText)
                }
            }
        }
    }
}
