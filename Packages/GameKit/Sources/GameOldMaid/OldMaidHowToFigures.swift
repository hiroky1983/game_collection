import Core
import CoreMiniCard
import SwiftUI

/// 図入りの遊び方（#2044）のババ抜きの図。文言は `HowToPlayGuide.oldMaid.items`（Core）と同じ順。
/// 数字札は図用の共通の小札（`RuleMiniCard`）、ジョーカーと CPU の顔は本番と同じ部品で描く。
@MainActor
enum OldMaidHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PairFigure()) },
        { AnyView(DrawFigure()) },
        { AnyView(FaceFigure()) },
        { AnyView(LoseFigure()) },
    ]

    /// 同じ数字の 2 枚を捨てる。
    struct PairFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        RuleMiniCardRow(overlap: 6) {
                            RuleMiniCard("5", suit: .spade, isHighlighted: true)
                            RuleMiniCard("9", suit: .diamond)
                            RuleMiniCard("5", suit: .heart, isHighlighted: true)
                        }
                        RuleFigureLabel(tr("同じ数字の2枚"), color: Theme.coralText)
                    } else {
                        RuleMiniCardRow(overlap: 6) {
                            RuleMiniCard("5", suit: .spade, isDimmed: true)
                            RuleMiniCard("5", suit: .heart, isDimmed: true)
                        }
                        RuleFigureLabel(tr("ペアで捨てる"))
                    }
                }
            }
        }
    }

    /// 次の CPU の伏せ札から 1 枚引き、ペアができたら捨てる。
    struct DrawFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 16) { index in
                VStack(spacing: 4) {
                    if index == 0 {
                        RuleMiniCardRow(overlap: 10) {
                            RuleMiniCard("", isFaceDown: true)
                            RuleMiniCard("", isFaceDown: true, isHighlighted: true)
                            RuleMiniCard("", isFaceDown: true)
                        }
                        RuleFigureLabel(tr("CPUの札から1枚"))
                    } else {
                        RuleMiniCardRow(overlap: 6) {
                            RuleMiniCard("7", suit: .club)
                            RuleMiniCard("7", suit: .diamond, isHighlighted: true)
                        }
                        RuleFigureLabel(tr("そろったら捨てる"), color: Theme.coralText)
                    }
                }
            }
        }
    }

    /// 札に指をかけると、ジョーカーを持つ CPU の顔に出ることがある。
    struct FaceFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 20) {
                example(face: .smile, label: tr("にやり→ジョーカーかも"), color: Theme.coralText) {
                    OldMaidCardFaceView(card: .joker, highlighted: true)
                }
                example(face: .worried, label: tr("ひやり→ほかの札かも"), color: Theme.inkSubText) {
                    RuleMiniCard("", isFaceDown: true, isHighlighted: true)
                }
            }
        }

        private func example<Card: View>(face: OldMaidFace, label: String, color: Color,
                                         @ViewBuilder card: () -> Card) -> some View {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    OldMaidFaceView(face: face)
                        .frame(width: 34, height: 34)
                    card()
                }
                RuleFigureLabel(label, color: color)
            }
        }
    }

    /// 手札がなくなった人から抜け、ジョーカーを持って残った人が負け。
    struct LoseFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 4) {
                        RuleMiniSlot()
                        RuleFigureLabel(tr("あがり"))
                    }
                }
                VStack(spacing: 4) {
                    OldMaidCardFaceView(card: .joker, highlighted: true)
                    RuleFigureLabel(tr("残ったら負け"), color: Theme.coralText)
                }
            }
        }
    }
}
