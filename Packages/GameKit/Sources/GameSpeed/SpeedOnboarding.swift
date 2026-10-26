import Core
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のスピード。
///
/// 出せる札・手札の枚数・補充・めくる・勝ち負けは `SpeedRules` / `SpeedModel` と突き合わせる
/// （`SpeedOnboardingTests`）。図は遊び方の図（`SpeedHowToFigures`）の部品を使い回す。
@MainActor
public enum SpeedOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "speed",
            title: tr("スピードのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("手札と山札を、CPU より先に出し切ったほうの勝ちです。"),
                        tr("順番はなく、CPU も同時に出してきます。"),
                    ],
                    figure: { AnyView(SpeedHowToFigures.WinFigure()) }
                ),
                OnboardingPage(
                    heading: tr("札の出し方"),
                    lines: [
                        tr("手札の札を、出したい台札のほうへ払います。"),
                        tr("出せない札は、手札に戻るだけです。"),
                    ],
                    figure: { AnyView(SpeedHowToFigures.SwipeFigure()) }
                ),
                OnboardingPage(
                    heading: tr("出せる札"),
                    lines: [
                        tr("台札の数字と、1 つ違いの札が出せます。"),
                        tr("台札が 7 なら、6 か 8 です。マークは関係ありません。"),
                    ],
                    figure: { AnyView(SpeedHowToFigures.AdjacentFigure()) }
                ),
                OnboardingPage(
                    heading: tr("A と K もつながる"),
                    lines: [
                        tr("K の上に A、A の上に K も出せます。"),
                        tr("K の次は、A にもどると考えましょう。"),
                    ],
                    figure: { AnyView(SpeedHowToFigures.WrapFigure()) }
                ),
                OnboardingPage(
                    heading: tr("手札の補充"),
                    lines: [
                        tr("手札は、最大 %lld 枚です。", SpeedRules.handSize),
                        tr("山札が残っているあいだは、1 枚出すごとに補充されます。"),
                    ],
                    figure: { AnyView(SpeedHowToFigures.SimultaneousFigure()) }
                ),
                OnboardingPage(
                    heading: tr("どちらも出せないとき"),
                    lines: [
                        tr("「めくる」を押すと、山札が残っている側が 1 枚ずつ台札に置きます。"),
                        tr("両方の山札が空なら、台札を切り直します。"),
                        tr("めくるだけが続いて場が動かないときは、引き分けです。"),
                    ],
                    figure: { AnyView(SpeedHowToFigures.FlipFigure()) }
                ),
            ]
        )
    }
}
