import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2826）のぱっと暗算。
///
/// 数の出し方・足し算・テンキー・難易度の図は遊び方の図（`AnzanHowToFigures`）の部品を使い回す。
/// 図の数は `AnzanHowToFigures.numbers`、正誤の図の誤答は `wrongAnswer` で持ち、`AnzanOnboardingTests` が
/// `AnzanLogic` と `AnzanModel` に読み込んで、図のとおりになることを確かめる。
@MainActor
enum AnzanOnboarding {
    /// 正誤の図の「ざんねん」の答え（図の数の合計とは違う数）。
    static let wrongAnswer = 14

    static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "anzan",
            title: tr("ぱっと暗算のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("パッと出ては消える数を、頭の中で足していくゲームです。"),
                        tr("合計を当てたら正解です。"),
                    ],
                    figure: { AnyView(AnzanHowToFigures.SumFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("数が 1 つずつ、パッと出ては消えます。"),
                        tr("出た数を、頭の中でぜんぶ足していきます。"),
                    ],
                    figure: { AnyView(AnzanHowToFigures.FlashFigure()) }
                ),
                OnboardingPage(
                    heading: tr("答えを入れる"),
                    lines: [
                        tr("最後の数が消えたら、合計をテンキーで入力します。"),
                        tr("「決定」を押すと、正解かどうかが出ます。"),
                    ],
                    figure: { AnyView(AnzanHowToFigures.AnswerFigure()) }
                ),
                OnboardingPage(
                    heading: tr("難易度を選ぶ"),
                    lines: [
                        tr("右上の「難易度」で、桁数・個数・速さを選べます。"),
                        tr("桁数は 1〜3 桁、個数は 5・10・15 個です。"),
                        tr("まずは 1 桁・5 個・ゆっくりから。"),
                    ],
                    figure: { AnyView(AnzanHowToFigures.LevelFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("合計が合っていれば正解。続けて正解すると連続正解が伸びます。"),
                        tr("間違えると、連続正解は 0 に戻ります。"),
                        tr("答える前に広告を見ると、同じ数をもう一度見られます（1 問 1 回）。"),
                    ],
                    figure: { AnyView(ResultFigure()) }
                ),
            ]
        )
    }

    // MARK: - 図

    /// 図の数の合計を入れたら「せいかい！」、違う数なら「ざんねん…」。
    private struct ResultFigure: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                row(answer: AnzanLogic.sum(AnzanHowToFigures.numbers), isCorrect: true)
                row(answer: AnzanOnboarding.wrongAnswer, isCorrect: false)
            }
        }

        private func row(answer: Int, isCorrect: Bool) -> some View {
            HStack(spacing: 10) {
                Text(verbatim: "\(answer)")
                    .scaledFont(22, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 70, height: 40)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall / 2, style: .continuous)
                        .strokeBorder(isCorrect ? Theme.coral : Theme.inkSub.opacity(0.5), lineWidth: 2))
                RuleVerdictMark(isCorrect)
                Text(isCorrect ? tr("せいかい！") : tr("ざんねん…"))
                    .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(isCorrect ? Theme.coralText : Theme.inkSubText)
            }
        }
    }
}
