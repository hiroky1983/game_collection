import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のいろリレー。
///
/// 出せる札・引き方・特殊札の効き方・勝ち負けは `ColorRelayRules` / `ColorRelayModel` と突き合わせる
/// （`ColorRelayOnboardingTests`）。図は遊び方の図（`ColorRelayHowToFigures`）の部品を使い回す。
@MainActor
public enum ColorRelayOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "colorrelay",
            title: tr("いろリレーのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("配られた %lld 枚の手札を、先になくした人の勝ちです。", ColorRelayRules.initialHandCount),
                        tr("ほかの CPU と、順番に札を出し合います。"),
                    ],
                    figure: { AnyView(ColorRelayHowToFigures.WinFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("場の札と、同じ色か同じ数字・記号の札を 1 枚出します。"),
                        tr("色も数字・記号もちがう札は、出せません。いろがえは別です。"),
                    ],
                    figure: { AnyView(ColorRelayHowToFigures.MatchFigure()) }
                ),
                OnboardingPage(
                    heading: tr("出せないとき"),
                    lines: [
                        tr("出せる札がないときは、山から 1 枚引きます。"),
                        tr("引いた札が出せるなら、そのまま出せます。"),
                    ],
                    figure: { AnyView(ColorRelayHowToFigures.DrawFigure()) }
                ),
                OnboardingPage(
                    heading: tr("とばしとぎゃく"),
                    lines: [
                        tr("「とばし」は、次の人の番を飛ばします。"),
                        tr("「ぎゃく」は、回る向きを逆にします。"),
                    ],
                    figure: { AnyView(ColorRelayHowToFigures.SkipReverseFigure()) }
                ),
                OnboardingPage(
                    heading: tr("+2"),
                    lines: [
                        tr("「+2」を出すと、次の人が 2 枚引きます。"),
                        tr("引いた人は、その番を飛ばされます。"),
                    ],
                    figure: { AnyView(ColorRelayHowToFigures.DrawTwoFigure()) }
                ),
                OnboardingPage(
                    heading: tr("いろがえ"),
                    lines: [
                        tr("「いろがえ」は、どの札の上にも出せて、次の色を選べます。"),
                        tr("「いろがえ+4」は、次の人が 4 枚引きます。"),
                    ],
                    figure: { AnyView(ColorRelayHowToFigures.WildFigure()) }
                ),
            ]
        )
    }
}
