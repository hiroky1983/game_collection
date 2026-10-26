import Core
import CoreMiniBoard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2825）の五目並べ。
///
/// 禁じ手（連珠ルール）のオン・オフで中身が変わる（オンのときだけ「黒は打てない場所」のカードが入り、
/// 長連の扱いも違う）ので、「？」の遊び方と同じく `forbiddenMoves` を受けて組む。
/// 図は遊び方の図（`GomokuHowToFigures`）の部品を使い回す。`GomokuOnboardingTests` が図の形を実際の盤で確かめる。
@MainActor
enum GomokuOnboarding {
    static func guide(forbiddenMoves: Bool) -> OnboardingGuide {
        var pages = [
            OnboardingPage(
                heading: tr("このゲームの目的"),
                lines: [
                    tr("黒と白が交互に石を置いて、先に自分の石を 5 つ並べるゲームです。"),
                    tr("たて・よこ・ななめ、どの向きでもかまいません。"),
                ],
                figure: { AnyView(GomokuHowToFigures.FiveFigure()) }
            ),
            OnboardingPage(
                heading: tr("1 回の番でやること"),
                lines: [
                    tr("空いている交点をタップして、石を置きます。"),
                    tr("はじめの設定は 2 回タップ。1 回目は仮の石、同じ交点をもう一度タップで置きます。"),
                    tr("黒が先手、白が後手です。"),
                ],
                figure: { AnyView(GomokuHowToFigures.PlaceFigure()) }
            ),
            OnboardingPage(
                heading: tr("相手の列を止める"),
                lines: [
                    tr("相手が 4 つ並べたら、次の一手で 5 つになってしまいます。"),
                    tr("あいている端に石を置いて、止めましょう。"),
                ],
                figure: { AnyView(GomokuHowToFigures.BlockFigure()) }
            ),
        ]
        if forbiddenMoves {
            pages.append(OnboardingPage(
                heading: tr("黒の禁じ手"),
                lines: [
                    tr("禁じ手ありのときは、黒だけ打てない場所があります。"),
                    tr("三三・四四・長連（6 つ以上）になる場所です。"),
                    tr("白には禁じ手がありません。"),
                ],
                figure: { AnyView(GomokuHowToFigures.DoubleThreeFigure()) }
            ))
        }
        pages.append(OnboardingPage(
            heading: tr("勝ち負けの決まり"),
            lines: forbiddenMoves
                ? [
                    tr("先に 5 つ並べた方の勝ちです。"),
                    tr("黒はちょうど 5 つで勝ち（6 つ以上は禁じ手）。白は 6 つ以上でも勝ちです。"),
                    tr("盤が全部埋まったら引き分けです。"),
                ]
                : [
                    tr("先に 5 つ並べた方の勝ちです。6 つ以上並んでも勝ちです。"),
                    tr("盤が全部埋まったら引き分けです。"),
                ],
            figure: { AnyView(WinFigure()) }
        ))
        return OnboardingGuide(
            gameID: "gomoku",
            title: forbiddenMoves ? tr("五目並べのはじめての遊び方（禁じ手あり）") : tr("五目並べのはじめての遊び方"),
            pages: pages
        )
    }

    // MARK: - 図

    /// ななめに黒が 5 つ並んだ（勝ち）。
    private struct WinFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                RuleMiniBoard(rows: 6, cols: 6, cell: 24, style: .lines) { row, col in
                    ZStack {
                        if row == col, row < 5 { RuleStone(.black, size: 24) }
                        if (row, col) == (0, 3) || (row, col) == (2, 4) || (row, col) == (4, 1) {
                            RuleStone(.white, size: 24)
                        }
                    }
                }
                RuleFigureLabel(tr("5 つ並んだ！"), color: Theme.coralText)
            }
        }
    }
}
