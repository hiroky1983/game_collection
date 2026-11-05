import Core
import CoreMiniCard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）の神経衰弱。
///
/// ペアの判定・手番の移り方・勝ち負けは `ConcentrationModel` と突き合わせる（`ConcentrationOnboardingTests`）。
/// 図は遊び方の図（`ConcentrationHowToFigures`）の部品を使い回す。
@MainActor
public enum ConcentrationOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "concentration",
            title: tr("神経衰弱のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("伏せられた札から、同じ絵柄の 2 枚をそろえます。"),
                        tr("そろえた 2 枚が 1 ペアです。"),
                    ],
                    figure: { AnyView(BoardFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("札を 2 枚、タップしてめくります。"),
                        tr("同じ絵柄ならペアになり、もう一度めくれます。"),
                    ],
                    figure: { AnyView(ConcentrationHowToFigures.PairFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ちがう絵柄だったとき"),
                    lines: [
                        tr("ちがう絵柄なら、札は伏せられます。"),
                        tr("そこで CPU の番になります。"),
                    ],
                    figure: { AnyView(ConcentrationHowToFigures.MissFigure()) }
                ),
                OnboardingPage(
                    heading: tr("覚えるのがコツ"),
                    lines: [
                        tr("めくった札の絵柄と場所を、覚えておきましょう。"),
                        tr("CPU がめくった札も、覚えるヒントになります。"),
                    ],
                    figure: { AnyView(RememberFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("すべてのペアが取られたら、終わりです。"),
                        tr("取ったペアが多いほうの勝ちです。"),
                        tr("同じ数なら、引き分けです。"),
                    ],
                    figure: { AnyView(ConcentrationHowToFigures.ScoreFigure()) }
                ),
            ]
        )
    }

    /// 伏せた札が並ぶ盤。その中の 2 枚をめくって同じ絵柄にそろえる。
    private struct BoardFigure: View {
        var body: some View {
            VStack(spacing: 8) {
                RuleMiniCardWrap(count: 8, perRow: 4) { index in
                    if index == 1 || index == 6 {
                        RuleMiniCard("🍎", isHighlighted: true)
                    } else {
                        RuleMiniCard("", isFaceDown: true)
                    }
                }
                RuleFigureLabel(tr("同じ絵柄の 2 枚をそろえる"), color: Theme.coralText)
            }
        }
    }

    /// 前にめくった札は伏せ直される。場所を覚えておけば、あとで同じ絵柄の札に出会ったときにそろえられる。
    private struct RememberFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        RuleMiniCard("🍎", isHighlighted: index == 1)
                        RuleMiniCard("", isFaceDown: true)
                        if index == 0 {
                            RuleMiniCard("", isFaceDown: true)
                        } else {
                            RuleMiniCard("🍎", isHighlighted: true)
                        }
                    }
                    .padding(.top, 4)
                    RuleFigureLabel(index == 0 ? tr("🍎 の場所を覚える") : tr("覚えた場所をめくってペア"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }
}
