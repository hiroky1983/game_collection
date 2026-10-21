import Core
import SwiftUI

/// 図入りの遊び方（#2044）のスパイダーソリティアの図。文言は `HowToPlayGuide.spider.items`（Core）と同じ順。
@MainActor
enum SpiderHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(RuleSelectPlaceFigure(moving: RuleCardSpec("7", .heart), target: RuleCardSpec("8", .spade))) },
        { AnyView(StackFigure()) },
        { AnyView(RunFigure()) },
        { AnyView(DealFigure()) },
        { AnyView(CompleteFigure()) },
    ]

    /// スートは問わない。1 つ小さい札ならどれでも置ける。
    private struct StackFigure: View {
        var body: some View {
            RuleStackPairsFigure([
                .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .heart), isOK: true),
                .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .spade), isOK: true),
                .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("6", .spade), isOK: false),
            ])
        }
    }

    /// 同じスートで降順に揃った並びだけ、まとめて動かせる。
    private struct RunFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 36) {
                column(ranks: [("8", .spade), ("7", .spade), ("6", .spade)], isOK: true)
                column(ranks: [("8", .spade), ("7", .heart), ("6", .spade)], isOK: false)
            }
        }

        private func column(ranks: [(String, RuleMiniCard.Suit)], isOK: Bool) -> some View {
            VStack(spacing: 6) {
                RuleMiniCardColumn(step: 20) {
                    ForEach(Array(ranks.enumerated()), id: \.offset) { _, rank in
                        RuleMiniCard(rank.0, suit: rank.1, isHighlighted: isOK)
                    }
                }
                .frame(height: RuleMiniCard.height + 40)
                RuleVerdictMark(isOK)
            }
        }
    }

    /// 山札をタップすると各列に 1 枚ずつ配る。
    private struct DealFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        RuleMiniCard("", isFaceDown: true, isHighlighted: true)
                        RuleFigureLabel(tr("山札をタップ"), color: Theme.coralText)
                    } else {
                        HStack(spacing: 5) {
                            ForEach(0..<4, id: \.self) { _ in
                                RuleMiniCardColumn(step: 12) {
                                    RuleMiniCard("", isFaceDown: true)
                                    RuleMiniCard("", isFaceDown: true)
                                }
                                .frame(height: RuleMiniCard.height + 12)
                            }
                        }
                        RuleFigureLabel(tr("各列に 1 枚ずつ"))
                    }
                }
            }
        }
    }

    /// K から A まで 13 枚揃うと取り除かれる。
    private struct CompleteFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 20) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        RuleMiniCardColumn(step: 18) {
                            RuleMiniCard("K", suit: .spade)
                            RuleMiniCard("Q", suit: .spade)
                            RuleMiniCard("J", suit: .spade)
                            RuleMiniCard("…", suit: .spade)
                            RuleMiniCard("A", suit: .spade)
                        }
                        .frame(height: RuleMiniCard.height + 72)
                        RuleFigureLabel(tr("K → A の 13 枚"))
                    } else {
                        RuleMiniSlot(tr("消える"))
                        RuleFigureLabel(tr("8 組でクリア"), color: Theme.coralText)
                    }
                }
            }
        }
    }
}
