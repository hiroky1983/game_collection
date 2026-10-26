import Core
import CoreMiniCard
import SwiftUI

/// 図入りの遊び方（#2386）のスピードの図。文言は `HowToPlayGuide.speed.items`（Core）と同じ順。
/// 札は図用の共通の小札（`RuleMiniCard`）で描く。
@MainActor
enum SpeedHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(AdjacentFigure()) },
        { AnyView(SwipeFigure()) },
        { AnyView(WrapFigure()) },
        { AnyView(SimultaneousFigure()) },
        { AnyView(FlipFigure()) },
        { AnyView(WinFigure()) },
    ]

    /// 台札が 7 なら、6 か 8 を重ねられる。9 は出せない。
    struct AdjacentFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    RuleMiniCard("7", suit: .spade)
                    RuleFigureLabel(tr("台札"))
                }
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        RuleMiniCard("6", suit: .heart, isHighlighted: true)
                        RuleMiniCard("8", suit: .diamond, isHighlighted: true)
                        RuleMiniCard("9", suit: .heart, isDimmed: true)
                    }
                    HStack(spacing: 8) {
                        RuleVerdictMark(true).frame(width: RuleMiniCard.width)
                        RuleVerdictMark(true).frame(width: RuleMiniCard.width)
                        RuleVerdictMark(false).frame(width: RuleMiniCard.width)
                    }
                    RuleFigureLabel(tr("1つ違いの札"))
                }
            }
        }
    }

    /// 手札の札を、出したい台札のほうへ払う（会長 QA 2026-10-23・スワイプ前提）。
    struct SwipeFigure: View {
        var body: some View {
            VStack(spacing: 4) {
                HStack(spacing: 20) {
                    RuleMiniCard("6", suit: .spade, isHighlighted: true)
                    RuleMiniCard("10", suit: .club)
                }
                HStack(spacing: 20) {
                    Image(systemName: "arrow.up.left")
                        .scaledFont(16, weight: .black)
                        .foregroundStyle(Theme.coralText)
                        .frame(width: RuleMiniCard.width)
                    Color.clear.frame(width: RuleMiniCard.width, height: 1)
                }
                .offset(x: RuleMiniCard.width / 2 + 10)
                HStack(spacing: 4) {
                    RuleMiniCard("5", suit: .heart, isHighlighted: true)
                    RuleMiniCard("J", suit: .diamond)
                    RuleMiniCard("9", suit: .heart)
                }
                .offset(x: RuleMiniCard.width + 14)
                RuleFigureLabel(tr("台札のほうへ払う"), color: Theme.coralText)
            }
        }
    }

    /// K の上に A、A の上に K も重ねられる。
    struct WrapFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 12) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if index == 0 {
                            RuleMiniCard("K", suit: .club)
                            RuleMiniCard("A", suit: .heart, isHighlighted: true)
                        } else {
                            RuleMiniCard("A", suit: .spade)
                            RuleMiniCard("K", suit: .diamond, isHighlighted: true)
                        }
                    }
                    RuleFigureLabel(index == 0 ? tr("K の上に A") : tr("A の上に K"))
                }
            }
        }
    }

    /// 手札から台札へ出すと、山札から手札に補充される。CPU も同時に出す。
    struct SimultaneousFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        RuleMiniCardRow(overlap: 6) {
                            RuleMiniCard("5", suit: .heart, isHighlighted: true)
                            RuleMiniCard("2", suit: .diamond)
                            RuleMiniCard("J", suit: .heart)
                            RuleMiniCard("9", suit: .diamond)
                        }
                        RuleFigureLabel(tr("手札は4枚"))
                    } else {
                        RuleMiniCardRow(overlap: 6) {
                            RuleMiniCard("", isFaceDown: true, isHighlighted: true)
                            RuleMiniCard("2", suit: .diamond)
                            RuleMiniCard("J", suit: .heart)
                            RuleMiniCard("9", suit: .diamond)
                        }
                        RuleFigureLabel(tr("山札から補充"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// つまったら「めくる」。両方の山札から 1 枚ずつ台札に置く。
    struct FlipFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        HStack(spacing: 20) {
                            RuleMiniCard("", isFaceDown: true, isHighlighted: true)
                            RuleMiniCard("", isFaceDown: true, isHighlighted: true)
                        }
                        RuleFigureLabel(tr("両方の山札から1枚"))
                    } else {
                        HStack(spacing: 20) {
                            RuleMiniCard("3", suit: .club)
                            RuleMiniCard("Q", suit: .heart)
                        }
                        RuleFigureLabel(tr("台札になる"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 手札も山札も空になったほうの勝ち。
    struct WinFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        RuleMiniSlot()
                        RuleMiniSlot()
                    }
                    RuleFigureLabel(tr("手札0枚"))
                }
                VStack(spacing: 4) {
                    RuleMiniSlot()
                    RuleFigureLabel(tr("山札0枚"))
                }
            }
        }
    }
}
