import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のナンプレ。
///
/// 盤・数字パッド・行/列/3×3 の図は遊び方の図（`SudokuHowToFigures`）の部品を使い回す。ミスの図は
/// `SudokuHowToFigures.solved` の左上の 3×3 に誤答を 1 つ入れたもので、`SudokuOnboardingTests` が
/// 誤答・ミス上限・コンティニュー・クリア・諦めを `SudokuModel` と突き合わせる。
@MainActor
enum SudokuOnboarding {
    /// ミスの図で誤答を入れるマス（左上の 3×3 の中の行・列）。
    static let mistakeCell = (row: 1, col: 1)
    /// ミスの図で入れる誤答（そのマスの答えとは違う数字）。
    static let mistakeDigit = 9

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "sudoku",
            title: tr("ナンプレのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("空いているマスに、1〜9 の数字を入れていくパズルです。"),
                        tr("盤をすべて埋めたらクリアです。"),
                    ],
                    figure: { AnyView(GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("空いているマスをタップして選びます。"),
                        tr("下の数字パッドで、1〜9 の数字を入れます。"),
                    ],
                    figure: { AnyView(SudokuHowToFigures.InputFigure()) }
                ),
                OnboardingPage(
                    heading: tr("同じ数字は 1 つまで"),
                    lines: [
                        tr("よこの行・たての列・太線の 3×3 には、1〜9 が 1 つずつ入ります。"),
                        tr("同じ数字は、どれにも 2 つ入りません。"),
                    ],
                    figure: { AnyView(SudokuHowToFigures.RuleFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ミスは 3 回まで"),
                    lines: [
                        tr("答えと違う数字を入れると、ミスになります。"),
                        tr("ミスが 3 回になると、そこで止まります。"),
                        tr("広告を見るとミスが 0 に戻り、続きから遊べます。"),
                    ],
                    figure: { AnyView(MistakeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("空いているマスを、すべて正しく埋めたらクリアです。"),
                        tr("「諦める」と答えが表示され、クリアできなかった記録になります。"),
                    ],
                    figure: { AnyView(SudokuHowToFigures.ClearFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 問題の盤（およそ半分が空き）→ 全部埋まった盤。
    private struct GoalFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    SudokuHowToFigures.Board(cell: 13, shows: { r, c in index == 1 || SudokuHowToFigures.given(r, c) })
                    RuleFigureLabel(index == 0 ? tr("はじめ") : tr("おわり"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }

    /// 左上の 3×3 に答えと違う数字を入れると、赤い枠と×が付いてミスが 1 つ増える。
    private struct MistakeFigure: View {
        private let cell: CGFloat = 40

        var body: some View {
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<3, id: \.self) { c in
                                square(r, c)
                            }
                        }
                    }
                }
                .overlay(Rectangle().stroke(Color(hex: 0x2A2A2A), lineWidth: 2))
                RuleFigureLabel(tr("ミス %1$lld/%2$lld", 1, SudokuModel.maxMistakes), color: Theme.coralText)
            }
        }

        private func square(_ r: Int, _ c: Int) -> some View {
            let isMistake = r == SudokuOnboarding.mistakeCell.row && c == SudokuOnboarding.mistakeCell.col
            let digit = isMistake ? SudokuOnboarding.mistakeDigit : SudokuHowToFigures.solved[r][c]
            return ZStack(alignment: .topTrailing) {
                Rectangle().fill(Color.white)
                Text(verbatim: "\(digit)")
                    .font(.system(size: cell * 0.6, weight: .bold, design: .rounded)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                    .foregroundStyle(isMistake ? Theme.coralText : Color(hex: 0x2A2A2A))
                    .frame(width: cell, height: cell)
                if isMistake {
                    Rectangle().strokeBorder(Theme.coralText, lineWidth: 2.5)
                    Image(systemName: "xmark")
                        .font(.system(size: cell * 0.2, weight: .heavy)) // fixed-size: 盤・駒・牌・タイルの寸法に比例させる文字（図形のジオメトリに従う）
                        .foregroundStyle(Theme.coralText)
                        .padding(cell * 0.08)
                }
            }
            .frame(width: cell, height: cell)
            .overlay(Rectangle().stroke(Color.gray.opacity(0.35), lineWidth: 0.5))
        }
    }
}
