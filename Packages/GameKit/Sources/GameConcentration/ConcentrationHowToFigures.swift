import Core
import CoreMiniCard
import SwiftUI

/// 図入りの遊び方（#2044）の神経衰弱の図。文言は `HowToPlayGuide.concentration.items`（Core）と同じ順。
@MainActor
enum ConcentrationHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(PairFigure()) },
        { AnyView(MissFigure()) },
        { AnyView(ScoreFigure()) },
    ]

    /// 2 枚めくって同じ絵柄ならペア。
    struct PairFigure: View {
        var body: some View {
            RuleFrames(count: 3, spacing: 12) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        switch index {
                        case 0:
                            RuleMiniCard("", isFaceDown: true)
                            RuleMiniCard("", isFaceDown: true)
                        case 1:
                            RuleMiniCard("🍎", isHighlighted: true)
                            RuleMiniCard("🍎", isHighlighted: true)
                        default:
                            RuleMiniCard("🍎", isDimmed: true)
                            RuleMiniCard("🍎", isDimmed: true)
                        }
                    }
                    .padding(.top, 4)
                    RuleFigureLabel([tr("2 枚めくる"), tr("同じ絵柄"), tr("ペア！もう一度")][index],
                                    color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }

    /// ちがう絵柄なら伏せ直して相手の番。
    struct MissFigure: View {
        var body: some View {
            RuleFrames(count: 2, spacing: 14) { index in
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        if index == 0 {
                            RuleMiniCard("🍎", isHighlighted: true)
                            RuleMiniCard("🍋", isHighlighted: true)
                        } else {
                            RuleMiniCard("", isFaceDown: true)
                            RuleMiniCard("", isFaceDown: true)
                        }
                    }
                    .padding(.top, 4)
                    RuleFigureLabel(index == 0 ? tr("ちがう絵柄") : tr("伏せて CPU の番"), color: index == 0 ? Theme.inkSubText : Theme.coralText)
                }
            }
        }
    }

    /// 取ったペアの数を比べる。
    struct ScoreFigure: View {
        var body: some View {
            HStack(spacing: 24) {
                score(name: tr("あなた"), pairs: 5, isWinner: true)
                score(name: "CPU", pairs: 3, isWinner: false)
            }
        }

        private func score(name: String, pairs: Int, isWinner: Bool) -> some View {
            VStack(spacing: 4) {
                HStack(spacing: -6) {
                    ForEach(0..<pairs, id: \.self) { _ in
                        RuleMiniCard("🍎").scaleEffect(0.55)
                            .frame(width: RuleMiniCard.width * 0.4, height: RuleMiniCard.height * 0.55)
                    }
                }
                .frame(height: RuleMiniCard.height * 0.6)
                Text(tr("%lld ペア", pairs))
                    .scaledFont(16, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(isWinner ? Theme.coralText : Theme.inkSubText)
                RuleFigureLabel(isWinner ? tr("%@（勝ち）", name) : name, color: isWinner ? Theme.coralText : Theme.inkSubText)
            }
        }
    }
}
