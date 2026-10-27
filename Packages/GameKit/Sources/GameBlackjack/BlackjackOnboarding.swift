import Core
import CoreMiniCard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のブラックジャック。
///
/// 点数の数え方・勝ち点・勝負の回数は `handValue` / `blackjackPoints` / `BlackjackModel.roundsPerMatch` から引く
/// （`BlackjackOnboardingTests` が突き合わせる）。図は遊び方の図（`BlackjackHowToFigures`）の部品を使い回す。
@MainActor
public enum BlackjackOnboarding {
    /// ディーラーが止まる合計（`drawDealerToStand` の「17 未満なら引く」）。
    static let dealerStandsAt = 17

    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "blackjack",
            title: tr("ブラックジャックのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("カードの合計を、21 に近づけます。"),
                        tr("ディーラーより 21 に近ければ勝ちです。"),
                        tr("21 を超えると、その場で負けです。"),
                    ],
                    figure: { AnyView(BlackjackHowToFigures.GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("カードの点数"),
                    lines: [
                        tr("A は 1 点か 11 点、J・Q・K は 10 点です。"),
                        tr("2〜10 は書いてある数のままです。"),
                        tr("A は、21 を超えないほうで自動で数えます。"),
                    ],
                    figure: { AnyView(BlackjackHowToFigures.PointsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("「ヒット」で、もう 1 枚引きます。"),
                        tr("これでいいと思ったら「スタンド」で止めます。"),
                    ],
                    figure: { AnyView(BlackjackHowToFigures.HitStandFigure()) }
                ),
                OnboardingPage(
                    heading: tr("スプリット"),
                    lines: [
                        tr("最初の 2 枚が同じ点数なら、2 つの手に分けられます。"),
                        tr("分けられるのは 1 回だけ。分けた A は 1 枚ずつで終わります。"),
                    ],
                    figure: { AnyView(BlackjackHowToFigures.SplitFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ディーラーの番"),
                    lines: [
                        tr("あなたが止めたら、ディーラーが引きます。"),
                        tr("合計が %1$lld 未満の間は引き、%1$lld 以上で止まります。", dealerStandsAt),
                    ],
                    figure: { AnyView(DealerFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("%lld 回勝負して、勝ち点の合計で競います。", BlackjackModel.roundsPerMatch),
                        tr("勝てば 1 点。分けずに、最初の 2 枚で 21 を作って勝てば 2 点です。"),
                        tr("引き分けと負けは 0 点です。"),
                    ],
                    figure: { AnyView(ScoreFigure()) }
                ),
            ]
        )
    }

    /// ディーラーは 16 までは引き、17 になったら止まる（A は 1 点に下がって 17）。
    private struct DealerFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        RuleMiniCard("10", suit: .club)
                        RuleMiniCard("6", suit: .diamond)
                        if index > 0 { RuleMiniCard("A", suit: .spade, isHighlighted: true) }
                    }
                    .padding(.top, 4)
                    Text(index == 0 ? tr("合計 16") : tr("合計 17"))
                        .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
                        .foregroundStyle(index == 0 ? Theme.ink : Theme.coralText)
                    RuleFigureLabel(index == 0 ? tr("17 未満なので引く") : tr("17 以上なので止まる"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }

    /// 勝ち点。勝ち 1 点、最初の 2 枚の 21 は 2 点。
    private struct ScoreFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 22) {
                column(cards: [RuleMiniCard("9", suit: .heart), RuleMiniCard("8", suit: .club)],
                       caption: tr("勝ち 1 点"))
                column(cards: [RuleMiniCard("A", suit: .spade), RuleMiniCard("K", suit: .heart)],
                       caption: tr("最初の 2 枚で 21\n2 点"), color: Theme.coralText)
            }
        }

        private func column(cards: [RuleMiniCard], caption: String, color: Color = Theme.inkSubText) -> some View {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in card }
                }
                RuleFigureLabel(caption, color: color)
            }
        }
    }
}
