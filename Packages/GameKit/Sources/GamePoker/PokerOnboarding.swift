import Core
import CoreMiniCard
import SwiftUI

/// 図で見る「はじめての遊び方」（#2824）のポーカー。
///
/// 勝負の回数・役の数・点は `PokerModel.roundsPerSession` / `PokerScoreTable` から引く
/// （`PokerOnboardingTests` が突き合わせる）。図は遊び方の図（`PokerHowToFigures`）の部品を使い回す。
/// 札を「タップすると入れ替える札に選ぶ」実装（`toggleCardSelection` → `confirmExchange`）に合わせる。
@MainActor
public enum PokerOnboarding {
    public static var guide: OnboardingGuide {
        OnboardingGuide(
            gameID: "poker",
            title: tr("ポーカーのはじめての遊び方"),
            pages: [
                OnboardingPage(
                    heading: tr("このゲームの目的"),
                    lines: [
                        tr("5 枚の手札で「役」を作ります。"),
                        tr("CPU より強い役を作れば、その回の勝ちです。"),
                    ],
                    figure: { AnyView(VersusFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること①"),
                    lines: [
                        tr("入れ替えたい札を、タップで選びます。"),
                        tr("選んだ札は少し下がって、枠がつきます。"),
                    ],
                    figure: { AnyView(PokerHowToFigures.SelectFigure()) }
                ),
                OnboardingPage(
                    heading: tr("1 回の番でやること②"),
                    lines: [
                        tr("「交換」を押すと、選んだ札が新しい札になります。"),
                        tr("入れ替えない札は、そのまま残ります。"),
                        tr("替えないときは「交換しない」を押します。"),
                    ],
                    figure: { AnyView(PokerHowToFigures.DrawFigure()) }
                ),
                OnboardingPage(
                    heading: tr("役の強さ"),
                    lines: [
                        tr("役は全部で %lld 種類あります。", PokerScoreTable.table.count),
                        tr("ペアが 2 組、3 枚そろい…と、強くなっていきます。"),
                        tr("一覧は「？」の「くわしいルール」で見られます。"),
                    ],
                    figure: { AnyView(PokerHowToFigures.RankFigure()) }
                ),
                OnboardingPage(
                    heading: tr("点の入り方"),
                    lines: [
                        tr("勝った回は、自分の役の点が入ります。"),
                        tr("役が強いほど、大きな点です。"),
                        tr("引き分けと負けは、点が入りません。"),
                    ],
                    figure: { AnyView(PokerHowToFigures.PointsFigure()) }
                ),
                OnboardingPage(
                    heading: tr("勝ち負けの決まり"),
                    lines: [
                        tr("%lld 回勝負して、合計点の多いほうが勝ちです。", PokerModel.roundsPerSession),
                        tr("広告を見ると、1 度だけもう 1 回交換できます。"),
                    ],
                    figure: { AnyView(TotalFigure()) }
                ),
            ]
        )
    }

    /// 例: あなたのフルハウス（K が 3 枚・5 が 2 枚）が、CPU のワンペアに勝つ。
    static let exampleYou: [(String, RuleMiniCard.Suit)] = [("K", .spade), ("K", .heart), ("K", .club), ("5", .diamond), ("5", .spade)]
    static let exampleCPU: [(String, RuleMiniCard.Suit)] = [("9", .spade), ("9", .heart), ("7", .club), ("4", .diamond), ("2", .spade)]

    private struct VersusFigure: View {
        var body: some View {
            VStack(spacing: 10) {
                row(label: tr("あなた"), cards: PokerOnboarding.exampleYou, result: tr("フルハウス"), isWinner: true)
                row(label: tr("CPU"), cards: PokerOnboarding.exampleCPU, result: tr("ワンペア"), isWinner: false)
            }
        }

        private func row(label: String, cards: [(String, RuleMiniCard.Suit)], result: String, isWinner: Bool) -> some View {
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                        RuleMiniCard(card.0, suit: card.1, isHighlighted: isWinner)
                    }
                }
                HStack(spacing: 6) {
                    RuleFigureLabel(label)
                    RuleFigureLabel(result, color: isWinner ? Theme.coralText : Theme.inkSubText)
                    RuleVerdictMark(isWinner)
                }
            }
        }
    }

    /// 10 回ぶんの点を足して比べる。
    private struct TotalFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 28) {
                column(tr("あなた"), points: 24, isWinner: true)
                column(tr("CPU"), points: 18, isWinner: false)
            }
        }

        private func column(_ label: String, points: Int, isWinner: Bool) -> some View {
            VStack(spacing: 4) {
                Text(tr("%lld点", points))
                    .scaledFont(22, weight: .black, design: .rounded, maxScale: 1.15)
                    .foregroundStyle(isWinner ? Theme.coralText : Theme.ink)
                RuleFigureLabel(label, color: isWinner ? Theme.coralText : Theme.inkSubText)
                RuleVerdictMark(isWinner)
            }
        }
    }
}
