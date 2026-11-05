import Core
import CoreMiniCard
import CoreSolitaireFigures
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のソリティア（クロンダイク）。
///
/// 札の置き方・空き列・山札のめくり方・クリアの条件は `SolitaireBoard` / `SolitaireDrawMode` と突き合わせる
/// （`SolitaireOnboardingTests`）。図は Core の部品（遊び方の図と同じ）を使い回す。
@MainActor
public enum SolitaireOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "solitaire",
            title: tr("ソリティアのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("配られた札を、右上の組札に積み上げていきます。"),
                        tr("♠♥♦♣ ごとに、A から K まで順に積みます。"),
                    ],
                    figure: { AnyView(RuleFoundationFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("動かす札をタップして選び、置きたい列か組札をタップします。"),
                        tr("もう一度同じ札をタップすると、選びを外せます。"),
                    ],
                    figure: { AnyView(RuleSelectPlaceFigure(moving: RuleCardSpec("7", .heart), target: RuleCardSpec("8", .spade))) }
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
                        .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("6", .heart), isOK: false),
                    ])) }
                ),
                OnboardingPage(
                    heading: tr("空いた列"),
                    lines: [
                        tr("札がなくなった列には、K だけ置けます。"),
                        tr("K から始まる並びなら、まとめて置けます。"),
                    ],
                    figure: { AnyView(RuleEmptyColumnFigure(card: RuleCardSpec("K", .heart), caption: tr("K だけ置ける"))) }
                ),
                OnboardingPage(
                    heading: tr("山札"),
                    lines: [
                        tr("左上の山札をタップして、札をめくります。"),
                        tr("めくった札も、列や組札に置けます。"),
                        tr("最後までめくったら、もう一度タップすると最初からめくれます。"),
                    ],
                    figure: { AnyView(StockFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("4 つの組札が、すべて K まで積み上がったらクリアです。"),
                        tr("「新規ゲーム」で、山札を 1 枚ずつか 3 枚ずつか選べます。"),
                    ],
                    figure: { AnyView(ClearFigure()) }
                ),
            ]
        )
    }

    /// 山札をタップすると、1 枚ずつ（3 枚めくりなら 3 枚ずつ）捨て札へ。
    private struct StockFigure: View {
        var body: some View {
            HStack(spacing: 18) {
                VStack(spacing: 4) {
                    RuleMiniCard("", isFaceDown: true, isHighlighted: true)
                    RuleFigureLabel(tr("山札"), color: Theme.coralText)
                }
                Image(systemName: "arrow.right")
                    .scaledFont(14, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.coralText)
                VStack(spacing: 4) {
                    RuleMiniCard("9", suit: .diamond)
                    RuleFigureLabel(tr("めくった札"))
                }
            }
        }
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
