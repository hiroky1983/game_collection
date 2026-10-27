import Core
import CoreMiniCard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のババ抜き。
///
/// ペアの捨て方・引き方・ジョーカーの置き場所・勝ち負けは `OldMaidGame` と突き合わせる
/// （`OldMaidOnboardingTests`）。図は遊び方の図（`OldMaidHowToFigures`）の部品を使い回す。
@MainActor
public enum OldMaidOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: OldMaidModel.gameID,
            title: tr("ババ抜きのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("ジョーカーを、最後まで持たないことが目的です。"),
                        tr("ほかの札をぜんぶ出し切って、先に抜けましょう。"),
                    ],
                    figure: { AnyView(JokerFigure()) }
                ),
                OnboardingPage(
                    heading: tr("最初に起こること"),
                    lines: [
                        tr("配られた手札の、同じ数字の 2 枚（ペア）は、自動で捨てられます。"),
                        tr("ジョーカーはペアになりません。"),
                    ],
                    figure: { AnyView(OldMaidHowToFigures.PairFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("次の CPU の伏せた札を、1 枚選んで引きます。"),
                        tr("ペアができたら捨てます。"),
                    ],
                    figure: { AnyView(OldMaidHowToFigures.DrawFigure()) }
                ),
                OnboardingPage(
                    heading: tr("CPU の顔をよく見る"),
                    lines: [
                        tr("札を選ぶと、CPU の顔に出ることがあります。"),
                        tr("にやりとしたら、ジョーカーかもしれません。"),
                    ],
                    figure: { AnyView(OldMaidHowToFigures.FaceFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ジョーカーを引いたら"),
                    lines: [
                        tr("引いたジョーカーは、手札の右端に入ります。"),
                        tr("CPU に場所を見られるので、「シャッフル」で混ぜましょう。"),
                    ],
                    figure: { AnyView(ShuffleFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("手札がなくなった人から、抜けていきます。"),
                        tr("最後にジョーカーを持って残った人が、負けです。"),
                    ],
                    figure: { AnyView(OldMaidHowToFigures.LoseFigure()) }
                ),
            ]
        )
    }

    /// ジョーカー 1 枚。これを持って残らないのが目的。
    private struct JokerFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                OldMaidCardFaceView(card: .joker, highlighted: true)
                RuleFigureLabel(tr("ジョーカー（ペアにならない）"), color: Theme.coralText)
            }
        }
    }

    /// 引いたジョーカーは右端に入る。「シャッフル」で並びを混ぜる。
    private struct ShuffleFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if index == 0 {
                            RuleMiniCard("3", suit: .heart)
                            RuleMiniCard("9", suit: .club)
                            OldMaidCardFaceView(card: .joker, highlighted: true)
                        } else {
                            OldMaidCardFaceView(card: .joker, highlighted: true)
                            RuleMiniCard("3", suit: .heart)
                            RuleMiniCard("9", suit: .club)
                        }
                    }
                    .padding(.top, 4)
                    RuleFigureLabel(index == 0 ? tr("右端に入る") : tr("シャッフルで混ぜる"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }
}
