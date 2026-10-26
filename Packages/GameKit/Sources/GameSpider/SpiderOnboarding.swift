import Core
import CoreSolitaireFigures
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のスパイダーソリティア。
///
/// 札の置き方・まとめて動かせる並び・山札を配る条件・クリアの条件・スートの数は `SpiderBoard` /
/// `SpiderSuitCount` と突き合わせる（`SpiderOnboardingTests`）。図は遊び方の図（`SpiderHowToFigures`）の部品を使い回す。
@MainActor
public enum SpiderOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "spider",
            title: tr("スパイダーのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("同じスートの札を、K から A まで 13 枚つなげます。"),
                        tr("つながった 13 枚は、自動で取り除かれます。"),
                    ],
                    figure: { AnyView(SpiderHowToFigures.CompleteFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること"),
                    lines: [
                        tr("動かす札をタップして選びます。"),
                        tr("置きたい列をタップします。"),
                    ],
                    figure: { AnyView(RuleSelectPlaceFigure(moving: RuleCardSpec("7", .heart), target: RuleCardSpec("8", .spade))) }
                ),
                OnboardingPage(
                    heading: tr("札の置き方"),
                    lines: [
                        tr("1 つ小さい札なら、スートは問わず置けます。"),
                        tr("空いた列には、どの札でも置けます。"),
                    ],
                    figure: { AnyView(SpiderHowToFigures.StackFigure()) }
                ),
                OnboardingPage(
                    heading: tr("まとめて動かす"),
                    lines: [
                        tr("まとめて動かせるのは、同じスートで数が順に並んだ札だけです。"),
                        tr("スートがちがう札がまざっていたら、1 枚ずつ動かします。"),
                    ],
                    figure: { AnyView(SpiderHowToFigures.RunFigure()) }
                ),
                OnboardingPage(
                    heading: tr("山札を配る"),
                    lines: [
                        tr("動かせる手がなくなったら、左上の山札をタップします。"),
                        tr("各列に、1 枚ずつ配られます。"),
                        tr("空いた列があるあいだは、配れません。"),
                    ],
                    figure: { AnyView(SpiderHowToFigures.DealFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("%lld 組すべて取り除いたら、クリアです。", SpiderBoard.sequenceGoal),
                        tr("「新規ゲーム」で、使うスートの数を選べます。"),
                        tr("スートが多いほど、むずかしくなります。"),
                    ],
                    figure: { AnyView(SuitCountFigure()) }
                ),
            ]
        )
    }

    /// スートの数（1・2・4）。1 スートは ♠ だけ、2 スートは ♠♥、4 スートは 4 種すべて。
    private struct SuitCountFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                ForEach([SpiderSuitCount.one, .two, .four], id: \.self) { count in
                    VStack(spacing: 4) {
                        Text(count.suits.map(\.symbol).joined())
                            .scaledFont(20, weight: .black, maxScale: 1.15)
                            .foregroundStyle(Theme.ink)
                        RuleFigureLabel(tr("%lld スート", count.rawValue))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .fill(Theme.coral.opacity(0.15)))
                }
            }
        }
    }
}
