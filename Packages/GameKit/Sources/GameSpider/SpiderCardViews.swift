import SwiftUI
import Core

// MARK: - 札 1 枚の見た目

/// 札 1 枚の外形と中身（表 / 裏）。
struct SpiderCardBody: View {
    let card: SpiderCard
    let faceUp: Bool
    let isSelected: Bool
    /// 下に重なって帯だけ見えている表向きの札なら、その見出しの寸法（`nil` = 全体が見えている札）。
    let coveredIndex: CardStackIndexMetrics?
    let metrics: PlayingCardMetrics

    var body: some View {
        ZStack(alignment: .topLeading) {
            PlayingCardSurface(
                faceUp: faceUp,
                cornerRadius: metrics.cornerRadius,
                border: isSelected ? Theme.coral : Color.gray.opacity(0.2),
                borderWidth: isSelected ? 2.5 : 0.5
            )
            if !faceUp {
                PlayingCardBack(metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)
            } else if let coveredIndex {
                // フリーセルと共通の `CardStackIndex`（帯の高さいっぱいの数字 + マーク）。
                CardStackIndex(rankLabel: card.rankLabel, suit: card.suit.playingCardSuit,
                               metrics: coveredIndex)
            } else {
                PlayingCardFace(figure: card.figure, metrics: metrics)
                    .frame(width: metrics.width, height: metrics.height)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }
}

// MARK: - 配札

/// 配られてくる 1 枚。最初の 54 枚は列ごとに順に、山札からの 10 枚は列の順に飛ぶ。
struct SpiderDealtCardView<Content: View>: View {
    let pile: Int
    let depth: Int
    let restY: CGFloat
    let metrics: PlayingCardMetrics
    let dealing: Bool
    /// 山札からの配りか（最初の配札より速く、列の順だけで飛ぶ）。
    let fromStock: Bool
    let content: Content

    init(pile: Int, depth: Int, restY: CGFloat, metrics: PlayingCardMetrics,
         dealing: Bool, fromStock: Bool, @ViewBuilder content: () -> Content) {
        self.pile = pile
        self.depth = depth
        self.restY = restY
        self.metrics = metrics
        self.dealing = dealing
        self.fromStock = fromStock
        self.content = content()
    }

    var body: some View {
        CardDealtView(
            startOffset: SpiderMotion.dealStartOffset(pile: pile, restY: restY, metrics: metrics),
            animation: fromStock
                ? SpiderMotion.stockDealAppear(pile: pile)
                : SpiderMotion.dealAppear(pile: pile, depth: depth),
            dealing: dealing
        ) {
            content
        }
    }
}
