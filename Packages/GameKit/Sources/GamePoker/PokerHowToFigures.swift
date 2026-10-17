import Core
import SwiftUI

/// 図入りの遊び方（#2044）のポーカーの図。文言は `HowToPlayGuide.poker.items`（Core）と同じ順。
/// 札は Core の `RuleMiniCard`。
@MainActor
enum PokerHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(SelectFigure()) },
        { AnyView(DrawFigure()) },
        { AnyView(RankFigure()) },
    ]

    /// ボーナスルール（`HowToPlayGuide.pokerBonus`）の図。先頭 3 つはスタンダードと同じ。
    static let bonusItems: [@MainActor @Sendable () -> AnyView] = items + [
        { AnyView(BonusFigure()) },
        { AnyView(DoubleUpFigure()) },
    ]

    /// 選んでいるルールの遊び方（開始シートと「？」で共有する）。図は項目と同じ順。
    static func guide(for rules: PokerRuleSet) -> HowToPlayGuide {
        switch rules {
        case .standard: return HowToPlayGuide.poker.illustrated(items)
        case .bonus:    return HowToPlayGuide.pokerBonus.illustrated(bonusItems)
        }
    }

    /// 5 枚のうち残す 2 枚を選んだところ。
    private struct SelectFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    RuleMiniCard("K", suit: .spade, isHighlighted: true)
                    RuleMiniCard("K", suit: .heart, isHighlighted: true)
                    RuleMiniCard("9", suit: .diamond)
                    RuleMiniCard("5", suit: .club)
                    RuleMiniCard("2", suit: .spade)
                }
                .padding(.top, 4)
                RuleFigureLabel(tr("タップで選んだ札は残る"), color: Theme.coralText)
            }
        }
    }

    /// 選ばなかった 3 枚が新しい札に入れ替わる。
    ///
    /// 5 枚の手札 2 コマを横に並べると iPhone の幅（SE・17 Pro とも）に収まらず、シート全体が
    /// 横に押し広げられて左右の余白が消える（#2207）。横 1 列に収まらない幅では、
    /// 「前」の下に「後」を置く 2 段にする（iPad など広い幅では横並びのまま）。
    private struct DrawFigure: View {
        var body: some View {
            ViewThatFits(in: .horizontal) {
                RuleFrames(count: 2, spacing: 10) { index in hand(index) }
                VStack(spacing: 6) {
                    hand(0)
                    Image(systemName: "arrow.down")
                        .scaledFont(12, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSub)
                    hand(1)
                }
            }
        }

        private func hand(_ index: Int) -> some View {
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    RuleMiniCard("K", suit: .spade, isHighlighted: index == 0)
                    RuleMiniCard("K", suit: .heart, isHighlighted: index == 0)
                    if index == 0 {
                        RuleMiniCard("9", suit: .diamond, isDimmed: true)
                        RuleMiniCard("5", suit: .club, isDimmed: true)
                        RuleMiniCard("2", suit: .spade, isDimmed: true)
                    } else {
                        RuleMiniCard("K", suit: .diamond)
                        RuleMiniCard("7", suit: .club)
                        RuleMiniCard("3", suit: .heart)
                    }
                }
                .padding(.top, 4)
                RuleFigureLabel(index == 0 ? tr("選ばなかった 3 枚") : tr("引き直した 3 枚"))
            }
        }
    }

    /// 役の強さの並び（弱い → 強い）。
    private struct RankFigure: View {
        private let names = [tr("ワン\nペア"), tr("ツー\nペア"), tr("スリー\nカード"), tr("フル\nハウス")]

        var body: some View {
            RuleLineup(count: names.count, low: tr("弱い"), high: tr("強い")) { index in
                Text(names[index])
                    .scaledFont(12, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.coral.opacity(0.15 + 0.12 * Double(index))))
            }
        }
    }

    /// 役ごとのボーナス（配当表の一部）。数字は `PokerBonusTable` から引く。
    private struct BonusFigure: View {
        private let ranks: [PokerHandRank] = [.twoPair, .fullHouse, .fourOfAKind]

        var body: some View {
            VStack(spacing: 6) {
                ForEach(ranks, id: \.self) { rank in
                    HStack {
                        Text(rank.description)
                            .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 8)
                        Text(verbatim: "+\(PokerBonusTable.chips(for: rank))")
                            .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                            .foregroundStyle(Theme.coralText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous).fill(Theme.coral.opacity(0.15)))
                }
                RuleFigureLabel(tr("役が強いほどボーナスも大きい"))
            }
        }
    }

    /// ダブルアップ。見せ札より次の札が上か下かを当てる。
    private struct DoubleUpFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    VStack(spacing: 3) {
                        RuleMiniCard("7", suit: .spade)
                        RuleFigureLabel(tr("見せ札"))
                    }
                    Image(systemName: "arrow.right")
                        .scaledFont(12, weight: .black, maxScale: 1.2)
                        .foregroundStyle(Theme.inkSub)
                    VStack(spacing: 3) {
                        RuleMiniCard("?", isFaceDown: true, isHighlighted: true)
                        RuleFigureLabel(tr("次の札は上？下？"), color: Theme.coralText)
                    }
                }
            }
        }
    }
}
