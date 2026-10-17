import Core
import SwiftUI

/// 図入りの遊び方（#2044）の大富豪の図。文言は `HowToPlayGuide.daifugo.items`（Core）と同じ順。
@MainActor
enum DaifugoHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PlayFigure()) },
        { AnyView(StrengthFigure()) },
        { AnyView(PassFigure()) },
    ]

    /// 場の札より強い札を出す。
    private struct PlayFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HStack(spacing: 14) {
                            VStack(spacing: 4) {
                                RuleMiniCard("7", suit: .club)
                                RuleFigureLabel(tr("場の札"))
                            }
                            VStack(spacing: 4) {
                                RuleMiniCard("J", suit: .heart, isHighlighted: true)
                                RuleFigureLabel(tr("より強い札を"), color: Theme.coral)
                            }
                        }
                    } else {
                        RuleMiniCardRow(overlap: 14) {
                            RuleMiniCard("7", suit: .club, isDimmed: true)
                            RuleMiniCard("J", suit: .heart)
                        }
                        RuleFigureLabel(tr("出して場が J に"))
                    }
                }
            }
        }
    }

    /// カードの強さの並び（弱い → 強い）。
    private struct StrengthFigure: View {
        private let cards: [(String, RuleMiniCard.Suit?)] = [
            ("3", .spade), ("7", .heart), ("J", .club), ("A", .diamond), ("2", .spade), ("JK", nil),
        ]

        var body: some View {
            RuleLineup(count: cards.count, low: tr("弱い"), high: tr("強い")) { index in
                RuleMiniCard(cards[index].0, suit: cards[index].1, isHighlighted: index == 0 || index >= 4)
            }
            .padding(.top, 4)
        }
    }

    /// 全員がパスすると場が流れる。
    private struct PassFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HStack(spacing: 10) {
                            RuleMiniCard("9", suit: .diamond)
                            Text(tr("パス ×全員"))
                                .scaledFont(13, weight: .black, design: .rounded, maxScale: 1.15)
                                .foregroundStyle(Theme.coralText)
                        }
                        RuleFigureLabel(tr("みんな出せない"))
                    } else {
                        RuleMiniSlot(tr("空"))
                        RuleFigureLabel(tr("場が流れる"))
                    }
                }
            }
        }
    }
}
