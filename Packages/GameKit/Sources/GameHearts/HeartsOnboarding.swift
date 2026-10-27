import Core
import CoreMiniCard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2827）のハーツ。
///
/// 点数・終わりの点・渡す枚数は `HeartsRules` / `HeartsReference` から引き、札の強さの並びは
/// 早見表（#2788）と同じ `HeartsReference.strengthOrder` を使う（`HeartsOnboardingTests` が突き合わせる）。
/// 図は遊び方の図（`HeartsHowToFigures`）の部品を使い回す。
@MainActor
public enum HeartsOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: HeartsModel.gameID,
            title: tr("ハーツのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("札を「取らない」ゲームです。"),
                        tr("ハートは 1 枚 1 点、スペードの Q は 13 点です。"),
                        tr("点が少ないほど勝ちです。"),
                    ],
                    figure: { AnyView(HeartsHowToFigures.PointsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("最初にやること"),
                    lines: [
                        tr("13 枚が配られたら、まず %lld 枚を選んで左どなりへ渡します。", HeartsRules.passCount),
                        tr("最初はクラブの 2 を持っている人から出します。"),
                    ],
                    figure: { AnyView(HeartsHowToFigures.PassFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("最初に出た札と同じマークを、1 枚出します。"),
                        tr("同じマークが無ければ、どの札でも出せます。"),
                    ],
                    figure: { AnyView(HeartsHowToFigures.FollowFigure()) }
                ),
                OnboardingPage(
                    heading: tr("だれが取るか"),
                    lines: [
                        tr("最初のマークで、いちばん強い札を出した人が 4 枚を取ります。"),
                        tr("A が最強、2 が最弱。切り札はありません。"),
                    ],
                    figure: { AnyView(HeartsHowToFigures.TakeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("ハートの出し方"),
                    lines: [
                        tr("ハートは、だれかが場に出すまで先頭に出せません。"),
                        tr("1 巡目は、ハートとスペードの Q を出せません。"),
                        tr("手札がそれだけのときは出せます。"),
                    ],
                    figure: { AnyView(HeartsBrokenFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("だれかが %lld 点に届いたら、そこで終わりです。", HeartsRules.targetScore),
                        tr("合計の点がいちばん少ない人が勝ちです。"),
                    ],
                    figure: { AnyView(HeartsHowToFigures.FinishFigure()) }
                ),
            ]
        )
    }

    /// ハートを先頭に出せるか。出る前は ✕、だれかが出したあとは ○。
    private struct HeartsBrokenFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 24) {
                column(tr("ハートがまだ出ていない"), isOK: false)
                column(tr("ハートが出たあと"), isOK: true)
            }
        }

        private func column(_ caption: String, isOK: Bool) -> some View {
            VStack(spacing: 6) {
                RuleMiniCard("7", suit: .heart, isHighlighted: isOK)
                RuleVerdictMark(isOK)
                RuleFigureLabel(caption, color: isOK ? Theme.coralText : Theme.inkSubText)
                    .frame(maxWidth: 84)
            }
        }
    }
}
