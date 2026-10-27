import Core
import CoreMiniCard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）の大富豪。
///
/// 革命の枚数・階級の呼び名は `DaifugoRules` から引き、強さの並びは早見表（#2788）と同じ
/// `DaifugoReference.strengthOrder` を使う（`DaifugoOnboardingTests` が突き合わせる）。
/// 図は遊び方の図（`DaifugoHowToFigures`）の部品を使い回す。しばり（任意）は開始シートで選ぶ設定なので、ここでは触れない。
@MainActor
public enum DaifugoOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "daifugo",
            title: tr("大富豪のはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("手札を、だれよりも早く出し切るゲームです。"),
                        tr("早く上がるほど、上の階級になります。"),
                    ],
                    figure: { AnyView(GoalFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("場に組があるときは、同じ枚数で、より強い組を出します。"),
                        tr("場が空なら、1 枚・ペア・3 枚…を好きに出せます。"),
                    ],
                    figure: { AnyView(DaifugoHowToFigures.PlayFigure()) }
                ),
                OnboardingPage(
                    heading: tr("カードの強さ"),
                    lines: [
                        tr("3 がいちばん弱く、K・A・2 の順に強くなります。"),
                        tr("ジョーカーが最強で、どの札の代わりにもなります。"),
                    ],
                    figure: { AnyView(DaifugoHowToFigures.StrengthFigure()) }
                ),
                OnboardingPage(
                    heading: tr("パス"),
                    lines: [
                        tr("出せないとき、出したくないときは、パスします。"),
                        tr("全員がパスすると、場が流れます。"),
                    ],
                    figure: { AnyView(DaifugoHowToFigures.PassFigure()) }
                ),
                OnboardingPage(
                    heading: tr("革命と 8 切り"),
                    lines: [
                        tr("同じ数字を %lld 枚以上まとめて出すと「革命」。強さが逆になります。", DaifugoRules.revolutionCount),
                        tr("8 を含む組を出すと「8 切り」。場が流れて、続けて出せます。"),
                    ],
                    figure: { AnyView(SpecialFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("上がった順に、大富豪・富豪・貧民・大貧民になります。"),
                        tr("最後の 1 手が 2・8・ジョーカーだと反則。大貧民に落ちます。"),
                        tr("次のゲームの前に、階級に応じてカードを交換します。"),
                    ],
                    figure: { AnyView(TitlesFigure()) }
                ),
            ]
        )
    }

    /// 手札が 0 枚になったら上がり。
    private struct GoalFigure: View {
        var body: some View {
            HStack(spacing: 14) {
                VStack(spacing: 4) {
                    RuleMiniCardRow(overlap: 14) {
                        RuleMiniCard("5", suit: .heart)
                        RuleMiniCard("9", suit: .club)
                        RuleMiniCard("K", suit: .diamond)
                    }
                    RuleFigureLabel(tr("手札"))
                }
                Image(systemName: "arrow.right")
                    .scaledFont(14, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.coralText)
                VStack(spacing: 4) {
                    RuleMiniSlot(tr("空"))
                    RuleFigureLabel(tr("0 枚で上がり"), color: Theme.coralText)
                }
            }
        }
    }

    /// 革命（4 枚で強さが逆）と 8 切り（場が流れる）。
    private struct SpecialFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        RuleMiniCardRow(overlap: 20) {
                            RuleMiniCard("5", suit: .spade, isHighlighted: true)
                            RuleMiniCard("5", suit: .heart, isHighlighted: true)
                            RuleMiniCard("5", suit: .diamond, isHighlighted: true)
                            RuleMiniCard("5", suit: .club, isHighlighted: true)
                        }
                        RuleFigureLabel(tr("同じ数字 4 枚\n革命で強さが逆に"), color: Theme.coralText)
                    } else {
                        RuleMiniCard("8", suit: .spade, isHighlighted: true)
                        RuleFigureLabel(tr("8 を出すと\n場が流れる"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 階級の呼び名（上がった順）。
    private struct TitlesFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                ForEach(Array(DaifugoRules.titles.enumerated()), id: \.offset) { index, title in
                    HStack {
                        Text(tr("%lld 番目に上がる", index + 1))
                            .scaledFont(12, weight: .bold, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(Theme.inkSubText)
                        Spacer(minLength: 8)
                        Text(title)
                            .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(index == 0 ? Theme.coralText : Theme.ink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(Theme.coral.opacity(0.15 - 0.03 * Double(index))))
                }
            }
            .frame(maxWidth: 220)
        }
    }
}
