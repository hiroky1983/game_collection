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
                RuleFigureLabel("タップで選んだ札は残る", color: Theme.coral)
            }
        }
    }

    /// 選ばなかった 3 枚が新しい札に入れ替わる。
    private struct DrawFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 10) { index in
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
                    RuleFigureLabel(index == 0 ? "選ばなかった 3 枚" : "引き直した 3 枚")
                }
            }
        }
    }

    /// 役の強さの並び（弱い → 強い）。
    private struct RankFigure: View {
        private let names = ["ワン\nペア", "ツー\nペア", "スリー\nカード", "フル\nハウス"]

        var body: some View {
            RuleLineup(count: names.count, low: "弱い", high: "強い") { index in
                Text(names[index])
                    .scaledFont(12, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.coral.opacity(0.15 + 0.12 * Double(index))))
            }
        }
    }
}
