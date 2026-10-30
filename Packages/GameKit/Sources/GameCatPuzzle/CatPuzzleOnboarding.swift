import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のおじさんちのねこさがし。
///
/// 盤は本番と同じ `CatPuzzleBoardCanvas` で、遊び方の図（`CatPuzzleHowToFigures`）の 4×4 の問題（`sample`）と
/// 部品を使い回す。ミスの図のマスは定数（`mistakeCell`）で持ち、`CatPuzzleOnboardingTests` が
/// `CatPuzzleModel` と `CatPuzzleLogic` に読み込んで、図のとおりになることを確かめる。
@MainActor
enum CatPuzzleOnboarding {
    /// ミスの図で、ダブルタップして赤い × が付いたマス（`sample` の答えでないマス）。
    static let mistakeCell = 4
    /// ミスの図で、先に見つけてある猫のマス（`sample` の答えのマス）。
    static let foundCat = CatPuzzleHowToFigures.tapCell

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "catpuzzle",
            title: tr("ねこさがしのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("おじさんの家に隠れている猫を、全部見つけるパズルです。"),
                        tr("猫は、部屋の数と同じだけいます。"),
                    ],
                    figure: { AnyView(GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("マスをタップすると、×（いない）を付け外しします。"),
                        tr("ダブルタップで、そのマスの猫を見つけます。"),
                        tr("指をすべらせると、続けて × を付けたり外したりできます。"),
                    ],
                    figure: { AnyView(CatPuzzleHowToFigures.TapControlsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("部屋・行・列に 1 匹ずつ"),
                    lines: [
                        tr("部屋・行・列のそれぞれに、猫がちょうど 1 匹ずついます。"),
                        tr("いないと分かったマスに × を付けて、絞り込みましょう。"),
                    ],
                    figure: { AnyView(CatPuzzleHowToFigures.OnePerRoomFigure()) }
                ),
                OnboardingPage(
                    heading: tr("猫どうしは隣り合わない"),
                    lines: [
                        tr("猫どうしは、ななめも含めて隣り合いません。"),
                        tr("猫を見つけたら、まわりの 8 マスにはほかの猫はいません。"),
                    ],
                    figure: { AnyView(CatPuzzleHowToFigures.NotAdjacentFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ミスは 3 回まで"),
                    lines: [
                        tr("答えでないマスをダブルタップすると、赤い × が付いてミスになります。"),
                        tr("赤い × は消せません。× の付け外しはミスになりません。"),
                    ],
                    figure: { AnyView(MistakeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("全部の猫を見つけたらクリア。記録はクリアまでのタイムです。"),
                        tr("ミスが 3 回になると負けです。"),
                        tr("広告を見ると、1 回だけ続きから遊べます。"),
                    ],
                    figure: { AnyView(ClearFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 何も印の無い盤 → 全部の猫を見つけた盤。
    private struct GoalFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 10) { index in
                VStack(spacing: 4) {
                    CatPuzzleHowToFigures.Board(
                        cats: index == 0 ? [] : CatPuzzleHowToFigures.sample.solutionCells,
                        solved: index == 1, cellSide: 22, showsRoomLabels: false
                    )
                    RuleFigureLabel(index == 0 ? tr("はじめ") : tr("おわり"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }

    /// 答えでないマスをダブルタップ → 赤い × が付き、ミスが 1 つ増える。
    private struct MistakeFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                CatPuzzleHowToFigures.Board(
                    cats: [CatPuzzleOnboarding.foundCat],
                    crosses: [CatPuzzleOnboarding.mistakeCell],
                    wrongCrosses: [CatPuzzleOnboarding.mistakeCell]
                )
                RuleFigureLabel(tr("ミス %1$lld/%2$lld", 1, CatPuzzleModel.maxMistakes), color: Theme.coralText)
            }
        }
    }

    /// 全部の猫を見つけた盤 → クリア。
    private struct ClearFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                CatPuzzleHowToFigures.Board(cats: CatPuzzleHowToFigures.sample.solutionCells, solved: true)
                RuleFigureLabel(tr("全部見つけたらクリア"), color: Theme.coralText)
            }
        }
    }
}
