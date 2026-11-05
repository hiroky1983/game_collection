import Core
import CoreSolitaireFigures
import SwiftUI

/// 図入りの遊び方（#2044）のソリティアの図。文言は `HowToPlayGuide.solitaire.items`（Core）と同じ順。
/// 札を重ねる決まり・空いた列・組札の図は、フリーセル・スパイダーと共通の Core の部品を使う。
@MainActor
enum SolitaireHowToFigures {
    static let items: [@MainActor @Sendable () -> AnyView] = [
        { AnyView(RuleSelectPlaceFigure(moving: RuleCardSpec("7", .heart), target: RuleCardSpec("8", .spade))) },
        { AnyView(RuleStackPairsFigure([
            .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .heart), isOK: true),
            .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("7", .club), isOK: false),
            .init(base: RuleCardSpec("8", .spade), placed: RuleCardSpec("6", .heart), isOK: false),
        ])) },
        { AnyView(RuleEmptyColumnFigure(card: RuleCardSpec("K", .heart), caption: tr("K だけ置ける"))) },
        { AnyView(RuleFoundationFigure()) },
    ]
}
