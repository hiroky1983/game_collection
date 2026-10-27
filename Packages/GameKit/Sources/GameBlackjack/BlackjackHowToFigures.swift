import Core
import CoreMiniCard
import SwiftUI

/// 図入りの遊び方（#2044）のブラックジャックの図。文言は `HowToPlayGuide.blackjack.items`（Core）と同じ順。
@MainActor
enum BlackjackHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(GoalFigure()) },
        { AnyView(PointsFigure()) },
        { AnyView(HitStandFigure()) },
        { AnyView(SplitFigure()) },
    ]

    private static func total(_ text: String, color: Color = Theme.ink) -> some View {
        Text(text)
            .scaledFont(14, weight: .black, design: .rounded, maxScale: 1.15)
            .foregroundStyle(color)
    }

    /// 21 ぴったりと、21 超え。
    struct GoalFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        RuleMiniCard("K", suit: .spade)
                        RuleMiniCard("A", suit: .heart)
                    }
                    BlackjackHowToFigures.total(tr("合計 21"))
                    RuleVerdictMark(true)
                }
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        RuleMiniCard("K", suit: .club)
                        RuleMiniCard("7", suit: .diamond)
                        RuleMiniCard("6", suit: .spade)
                    }
                    BlackjackHowToFigures.total(tr("合計 23"), color: Theme.coralText)
                    RuleVerdictMark(false)
                }
            }
        }
    }

    /// 札の点数。
    struct PointsFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 22) {
                column(cards: [RuleMiniCard("A", suit: .spade)], caption: tr("1 か 11"))
                column(cards: [RuleMiniCard("J", suit: .heart), RuleMiniCard("Q", suit: .club), RuleMiniCard("K", suit: .diamond)],
                       caption: tr("どれも 10 点"))
                column(cards: [RuleMiniCard("2", suit: .spade), RuleMiniCard("…"), RuleMiniCard("9", suit: .heart)],
                       caption: tr("数字のまま"))
            }
        }

        private func column(cards: [RuleMiniCard], caption: String) -> some View {
            VStack(spacing: 4) {
                HStack(spacing: -10) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in card }
                }
                RuleFigureLabel(caption)
            }
        }
    }

    /// ヒットで 1 枚足す。ここで止めるのがスタンド。
    struct HitStandFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 3) {
                        RuleMiniCard("8", suit: .spade)
                        RuleMiniCard("6", suit: .heart)
                        if index > 0 { RuleMiniCard("5", suit: .club, isHighlighted: true) }
                    }
                    .padding(.top, 4)
                    BlackjackHowToFigures.total(index == 0 ? tr("合計 14") : tr("合計 19"), color: index == 0 ? Theme.ink : Theme.coralText)
                    RuleFigureLabel(index == 0 ? tr("いま") : tr("ヒット（+1 枚）\nここで止めるのがスタンド"),
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }

    /// 同じ点数の 2 枚を 2 手に分ける。
    struct SplitFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HStack(spacing: 3) {
                            RuleMiniCard("8", suit: .spade)
                            RuleMiniCard("8", suit: .heart)
                        }
                        RuleFigureLabel(tr("同じ点数の 2 枚"))
                    } else {
                        HStack(spacing: 14) {
                            RuleMiniCard("8", suit: .spade)
                            RuleMiniCard("8", suit: .heart)
                        }
                        RuleFigureLabel(tr("2 つの手に分ける"), color: Theme.coralText)
                    }
                }
            }
        }
    }
}
