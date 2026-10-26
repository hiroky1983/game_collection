import Core
import CoreSolitaireFigures
import SwiftUI

/// 図入りの遊び方（#2044）のフリーセルの図。文言は `HowToPlayGuide.freecell.items`（Core）と同じ順。
@MainActor
enum FreeCellHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(RuleSelectPlaceFigure(moving: RuleCardSpec("7", .heart), target: RuleCardSpec("8", .spade))) },
        { AnyView(CellsFigure()) },
        { AnyView(StackFigure()) },
        { AnyView(RuleFoundationFigure()) },
    ]

    /// 左上のフリーセル 4 つ（札を 1 枚ずつ置いておける）と右上の組札。
    struct CellsFigure: View {
        var body: some View {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    RuleMiniCard("5", suit: .diamond, isHighlighted: true)
                    RuleMiniSlot()
                    RuleMiniSlot()
                    RuleMiniSlot()
                }
                RuleFigureLabel(tr("フリーセル（1 枚ずつ置いておける）"))
            }
            .padding(.top, 4)
        }
    }

    /// 札を重ねる決まりと、空いた列にはどの札でも置けること。
    private struct StackFigure: View {
        var body: some View {
            VStack(spacing: 12) {
                RuleStackPairsFigure([
                    .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .heart), isOK: true),
                    .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .club), isOK: false),
                ])
                RuleEmptyColumnFigure(card: RuleCardSpec("5", .diamond), caption: tr("どの札でも置ける"))
            }
        }
    }
}
