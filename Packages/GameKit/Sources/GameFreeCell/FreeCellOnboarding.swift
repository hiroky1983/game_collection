import Core
import CoreMiniCard
import CoreSolitaireFigures
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のフリーセル。
///
/// 札の置き方・フリーセルの数・空き列・まとめて動かせる枚数・クリアの条件は `FreeCellBoard` と突き合わせる
/// （`FreeCellOnboardingTests`）。図は Core の部品と遊び方の図（`FreeCellHowToFigures`）を使い回す。
@MainActor
public enum FreeCellOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "freecell",
            title: tr("フリーセルのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("配られた札を、右上の組札に積み上げていきます。"),
                        tr("♠♥♦♣ ごとに、A から K まで順に積みます。"),
                        tr("52 枚すべて、最初から見えています。"),
                    ],
                    figure: { AnyView(RuleFoundationFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("動かす札をタップして選びます。"),
                        tr("置きたい列・フリーセル・組札のどれかをタップします。"),
                    ],
                    figure: { AnyView(RuleSelectPlaceFigure(moving: RuleCardSpec("7", .heart), target: RuleCardSpec("8", .spade))) }
                ),
                OnboardingPage(
                    heading: tr("フリーセル"),
                    lines: [
                        tr("左上の %lld つの枠が「フリーセル」です。", FreeCellBoard.cellCount),
                        tr("札を 1 枚ずつ、一時的に置いておけます。"),
                        tr("入れた札は、置ける場所があればいつでも列や組札へ動かせます。"),
                    ],
                    figure: { AnyView(FreeCellHowToFigures.CellsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("札の重ね方"),
                    lines: [
                        tr("列には、1 つ小さくて色ちがいの札だけ重ねられます。"),
                        tr("そろった並びは、まとめて動かせます。"),
                    ],
                    figure: { AnyView(RuleStackPairsFigure([
                        .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .heart), isOK: true),
                        .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .club), isOK: false),
                    ])) }
                ),
                OnboardingPage(
                    heading: tr("空いた列"),
                    lines: [
                        tr("札がなくなった列には、どの札でも置けます。"),
                        tr("空きのフリーセルや空き列が多いほど、まとめて動かせる枚数が増えます。"),
                    ],
                    figure: { AnyView(RuleEmptyColumnFigure(card: RuleCardSpec("5", .diamond), caption: tr("どの札でも置ける"))) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("4 つの組札が、すべて K まで積み上がったらクリアです。"),
                        tr("全部の札が見えているので、運ではなく読みで決まります。"),
                    ],
                    figure: { AnyView(ClearFigure()) }
                ),
            ]
        )
    }

    /// 4 つの組札がどれも K まで。
    private struct ClearFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    RuleMiniCard("K", suit: .spade)
                    RuleMiniCard("K", suit: .heart)
                    RuleMiniCard("K", suit: .diamond)
                    RuleMiniCard("K", suit: .club)
                }
                RuleFigureLabel(tr("4 つとも K まで積めたらクリア"), color: Theme.coralText)
            }
            .padding(.top, 4)
        }
    }
}
