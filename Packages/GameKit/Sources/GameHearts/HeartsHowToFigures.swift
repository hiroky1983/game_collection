import Core
import CoreMiniCard
import SwiftUI

/// 図入りの遊び方（#2044）のハーツの図。文言は `HowToPlayGuide.hearts.items`（Core）と同じ順。
/// 札は Core の図用の小さな札（`RuleMiniCard`）で描き、外部の画像は使わない。
@MainActor
enum HeartsHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(StrengthFigure()) },
        { AnyView(TakeFigure()) },
        { AnyView(PointsFigure()) },
        { AnyView(PassFigure()) },
        { AnyView(FollowFigure()) },
        { AnyView(DumpFigure()) },
        { AnyView(FinishFigure()) },
    ]

    /// 札と、その下の名前（誰が出したか）。
    struct Played: View {
        let rank: String
        let suit: RuleMiniCard.Suit
        let who: String
        var highlighted = false
        var dimmed = false

        var body: some View {
            VStack(spacing: 4) {
                RuleMiniCard(rank, suit: suit, isHighlighted: highlighted, isDimmed: dimmed)
                RuleFigureLabel(who, color: highlighted ? Theme.coralText : Theme.inkSubText)
            }
        }
    }

    /// 手札から 3 枚を選んで、左どなり（CPU1）へ渡す。
    struct PassFigure: View {
        var body: some View {
            HStack(spacing: 10) {
                RuleMiniCardRow(overlap: 10) {
                    RuleMiniCard("4", suit: .club)
                    RuleMiniCard("Q", suit: .spade, isHighlighted: true)
                    RuleMiniCard("9", suit: .diamond)
                    RuleMiniCard("A", suit: .heart, isHighlighted: true)
                    RuleMiniCard("K", suit: .club, isHighlighted: true)
                }
                Image(systemName: "arrow.left")
                    .scaledFont(14, weight: .black, maxScale: 1.2)
                    .foregroundStyle(Theme.coralText)
                VStack(spacing: 2) {
                    Image(systemName: "cpu")
                        .scaledFont(18, weight: .bold, maxScale: 1.15)
                        .foregroundStyle(Theme.inkSubText)
                    RuleFigureLabel(tr("左のCPU1"))
                }
            }
        }
    }

    /// クラブの 2 から、同じスートを順に出す。
    struct FollowFigure: View {
        var body: some View {
            RuleFrames(count: 4, spacing: 4) { index in
                let plays: [(String, String)] = [("2", tr("あなた")), ("9", "CPU1"), ("K", "CPU2"), ("5", "CPU3")]
                Played(rank: plays[index].0, suit: .club, who: plays[index].1, highlighted: index == 0)
            }
        }
    }

    /// 札の強さ。A がいちばん強く 2 がいちばん弱い（13 枚を重ねて 1 行に並べる）。早見表（#2788）でも使う。
    struct StrengthFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                let order = HeartsReference.strengthOrder
                RuleMiniCardWrap(count: order.count, perRow: 7) { index in
                    RuleMiniCard(HeartsReference.rankLabel(order[index]), suit: .spade, isHighlighted: index == 0)
                }
                RuleFigureLabel(tr("左上がいちばん強く、右下がいちばん弱い"))
            }
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("強い順に A K Q J 10 9 8 7 6 5 4 3 2"))
        }
    }

    /// 最初のスートで数字がいちばん大きい人が 4 枚を取る（ほかのスートの A は勝てない）。早見表（#2788）でも使う。
    struct TakeFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Played(rank: "7", suit: .diamond, who: tr("あなた"), dimmed: true)
                Played(rank: "Q", suit: .diamond, who: "CPU1", highlighted: true)
                Played(rank: "3", suit: .diamond, who: "CPU2", dimmed: true)
                Played(rank: "A", suit: .spade, who: "CPU3", dimmed: true)
            }
        }
    }

    /// ハートは 1 点、スペードの Q は 13 点。早見表（#2788）でも使う。
    struct PointsFigure: View {
        var body: some View {
            HStack(spacing: 22) {
                let entries = HeartsReference.pointEntries
                ForEach(entries.indices, id: \.self) { index in
                    let entry = entries[index]
                    pointCard(RuleMiniCard(HeartsReference.rankLabel(entry.rank), suit: .init(entry.suit),
                                           isDimmed: entry.points == 0),
                              text: index == 0 ? tr("1枚%lld点", entry.points) : tr("%lld点", entry.points))
                }
            }
        }

        private func pointCard(_ card: RuleMiniCard, text: String) -> some View {
            VStack(spacing: 4) {
                card
                RuleFigureLabel(text, color: Theme.coralText)
            }
        }
    }

    /// 出されたスート（ダイヤ）が無ければ、点の札を押し付けられる。
    private struct DumpFigure: View {
        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Played(rank: "K", suit: .diamond, who: "CPU1")
                Played(rank: "8", suit: .diamond, who: "CPU2", dimmed: true)
                Played(rank: "4", suit: .diamond, who: "CPU3", dimmed: true)
                Played(rank: "Q", suit: .spade, who: tr("あなた"), highlighted: true)
            }
        }
    }

    /// 50 点に届いたら終わり。合計の少ない人が勝ち。
    struct FinishFigure: View {
        private let rows: [(String, Int)] = [(tr("あなた"), 21), ("CPU1", 53), ("CPU2", 26), ("CPU3", 41)]

        var body: some View {
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack(spacing: 6) {
                        Image(systemName: index == 0 ? "crown.fill" : "circle.fill")
                            .scaledFont(index == 0 ? 11 : 4, weight: .bold, maxScale: 1.15)
                            .foregroundStyle(index == 0 ? Theme.yellowText : Theme.inkSubText)
                            .frame(width: 14)
                        RuleFigureLabel(row.0, color: index == 0 ? Theme.coralText : Theme.ink)
                            .frame(width: 52, alignment: .leading)
                        Capsule()
                            .fill(row.1 >= HeartsRules.targetScore ? Theme.Fill.coral : Theme.inkSub.opacity(0.35))
                            .frame(width: CGFloat(row.1) * 1.6, height: 8)
                        RuleFigureLabel(tr("%lld点", row.1), color: row.1 >= HeartsRules.targetScore ? Theme.coralText : Theme.inkSubText)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: 220)
        }
    }
}
